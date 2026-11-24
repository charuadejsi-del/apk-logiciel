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

  /// Construction en deux passes sur des tableaux typés (aucune liste de
  /// doubles intermédiaire) : rapide même avec plusieurs centaines de milliers de points.
  factory PatternGeometry.from(EmbPattern p) {
    final st = p.stitches;
    const light = 40 * math.pi / 180; // lumière venant du haut à gauche
    final cl = math.cos(light), sl = math.sin(light);
    int shadeOf(Stitch a, Stitch b) {
      final dx = (b.x - a.x).toDouble(), dy = (b.y - a.y).toDouble();
      final d = math.sqrt(dx * dx + dy * dy);
      if (d == 0) return _shades - 1;
      final c = ((dx * cl + dy * sl) / d).abs(); // |cos(angle - lumière)|
      return math.min(_shades - 1, (c * _shades).floor());
    }

    // 1. Comptage.
    final segCount = <int>[0];
    final shadeCount = <List<int>>[List<int>.filled(_shades, 0)];
    var nJumps = 0, nTrims = 0;
    var block = 0;
    for (var i = 1; i <= st.length; i++) {
      final s = st[i - 1];
      if (s.type == StitchType.colorChange) {
        block++;
        segCount.add(0);
        shadeCount.add(List<int>.filled(_shades, 0));
      } else if (s.type == StitchType.trim) {
        nTrims++;
      }
      if (i == st.length) break;
      final n = st[i];
      if (n.type == StitchType.stitch && s.isStitch) {
        segCount[block]++;
        shadeCount[block][shadeOf(s, n)]++;
      } else if (n.type == StitchType.jump && (s.x != n.x || s.y != n.y)) {
        nJumps++;
      }
    }
    // 2. Remplissage.
    final pts = [for (final c in segCount) Float32List(c * 4)];
    final ends = [for (final c in segCount) Int32List(c)];
    final sPts = [
      for (final b in shadeCount) [for (final c in b) Float32List(c * 4)]
    ];
    final sEnd = [
      for (final b in shadeCount) [for (final c in b) Int32List(c)]
    ];
    final fill = List<int>.filled(segCount.length, 0);
    final sFill = [for (final _ in segCount) List<int>.filled(_shades, 0)];
    final jumps = Float32List(nJumps * 4);
    final trims = Float32List(nTrims * 2);
    var ji = 0, ti = 0;
    block = 0;
    Stitch? prev;
    for (var i = 0; i < st.length; i++) {
      final s = st[i];
      switch (s.type) {
        case StitchType.stitch:
          if (prev != null && prev.isStitch) {
            final x0 = prev.x.toDouble(), y0 = prev.y.toDouble();
            final x1 = s.x.toDouble(), y1 = s.y.toDouble();
            final k = fill[block]++;
            final pb = pts[block];
            pb[k * 4] = x0;
            pb[k * 4 + 1] = y0;
            pb[k * 4 + 2] = x1;
            pb[k * 4 + 3] = y1;
            ends[block][k] = i;
            final sh = shadeOf(prev, s);
            final m = sFill[block][sh]++;
            final sp = sPts[block][sh];
            sp[m * 4] = x0;
            sp[m * 4 + 1] = y0;
            sp[m * 4 + 2] = x1;
            sp[m * 4 + 3] = y1;
            sEnd[block][sh][m] = i;
          }
        case StitchType.colorChange:
          block++;
        case StitchType.jump:
          if (prev != null && (prev.x != s.x || prev.y != s.y)) {
            jumps[ji++] = prev.x.toDouble();
            jumps[ji++] = prev.y.toDouble();
            jumps[ji++] = s.x.toDouble();
            jumps[ji++] = s.y.toDouble();
          }
        case StitchType.trim:
          trims[ti++] = s.x.toDouble();
          trims[ti++] = s.y.toDouble();
        case StitchType.end:
          break;
      }
      prev = s;
    }
    return PatternGeometry._(
      pts,
      ends,
      sPts,
      sEnd,
      [for (var b = 0; b < pts.length; b++) Color(p.colorOfBlock(b))],
      p.bounds,
      st,
      jumps,
      trims,
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

  /// Image déjà dessinée du motif complet, par géométrie : zoomer, déplacer
  /// ou reconstruire l'écran ne redessine plus des centaines de milliers de
  /// points, on affiche simplement l'image.
  static final Expando<_RasterCache> _cache = Expando<_RasterCache>();

  @override
  void paint(Canvas canvas, Size size) {
    final prog = progress?.value ?? fixedProgress ?? g.total - 1;
    final full = prog >= g.total - 1 && !showNeedle;
    if (full && size.width >= 1 && size.height >= 1) {
      final key = '${size.width.round()}x${size.height.round()}/$realistic/$showJumps/$showStartEnd';
      var c = _cache[g];
      if (c == null || c.key != key) {
        final dpr = ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
        // Résolution doublée pour rester net au zoom, plafonnée (mémoire).
        final q = math.min(dpr * 2, 3072 / math.max(size.width, size.height));
        final rec = ui.PictureRecorder();
        final cc = Canvas(rec);
        cc.scale(q);
        _paintAll(cc, size, prog, realistic);
        final pic = rec.endRecording();
        final img = pic.toImageSync((size.width * q).ceil(), (size.height * q).ceil());
        pic.dispose();
        c?.image.dispose();
        c = _RasterCache(key, img);
        _cache[g] = c;
      }
      canvas.drawImageRect(
        c.image,
        Rect.fromLTWH(0, 0, c.image.width.toDouble(), c.image.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }
    // Simulation en cours : rendu simple (une passe au lieu de neuf), fluide.
    _paintAll(canvas, size, prog, realistic && !showNeedle);
  }

  void _paintAll(Canvas canvas, Size size, int prog, bool realistic) {
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

class _RasterCache {
  final String key;
  final ui.Image image;
  _RasterCache(this.key, this.image);
}
