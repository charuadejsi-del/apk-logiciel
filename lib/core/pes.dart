import 'dart:math' as math;
import 'dart:typed_data';

import 'pattern.dart';

/// Lecture des formats Brother PES (via sa section PEC) et PEC.
/// L'écriture PES viendra dans une étape suivante.

EmbPattern readPes(Uint8List data, {String name = 'design'}) {
  if (data.length < 12 || String.fromCharCodes(data.sublist(0, 4)) != '#PES') {
    throw const FormatException('Fichier PES invalide.');
  }
  final pecStart = ByteData.sublistView(data).getUint32(8, Endian.little);
  if (pecStart <= 0 || pecStart >= data.length) {
    throw const FormatException('Section PEC introuvable dans le fichier PES.');
  }
  return _readPecBlock(data, pecStart, name);
}

EmbPattern readPec(Uint8List data, {String name = 'design'}) {
  if (data.length < 8 || String.fromCharCodes(data.sublist(0, 8)) != '#PEC0001') {
    throw const FormatException('Fichier PEC invalide.');
  }
  return _readPecBlock(data, 8, name);
}

EmbPattern _readPecBlock(Uint8List d, int start, String fallbackName) {
  var p = start;
  if (p + 512 + 20 > d.length) {
    throw const FormatException('Section PEC tronquée.');
  }
  p += 3; // "LA:"
  final label = String.fromCharCodes(d.sublist(p, p + 16)).trim();
  p += 16;
  p += 0xF; // octets réservés
  p += 2; // largeur et hauteur de l'icône
  p += 0xC;
  final colorChanges = d[p];
  p += 1;
  final colors = <int>[];
  for (var i = 0; i <= colorChanges; i++) {
    final idx = d[p + i];
    colors.add(pecPalette[idx < pecPalette.length ? idx : 0]);
  }
  p += colorChanges + 1;
  p += 0x1D0 - colorChanges;
  // Taille du bloc de points (entier 24 bits) puis en-tête graphique.
  p += 3;
  p += 0x0B;
  final stitches = decodePecStitches(d, p);
  return EmbPattern(
    name: label.isEmpty ? fallbackName : label,
    stitches: stitches,
    colors: colors,
  );
}

/// Décode les points PEC à partir de l'offset [p].
List<Stitch> decodePecStitches(Uint8List d, int p) {
  final out = <Stitch>[];
  var x = 0, y = 0;
  int next() {
    if (p >= d.length) throw const FormatException('Points PEC tronqués.');
    return d[p++];
  }

  while (p + 1 < d.length) {
    final v1 = next();
    var v2 = next();
    if (v1 == 0xFF && v2 == 0x00) break;
    if (v1 == 0xFE && v2 == 0xB0) {
      next();
      out.add(Stitch(x, y, StitchType.colorChange));
      continue;
    }
    var jump = false, trim = false;
    int dx, dy;
    if ((v1 & 0x80) != 0) {
      if ((v1 & 0x20) != 0) trim = true;
      if ((v1 & 0x10) != 0) jump = true;
      dx = ((v1 << 8) | v2) & 0xFFF;
      if (dx > 0x7FF) dx -= 0x1000;
      v2 = next();
    } else {
      dx = v1;
      if (dx > 0x3F) dx -= 0x80;
    }
    if ((v2 & 0x80) != 0) {
      if ((v2 & 0x20) != 0) trim = true;
      if ((v2 & 0x10) != 0) jump = true;
      dy = ((v2 << 8) | next()) & 0xFFF;
      if (dy > 0x7FF) dy -= 0x1000;
    } else {
      dy = v2;
      if (dy > 0x3F) dy -= 0x80;
    }
    x += dx;
    y += dy;
    if (trim) {
      out.add(Stitch(x, y, StitchType.trim));
    } else if (jump) {
      out.add(Stitch(x, y, StitchType.jump));
    } else {
      out.add(Stitch(x, y, StitchType.stitch));
    }
  }
  out.add(Stitch(x, y, StitchType.end));
  return out;
}

/// Palette standard des fils Brother (index PEC).
const List<int> pecPalette = [
  0xFF000000, 0xFF0E1F7C, 0xFF0A55A3, 0xFF308777, 0xFF4B6BAF, 0xFFED171F,
  0xFFD15C00, 0xFF913697, 0xFFE49ACB, 0xFF915FAC, 0xFF9ED67D, 0xFFE8A900,
  0xFFFEBA35, 0xFFFFFF00, 0xFF70BC1F, 0xFFBA9800, 0xFFA8A8A8, 0xFF7D6F00,
  0xFFFFFFB3, 0xFF4F5556, 0xFF000000, 0xFF0B3D91, 0xFF770176, 0xFF293133,
  0xFF2A1301, 0xFFF64A8A, 0xFFB27624, 0xFFFCBBC5, 0xFFFE370F, 0xFFF0F0F0,
  0xFF6A1C8A, 0xFFA8DDC4, 0xFF2584BB, 0xFFFEB343, 0xFFFFF36B, 0xFFD0A660,
  0xFFD15400, 0xFF66BA49, 0xFF134A46, 0xFF878787, 0xFFD8CCC6, 0xFF435607,
  0xFFFDD9DE, 0xFFF993BC, 0xFF003822, 0xFFB2AFD4, 0xFF686AB0, 0xFFEFE3B9,
  0xFFF73866, 0xFFB54B64, 0xFF132B1A, 0xFFC70156, 0xFFFE9E32, 0xFFA8DEEB,
  0xFF00673E, 0xFF4E2990, 0xFF2F7E20, 0xFFFFCCCC, 0xFFFFD911, 0xFF095BA6,
  0xFFF0F970, 0xFFE3F35B, 0xFFFF9900, 0xFFFFF08D, 0xFFFFC8C8,
];

