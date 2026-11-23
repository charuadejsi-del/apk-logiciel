import 'dart:typed_data';

import 'package:broderie/core/demo.dart';
import 'package:broderie/core/dst.dart';
import 'package:broderie/core/edits.dart';
import 'package:broderie/core/pattern.dart';
import 'package:broderie/core/pes.dart';
import 'package:broderie/core/font_block.dart';
import 'package:broderie/core/text_engine.dart';
import 'package:broderie/core/transform.dart';
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

  test('chaque caractère de la police se brode', () {
    for (final c in blockFont.keys.where((k) => k != ' ')) {
      final p = TextDesign(text: c, heightMm: 20).generate();
      expect(p.stitchCount, greaterThan(15), reason: 'caractère $c');
      for (final s in p.stitches) {
        expect(s.x.isFinite && s.y.isFinite, isTrue);
      }
    }
  });

  test('texte : hauteur respectée, centré, aller-retour DST', () {
    const d = TextDesign(text: 'FARES 2026', heightMm: 25);
    final p = d.generate();
    expect(d.unsupported, isEmpty);
    expect(p.heightMm, closeTo(25, 2.5));
    final b = p.bounds;
    expect(((b.minX + b.maxX) / 2).abs(), lessThan(20));
    expect(((b.minY + b.maxY) / 2).abs(), lessThan(20));
    final none = d.copyWith(trimMode: TrimMode.none).generate();
    expect(none.trimCount, 1); // une seule coupe, à la fin
    final all = d.copyWith(trimMode: TrimMode.all).generate();
    expect(all.trimCount, greaterThanOrEqualTo(9));
    final auto30 = d.copyWith(trimMode: TrimMode.auto, jumpMaxMm: 30).generate();
    expect(auto30.trimCount, lessThan(all.trimCount));
    final back = readDst(writeDst(p));
    expect(back.stitchCount, p.stitchCount);
  });

  test('texte : densité et taille recalculées', () {
    final a = const TextDesign(text: 'AB', autoDensity: false, densityMm: 0.4).generate();
    final b = const TextDesign(text: 'AB', autoDensity: false, densityMm: 0.6).generate();
    expect(b.stitchCount, lessThan(a.stitchCount));
    final big = const TextDesign(text: 'AB', heightMm: 40).generate();
    expect(big.heightMm, closeTo(40, 4));
  });

  test('chaque lettre se brode d\'un seul tenant : ni saut ni coupe à l\'intérieur', () {
    for (final c in blockFont.keys.where((k) => k != ' ')) {
      final p = TextDesign(text: c, heightMm: 20).generate();
      expect(p.jumpCount, 1, reason: 'sauts dans $c');
      expect(p.trimCount, 1, reason: 'coupes dans $c');
      Stitch? prev;
      var longest = 0.0;
      for (final s in p.stitches) {
        if (s.isStitch && prev != null && prev.isStitch) {
          final l = distance(prev, s);
          if (l > longest) longest = l;
        }
        prev = s;
      }
      expect(longest, lessThan(80), reason: 'point trop long dans $c');
    }
  });

  test('mot sans coupe : un saut par lettre, une seule coupe finale', () {
    final p = const TextDesign(text: 'FARES', trimMode: TrimMode.none).generate();
    expect(p.jumpCount, 5);
    expect(p.trimCount, 1);
  });

  test('caractères non pris en charge signalés', () {
    expect(const TextDesign(text: 'A@b').unsupported, ['@']);
  });

  test('taille d\'un fichier en points', () {
    final demo = demoPattern();
    final up = scalePattern(demo, 1.1).pattern;
    expect(up.widthMm, closeTo(demo.widthMm * 1.1, 0.5));
    final down = scalePattern(demo, 0.9).pattern;
    expect(down.widthMm, closeTo(demo.widthMm * 0.9, 0.5));
    final long = EmbPattern(name: 'l', stitches: const [
      Stitch(0, 0, StitchType.stitch),
      Stitch(200, 0, StitchType.stitch),
      Stitch(200, 0, StitchType.end),
    ]);
    final r = splitLongStitches(long, 8);
    expect(r.removed, 2);
  });

  test('allègement de densité du satin', () {
    final s = <Stitch>[];
    for (var i = 0; i < 100; i++) {
      s.add(Stitch(i * 2, i.isEven ? 0 : 30, StitchType.stitch)); // écart 0,2 mm
    }
    s.add(const Stitch(198, 30, StitchType.end));
    final p = EmbPattern(name: 's', stitches: s);
    expect(estimateSatinDensity(p), closeTo(0.2, 0.01));
    final r = thinDensity(p, 0.4);
    expect(r.removed, greaterThan(40));
    final est = estimateSatinDensity(r.pattern);
    expect(est, isNotNull);
    expect(est!, greaterThanOrEqualTo(0.38));
  });

  test('point de départ et retour', () {
    final p = demoPattern();
    final c = applyStart(p, StartAnchor.topLeft);
    expect(c.bounds.minX, 0);
    expect(c.bounds.minY, 0);
    final r = applyStart(p, StartAnchor.center, returnToStart: true);
    final last = r.stitches[r.stitches.length - 2];
    expect((last.x, last.y, last.type), (0, 0, StitchType.jump));
  });
}
