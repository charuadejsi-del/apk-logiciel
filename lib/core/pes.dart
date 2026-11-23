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
