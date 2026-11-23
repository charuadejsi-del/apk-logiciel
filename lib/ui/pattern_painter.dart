import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/pattern.dart';
import 'theme.dart';

/// Nombre de nuances de reflet selon l'orientation du point.
const int _shades = 4;
const List<double> _shadeFactor = [0.70, 0.86, 1.0, 1.16];

/// Géométrie pré-calculée une seule fois : segments cousus par bloc de couleur,
/// et, pour le rendu réaliste, répartis par nuance selon leur angle (reflet du fil).
class PatternGeometry {
  final List<Float32List> points; // 4 valeurs par segment
  final List<Int32List> endIndex; // index de l'instruction qui termine le segment
  final List<List<Float32List>> shadePoints;
  final List<List<Int32List>> shadeEnd;
  final List<Color> colors;
  final Bounds bounds;
  final List<Stitch> stitches;
  final Float32List jumpLines; // sauts : départ → arrivée
  final Float32List trimPoints; // coupes

  PatternGeometry._(this.points, this.endIndex, this.shadePoints, this.shadeEnd,
      this.colors, this.bounds, this.stitches, this.jumpLines, this.trimPoints);

  factory PatternGeometry.from(EmbPattern p) {
    final pts = <List<double>>[<double>[]];
    final ends = <List<int>>[<int>[]];
    List<List<double>> newShadePts() => [for (var i = 0; i < _shades; i++) <double>[]];
    List<List<int>> newShadeEnds() => [for (var i = 0; i < _shades; i++) <int>[]];
    final sPts = <List<List<double>>>[newShadePts()];
    final sEnd = <List<List<int>>>[newShadeEnds()];
    var block = 0;
    Stitch? prev;
    final jumps = <double>[];
    final trims = <double>[];
    const light = 40 * math.pi / 180; // lumière venant du haut à gauche
    for (var i = 0; i < p.stitches.length; i++) {
      final s = p.stitches[i];
      switch (s.type) {
        case StitchType.stitch:
          if (prev != null && prev.isStitch) {
            final x0 = prev.x.toDouble(), y0 = prev.y.toDouble();
            final x1 = s.x.toDouble(), y1 = s.y.toDouble();
            pts[block].addAll([x0, y0, x1, y1]);
            ends[block].add(i);
            final a = math.atan2(y1 - y0, x1 - x0);
            final b = math.cos(a - light).abs();
            final shade = math.min(_shades - 1, (b * _shades).floor());
            sPts[block][shade].addAll([x0, y0, x1, y1]);
            sEnd[block][shade].add(i);
          }
        case StitchType.colorChange:
          block++;
          pts.add(<double>[]);
          ends.add(<int>[]);
          sPts.add(newShadePts());
          sEnd.add(newShadeEnds());
        case StitchType.jump:
          if (prev != null && (prev.x != s.x || prev.y != s.y)) {
            jumps.addAll([prev.x.toDouble(), prev.y.toDouble(), s.x.toDouble(), s.y.toDouble()]);
          }
        case StitchType.trim:
          trims.addAll([s.x.toDouble(), s.y.toDouble()]);
        case StitchType.end:
          break;
      }
      prev = s;
    }
    return PatternGeometry._(
      [for (final l in pts) Float32List.fromList(l)],
      [for (final l in ends) Int32List.fromList(l)],
      [for (final b in sPts) [for (final l in b) Float32List.fromList(l)]],
      [for (final b in sEnd) [for (final l in b) Int32List.fromList(l)]],
      [for (var b = 0; b < pts.length; b++) Color(p.colorOfBlock(b))],
      p.bounds,
      p.stitches,
      Float32List.fromList(jumps),
      Float32List.fromList(trims),
    );
  }

  int get total => stitches.length;
  int segmentsOfBlock(int b) => endIndex[b].length;

  Stitch? get lastStitch {
    for (var i = stitches.length - 1; i >= 0; i--) {
      if (stitches[i].isStitch) return stitches[i];
    }
    return null;
  }
}