// ───────────────────────── Écriture PES (Brother) ─────────────────────────

/// Fil le plus proche dans la palette Brother.
int nearestPecIndex(int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  var best = 1, bestD = 1 << 30;
  for (var i = 1; i < pecPalette.length; i++) {
    final c = pecPalette[i];
    final dr = r - ((c >> 16) & 0xFF), dg = g - ((c >> 8) & 0xFF), db = b - (c & 0xFF);
    // Distance pondérée (l'œil est plus sensible au vert).
    final d = 2 * dr * dr + 4 * dg * dg + 3 * db * db;
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// Fichier PES (version 1 courte) : en-tête PES puis bloc PEC, que lisent les
/// machines Brother. Unités 0,1 mm, Y vers le bas.
Uint8List writePes(EmbPattern pattern) {
  final out = BytesBuilder();
  out.add('#PES0001'.codeUnits);
  out.add(const [0x16, 0x00, 0x00, 0x00]); // le bloc PEC commence à l'octet 22
  out.add(List<int>.filled(10, 0));
  out.add(_pecBlock(pattern));
  return out.toBytes();
}

Uint8List _pecBlock(EmbPattern p) {
  final h = BytesBuilder();
  var label = p.name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9 _-]'), '');
  if (label.length > 8) label = label.substring(0, 8);
  h.add('LA:${label.padRight(16)}\r'.codeUnits);
  h.add(List<int>.filled(12, 0x20));
  h.add(const [0xFF, 0x00]);
  h.add(const [6, 38]); // icône 48 × 38 points
  h.add(const [0x20, 0x20, 0x20, 0x20, 0x64, 0x20, 0x00, 0x20, 0x00, 0x20, 0x20, 0x20]);
  final n = p.colorBlockCount;
  h.add([n - 1]);
  for (var i = 0; i < n; i++) {
    h.add([nearestPecIndex(p.colorOfBlock(i))]);
  }
  h.add(List<int>.filled(463 - n, 0x20));
  final header = h.toBytes();
  assert(header.length == 512);

  final st = _pecStitches(p);
  final b = p.bounds;
  final blockLen = 16 + st.length;
  final blk = BytesBuilder()
    ..add(const [0x00, 0x00])
    ..add([blockLen & 0xFF, (blockLen >> 8) & 0xFF, (blockLen >> 16) & 0xFF])
    ..add(const [0x31, 0xFF, 0xF0])
    ..add(_i16(b.width))
    ..add(_i16(b.height))
    ..add(_i16(0x1E0))
    ..add(_i16(0x1B0))
    ..add(st);
  // Icônes (vue d'ensemble + une par couleur) : laissées vides.
  final icons = List<int>.filled(228 * (n + 1), 0);
  return (BytesBuilder()
        ..add(header)
        ..add(blk.toBytes())
        ..add(icons))
      .toBytes();
}

List<int> _i16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

Uint8List _pecStitches(EmbPattern p) {
  final o = BytesBuilder();
  var x = 0, y = 0;
  var colorTwo = true;
  void long(int dx, int dy, int flag) {
    final a = (dx & 0x0FFF) | 0x8000 | (flag << 8), c = (dy & 0x0FFF) | 0x8000 | (flag << 8);
    o.add([(a >> 8) & 0xFF, a & 0xFF, (c >> 8) & 0xFF, c & 0xFF]);
  }

  void move(int tx, int ty, int flag) {
    // Déplacements de plus de 204,7 mm : découpés.
    while (true) {
      final dx = tx - x, dy = ty - y;
      final steps = math.max(1, (math.max(dx.abs(), dy.abs()) / 2000).ceil());
      final sx = (dx / steps).round(), sy = (dy / steps).round();
      if (flag == 0 && steps == 1 && sx >= -64 && sx <= 63 && sy >= -64 && sy <= 63) {
        o.add([sx & 0x7F, sy & 0x7F]);
      } else {
        long(sx, sy, steps > 1 && flag == 0 ? 0x10 : flag);
      }
      x += sx;
      y += sy;
      if (steps == 1) return;
    }
  }

  for (final s in p.stitches) {
    switch (s.type) {
      case StitchType.stitch:
        move(s.x, s.y, 0);
      case StitchType.jump:
        if (s.x != x || s.y != y) move(s.x, s.y, 0x10);
      case StitchType.trim:
        move(s.x, s.y, 0x20); // coupe (déplacement nul si déjà sur place)
      case StitchType.colorChange:
        if (s.x != x || s.y != y) move(s.x, s.y, 0x10);
        o.add([0xFE, 0xB0, colorTwo ? 2 : 1]);
        colorTwo = !colorTwo;
      case StitchType.end:
        break;
    }
  }
  o.add(const [0xFF, 0x00]);
  return o.toBytes();
}
