import 'dart:typed_data';

import 'package:broderie/core/demo.dart';
import 'package:broderie/core/dst.dart';
import 'package:broderie/core/edits.dart';
import 'package:broderie/core/pattern.dart';
import 'package:broderie/core/pes.dart';
import 'package:flutter_test/flutter_test.dart';

List<(int, int)> stitchPoints(EmbPattern p) =>
    [for (final s in p.stitches) if (s.isStitch) (s.x, s.y)];

void main() {
  test('chaque déplacement DST se code et se décode à l\'identique', () {
    for (var dx = -121; dx <= 121; dx++) {
      for (var dy = -121; dy <= 121; dy += 7) {
        final r = encodeDstRecord(dx, dy, 0);
        expect(decodeDstMove(r[0], r[1], r[2]), (dx, dy));
        expect(r[2] & 0x03, 0x03);
      }
    }
  });

  test('aller-retour DST du motif de démonstration', () {
    final demo = demoPattern();
    final bytes = writeDst(demo);
    expect(bytes.length % 3, 512 % 3);
    expect(String.fromCharCodes(bytes.sublist(0, 3)), 'LA:');
    final back = readDst(bytes);
    expect(back.name, 'DEMO');
    expect(stitchPoints(back), stitchPoints(demo));
    expect(back.colorChangeCount, demo.colorChangeCount);
  });

  test('les longs déplacements sont découpés', () {
    final p = EmbPattern(name: 'long', stitches: const [
      Stitch(0, 0, StitchType.stitch),
      Stitch(1000, -600, StitchType.jump),
      Stitch(1000, -600, StitchType.stitch),
      Stitch(1000, -600, StitchType.end),
    ]);
    final back = readDst(writeDst(p));
    expect(stitchPoints(back), [(0, 0), (1000, -600)]);
  });

  test('décodage des points PEC (forme courte et longue)', () {
    final d = Uint8List.fromList([
      0x05, 0x7D, // +5, -3
      0x90, 0x64, 0x05, // saut long : x = +100, y = +5
      0xFE, 0xB0, 0x02, // changement de couleur
      0xFF, 0x00,
    ]);
    final s = decodePecStitches(d, 0);
    expect((s[0].x, s[0].y, s[0].type), (5, -3, StitchType.stitch));
    expect((s[1].x, s[1].y, s[1].type), (105, 2, StitchType.jump));
    expect(s[2].type, StitchType.colorChange);
    expect(s.last.type, StitchType.end);
  });

  test('suppression des petits points', () {
    final p = EmbPattern(name: 't', stitches: const [
      Stitch(0, 0, StitchType.stitch),
      Stitch(2, 0, StitchType.stitch), // 0,2 mm : supprimé
      Stitch(30, 0, StitchType.stitch),
      Stitch(31, 0, StitchType.stitch), // dernier du segment : gardé
      Stitch(31, 0, StitchType.end),
    ]);
    expect(countSmallStitches(p, 0.4), 1);
    final r = removeSmallStitches(p, 0.4);
    expect(stitchPoints(r.pattern), [(0, 0), (30, 0), (31, 0)]);
  });
}
