import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/pattern.dart';

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

  PatternPainter(this.g, this.progress, {this.showNeedle = false});

  @override
  void paint(Canvas canvas, Size size) {
    final b = g.bounds;
    final w = math.max(b.width, 10).toDouble();
    final h = math.max(b.height, 10).toDouble();
    final scale = math.min(size.width / w, size.height / h) * 0.9;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-(b.minX + b.width / 2), -(b.minY + b.height / 2));

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < g.points.length; k++) {
      final n = _countUpTo(g.endIndex[k], progress);
      if (n == 0) continue;
      paint.color = g.colors[k];
      canvas.drawRawPoints(
          ui.PointMode.lines, Float32List.sublistView(g.points[k], 0, n * 4), paint);
    }

    if (showNeedle && progress >= 0 && progress < g.total) {
      final s = g.stitches[progress];
      canvas.drawCircle(
        Offset(s.x.toDouble(), s.y.toDouble()),
        6 / scale * 2,
        Paint()..color = Colors.white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PatternPainter old) =>
      old.g != g || old.progress != progress || old.showNeedle != showNeedle;
}
