import 'dart:math' as math;

import 'pattern.dart';

/// Motif de démonstration : un remplissage rectangulaire puis un anneau en satin.
EmbPattern demoPattern() {
  final s = <Stitch>[];
  const w = 400, h = 250; // 40 x 25 mm
  var row = 0;
  for (var y = 0; y <= h; y += 4) {
    final xs = <int>[for (var k = 0; k < w; k += 30) k, w];
    final line = row.isEven ? xs : xs.reversed.toList();
    for (final x in line) {
      s.add(Stitch(x - w ~/ 2, y - h ~/ 2, StitchType.stitch));
    }
    row++;
  }
  s.add(Stitch(s.last.x, s.last.y, StitchType.trim));

  const cx = 340, cy = 0, rOut = 110, rIn = 80, steps = 180;
  s.add(Stitch(cx + rOut, cy, StitchType.colorChange));
  for (var i = 0; i <= steps; i++) {
    final a = 2 * math.pi * i / steps;
    final r = i.isEven ? rOut : rIn;
    s.add(Stitch(cx + (r * math.cos(a)).round(), cy + (r * math.sin(a)).round(),
        StitchType.stitch));
  }
  s.add(Stitch(s.last.x, s.last.y, StitchType.end));
  return EmbPattern(name: 'DEMO', stitches: s);
}
