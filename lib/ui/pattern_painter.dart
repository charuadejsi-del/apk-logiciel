import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/pattern.dart';
import 'theme.dart';

/// Géométrie pré-calculée : segments cousus regroupés par bloc de couleur.
class PatternGeometry {
  final List<Float32List> points; // 4 valeurs par segment
  final List<Int32List> endIndex; // index de l'instruction qui termine le segment
  final List<Color> colors;
  final Bounds bounds;
  final List<Stitch> stitches;

  PatternGeometry._(this.points, this.endIndex, this.colors, this.bounds, this.stitches);

  factory PatternGeometry.from(EmbPattern p) {
    final pts = <List<double>>[<double>[]];
    final ends = <List<int>>[<int>[]];
    var block = 0;
    Stitch? prev;
    for (var i = 0; i < p.stitches.length; i++) {
      final s = p.stitches[i];
      switch (s.type) {
        case StitchType.stitch:
          if (prev != null && prev.isStitch) {
            pts[block].addAll([
              prev.x.toDouble(), prev.y.toDouble(), s.x.toDouble(), s.y.toDouble()
            ]);
            ends[block].add(i);
          }
        case StitchType.colorChange:
          block++;
          pts.add(<double>[]);
          ends.add(<int>[]);
        case StitchType.jump:
        case StitchType.trim:
        case StitchType.end:
          break;
      }
      prev = s;
    }
    return PatternGeometry._(
      [for (final l in pts) Float32List.fromList(l)],
      [for (final l in ends) Int32List.fromList(l)],
      [for (var b = 0; b < pts.length; b++) Color(p.colorOfBlock(b))],
      p.bounds,
      p.stitches,
    );
  }

  int get total => stitches.length;

  Stitch? get lastStitch {
    for (var i = stitches.length - 1; i >= 0; i--) {
      if (stitches[i].isStitch) return stitches[i];
    }
    return null;
  }
  int segmentsOfBlock(int b) => endIndex[b].length;
}

int _countUpTo(Int32List ends, int progress) {
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

class PatternPainter extends CustomPainter {
  final PatternGeometry g;
  final int progress; // index de la dernière instruction affichée
  final bool showNeedle;
  final bool realistic;
  final bool showStartEnd;

  PatternPainter(this.g, this.progress,
      {this.showNeedle = false, this.realistic = true, this.showStartEnd = false});

  @override
  void paint(Canvas canvas, Size size) {
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
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < g.points.length; k++) {
      final n = _countUpTo(g.endIndex[k], progress);
      if (n == 0) continue;
      final pts = Float32List.sublistView(g.points[k], 0, n * 4);
      final c = g.colors[k];
      if (realistic) {
        // Ombre du fil, corps, puis reflet : effet de fil brodé.
        paint
          ..color = Color.lerp(c, Colors.black, 0.6)!
          ..strokeWidth = 4.6;
        canvas.drawRawPoints(ui.PointMode.lines, pts, paint);
        paint
          ..color = c
          ..strokeWidth = 3.4;
        canvas.drawRawPoints(ui.PointMode.lines, pts, paint);
        canvas.save();
        canvas.translate(-0.5, -0.6);
        paint
          ..color = Color.lerp(c, Colors.white, 0.5)!.withValues(alpha: 0.75)
          ..strokeWidth = 1.1;
        canvas.drawRawPoints(ui.PointMode.lines, pts, paint);
        canvas.restore();
      } else {
        paint
          ..color = c
          ..strokeWidth = 2.4;
        canvas.drawRawPoints(ui.PointMode.lines, pts, paint);
      }
    }

    if (showStartEnd) {
      final r = 7 / scale;
      // Départ (origine machine) : anneau vert. Fin : point rouge.
      canvas.drawCircle(Offset.zero, r * 1.6,
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

    if (showNeedle && progress >= 0 && progress < g.total) {
      final s = g.stitches[progress];
      final o = Offset(s.x.toDouble(), s.y.toDouble());
      final r = 7 / scale;
      canvas.drawCircle(o, r * 2.6,
          Paint()..color = AppColors.gold.withValues(alpha: 0.18));
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
      old.showNeedle != showNeedle ||
      old.realistic != realistic ||
      old.showStartEnd != showStartEnd;
}
