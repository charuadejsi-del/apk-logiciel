import 'dart:math' as math;

/// Police de broderie « Bloc » : chaque lettre est un squelette de lignes centrales.
/// Le moteur de texte transforme chaque ligne en colonne de point satin.
///
/// Repère : hauteur des capitales = 100 unités, Y vers le bas, ligne de base à y = 100.
/// Les lignes centrales sont en retrait de 7 unités (demi-colonne nominale) ;
/// le moteur prolonge chaque extrémité d'une demi-largeur pour fermer les angles.

typedef Pt = (double, double);

class GlyphStroke {
  final List<Pt> points;
  final bool closed;
  const GlyphStroke(this.points, {this.closed = false});
}

class Glyph {
  /// Chasse (largeur totale de la lettre) en unités.
  final double width;
  final List<GlyphStroke> strokes;
  const Glyph(this.width, this.strokes);
}

List<Pt> _arc(double cx, double cy, double rx, double ry, double a0, double a1) {
  final n = math.max(2, ((a1 - a0).abs() / 6).ceil());
  return [
    for (var i = 0; i <= n; i++)
      (
        cx + rx * math.cos((a0 + (a1 - a0) * i / n) * math.pi / 180),
        cy + ry * math.sin((a0 + (a1 - a0) * i / n) * math.pi / 180),
      ),
  ];
}

GlyphStroke _l(double x1, double y1, double x2, double y2) =>
    GlyphStroke([(x1, y1), (x2, y2)]);

/// Concatène des morceaux en une seule ligne, sans doublons aux jonctions.
GlyphStroke _j(List<List<Pt>> parts) {
  final out = <Pt>[];
  for (final part in parts) {
    for (final p in part) {
      if (out.isNotEmpty) {
        final q = out.last;
        if ((q.$1 - p.$1).abs() < 0.01 && (q.$2 - p.$2).abs() < 0.01) continue;
      }
      out.add(p);
    }
  }
  return GlyphStroke(out);
}

GlyphStroke _a(double cx, double cy, double rx, double ry, double a0, double a1) =>
    GlyphStroke(_arc(cx, cy, rx, ry, a0, a1));

GlyphStroke _o(double cx, double cy, double rx, double ry) {
  final pts = _arc(cx, cy, rx, ry, -90, 270)..removeLast();
  return GlyphStroke(pts, closed: true);
}

List<Pt> _seg(double x1, double y1, double x2, double y2) => [(x1, y1), (x2, y2)];

final Map<String, Glyph> blockFont = _buildFont();