int _countUpTo(Int32List ends, int progress) {
  if (ends.isEmpty || ends.last <= progress) return ends.length;
  var lo = 0, hi = ends.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (ends[mid] <= progress) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

Color _shadeOf(Color c, double f) => f < 1
    ? Color.lerp(c, Colors.black, 1 - f)!
    : Color.lerp(c, Colors.white, f - 1)!;

/// Peintre du motif. La progression est une [ValueListenable] : pendant la
/// simulation, seule la toile est redessinée, pas l'écran entier.
class PatternPainter extends CustomPainter {
  final PatternGeometry g;
  final ValueListenable<int>? progress;
  final int? fixedProgress;
  final bool showNeedle;
  final bool realistic;
  final bool showStartEnd;
  final bool showJumps;

  PatternPainter(
    this.g, {
    this.progress,
    this.fixedProgress,
    this.showNeedle = false,
    this.realistic = true,
    this.showStartEnd = false,
    this.showJumps = false,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final prog = progress?.value ?? fixedProgress ?? g.total - 1;
    final b = g.bounds;
    final w = math.max(b.width, 10).toDouble();
    final h = math.max(b.height, 10).toDouble();
    final scale = math.min(size.width / w, size.height / h) * 0.86;
    final cx = size.width / 2, cy = size.height / 2;

    _paintFabric(canvas, size, scale, cx, cy);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale);
    canvas.translate(-(b.minX + b.width / 2), -(b.minY + b.height / 2));

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    for (var k = 0; k < g.points.length; k++) {
      final n = _countUpTo(g.endIndex[k], prog);
      if (n == 0) continue;
      final c = g.colors[k];
      if (!realistic) {
        paint
          ..color = c
          ..strokeWidth = 2.6;
        canvas.drawRawPoints(
            ui.PointMode.lines, Float32List.sublistView(g.points[k], 0, n * 4), paint);
        continue;
      }
      // 1. Ombre portée du fil.
      paint
        ..color = Color.lerp(c, Colors.black, 0.65)!
        ..strokeWidth = 4.4;
      canvas.drawRawPoints(
          ui.PointMode.lines, Float32List.sublistView(g.points[k], 0, n * 4), paint);
      // 2. Corps du fil, nuancé selon l'orientation (reflet satiné).
      paint.strokeWidth = 3.2;
      for (var s = 0; s < _shades; s++) {
        final m = _countUpTo(g.shadeEnd[k][s], prog);
        if (m == 0) continue;
        paint.color = _shadeOf(c, _shadeFactor[s]);
        canvas.drawRawPoints(ui.PointMode.lines,
            Float32List.sublistView(g.shadePoints[k][s], 0, m * 4), paint);
      }
      // 3. Reflet fin sur le dessus du fil.
      canvas.save();
      canvas.translate(-0.45, -0.55);
      paint.strokeWidth = 0.9;
      for (var s = 0; s < _shades; s++) {
        final m = _countUpTo(g.shadeEnd[k][s], prog);
        if (m == 0) continue;
        paint.color = Color.lerp(c, Colors.white, 0.35 + 0.12 * s)!
            .withValues(alpha: 0.35 + 0.15 * s);
        canvas.drawRawPoints(ui.PointMode.lines,
            Float32List.sublistView(g.shadePoints[k][s], 0, m * 4), paint);
      }
      canvas.restore();
    }

    if (showJumps) {
      // Sauts en rouge, coupes marquées d'une croix.
      final jp = Paint()
        ..color = const Color(0xCCFF3B30)
        ..strokeWidth = 1.6 / scale
        ..style = PaintingStyle.stroke;
      canvas.drawRawPoints(ui.PointMode.lines, g.jumpLines, jp);
      final r = 5 / scale;
      for (var i = 0; i + 1 < g.trimPoints.length; i += 2) {
        final x = g.trimPoints[i], y = g.trimPoints[i + 1];
        canvas.drawLine(Offset(x - r, y - r), Offset(x + r, y + r), jp);
        canvas.drawLine(Offset(x - r, y + r), Offset(x + r, y - r), jp);
      }
    }

    if (showStartEnd) {
      final r = 7 / scale;
      canvas.drawCircle(
          Offset.zero,
          r * 1.6,
          Paint()
            ..color = const Color(0xFF4ADE80)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.6);
      final last = g.lastStitch;
      if (last != null) {
        canvas.drawCircle(Offset(last.x.toDouble(), last.y.toDouble()), r,
            Paint()..color = const Color(0xFFF87171));
      }
    }

    if (showNeedle && prog >= 0 && prog < g.total) {
      final s = g.stitches[prog];
      final o = Offset(s.x.toDouble(), s.y.toDouble());
      final r = 7 / scale;
      canvas.drawCircle(o, r * 2.6, Paint()..color = AppColors.gold.withValues(alpha: 0.18));
      canvas.drawCircle(o, r, Paint()..color = AppColors.goldLight);
    }
    canvas.restore();
  }

  /// Tissu sombre avec grille de 1 cm (ou 5 cm si le zoom est faible).
  void _paintFabric(Canvas canvas, Size size, double scale, double cx, double cy) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF1A1A22), Color(0xFF0E0E13)],
          radius: 0.9,
        ).createShader(Offset.zero & size),
    );
    var step = 100 * scale; // 10 mm
    if (step < 10) step *= 5;
    if (step < 4) return;
    final grid = Paint()
      ..color = const Color(0x12FFFFFF)
      ..strokeWidth = 1;
    for (var x = cx % step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = cy % step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final axis = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), axis);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), axis);
  }

  @override
  bool shouldRepaint(PatternPainter old) =>
      old.g != g ||
      old.progress != progress ||
      old.fixedProgress != fixedProgress ||
      old.showNeedle != showNeedle ||
      old.realistic != realistic ||
      old.showStartEnd != showStartEnd ||
      old.showJumps != showJumps;
}
