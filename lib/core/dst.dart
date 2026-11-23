import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'pattern.dart';

/// Format Tajima DST : en-tête de 512 octets puis enregistrements de 3 octets.
/// Déplacement maximal par enregistrement : ±121 (12,1 mm). Axe Y du fichier vers le haut.

const int _flagStitch = 0;
const int _flagJump = 1;
const int _flagColor = 2;
const int maxDstMove = 121;

int _bit(int n) => 1 << n;

/// Encode un déplacement relatif (dx, dy en coordonnées écran, Y vers le bas).
List<int> encodeDstRecord(int dx, int dy, int flag) {
  if (dx.abs() > maxDstMove || dy.abs() > maxDstMove) {
    throw ArgumentError('Déplacement DST hors limites: $dx, $dy');
  }
  var x = dx;
  var y = -dy;
  var b0 = 0, b1 = 0, b2 = 0x03;
  if (flag == _flagJump) b2 |= _bit(7);
  if (flag == _flagColor) b2 |= _bit(7) | _bit(6);

  if (x > 40) { b2 |= _bit(2); x -= 81; }
  if (x < -40) { b2 |= _bit(3); x += 81; }
  if (x > 13) { b1 |= _bit(2); x -= 27; }
  if (x < -13) { b1 |= _bit(3); x += 27; }
  if (x > 4) { b0 |= _bit(2); x -= 9; }
  if (x < -4) { b0 |= _bit(3); x += 9; }
  if (x > 1) { b1 |= _bit(0); x -= 3; }
  if (x < -1) { b1 |= _bit(1); x += 3; }
  if (x > 0) { b0 |= _bit(0); x -= 1; }
  if (x < 0) { b0 |= _bit(1); x += 1; }

  if (y > 40) { b2 |= _bit(5); y -= 81; }
  if (y < -40) { b2 |= _bit(4); y += 81; }
  if (y > 13) { b1 |= _bit(5); y -= 27; }
  if (y < -13) { b1 |= _bit(4); y += 27; }
  if (y > 4) { b0 |= _bit(5); y -= 9; }
  if (y < -4) { b0 |= _bit(4); y += 9; }
  if (y > 1) { b1 |= _bit(7); y -= 3; }
  if (y < -1) { b1 |= _bit(6); y += 3; }
  if (y > 0) { b0 |= _bit(7); y -= 1; }
  if (y < 0) { b0 |= _bit(6); y += 1; }
  return [b0, b1, b2];
}

bool _on(int b, int n) => (b & _bit(n)) != 0;

/// Décode un enregistrement : renvoie (dx, dy) en coordonnées écran.
(int, int) decodeDstMove(int b0, int b1, int b2) {
  var x = 0, y = 0;
  if (_on(b0, 0)) x += 1;
  if (_on(b0, 1)) x -= 1;
  if (_on(b0, 2)) x += 9;
  if (_on(b0, 3)) x -= 9;
  if (_on(b1, 0)) x += 3;
  if (_on(b1, 1)) x -= 3;
  if (_on(b1, 2)) x += 27;
  if (_on(b1, 3)) x -= 27;
  if (_on(b2, 2)) x += 81;
  if (_on(b2, 3)) x -= 81;

  if (_on(b0, 7)) y += 1;
  if (_on(b0, 6)) y -= 1;
  if (_on(b0, 5)) y += 9;
  if (_on(b0, 4)) y -= 9;
  if (_on(b1, 7)) y += 3;
  if (_on(b1, 6)) y -= 3;
  if (_on(b1, 5)) y += 27;
  if (_on(b1, 4)) y -= 27;
  if (_on(b2, 5)) y += 81;
  if (_on(b2, 4)) y -= 81;
  return (x, -y);
}

EmbPattern readDst(Uint8List data, {String name = 'design'}) {
  if (data.length < 512) {
    throw const FormatException('Fichier DST invalide (moins de 512 octets).');
  }
  final header = latin1.decode(data.sublist(0, 512), allowInvalid: true);
  var label = name;
  final m = RegExp(r'LA:([^\r\n]*)').firstMatch(header);
  if (m != null && m.group(1)!.trim().isNotEmpty) label = m.group(1)!.trim();

  final out = <Stitch>[];
  var x = 0, y = 0;
  for (var i = 512; i + 2 < data.length; i += 3) {
    final b0 = data[i], b1 = data[i + 1], b2 = data[i + 2];
    if ((b2 & 0xF3) == 0xF3) break;
    final (dx, dy) = decodeDstMove(b0, b1, b2);
    x += dx;
    y += dy;
    if ((b2 & 0xC3) == 0xC3) {
      out.add(Stitch(x, y, StitchType.colorChange));
    } else if (_on(b2, 7)) {
      out.add(Stitch(x, y, StitchType.jump));
    } else {
      out.add(Stitch(x, y, StitchType.stitch));
    }
  }
  out.add(Stitch(x, y, StitchType.end));
  return EmbPattern(name: label, stitches: out);
}