Map<String, Glyph> _buildFont() {
  final two = _arc(31, 30, 24, 23, -160, 35);
  return {
    'A': Glyph(72, [_l(7, 93, 36, 7), _l(36, 7, 65, 93), _l(17, 62, 55, 62)]),
    'B': Glyph(66, [
      _l(7, 7, 7, 93),
      _j([_seg(7, 7, 36, 7), _arc(36, 28.5, 21.5, 21.5, -90, 90), _seg(36, 50, 7, 50)]),
      _j([_seg(7, 50, 39, 50), _arc(39, 71.5, 21.5, 21.5, -90, 90), _seg(39, 93, 7, 93)]),
    ]),
    'C': Glyph(74, [_a(37, 50, 30, 43, -45, -315)]),
    'D': Glyph(68, [
      _l(7, 7, 7, 93),
      _j([_seg(7, 7, 28, 7), _arc(28, 50, 33, 43, -90, 90), _seg(28, 93, 7, 93)]),
    ]),
    'E': Glyph(58, [_l(7, 7, 7, 93), _l(7, 7, 51, 7), _l(7, 50, 45, 50), _l(7, 93, 51, 93)]),
    'F': Glyph(54, [_l(7, 7, 7, 93), _l(7, 7, 47, 7), _l(7, 50, 43, 50)]),
    'G': Glyph(74, [_a(37, 50, 30, 43, -40, -353.3), _l(42, 55, 67, 55)]),
    'H': Glyph(66, [_l(7, 7, 7, 93), _l(59, 7, 59, 93), _l(7, 50, 59, 50)]),
    'I': Glyph(14, [_l(7, 7, 7, 93)]),
    'J': Glyph(52, [_j([_seg(45, 7, 45, 68), _arc(26, 68, 19, 25, 0, 180)])]),
    'K': Glyph(64, [_l(7, 7, 7, 93), _l(55, 7, 9, 56), _l(24, 42, 57, 93)]),
    'L': Glyph(58, [_l(7, 7, 7, 93), _l(7, 93, 51, 93)]),
    'M': Glyph(76, [_l(7, 93, 7, 7), _l(7, 7, 38, 70), _l(38, 70, 69, 7), _l(69, 7, 69, 93)]),
    'N': Glyph(66, [_l(7, 93, 7, 7), _l(7, 7, 59, 93), _l(59, 93, 59, 7)]),
    'O': Glyph(74, [_o(37, 50, 30, 43)]),
    'P': Glyph(63, [
      _l(7, 7, 7, 93),
      _j([_seg(7, 7, 34, 7), _arc(34, 29, 22, 22, -90, 90), _seg(34, 51, 7, 51)]),
    ]),
    'Q': Glyph(76, [_o(37, 50, 30, 43), _l(44, 72, 70, 97)]),
    'R': Glyph(66, [
      _l(7, 7, 7, 93),
      _j([_seg(7, 7, 34, 7), _arc(34, 29, 22, 22, -90, 90), _seg(34, 51, 7, 51)]),
      _l(30, 51, 59, 93),
    ]),
    'S': Glyph(62, [
      _j([_arc(31, 28.5, 24, 21.5, -30, -270), _arc(31, 71.5, 24, 21.5, -90, 150)]),
    ]),
    'T': Glyph(68, [_l(7, 7, 61, 7), _l(34, 7, 34, 93)]),
    'U': Glyph(66, [
      _j([_seg(7, 7, 7, 64), _arc(33, 64, 26, 29, 180, 0), _seg(59, 64, 59, 7)]),
    ]),
    'V': Glyph(68, [_l(7, 7, 34, 93), _l(34, 93, 61, 7)]),
    'W': Glyph(86, [_l(7, 7, 25, 93), _l(25, 93, 43, 30), _l(43, 30, 61, 93), _l(61, 93, 79, 7)]),
    'X': Glyph(66, [_l(7, 7, 59, 93), _l(59, 7, 7, 93)]),
    'Y': Glyph(66, [_l(7, 7, 33, 50), _l(59, 7, 33, 50), _l(33, 50, 33, 93)]),
    'Z': Glyph(64, [_l(7, 7, 57, 7), _l(57, 7, 7, 93), _l(7, 93, 57, 93)]),
    '0': Glyph(64, [_o(32, 50, 25, 43)]),
    '1': Glyph(44, [_l(16, 22, 30, 7), _l(30, 7, 30, 93)]),
    '2': Glyph(62, [_j([two, [(7.0, 93.0)]]), _l(7, 93, 57, 93)]),
    '3': Glyph(62, [_a(30, 28.5, 23, 21.5, -150, 90), _a(30, 71.5, 25, 21.5, -90, 150)]),
    '4': Glyph(64, [_l(44, 93, 44, 7), _l(44, 7, 7, 66), _l(7, 66, 57, 66)]),
    '5': Glyph(62, [_l(53, 7, 13, 7), _l(13, 7, 15.57, 45.32), _a(31, 66, 24, 27, -130, 155)]),
    '6': Glyph(64, [_o(32, 66, 25, 27), _a(39, 66, 32, 59, 180, 290)]),
    '7': Glyph(64, [_l(7, 7, 57, 7), _l(57, 7, 24, 93)]),
    '8': Glyph(64, [_o(32, 29, 21, 22), _o(32, 71, 25, 22)]),
    '9': Glyph(64, [_o(32, 34, 25, 27), _a(25, 34, 32, 59, 0, 110)]),
    '-': Glyph(44, [_l(7, 55, 37, 55)]),
    '.': Glyph(14, [_l(7, 86, 7, 93)]),
    ' ': const Glyph(30, []),
  };
}