Uint8List writeDst(EmbPattern pattern) {
  final body = BytesBuilder();
  var cx = 0, cy = 0, records = 0;

  void rec(int dx, int dy, int flag) {
    body.add(encodeDstRecord(dx, dy, flag));
    records++;
  }

  void moveTo(int tx, int ty, int flag) {
    while (true) {
      final dx = tx - cx, dy = ty - cy;
      // Pas d'enregistrement de saut vide (certains logiciels les refusent).
      if (flag == _flagJump && dx == 0 && dy == 0) return;
      if (dx.abs() <= maxDstMove && dy.abs() <= maxDstMove) {
        rec(dx, dy, flag);
        cx = tx;
        cy = ty;
        return;
      }
      final steps = (math.max(dx.abs(), dy.abs()) / maxDstMove).ceil();
      final sx = (dx / steps).round(), sy = (dy / steps).round();
      // Les morceaux intermédiaires d'un long déplacement sont des sauts ;
      // seul le dernier morceau pique (pas de faux points).
      rec(sx, sy, _flagJump);
      cx += sx;
      cy += sy;
    }
  }

  var needJump = true; // début du motif, ou après une coupe / un changement de couleur
  for (final s in pattern.stitches) {
    switch (s.type) {
      case StitchType.stitch:
        if (needJump && (s.x != cx || s.y != cy)) {
          // Ne jamais tirer un point depuis l'origine ou après une coupe : on saute d'abord.
          moveTo(s.x, s.y, _flagJump);
          rec(0, 0, _flagStitch);
        } else {
          moveTo(s.x, s.y, _flagStitch);
        }
        needJump = false;
      case StitchType.jump:
        moveTo(s.x, s.y, _flagJump);
      case StitchType.trim:
        // Coupe = 3 petits sauts qui reviennent au même point (convention Tajima).
        rec(2, 2, _flagJump);
        rec(-4, -4, _flagJump);
        rec(2, 2, _flagJump);
        moveTo(s.x, s.y, _flagJump);
        needJump = true;
      case StitchType.colorChange:
        moveTo(s.x, s.y, _flagJump);
        rec(0, 0, _flagColor);
        needJump = true;
      case StitchType.end:
        break;
    }
  }
  body.add(const [0x00, 0x00, 0xF3]);

  final b = pattern.bounds;
  final header = StringBuffer()
    ..write('LA:${_ascii(pattern.name).padRight(16).substring(0, 16)}\r')
    ..write('ST:${records.toString().padLeft(7)}\r')
    ..write('CO:${pattern.colorChangeCount.toString().padLeft(3)}\r')
    ..write('+X:${math.max(0, b.maxX).toString().padLeft(5)}\r')
    ..write('-X:${math.max(0, -b.minX).toString().padLeft(5)}\r')
    ..write('+Y:${math.max(0, -b.minY).toString().padLeft(5)}\r')
    ..write('-Y:${math.max(0, b.maxY).toString().padLeft(5)}\r')
    ..write('AX:${_signed(cx)}\r')
    ..write('AY:${_signed(-cy)}\r')
    ..write('MX:+    0\r')
    ..write('MY:+    0\r')
    ..write('PD:******\r');
  final head = Uint8List(512)..fillRange(0, 512, 0x20);
  final hb = latin1.encode(header.toString());
  head.setRange(0, hb.length, hb);
  head[hb.length] = 0x1A;

  return (BytesBuilder()
        ..add(head)
        ..add(body.takeBytes()))
      .takeBytes();
}

String _signed(int v) => '${v < 0 ? '-' : '+'}${v.abs().toString().padLeft(5)}';

String _ascii(String s) =>
    String.fromCharCodes(s.runes.map((r) => (r >= 32 && r < 127) ? r : 0x5F));
