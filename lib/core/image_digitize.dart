import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'pattern.dart';
import 'text_engine.dart' show TrimMode;

/// Image → broderie (étape A : remplissage tatami pour chaque forme).
///
/// 1. Analyse : niveaux de gris, seuil automatique (Otsu), nettoyage, formes
///    (composantes connexes), mesures et groupes de couleurs.
/// 2. Génération : chaque forme est découpée en cellules balayables ; on pose
///    d'abord un point droit de soutien sur toute la forme (comme pour les
///    lettres), puis le tatami revient en le couvrant. Les trajets passent à
///    l'intérieur de la forme, sous le remplissage à venir.

// ───────────────────────── Analyse ─────────────────────────

class DigitizeInput {
  final Uint8List rgba;
  final int width, height;
  final int groups;
  const DigitizeInput(this.rgba, this.width, this.height, {this.groups = 2});
}

/// Type de point choisi pour une forme.
enum StitchMode { auto, satin, tatami }

/// Largeur maximale (mm) d'une forme brodée en satin en mode automatique.
const double autoSatinMaxMm = 8;

class ShapeInfo {
  final int id; // étiquette dans [ImageAnalysis.labels]
  final int pixels;
  final int minX, minY, maxX, maxY;
  final double compactness; // 1 = disque, proche de 0 = forme fine
  int group = 0;
  bool excluded = false; // retirée par l'utilisateur
  StitchMode mode = StitchMode.auto;

  /// Choix fait pour cette forme seule (prioritaire sur le choix de sa couleur).
  bool overridden = false;

  /// Demi-épaisseur maximale de la forme, en pixels.
  double maxRadiusPx = 0;

  /// Nombre de trous (zones blanches fermées) dans la forme.
  int holes = 0;
  ShapeInfo(this.id, this.pixels, this.minX, this.minY, this.maxX, this.maxY,
      this.compactness);

  /// Épaisseur maximale en mm pour une taille de pixel donnée.
  double widthMm(double pxMm) => 2 * maxRadiusPx * pxMm;

  /// Satin ou tatami, une fois le mode automatique résolu.
  bool isSatin(double pxMm) => switch (mode) {
        StitchMode.satin => true,
        StitchMode.tatami => false,
        // Fine et simple : satin. Large, ou ajourée (2 trous ou plus) : tatami.
        StitchMode.auto => widthMm(pxMm) <= autoSatinMaxMm && holes < 2,
      };
  double get cx => (minX + maxX) / 2;
  double get cy => (minY + maxY) / 2;
}

class ImageAnalysis {
  final int w, h;
  final Int32List labels; // 0 = fond, sinon id de forme
  final List<ShapeInfo> shapes;

  /// Taille du dessin en pixels (sans les marges de 2 px).
  final int designW, designH;

  /// Taille d'un pixel en mm : fixée par la largeur choisie.
  double pxMm;
  ImageAnalysis(this.w, this.h, this.labels, this.shapes, this.designW, this.designH,
      {this.pxMm = 0.25});

  void setWidthMm(double mm) => pxMm = designW <= 0 ? 0.25 : mm / designW;
  double get widthMm => designW * pxMm;
  double get heightMm => designH * pxMm;
}

Float32List _gray(Uint8List rgba, int w, int h) {
  final g = Float32List(w * h);
  for (var i = 0; i < w * h; i++) {
    final a = rgba[i * 4 + 3] / 255.0;
    final l = 0.299 * rgba[i * 4] + 0.587 * rgba[i * 4 + 1] + 0.114 * rgba[i * 4 + 2];
    g[i] = l * a + 255 * (1 - a); // transparent = blanc
  }
  return g;
}

double _otsu(Float32List g) {
  final hist = List<int>.filled(256, 0);
  for (final v in g) {
    hist[v.clamp(0, 255).toInt()]++;
  }
  final total = g.length;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = 0.0, thr = 128.0;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      thr = t + 0.5;
    }
  }
  return thr;
}

/// Étiquetage des composantes connexes (8 voisins pour les formes, 4 pour le fond).
(Int32List, int) _label(Uint8List mask, int w, int h, int value, bool eight) {
  final lab = Int32List(w * h);
  var next = 0;
  final stack = <int>[];
  for (var i = 0; i < w * h; i++) {
    if (mask[i] != value || lab[i] != 0) continue;
    next++;
    lab[i] = next;
    stack.add(i);
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      final x = p % w, y = p ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          if (!eight && dx != 0 && dy != 0) continue;
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final q = ny * w + nx;
          if (mask[q] == value && lab[q] == 0) {
            lab[q] = next;
            stack.add(q);
          }
        }
      }
    }
  }
  return (lab, next);
}

/// Analyse l'image (taille du dessin réglée ensuite avec [ImageAnalysis.setWidthMm]).
ImageAnalysis analyzeImage(DigitizeInput input) {
  final w0 = input.width, h0 = input.height;
  final g0 = _gray(input.rgba, w0, h0);
  final thr = _otsu(g0);

  // Formes qui touchent le bord de la photo (cadre, bandeau, filigrane) : ignorées.
  final dark0 = Uint8List(w0 * h0);
  for (var i = 0; i < w0 * h0; i++) {
    dark0[i] = g0[i] < thr ? 1 : 0;
  }
  final (lab0, n0) = _label(dark0, w0, h0, 1, true);
  final border = List<bool>.filled(n0 + 1, false);
  for (var x = 0; x < w0; x++) {
    border[lab0[x]] = true;
    border[lab0[(h0 - 1) * w0 + x]] = true;
  }
  for (var y = 0; y < h0; y++) {
    border[lab0[y * w0]] = true;
    border[lab0[y * w0 + w0 - 1]] = true;
  }
  border[0] = true;

  // Cadre du dessin.
  var minX = w0, minY = h0, maxX = -1, maxY = -1;
  for (var y = 0; y < h0; y++) {
    for (var x = 0; x < w0; x++) {
      if (!border[lab0[y * w0 + x]]) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return ImageAnalysis(1, 1, Int32List(1), [], 0, 0);
  final bw = maxX - minX + 1, bh = maxY - minY + 1;

  // Rééchantillonnage : le plus grand côté du dessin fait 1600 px (bords lisses).
  final f = 1600 / math.max(bw, bh);
  final w = (bw * f).round() + 4, h = (bh * f).round() + 4;
  final mask = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final sy = (y - 2 + 0.5) / f - 0.5 + minY;
    for (var x = 0; x < w; x++) {
      final sx = (x - 2 + 0.5) / f - 0.5 + minX;
      // Interpolation bilinéaire du gris, puis seuil.
      final x0 = sx.floor(), y0 = sy.floor();
      final fx = sx - x0, fy = sy - y0;
      double px(int xx, int yy) {
        if (xx < 0 || yy < 0 || xx >= w0 || yy >= h0) return 255;
        if (border[lab0[yy * w0 + xx]] && g0[yy * w0 + xx] < thr) return 255;
        return g0[yy * w0 + xx];
      }

      final v = px(x0, y0) * (1 - fx) * (1 - fy) +
          px(x0 + 1, y0) * fx * (1 - fy) +
          px(x0, y0 + 1) * (1 - fx) * fy +
          px(x0 + 1, y0 + 1) * fx * fy;
      mask[y * w + x] = v < thr ? 1 : 0;
    }
  }
  const minPixels = 8; // taches plus petites : bruit

  // Petits trous bouchés, petites taches supprimées.
  final (bgLab, bgCount) = _label(mask, w, h, 0, false);
  final bgSize = List<int>.filled(bgCount + 1, 0);
  final bgBorder = List<bool>.filled(bgCount + 1, false);
  for (var i = 0; i < w * h; i++) {
    final l = bgLab[i];
    if (l == 0) continue;
    bgSize[l]++;
    final x = i % w, y = i ~/ w;
    if (x == 0 || y == 0 || x == w - 1 || y == h - 1) bgBorder[l] = true;
  }
  for (var i = 0; i < w * h; i++) {
    final l = bgLab[i];
    if (l != 0 && !bgBorder[l] && bgSize[l] < minPixels) mask[i] = 1;
  }
  final (lab, count) = _label(mask, w, h, 1, true);
  final size = List<int>.filled(count + 1, 0);
  final perim = List<int>.filled(count + 1, 0);
  final bx0 = List<int>.filled(count + 1, w), by0 = List<int>.filled(count + 1, h);
  final bx1 = List<int>.filled(count + 1, -1), by1 = List<int>.filled(count + 1, -1);
  for (var i = 0; i < w * h; i++) {
    final l = lab[i];
    if (l == 0) continue;
    size[l]++;
    final x = i % w, y = i ~/ w;
    if (x < bx0[l]) bx0[l] = x;
    if (x > bx1[l]) bx1[l] = x;
    if (y < by0[l]) by0[l] = y;
    if (y > by1[l]) by1[l] = y;
    if (x == 0 || y == 0 || x == w - 1 || y == h - 1 ||
        lab[i - 1] == 0 || lab[i + 1] == 0 || lab[i - w] == 0 || lab[i + w] == 0) {
      perim[l]++;
    }
  }
  // Renumérotation sans les taches.
  final remap = Int32List(count + 1);
  final shapes = <ShapeInfo>[];
  for (var l = 1; l <= count; l++) {
    if (size[l] < minPixels) continue;
    final id = shapes.length + 1;
    remap[l] = id;
    final per = math.max(1, perim[l]).toDouble();
    final comp = (4 * math.pi * size[l] / (per * per)).clamp(0.0, 1.0).toDouble();
    shapes.add(ShapeInfo(id, size[l], bx0[l], by0[l], bx1[l], by1[l], comp));
  }
  for (var i = 0; i < w * h; i++) {
    lab[i] = remap[lab[i]];
  }
  // Trous : zones de fond fermées (assez grandes) entourées par une forme.
  final holeSeen = <int>{};
  for (var i = 0; i < w * h; i++) {
    final l = bgLab[i];
    if (l == 0 || bgBorder[l] || bgSize[l] < minPixels || holeSeen.contains(l)) continue;
    holeSeen.add(l);
    // Le pixel juste à gauche du premier pixel du trou appartient à la forme qui l'entoure.
    if (i > 0 && lab[i - 1] > 0) shapes[lab[i - 1] - 1].holes++;
  }

  // Épaisseur de chaque forme (distance au bord).
  final dt = chamferDistance(lab, w, h);
  for (var i = 0; i < w * h; i++) {
    final l = lab[i];
    if (l == 0) continue;
    final r = dt[i];
    if (r > shapes[l - 1].maxRadiusPx) shapes[l - 1].maxRadiusPx = r;
  }
  groupShapes(shapes, input.groups);
  return ImageAnalysis(w, h, lab, shapes, w - 4, h - 4);
}

/// Distance (en pixels) de chaque pixel de forme au fond le plus proche (chanfrein 3-4).
Float32List chamferDistance(Int32List lab, int w, int h) {
  final d = Int32List(w * h);
  const big = 1 << 28;
  for (var i = 0; i < w * h; i++) {
    d[i] = lab[i] == 0 ? 0 : big;
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (d[i] == 0) continue;
      var v = d[i];
      if (x > 0) v = math.min(v, d[i - 1] + 3);
      if (y > 0) {
        v = math.min(v, d[i - w] + 3);
        if (x > 0) v = math.min(v, d[i - w - 1] + 4);
        if (x < w - 1) v = math.min(v, d[i - w + 1] + 4);
      }
      if (x == 0 || y == 0 || x == w - 1 || y == h - 1) v = math.min(v, 3);
      d[i] = v;
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      if (d[i] == 0) continue;
      var v = d[i];
      if (x < w - 1) v = math.min(v, d[i + 1] + 3);
      if (y < h - 1) {
        v = math.min(v, d[i + w] + 3);
        if (x < w - 1) v = math.min(v, d[i + w + 1] + 4);
        if (x > 0) v = math.min(v, d[i + w - 1] + 4);
      }
      d[i] = v;
    }
  }
  final out = Float32List(w * h);
  for (var i = 0; i < w * h; i++) {
    out[i] = d[i] / 3.0;
  }
  return out;
}

/// Regroupe les formes qui se ressemblent (taille et finesse) : un groupe = une couleur.
void groupShapes(List<ShapeInfo> shapes, int k) {
  if (shapes.isEmpty) return;
  k = k.clamp(1, math.min(6, shapes.length)).toInt();
  final fa = [for (final s in shapes) math.log(s.pixels + 1.0)];
  final fc = [for (final s in shapes) s.compactness * 3];
  // Centres initiaux répartis sur les tailles.
  final order = List<int>.generate(shapes.length, (i) => i)..sort((a, b) => fa[a].compareTo(fa[b]));
  final ca = <double>[], cc = <double>[];
  for (var j = 0; j < k; j++) {
    final idx = order[((j + 0.5) * shapes.length / k).floor().clamp(0, shapes.length - 1)];
    ca.add(fa[idx]);
    cc.add(fc[idx]);
  }
  final assign = List<int>.filled(shapes.length, 0);
  for (var it = 0; it < 25; it++) {
    var changed = false;
    for (var i = 0; i < shapes.length; i++) {
      var best = 0;
      var bd = double.infinity;
      for (var j = 0; j < k; j++) {
        final d = (fa[i] - ca[j]) * (fa[i] - ca[j]) + (fc[i] - cc[j]) * (fc[i] - cc[j]);
        if (d < bd) {
          bd = d;
          best = j;
        }
      }
      if (assign[i] != best) changed = true;
      assign[i] = best;
    }
    for (var j = 0; j < k; j++) {
      var sa = 0.0, sc = 0.0, n = 0;
      for (var i = 0; i < shapes.length; i++) {
        if (assign[i] != j) continue;
        sa += fa[i];
        sc += fc[i];
        n++;
      }
      if (n > 0) {
        ca[j] = sa / n;
        cc[j] = sc / n;
      }
    }
    if (!changed && it > 0) break;
  }
  // Groupes numérotés du plus grand motif au plus petit (le fond se brode d'abord).
  final rank = List<int>.generate(k, (j) => j)..sort((a, b) => ca[b].compareTo(ca[a]));
  final pos = List<int>.filled(k, 0);
  for (var r = 0; r < k; r++) {
    pos[rank[r]] = r;
  }
  for (var i = 0; i < shapes.length; i++) {
    shapes[i].group = pos[assign[i]];
  }
}

// ───────────────────────── Génération ─────────────────────────

class DigitizeOptions {
  final List<int> groupColors; // couleur ARGB de chaque groupe
  final double densityMm; // écart entre rangées de tatami
  final double stitchMm; // longueur des points de tatami
  final double angleDeg; // angle des rangées
  final double pullCompMm;
  final bool underlay;
  final TrimMode trimMode;
  final double jumpMaxMm;
  const DigitizeOptions({
    required this.groupColors,
    this.densityMm = 0.35,
    this.stitchMm = 3.5,
    this.angleDeg = -1, // < 0 : angle automatique selon chaque forme
    this.pullCompMm = 0.3,
    this.underlay = true,
    this.trimMode = TrimMode.auto,
    this.jumpMaxMm = 5,
  });
}

class DigitizeRequest {
  final ImageAnalysis analysis;
  final DigitizeOptions options;
  final String name;
  const DigitizeRequest(this.analysis, this.options, this.name);
}

/// Résultat avec le bilan de coût.
class DigitizeResult {
  final List<String> linkLog;
  final EmbPattern pattern;
  final int hiddenRuns; // liaisons en point droit cachées (sans saut ni coupe)
  final List<int> colorOrder; // groupes dans l'ordre de couture
  const DigitizeResult(this.pattern, this.hiddenRuns, this.colorOrder, [this.linkLog = const []]);
}

/// Point d'entrée utilisable dans un isolat (`compute`).
DigitizeResult digitizeRequest(DigitizeRequest r) {
  final d = _Digitizer(r.analysis, r.options);
  final p = d.build(r.name);
  return DigitizeResult(p, d._hiddenRuns, d.colorOrder, d.linkLog);
}

class _P {
  final double x, y;
  const _P(this.x, this.y);
  double dist(_P o) => math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));
}

class _Row {
  final int k;
  final double u0, u1;
  const _Row(this.k, this.u0, this.u1);
}

class _Cell {
  final rows = <_Row>[];
  final above = <int>{}; // cellules touchées par la rangée précédente
  final below = <int>{};
  int get first => rows.first.k;
  int get last => rows.last.k;
}

EmbPattern digitize(ImageAnalysis a, DigitizeOptions o, {String name = 'IMAGE'}) {
  final b = _Digitizer(a, o);
  return b.build(name);
}

class _Digitizer {
  final ImageAnalysis a;
  final DigitizeOptions o;
  final out = <Stitch>[];
  _P cur = const _P(0, 0);
  _P lastDir = const _P(1, 0);
  late final double px; // unités (0,1 mm) par pixel
  double ca = 1, sa = 0; // rotation des rangées (réglée pour chaque forme)
  late final double ox, oy; // centrage du dessin
  static const double runLen = 20; // 2 mm
  static const double lockLen = 5;

  _Digitizer(this.a, this.o) {
    px = a.pxMm * 10;
    final t = o.angleDeg * math.pi / 180;
    ca = math.cos(t);
    sa = math.sin(t);
    ox = -a.w * px / 2;
    oy = -a.h * px / 2;
  }

  // Repère du dessin (0,1 mm, centré) ↔ repère tourné (u le long des rangées, v entre rangées).
  _P fromUV(double u, double v) => _P(u * ca - v * sa, u * sa + v * ca);
  (double, double) toUV(_P p) => (p.x * ca + p.y * sa, -p.x * sa + p.y * ca);

  int labelAt(_P p) {
    final ix = ((p.x - ox) / px).floor(), iy = ((p.y - oy) / px).floor();
    if (ix < 0 || iy < 0 || ix >= a.w || iy >= a.h) return 0;
    return a.labels[iy * a.w + ix];
  }

  _P pixelCenter(int ix, int iy) => _P(ox + (ix + 0.5) * px, oy + (iy + 0.5) * px);

  void _stitch(_P p) {
    final dx = p.x - cur.x, dy = p.y - cur.y;
    final l = math.sqrt(dx * dx + dy * dy);
    if (l > 0.5) lastDir = _P(dx / l, dy / l);
    cur = p;
    out.add(Stitch(p.x.round(), p.y.round(), StitchType.stitch));
  }

  /// Point vers [p] en découpant si le trajet dépasse [maxLen].
  void _stitchTo(_P p, double maxLen) {
    final d = cur.dist(p);
    if (d > maxLen) {
      final n = (d / maxLen).ceil();
      final s = cur;
      for (var i = 1; i < n; i++) {
        _stitch(_P(s.x + (p.x - s.x) * i / n, s.y + (p.y - s.y) * i / n));
      }
    }
    _stitch(p);
  }

  void _lockIn(_P p) {
    _stitch(p);
    _stitch(_P(p.x + lastDir.x * lockLen, p.y + lastDir.y * lockLen));
    _stitch(p);
  }

  void _lockOff() {
    final p = cur, d = lastDir;
    _stitch(_P(p.x - d.x * lockLen, p.y - d.y * lockLen));
    _stitch(p);
  }

  /// Vrai juste après un changement de couleur : on saute sans nœud d'arrêt.
  bool _fresh = true;

  void _jumpTo(_P p) {
    if (_fresh) {
      _fresh = false;
      out.add(Stitch(p.x.round(), p.y.round(), StitchType.jump));
      cur = p;
      _lockIn(p);
      return;
    }
    final dist = p.dist(cur);
    final cut = switch (o.trimMode) {
      TrimMode.none => false,
      TrimMode.auto => dist > o.jumpMaxMm * 10,
      TrimMode.all => true,
    };
    _lockOff();
    if (cut) out.add(Stitch(cur.x.round(), cur.y.round(), StitchType.trim));
    out.add(Stitch(p.x.round(), p.y.round(), StitchType.jump));
    cur = p;
    _lockIn(p);
  }

  /// Rangées balayées d'une forme dans le repère tourné.
  List<List<_Row>> _rows(ShapeInfo s, double spacing) {
    // Boîte de la forme dans le repère tourné.
    var u0 = double.infinity, u1 = -double.infinity, v0 = double.infinity, v1 = -double.infinity;
    for (final cx in [s.minX, s.maxX + 1]) {
      for (final cy in [s.minY, s.maxY + 1]) {
        final (u, v) = toUV(_P(ox + cx * px, oy + cy * px));
        u0 = math.min(u0, u);
        u1 = math.max(u1, u);
        v0 = math.min(v0, v);
        v1 = math.max(v1, v);
      }
    }
    final step = px * 0.5;
    const minRun = 2.0; // 0,2 mm : les pointes fines sont aussi remplies
    // Chevauchement : si une autre forme touche (≤ 0,6 mm), on déborde de 0,3 mm dessous.
    double grow(double u, double v, double dir) {
      for (var t = step; t <= 6; t += step) {
        final l = labelAt(fromUV(u + dir * t, v));
        if (l != 0 && l != s.id) return 3;
      }
      return 0;
    }

    final rows = <List<_Row>>[];
    var k = 0;
    for (var v = v0 + spacing / 2; v < v1; v += spacing, k++) {
      final runs = <_Row>[];
      double? start;
      var lastIn = 0.0;
      for (var u = u0; u <= u1 + step; u += step) {
        final inside = u <= u1 && labelAt(fromUV(u, v)) == s.id;
        if (inside) {
          start ??= u;
          lastIn = u;
        } else if (start != null) {
          if (lastIn - start >= minRun) {
            runs.add(_Row(k, start - grow(start, v, -1), lastIn + grow(lastIn, v, 1)));
          }
          start = null;
        }
      }
      rows.add(runs);
    }
    return rows;
  }

  /// Découpe en cellules : dans une cellule, chaque rangée n'a qu'un segment.
  List<_Cell> _cells(List<List<_Row>> rows) {
    final cells = <_Cell>[];
    var prev = <(_Row, int)>[]; // segment de la rangée précédente, cellule
    for (final runs in rows) {
      final now = <(_Row, int)>[];
      for (final r in runs) {
        final over = [
          for (final p in prev)
            if (p.$1.u0 <= r.u1 && r.u0 <= p.$1.u1) p,
        ];
        var cont = -1;
        if (over.length == 1) {
          final p = over.first;
          final back = runs.where((q) => p.$1.u0 <= q.u1 && q.u0 <= p.$1.u1).length;
          if (back == 1) cont = p.$2;
        }
        if (cont >= 0) {
          cells[cont].rows.add(r);
          now.add((r, cont));
        } else {
          final c = _Cell()..rows.add(r);
          cells.add(c);
          final id = cells.length - 1;
          for (final p in over) {
            c.above.add(p.$2);
            cells[p.$2].below.add(id);
          }
          now.add((r, id));
        }
      }
      prev = now;
    }
    return cells;
  }

  _P _rowPoint(_Row r, double u, double v0, double spacing) =>
      fromUV(u, v0 + spacing / 2 + r.k * spacing);

  /// Trajet en point droit à l'intérieur de la forme (chemin le plus court en pixels).
  void _travel(ShapeInfo s, _P to) {
    final d = cur.dist(to);
    if (d < 1) return;
    // Ligne droite si elle reste dans la forme.
    final n = math.max(2, (d / (px * 0.5)).ceil());
    var straight = true;
    for (var i = 1; i < n; i++) {
      final p = _P(cur.x + (to.x - cur.x) * i / n, cur.y + (to.y - cur.y) * i / n);
      if (labelAt(p) != s.id) {
        straight = false;
        break;
      }
    }
    if (straight) {
      _stitchTo(to, runLen);
      return;
    }
    final path = _bfs(s, cur, to);
    if (path == null) {
      _stitchTo(to, runLen);
      return;
    }
    final every = math.max(1, (runLen / px).floor());
    for (var i = every; i < path.length; i += every) {
      _stitch(path[i]);
    }
    _stitchTo(to, runLen);
  }

  List<_P>? _bfs(ShapeInfo s, _P from, _P to) {
    final x0 = math.max(0, s.minX - 1), y0 = math.max(0, s.minY - 1);
    final x1 = math.min(a.w - 1, s.maxX + 1), y1 = math.min(a.h - 1, s.maxY + 1);
    final bw = x1 - x0 + 1, bh = y1 - y0 + 1;
    int? snap(_P p) {
      final cx = ((p.x - ox) / px).floor(), cy = ((p.y - oy) / px).floor();
      int? best;
      var bd = 1 << 30;
      for (var dy = -3; dy <= 3; dy++) {
        for (var dx = -3; dx <= 3; dx++) {
          final x = cx + dx, y = cy + dy;
          if (x < x0 || y < y0 || x > x1 || y > y1) continue;
          if (a.labels[y * a.w + x] != s.id) continue;
          final dd = dx * dx + dy * dy;
          if (dd < bd) {
            bd = dd;
            best = (y - y0) * bw + (x - x0);
          }
        }
      }
      return best;
    }

    final sIdx = snap(from), tIdx = snap(to);
    if (sIdx == null || tIdx == null) return null;
    final prev = Int32List(bw * bh)..fillRange(0, bw * bh, -1);
    final q = Queue<int>()..add(sIdx);
    prev[sIdx] = sIdx;
    while (q.isNotEmpty) {
      final c = q.removeFirst();
      if (c == tIdx) break;
      final cx = c % bw, cy = c ~/ bw;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx, ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= bw || ny >= bh) continue;
          final ni = ny * bw + nx;
          if (prev[ni] != -1) continue;
          if (a.labels[(ny + y0) * a.w + nx + x0] != s.id) continue;
          prev[ni] = c;
          q.add(ni);
        }
      }
    }
    if (prev[tIdx] == -1) return null;
    final path = <_P>[];
    var c = tIdx;
    while (c != sIdx) {
      path.add(pixelCenter(c % bw + x0, c ~/ bw + y0));
      c = prev[c];
    }
    return path.reversed.toList();
  }

  /// Points d'une rangée, de [fromU] vers [toU], avec décalage tatami.
  void _rowStitches(_Row r, double fromU, double toU, double v0, double spacing, double len,
      double phase) {
    final dir = toU >= fromU ? 1.0 : -1.0;
    _stitchTo(_rowPoint(r, fromU, v0, spacing), len);
    // Points intermédiaires alignés sur une grille décalée (motif tatami).
    final startIdx = ((math.min(fromU, toU) - phase) / len).ceil();
    final endIdx = ((math.max(fromU, toU) - phase) / len).floor();
    final us = <double>[
      for (var i = startIdx; i <= endIdx; i++) phase + i * len,
    ].where((u) => (u - fromU).abs() > len * 0.3 && (u - toU).abs() > len * 0.3).toList();
    if (dir < 0) us.sort((x, y) => y.compareTo(x));
    for (final u in us) {
      _stitch(_rowPoint(r, u, v0, spacing));
    }
    _stitch(_rowPoint(r, toU, v0, spacing));
  }

  /// Contour extérieur de la forme (suivi de Moore), un point tous les ~1 mm.
  List<_P> _contour(ShapeInfo s) {
    bool isIn(int x, int y) =>
        x >= 0 && y >= 0 && x < a.w && y < a.h && a.labels[y * a.w + x] == s.id;
    var sx = -1, sy = -1;
    for (var y = s.minY; y <= s.maxY && sx < 0; y++) {
      for (var x = s.minX; x <= s.maxX; x++) {
        if (isIn(x, y)) {
          sx = x;
          sy = y;
          break;
        }
      }
    }
    if (sx < 0) return const [];
    const dx = [1, 1, 0, -1, -1, -1, 0, 1], dy = [0, 1, 1, 1, 0, -1, -1, -1];
    final pts = <_P>[];
    var x = sx, y = sy, dir = 0;
    int? firstDir;
    final every = math.max(1, (1.0 / a.pxMm).round());
    var count = 0;
    for (var guard = 0; guard < 8 * s.pixels + 16; guard++) {
      if (count++ % every == 0) pts.add(pixelCenter(x, y));
      var moved = false;
      for (var i = 0; i < 8; i++) {
        final d = (dir + 6 + i) % 8;
        if (isIn(x + dx[d], y + dy[d])) {
          x += dx[d];
          y += dy[d];
          dir = d;
          moved = true;
          break;
        }
      }
      if (!moved) break; // pixel isolé
      firstDir ??= dir;
      if (x == sx && y == sy && dir == firstDir && pts.length > 2) break;
    }
    return pts;
  }

  void _shape(ShapeInfo s, {_P? next}) {
    // Angle des rangées : fixe, ou automatique dans le sens de la forme.
    var ang = o.angleDeg * math.pi / 180;
    if (o.angleDeg < 0) {
      var n = 0;
      var mx = 0.0, my = 0.0, cxx = 0.0, cyy = 0.0, cxy = 0.0;
      for (var y = s.minY; y <= s.maxY; y++) {
        for (var x = s.minX; x <= s.maxX; x++) {
          if (a.labels[y * a.w + x] != s.id) continue;
          n++;
          mx += x;
          my += y;
          cxx += x * x.toDouble();
          cyy += y * y.toDouble();
          cxy += x * y.toDouble();
        }
      }
      if (n > 2) {
        mx /= n;
        my /= n;
        final vxx = cxx / n - mx * mx, vyy = cyy / n - my * my, vxy = cxy / n - mx * my;
        ang = 0.5 * math.atan2(2 * vxy, vxx - vyy);
        // Forme presque ronde : 45° classique.
        final lam = math.sqrt((vxx - vyy) * (vxx - vyy) / 4 + vxy * vxy);
        if (lam < 0.15 * (vxx + vyy) / 2) ang = math.pi / 4;
      } else {
        ang = math.pi / 4;
      }
    }
    ca = math.cos(ang);
    sa = math.sin(ang);
    final spacing = math.max(1.5, o.densityMm * 10);
    final comp = o.pullCompMm * 10;
    final len = o.stitchMm * 10;
    final rows = _rows(s, spacing);
    final cells = _cells(rows);
    if (cells.isEmpty) return;
    // v0 de la forme (même calcul que dans _rows).
    var v0 = double.infinity;
    for (final cx in [s.minX, s.maxX + 1]) {
      for (final cy in [s.minY, s.maxY + 1]) {
        v0 = math.min(v0, toUV(_P(ox + cx * px, oy + cy * px)).$2);
      }
    }
    _P endPoint(_Cell c, bool top) {
      final r = top ? c.rows.first : c.rows.last;
      return _rowPoint(r, (r.u0 + r.u1) / 2, v0, spacing);
    }

    // Extrémité de cellule la plus proche d'un point.
    (int, bool) nearestEnd(_P target) {
      var root = 0;
      var rootTop = true;
      var bd = double.infinity;
      for (var i = 0; i < cells.length; i++) {
        for (final top in const [true, false]) {
          final dd = endPoint(cells[i], top).dist(target);
          if (dd < bd) {
            bd = dd;
            root = i;
            rootTop = top;
          }
        }
      }
      return (root, rootTop);
    }

    // Parcours en profondeur des cellules ; on retient le côté parent de chacune.
    (List<int>, Map<int, bool>) dfsFrom(int root, bool rootTop) {
      final order = <int>[];
      final fromTop = <int, bool>{}; // la cellule est abordée par le haut ?
      final seen = <int>{};
      void visit(int c, bool top) {
        seen.add(c);
        order.add(c);
        fromTop[c] = top;
        final cell = cells[c];
        final far = top ? cell.below : cell.above;
        final nearSide = top ? cell.above : cell.below;
        for (final nb in far) {
          if (!seen.contains(nb)) visit(nb, top);
        }
        for (final nb in nearSide) {
          if (!seen.contains(nb)) visit(nb, !top);
        }
      }

      visit(root, rootTop);
      for (var i = 0; i < cells.length; i++) {
        if (!seen.contains(i)) visit(i, true); // îlots (ne devrait pas arriver)
      }
      return (order, fromTop);
    }

    // Entrée : au plus près de la forme précédente. Sortie : au plus près de la suivante.
    final (eRoot, eTop) = nearestEnd(cur);
    final (xRoot, xTop) = next == null ? (eRoot, eTop) : nearestEnd(next);
    final (uOrder, uFromTop) = dfsFrom(eRoot, eTop);
    final (fOrder, fFromTop) = dfsFrom(xRoot, xTop);

    final entry = endPoint(cells[eRoot], eTop);
    _enter(s, entry);

    // Point droit sur le contour (sous le tatami) : bords nets, pas de vide aux pointes.
    if (o.underlay) {
      final loop = _contour(s);
      if (loop.length > 3) {
        var k0 = 0;
        for (var i = 1; i < loop.length; i++) {
          if (loop[i].dist(cur) < loop[k0].dist(cur)) k0 = i;
        }
        final ring = [...loop.sublist(k0), ...loop.sublist(0, k0), loop[k0]];
        _travel(s, ring.first);
        _runPoly(ring);
      }
    }

    List<_Row> rowsFrom(_Cell c, bool top) => top ? c.rows : c.rows.reversed.toList();

    // 1. Soutien en point droit sur toute la forme (rangées espacées), depuis l'entrée.
    if (o.underlay) {
      final every = math.max(2, (25 / spacing).round()); // ≈ 2,5 mm
      for (final ci in uOrder) {
        final rs = rowsFrom(cells[ci], uFromTop[ci]!);
        var forward = true;
        var first = true;
        for (var i = 0; i < rs.length; i++) {
          if (i % every != 0 && i != rs.length - 1) continue;
          final r = rs[i];
          final inset = math.min(6.0, (r.u1 - r.u0) * 0.25);
          final a0 = r.u0 + inset, a1 = r.u1 - inset;
          final from = forward ? a0 : a1, to = forward ? a1 : a0;
          if (first) {
            _travel(s, _rowPoint(r, from, v0, spacing));
            first = false;
          }
          _rowStitches(r, from, to, v0, spacing, 25, 0);
          forward = !forward;
        }
      }
    }

    // 2. Tatami : couvre tout et finit du côté de la forme suivante.
    for (final ci in fOrder.reversed) {
      final rs = rowsFrom(cells[ci], fFromTop[ci]!).reversed.toList(); // du fond vers le parent
      var forward = true;
      var first = true;
      for (final r in rs) {
        final a0 = r.u0 - comp, a1 = r.u1 + comp;
        final from = forward ? a0 : a1, to = forward ? a1 : a0;
        if (first) {
          _travel(s, _rowPoint(r, from, v0, spacing));
          first = false;
        }
        final phase = (r.k % 3) * len / 3;
        _rowStitches(r, from, to, v0, spacing, len, phase);
        forward = !forward;
      }
    }
  }

  // ───────────────────────── Satin ─────────────────────────

  /// Point droit le long d'une ligne (points de 2 mm, coins respectés).
  void _runPoly(List<_P> pts) {
    if (pts.isEmpty) return;
    if (pts.first.dist(cur) > 0.5) _stitchTo(pts.first, runLen);
    var acc = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final p0 = pts[i - 1], p1 = pts[i];
      final seg = p0.dist(p1);
      if (seg < 1e-6) continue;
      var t = 0.0;
      while (acc + (seg - t) >= runLen) {
        t += runLen - acc;
        acc = 0;
        _stitch(_P(p0.x + (p1.x - p0.x) * t / seg, p0.y + (p1.y - p0.y) * t / seg));
      }
      acc += seg - t;
    }
    if (pts.last.dist(cur) > 0.5) _stitch(pts.last);
  }

  /// Amincissement de Zhang-Suen : squelette d'un pixel d'épaisseur.
  static Uint8List _thin(Uint8List src, int w, int h) {
    final m = Uint8List.fromList(src);
    final del = <int>[];
    var changed = true;
    while (changed) {
      changed = false;
      for (var pass = 0; pass < 2; pass++) {
        del.clear();
        for (var y = 1; y < h - 1; y++) {
          for (var x = 1; x < w - 1; x++) {
            final i = y * w + x;
            if (m[i] == 0) continue;
            final p2 = m[i - w], p3 = m[i - w + 1], p4 = m[i + 1], p5 = m[i + w + 1];
            final p6 = m[i + w], p7 = m[i + w - 1], p8 = m[i - 1], p9 = m[i - w - 1];
            final b = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9;
            if (b < 2 || b > 6) continue;
            var t = 0;
            if (p2 == 0 && p3 == 1) t++;
            if (p3 == 0 && p4 == 1) t++;
            if (p4 == 0 && p5 == 1) t++;
            if (p5 == 0 && p6 == 1) t++;
            if (p6 == 0 && p7 == 1) t++;
            if (p7 == 0 && p8 == 1) t++;
            if (p8 == 0 && p9 == 1) t++;
            if (p9 == 0 && p2 == 1) t++;
            if (t != 1) continue;
            if (pass == 0) {
              if (p2 * p4 * p6 != 0 || p4 * p6 * p8 != 0) continue;
            } else {
              if (p2 * p4 * p8 != 0 || p2 * p6 * p8 != 0) continue;
            }
            del.add(i);
          }
        }
        for (final i in del) {
          m[i] = 0;
        }
        if (del.isNotEmpty) changed = true;
      }
    }
    return m;
  }

  /// Satin d'une forme : squelette → colonnes à largeur variable, soutien en point
  /// droit d'abord, puis satin qui revient en couvrant tout. Renvoie false si la
  /// forme ne se prête pas au satin (elle sera alors en tatami).
  bool _satinShape(ShapeInfo s, {_P? next, bool auto = false}) {
    final x0 = math.max(0, s.minX - 1), y0 = math.max(0, s.minY - 1);
    final x1 = math.min(a.w - 1, s.maxX + 1), y1 = math.min(a.h - 1, s.maxY + 1);
    final bw = x1 - x0 + 1, bh = y1 - y0 + 1;
    final m = Uint8List(bw * bh);
    final labc = Int32List(bw * bh);
    var cnt = 0;
    var sx = 0.0, sy = 0.0;
    for (var y = 0; y < bh; y++) {
      for (var x = 0; x < bw; x++) {
        if (a.labels[(y + y0) * a.w + x + x0] == s.id) {
          m[y * bw + x] = 1;
          labc[y * bw + x] = 1;
          cnt++;
          sx += x;
          sy += y;
        }
      }
    }
    if (cnt == 0) return false;
    final dt = chamferDistance(labc, bw, bh);
    _P toD(double x, double y) => _P(ox + (x0 + x + 0.5) * px, oy + (y0 + y + 0.5) * px);
    double dtAt(double x, double y) {
      final ix = x.round().clamp(0, bw - 1).toInt(), iy = y.round().clamp(0, bh - 1).toInt();
      return dt[iy * bw + ix];
    }

    bool inside(double x, double y) {
      final ix = x.floor(), iy = y.floor();
      if (ix < 0 || iy < 0 || ix >= bw || iy >= bh) return false;
      return m[iy * bw + ix] == 1;
    }

    // ── Squelette et graphe (en pixels du recadrage).
    final sk = _thin(m, bw, bh);
    int nbCount(int i) {
      final x = i % bw, y = i ~/ bw;
      var c = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= bw || ny >= bh) continue;
          if (sk[ny * bw + nx] == 1) c++;
        }
      }
      return c;
    }

    List<int> nbs(int i) {
      final x = i % bw, y = i ~/ bw;
      return [
        for (var dy = -1; dy <= 1; dy++)
          for (var dx = -1; dx <= 1; dx++)
            if (!(dx == 0 && dy == 0) &&
                x + dx >= 0 &&
                y + dy >= 0 &&
                x + dx < bw &&
                y + dy < bh &&
                sk[(y + dy) * bw + x + dx] == 1)
              (y + dy) * bw + x + dx,
      ];
    }

    final nodeOf = Int32List(bw * bh)..fillRange(0, bw * bh, -1);
    final nodePix = <List<int>>[];
    final skPix = <int>[for (var i = 0; i < bw * bh; i++) if (sk[i] == 1) i];
    for (final i in skPix) {
      if (nbCount(i) == 2 || nodeOf[i] >= 0) continue;
      final id = nodePix.length;
      final cluster = <int>[i];
      nodeOf[i] = id;
      for (var k = 0; k < cluster.length; k++) {
        for (final n in nbs(cluster[k])) {
          if (nodeOf[n] < 0 && nbCount(n) != 2) {
            nodeOf[n] = id;
            cluster.add(n);
          }
        }
      }
      nodePix.add(cluster);
    }
    final edges = <(int, int, List<int>)>[]; // nœud a, nœud b, pixels
    final visited = Uint8List(bw * bh);
    void trace(int startNode, int startPix, int first) {
      final path = <int>[startPix, first];
      visited[first] = 1;
      var prev = startPix, at = first;
      while (true) {
        if (nodeOf[at] >= 0) {
          edges.add((startNode, nodeOf[at], path));
          return;
        }
        int? next;
        for (final n in nbs(at)) {
          if (n == prev) continue;
          if (nodeOf[n] >= 0 && !(nodeOf[n] == startNode && path.length < 4)) {
            next = n;
            break;
          }
        }
        if (next == null) {
          for (final n in nbs(at)) {
            if (n != prev && nodeOf[n] < 0 && visited[n] == 0) {
              next = n;
              break;
            }
          }
        }
        if (next == null) {
          // Fin inattendue : on crée un nœud ici.
          final id = nodePix.length;
          nodePix.add([at]);
          nodeOf[at] = id;
          edges.add((startNode, id, path));
          return;
        }
        if (nodeOf[next] < 0) visited[next] = 1;
        path.add(next);
        prev = at;
        at = next;
      }
    }

    for (var id = 0; id < nodePix.length; id++) {
      for (final p in List.of(nodePix[id])) {
        for (final q in nbs(p)) {
          if (nodeOf[q] >= 0 || visited[q] == 1) continue;
          trace(id, p, q);
        }
      }
    }
    // Boucles sans nœud (anneau) : on en crée un.
    for (final i in skPix) {
      if (nodeOf[i] >= 0 || visited[i] == 1) continue;
      final id = nodePix.length;
      nodePix.add([i]);
      nodeOf[i] = id;
      for (final q in nbs(i)) {
        if (nodeOf[q] < 0 && visited[q] == 0) {
          trace(id, i, q);
          break;
        }
      }
    }
    final nodePos = <(double, double)>[
      for (final c in nodePix)
        (
          c.map((i) => (i % bw).toDouble()).reduce((p, q) => p + q) / c.length,
          c.map((i) => (i ~/ bw).toDouble()).reduce((p, q) => p + q) / c.length,
        ),
    ];

    // ── Élagage des petites branches parasites, puis fusion des nœuds de degré 2.
    var es = [for (final e in edges) (e.$1, e.$2, [for (final i in e.$3) ((i % bw).toDouble(), (i ~/ bw).toDouble())])];
    int degree(int n) {
      var d = 0;
      for (final e in es) {
        if (e.$1 == n) d++;
        if (e.$2 == n) d++;
      }
      return d;
    }

    for (var pass = 0; pass < 3 && es.length > 1; pass++) {
      final keep = <(int, int, List<(double, double)>)>[];
      for (final e in es) {
        final da = degree(e.$1), db = degree(e.$2);
        final len = e.$3.length.toDouble();
        final spurA = da == 1 && db >= 3 && len < 1.6 * dtAt(nodePos[e.$2].$1, nodePos[e.$2].$2) + 3;
        final spurB = db == 1 && da >= 3 && len < 1.6 * dtAt(nodePos[e.$1].$1, nodePos[e.$1].$2) + 3;
        if (spurA || spurB) continue;
        keep.add(e);
      }
      if (keep.isEmpty) break;
      es = keep;
    }
    var merged = true;
    while (merged) {
      merged = false;
      for (var n = 0; n < nodePos.length && !merged; n++) {
        final inc = [for (var k = 0; k < es.length; k++) if (es[k].$1 == n || es[k].$2 == n) k];
        if (inc.length != 2 || es[inc[0]].$1 == es[inc[0]].$2) continue;
        final e1 = es[inc[0]], e2 = es[inc[1]];
        // Oriente e1 pour finir en n, e2 pour partir de n.
        final p1 = e1.$2 == n ? e1.$3 : e1.$3.reversed.toList();
        final a1 = e1.$2 == n ? e1.$1 : e1.$2;
        final p2 = e2.$1 == n ? e2.$3 : e2.$3.reversed.toList();
        final b2 = e2.$1 == n ? e2.$2 : e2.$1;
        final joined = (a1, b2, [...p1, ...p2.skip(1)]);
        es = [
          for (var k = 0; k < es.length; k++)
            if (k != inc[0] && k != inc[1]) es[k],
          joined,
        ];
        merged = true;
      }
    }

    // Petite forme ronde : axe principal à la place du squelette.
    var totalLen = 0;
    for (final e in es) {
      totalLen += e.$3.length;
    }
    final mx = sx / cnt, my = sy / cnt;
    if (es.isEmpty || totalLen < 2 * s.maxRadiusPx) {
      var cxx = 0.0, cyy = 0.0, cxy = 0.0;
      for (var y = 0; y < bh; y++) {
        for (var x = 0; x < bw; x++) {
          if (m[y * bw + x] == 0) continue;
          cxx += (x - mx) * (x - mx);
          cyy += (y - my) * (y - my);
          cxy += (x - mx) * (y - my);
        }
      }
      final ang = 0.5 * math.atan2(2 * cxy, cxx - cyy);
      final ux = math.cos(ang), uy = math.sin(ang);
      double reach(double sgn) {
        var t = 0.0;
        while (t < bw + bh && inside(mx + 0.5 + ux * sgn * (t + 0.5), my + 0.5 + uy * sgn * (t + 0.5))) {
          t += 0.5;
        }
        return t;
      }

      final ta = reach(-1), tb = reach(1);
      final n = math.max(2, (ta + tb).ceil());
      final line = [
        for (var k = 0; k <= n; k++)
          (mx + ux * (-ta + (ta + tb) * k / n), my + uy * (-ta + (ta + tb) * k / n)),
      ];
      final na = nodePos.length;
      nodePos
        ..add(line.first)
        ..add(line.last);
      es = [(na, na + 1, line)];
    }

    // Forme très ramifiée (dentelle, feuille ajourée) : tatami en mode automatique.
    if (auto && es.length > 6) return false;

    // ── Colonnes : ligne centrale lissée, prolongée, bords par lancer de rayons.
    final deg = <int, int>{};
    for (final e in es) {
      deg[e.$1] = (deg[e.$1] ?? 0) + 1;
      deg[e.$2] = (deg[e.$2] ?? 0) + 1;
    }
    final comp = o.pullCompMm * 10;

    List<(double, double)> smooth(List<(double, double)> p) {
      if (p.length < 5) return p;
      return [
        for (var i = 0; i < p.length; i++)
          if (i == 0 || i == p.length - 1)
            p[i]
          else
            () {
              final lo = math.max(0, i - 3), hi = math.min(p.length - 1, i + 3);
              var ax = 0.0, ay = 0.0;
              for (var k = lo; k <= hi; k++) {
                ax += p[k].$1;
                ay += p[k].$2;
              }
              final c = hi - lo + 1;
              return (ax / c, ay / c);
            }(),
      ];
    }

    List<(double, double)> resample(List<(double, double)> p, double step) {
      final out = <(double, double)>[p.first];
      var acc = 0.0;
      for (var i = 1; i < p.length; i++) {
        final dx = p[i].$1 - p[i - 1].$1, dy = p[i].$2 - p[i - 1].$2;
        final seg = math.sqrt(dx * dx + dy * dy);
        if (seg < 1e-9) continue;
        var t = 0.0;
        while (acc + (seg - t) >= step) {
          t += step - acc;
          acc = 0;
          out.add((p[i - 1].$1 + dx * t / seg, p[i - 1].$2 + dy * t / seg));
        }
        acc += seg - t;
      }
      if (out.length < 2 || acc > step * 0.3) out.add(p.last);
      return out;
    }

    (double, double) tangent(List<(double, double)> p, int i) {
      final a0 = p[math.max(0, i - 1)], a1 = p[math.min(p.length - 1, i + 1)];
      final dx = a1.$1 - a0.$1, dy = a1.$2 - a0.$2;
      final l = math.sqrt(dx * dx + dy * dy);
      return l < 1e-9 ? (1.0, 0.0) : (dx / l, dy / l);
    }

    final step = math.max(1.0, 8 / px); // ≈ 0,8 mm en pixels
    final cols = <(List<_P>, List<_P>, List<_P>, List<_P>)>[]; // centre brut, centre, gauche, droite
    for (final e in es) {
      var c = resample(smooth(e.$3), step);
      if (c.length < 2) c = [e.$3.first, e.$3.last];
      final raw = [for (final p in c) toD(p.$1, p.$2)];
      // Prolongements : jusqu'au bord pour une pointe, dans la jonction sinon.
      List<(double, double)> extend((double, double) end, (double, double) dir, int node) {
        final out = <(double, double)>[];
        if ((deg[node] ?? 1) == 1) {
          var t = step;
          while (t < 4 * s.maxRadiusPx + 6 && inside(end.$1 + 0.5 + dir.$1 * t, end.$2 + 0.5 + dir.$2 * t)) {
            out.add((end.$1 + dir.$1 * t, end.$2 + dir.$2 * t));
            t += step;
          }
        } else {
          final r = dtAt(nodePos[node].$1, nodePos[node].$2) * 0.8;
          for (var t = step; t <= r; t += step) {
            out.add((end.$1 + dir.$1 * t, end.$2 + dir.$2 * t));
          }
        }
        return out;
      }

      final t0 = tangent(c, 0), t1 = tangent(c, c.length - 1);
      final head = extend(c.first, (-t0.$1, -t0.$2), e.$1).reversed.toList();
      final tail = extend(c.last, t1, e.$2);
      final full = [...head, ...c, ...tail];
      final cen = <_P>[], le = <_P>[], ri = <_P>[];
      for (var i = 0; i < full.length; i++) {
        final (tx, ty) = tangent(full, i);
        final nx = -ty, ny = tx;
        final (cx, cy) = full[i];
        final limit = math.max(2.0, dtAt(cx, cy) * 1.7 + 1.5);
        double ray(double sgn) {
          var t = 0.0;
          while (t < limit && inside(cx + 0.5 + nx * sgn * (t + 0.4), cy + 0.5 + ny * sgn * (t + 0.4))) {
            t += 0.4;
          }
          return t;
        }

        final cD = toD(cx, cy);
        // Chevauchement de 0,3 mm sous une forme voisine qui touche (≤ 0,6 mm).
        double touch(double sgn, double t) {
          for (var k = 0.4; k <= 0.6 / a.pxMm; k += 0.4) {
            final q = toD(cx + nx * sgn * (t + k), cy + ny * sgn * (t + k));
            final l = labelAt(q);
            if (l != 0 && l != s.id) return 3 / px;
          }
          return 0;
        }

        final dl0 = ray(1), dr0 = ray(-1);
        final dl = dl0 + touch(1, dl0), dr = dr0 + touch(-1, dr0);
        cen.add(cD);
        le.add(_P(cD.x + nx * (dl * px + comp), cD.y + ny * (dl * px + comp)));
        ri.add(_P(cD.x - nx * (dr * px + comp), cD.y - ny * (dr * px + comp)));
      }
      cols.add((raw, cen, le, ri));
    }

    // ── Plan : soutien en avançant (parcours en profondeur), satin en revenant.
    final nodeD = [for (final p in nodePos) toD(p.$1, p.$2)];
    final adj = <int, List<int>>{};
    for (var k = 0; k < es.length; k++) {
      adj.putIfAbsent(es[k].$1, () => []).add(k);
      adj.putIfAbsent(es[k].$2, () => []).add(k);
    }
    int nearestNode(_P target) {
      var best = es.first.$1;
      var bd = double.infinity;
      for (final n in adj.keys) {
        // On préfère les pointes.
        final pen = (adj[n]!.length == 1) ? 0.0 : 30.0;
        final dd = nodeD[n].dist(target) + pen;
        if (dd < bd) {
          bd = dd;
          best = n;
        }
      }
      return best;
    }

    final entryN = nearestNode(cur);
    final exitN = next == null ? entryN : nearestNode(next);

    List<(int, int, int)> dfsFrom(int start) {
      final order = <(int, int, int)>[]; // arête, nœud de départ, nœud d'arrivée
      final usedE = <int>{};
      void dfs(int n) {
        for (final k in adj[n] ?? const <int>[]) {
          if (usedE.contains(k)) continue;
          usedE.add(k);
          final other = es[k].$1 == n ? es[k].$2 : es[k].$1;
          order.add((k, n, other));
          dfs(other);
        }
      }

      dfs(start);
      return order;
    }

    // Colonne simple (point, feuille, trait) traversée : entrée d'un bout, sortie de l'autre.
    if (es.length == 1 && es[0].$1 != es[0].$2 && entryN != exitN) {
      final fwd = es[0].$1 == entryN;
      final (_, cen0, le0, ri0) = cols[0];
      final cen = fwd ? cen0 : cen0.reversed.toList();
      final le = fwd ? le0 : le0.reversed.toList();
      final ri = fwd ? ri0 : ri0.reversed.toList();
      _enter(s, nodeD[entryN]);
      if (o.underlay) {
        // Point droit à l'aller sur un bord, au retour sur l'autre (sous le satin).
        _runPoly([
          for (var i = 0; i < cen.length; i++)
            _P(cen[i].x + (le[i].x - cen[i].x) * 0.55, cen[i].y + (le[i].y - cen[i].y) * 0.55),
        ]);
        _runPoly([
          for (var i = cen.length - 1; i >= 0; i--)
            _P(cen[i].x + (ri[i].x - cen[i].x) * 0.55, cen[i].y + (ri[i].y - cen[i].y) * 0.55),
        ]);
      }
      _satinColumn(cen, le, ri);
      return true;
    }

    // Satin : parcours enraciné sur la sortie, pour finir près de la forme suivante.
    final order = dfsFrom(exitN);
    final under = dfsFrom(entryN);

    List<_P> centerPath(int k, int from) {
      final r = cols[k].$1;
      return es[k].$1 == from ? r : r.reversed.toList();
    }

    // Plus court chemin entre nœuds par les arêtes autorisées.
    List<_P>? route(int from, int to, Set<int> allowed) {
      if (from == to) return [nodeD[from]];
      final dist = <int, double>{from: 0};
      final prev = <int, (int, int)>{};
      final open = <int>{from};
      while (open.isNotEmpty) {
        var u = open.first;
        for (final v in open) {
          if (dist[v]! < dist[u]!) u = v;
        }
        open.remove(u);
        if (u == to) break;
        for (final k in adj[u] ?? const <int>[]) {
          if (!allowed.contains(k)) continue;
          final v = es[k].$1 == u ? es[k].$2 : es[k].$1;
          final nd = dist[u]! + cols[k].$1.length.toDouble();
          if (nd < (dist[v] ?? double.infinity)) {
            dist[v] = nd;
            prev[v] = (u, k);
            open.add(v);
          }
        }
      }
      if (!dist.containsKey(to)) return null;
      final steps = <(int, int)>[];
      var v = to;
      while (v != from) {
        final (u, k) = prev[v]!;
        steps.add((u, k));
        v = u;
      }
      final pts = <_P>[nodeD[from]];
      for (final (u, k) in steps.reversed) {
        pts.addAll(centerPath(k, u));
      }
      return pts;
    }

    final all = {for (var k = 0; k < es.length; k++) k};
    _enter(s, nodeD[entryN]);
    var at = entryN;
    final satinStart = order.isEmpty ? exitN : order.last.$3;
    if (o.underlay) {
      // Point droit sur toute la forme depuis l'entrée…
      for (final (k, from, to) in under) {
        if (at != from) _runPoly(route(at, from, all) ?? [nodeD[from]]);
        _runPoly(centerPath(k, from));
        at = to;
      }
    }
    // … puis jusqu'au début du satin.
    if (at != satinStart) _runPoly(route(at, satinStart, all) ?? [nodeD[satinStart]]);
    at = satinStart;
    final notDone = {...all};
    for (final (k, from, to) in order.reversed) {
      if (at != to) {
        _runPoly(route(at, to, notDone) ?? route(at, to, all) ?? [nodeD[to]]);
      }
      final (_, cen, le, ri) = cols[k];
      final fwd = es[k].$1 == to; // satin de « to » vers « from »
      _satinColumn(fwd ? cen : cen.reversed.toList(), fwd ? le : le.reversed.toList(),
          fwd ? ri : ri.reversed.toList());
      notDone.remove(k);
      at = from;
    }
    return true;
  }

  /// Satin à largeur variable : pas réglé sur le bord extérieur, points courts à
  /// l'intérieur des courbes, points trop longs divisés en quinconce (invisible).
  void _satinColumn(List<_P> c, List<_P> l, List<_P> r) {
    final n = c.length;
    if (n < 2) return;
    final spacing = math.max(1.5, o.densityMm * 10);
    _P at(List<_P> arr, double t) {
      final i = t.floor().clamp(0, n - 2).toInt();
      final f = t - i;
      return _P(arr[i].x + (arr[i + 1].x - arr[i].x) * f, arr[i].y + (arr[i + 1].y - arr[i].y) * f);
    }

    var t = 0.0;
    var k = 0;
    const e = 0.05;
    final end = (n - 1).toDouble();
    while (true) {
      final left = k.isEven;
      var p = at(left ? l : r, t);
      final t2 = math.min(end, t + e);
      final sl = at(l, t2).dist(at(l, t)), sr = at(r, t2).dist(at(r, t));
      final mine = left ? sl : sr, other = left ? sr : sl;
      if ((k ~/ 2).isOdd && other > 1e-9 && mine / other < 0.65) {
        final cc = at(c, t);
        p = _P(cc.x + (p.x - cc.x) * 0.45, cc.y + (p.y - cc.y) * 0.45);
      }
      // Point long : divisé en quinconce pour garder l'aspect satin.
      final d = cur.dist(p);
      if (k > 0 && d > 70) {
        final parts = (d / 60).ceil();
        final s0 = cur;
        for (var i = 1; i < parts; i++) {
          final f = ((i + (k.isEven ? -0.2 : 0.2)) / parts).clamp(0.05, 0.95);
          _stitch(_P(s0.x + (p.x - s0.x) * f, s0.y + (p.y - s0.y) * f));
        }
      }
      _stitch(p);
      if (t >= end) break;
      final speed = math.max(math.max(sl, sr) / (t2 - t).clamp(1e-6, 1.0), 1e-6);
      // Pointe très fine (< 0,8 mm) : un point sur deux, pour éviter les nœuds.
      final width = at(l, t).dist(at(r, t));
      final factor = width < 8 ? 2.0 : 1.0;
      t = math.min(end, t + factor * spacing / speed);
      k++;
      if (k > 500000) break;
    }
  }

  /// Pixel de la forme [s] le plus proche de [p] (échantillonné pour aller vite).
  _P _nearestPixel(ShapeInfo s, _P p) {
    var best = pixelCenter(s.cx.round(), s.cy.round());
    var bd = double.infinity;
    final stepPx = math.max(1, ((s.maxX - s.minX) + (s.maxY - s.minY)) ~/ 60);
    for (var y = s.minY; y <= s.maxY; y += stepPx) {
      for (var x = s.minX; x <= s.maxX; x += stepPx) {
        if (a.labels[y * a.w + x] != s.id) continue;
        final q = pixelCenter(x, y);
        final dd = q.dist(p);
        if (dd < bd) {
          bd = dd;
          best = q;
        }
      }
    }
    return best;
  }

  // ───────────────────────── Ordre et trajets cachés ─────────────────────────

  /// Points du bord de chaque forme (≤ 48), pour mesurer les écarts entre formes.
  late final Map<int, List<_P>> _edgePts = _computeEdgePts();

  Map<int, List<_P>> _computeEdgePts() {
    final all = <int, List<_P>>{};
    for (var y = 1; y < a.h - 1; y++) {
      for (var x = 1; x < a.w - 1; x++) {
        final i = y * a.w + x;
        final l = a.labels[i];
        if (l == 0) continue;
        if (a.labels[i - 1] != l || a.labels[i + 1] != l || a.labels[i - a.w] != l ||
            a.labels[i + a.w] != l) {
          (all[l] ??= <_P>[]).add(pixelCenter(x, y));
        }
      }
    }
    return {
      for (final e in all.entries)
        e.key: [
          for (var k = 0; k < e.value.length; k += math.max(1, e.value.length ~/ 48)) e.value[k],
        ],
    };
  }

  /// Écart bord à bord entre deux formes (0,1 mm).
  double _gap(ShapeInfo p, ShapeInfo q) {
    final a1 = _edgePts[p.id] ?? const <_P>[], b1 = _edgePts[q.id] ?? const <_P>[];
    var best = double.infinity;
    for (final u in a1) {
      for (final v in b1) {
        final d = u.dist(v);
        if (d < best) best = d;
      }
    }
    return best.isFinite ? best : 0;
  }

  /// Chaîne des formes d'une couleur : plus proche voisin puis amélioration 2-opt,
  /// en pénalisant les écarts qui obligeraient à couper le fil.
  List<ShapeInfo> _chain(List<ShapeInfo> members) {
    final n = members.length;
    if (n <= 2) return members;
    final d = List.generate(n, (_) => Float64List(n));
    final limit = o.jumpMaxMm * 10;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final g = _gap(members[i], members[j]);
        final c = g + (g > limit ? 300 : 0);
        d[i][j] = c;
        d[j][i] = c;
      }
    }
    // Départ : la forme la plus en haut à gauche.
    var start = 0;
    for (var i = 1; i < n; i++) {
      if (members[i].cx + members[i].cy < members[start].cx + members[start].cy) start = i;
    }
    final used = List<bool>.filled(n, false);
    final tour = <int>[start];
    used[start] = true;
    for (var k = 1; k < n; k++) {
      final last = tour.last;
      var bi = -1;
      for (var j = 0; j < n; j++) {
        if (!used[j] && (bi < 0 || d[last][j] < d[last][bi])) bi = j;
      }
      used[bi] = true;
      tour.add(bi);
    }
    // 2-opt sur un chemin ouvert.
    var improved = true;
    var guard = 0;
    while (improved && guard++ < 40) {
      improved = false;
      for (var i = 0; i < n - 2; i++) {
        for (var j = i + 2; j < n; j++) {
          final a0 = tour[i], a1 = tour[i + 1], b0 = tour[j];
          final before = d[a0][a1] + (j + 1 < n ? d[b0][tour[j + 1]] : 0);
          final after = d[a0][b0] + (j + 1 < n ? d[a1][tour[j + 1]] : 0);
          if (after + 1e-6 < before) {
            var lo = i + 1, hi = j;
            while (lo < hi) {
              final t = tour[lo];
              tour[lo] = tour[hi];
              tour[hi] = t;
              lo++;
              hi--;
            }
            improved = true;
          }
        }
      }
    }
    return [for (final i in tour) members[i]];
  }

  // Grille grossière (≈ 1 mm) pour chercher les trajets cachés.
  late final int _gf = math.max(1, (1.0 / a.pxMm).round());
  late final int _gw = (a.w + _gf - 1) ~/ _gf, _gh = (a.h + _gf - 1) ~/ _gf;
  late final Int32List _grid = () {
    final g = Int32List(_gw * _gh);
    // Une case est « couverte » si une forme la touche (les fentes de moins d'1 mm
    // entre deux motifs ne comptent pas comme du tissu à découvert).
    for (var gy = 0; gy < _gh; gy++) {
      for (var gx = 0; gx < _gw; gx++) {
        var label = 0;
        for (var sy = 0; sy < 3 && label == 0; sy++) {
          for (var sx = 0; sx < 3 && label == 0; sx++) {
            final x = math.min(a.w - 1, gx * _gf + (_gf * (2 * sx + 1)) ~/ 6);
            final y = math.min(a.h - 1, gy * _gf + (_gf * (2 * sy + 1)) ~/ 6);
            label = a.labels[y * a.w + x];
          }
        }
        g[gy * _gw + gx] = label;
      }
    }
    return g;
  }();

  /// Rang de couture de chaque forme (pour savoir si elle sera brodée plus tard).
  final Map<int, int> _rank = {};
  int _sewnUpTo = -1; // rang de la dernière forme brodée
  int _hiddenRuns = 0;
  final linkLog = <String>[]; // diagnostic des liaisons entre motifs

  /// Trajet en point droit caché sous des formes pas encore brodées, de la position
  /// actuelle vers [to]. Renvoie false s'il faudrait trop marcher à découvert.
  bool _hiddenRun(_P to, int currentId) {
    final sx = ((cur.x - ox) / px / _gf).floor().clamp(0, _gw - 1).toInt();
    final sy = ((cur.y - oy) / px / _gf).floor().clamp(0, _gh - 1).toInt();
    final tx = ((to.x - ox) / px / _gf).floor().clamp(0, _gw - 1).toInt();
    final ty = ((to.y - oy) / px / _gf).floor().clamp(0, _gh - 1).toInt();
    final straight = math.sqrt(((sx - tx) * (sx - tx) + (sy - ty) * (sy - ty)).toDouble());
    if (straight > 150) {
      linkLog.add('trop loin');
      return false; // > 15 cm : on saute
    }
    final margin = 20;
    final x0 = math.max(0, math.min(sx, tx) - margin), x1 = math.min(_gw - 1, math.max(sx, tx) + margin);
    final y0 = math.max(0, math.min(sy, ty) - margin), y1 = math.min(_gh - 1, math.max(sy, ty) + margin);
    final bw = x1 - x0 + 1, bh = y1 - y0 + 1;
    const bare = 25.0;
    double cost(int gx, int gy) {
      final l = _grid[gy * _gw + gx];
      if (l == 0) return bare;
      if (l == currentId) return 6; // on quitte la forme qu'on vient de broder
      final r = _rank[l];
      if (r == null) return bare; // forme retirée
      return r > _sewnUpTo ? 1 : double.infinity; // déjà brodée : interdit
    }

    final dist = Float64List(bw * bh)..fillRange(0, bw * bh, double.infinity);
    final prev = Int32List(bw * bh)..fillRange(0, bw * bh, -1);
    final s = (sy - y0) * bw + (sx - x0), t = (ty - y0) * bw + (tx - x0);
    dist[s] = 0;
    final heap = _Heap();
    heap.push(0, s);
    while (heap.isNotEmpty) {
      final (dc, c) = heap.pop();
      if (dc > dist[c]) continue;
      if (c == t) break;
      final cx = c % bw, cy = c ~/ bw;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx, ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= bw || ny >= bh) continue;
          final ni = ny * bw + nx;
          final w = ni == t ? 1.0 : cost(nx + x0, ny + y0);
          if (w.isInfinite) continue;
          final nd = dc + w * ((dx != 0 && dy != 0) ? 1.414 : 1.0);
          if (nd < dist[ni]) {
            dist[ni] = nd;
            prev[ni] = c;
            heap.push(nd, ni);
          }
        }
      }
    }
    if (dist[t].isInfinite) {
      linkLog.add('aucun chemin');
      return false;
    }
    // Chemin, et longueur parcourue à découvert.
    final cells = <int>[];
    var c = t;
    while (c != s) {
      cells.add(c);
      c = prev[c];
    }
    // Cases à découvert, sauf la toute première et la toute dernière (au bord même
    // des deux motifs, recouvertes par leur épaisseur).
    var bareCells = 0;
    for (var i = 1; i < cells.length - 1; i++) {
      final cc = cells[i];
      if (_grid[(cc ~/ bw + y0) * _gw + cc % bw + x0] == 0) bareCells++;
    }
    final cellMm = _gf * a.pxMm;
    if (cells.isEmpty) {
      _stitchTo(to, runLen);
      return true;
    }
    if (bareCells > 0) {
      linkLog.add('découvert $bareCells cases sur ${cells.length}');
      return false; // jamais de point droit visible sur le tissu
    }
    if (cells.length * cellMm > math.max(3 * straight * cellMm, straight * cellMm + 40)) {
      linkLog.add('détour ${cells.length} cases pour ${straight.toStringAsFixed(0)}');
      return false; // détour trop long
    }
    final pts = <_P>[
      for (final cc in cells.reversed)
        _P(ox + ((cc % bw + x0) * _gf + _gf / 2) * px, oy + ((cc ~/ bw + y0) * _gf + _gf / 2) * px),
    ];
    pts[pts.length - 1] = to;
    _runPoly(pts);
    _hiddenRuns++;
    linkLog.add('caché ${cells.length} cases');
    return true;
  }

  /// Entrée dans une forme : trajet intérieur si on est déjà dessus, sinon saut.
  void _enter(ShapeInfo s, _P p) {
    if (_fresh || out.isEmpty) {
      _jumpTo(p);
      return;
    }
    if (cur.dist(p) <= 0.5) return;
    var near = false;
    for (var dy = -3; dy <= 3 && !near; dy++) {
      for (var dx = -3; dx <= 3 && !near; dx++) {
        if (labelAt(_P(cur.x + dx * px, cur.y + dy * px)) == s.id) near = true;
      }
    }
    if (near) {
      _travel(s, p);
    } else {
      _jumpTo(p);
    }
  }

  /// Ordre des couleurs : on essaie toutes les permutations (jusqu'à 5 couleurs) et
  /// on garde celle où les trajets entre formes sont le plus cachés par les couleurs
  /// brodées ensuite (les couleurs éparpillées passent d'abord).
  List<int> _colorOrder(Map<int, List<ShapeInfo>> chains) {
    final groups = chains.keys.toList()..sort();
    if (groups.length <= 1) return groups;
    // Pour chaque liaison d'une chaîne : étiquettes rencontrées en ligne droite.
    final links = <int, List<(double, List<int>)>>{};
    for (final g in groups) {
      final ch = chains[g]!;
      final ls = <(double, List<int>)>[];
      for (var i = 0; i + 1 < ch.length; i++) {
        final p = _nearestPixel(ch[i], pixelCenter(ch[i + 1].cx.round(), ch[i + 1].cy.round()));
        final q = _nearestPixel(ch[i + 1], p);
        final n = math.max(1, (p.dist(q) / 10).ceil()); // tous les 1 mm
        ls.add((
          p.dist(q),
          [for (var k = 1; k < n; k++) labelAt(_P(p.x + (q.x - p.x) * k / n, p.y + (q.y - p.y) * k / n))],
        ));
      }
      links[g] = ls;
    }
    final groupOf = {for (final s in a.shapes) s.id: s.group};
    double score(List<int> order) {
      final pos = {for (var i = 0; i < order.length; i++) order[i]: i};
      var total = 0.0;
      for (final g in order) {
        for (final (gap, samples) in links[g]!) {
          if (gap <= o.jumpMaxMm * 10) continue; // forme proche : saut court, aucun coût
          var bareMm = 0.0;
          for (final l in samples) {
            if (l == 0) {
              bareMm += 1;
            } else {
              final gl = groupOf[l];
              if (gl == null || pos[gl] == null) {
                bareMm += 1;
              } else if (pos[gl]! < pos[g]!) {
                bareMm += 3; // par-dessus une couleur déjà brodée
              }
            }
          }
          total += bareMm <= 0 ? 0 : 30 + bareMm;
        }
      }
      return total;
    }

    List<int> best = groups;
    var bestScore = score(groups);
    if (groups.length <= 5) {
      void permute(List<int> done, List<int> rest) {
        if (rest.isEmpty) {
          final sc = score(done);
          if (sc < bestScore - 1e-9) {
            bestScore = sc;
            best = List.of(done);
          }
          return;
        }
        for (var i = 0; i < rest.length; i++) {
          permute([...done, rest[i]], [...rest]..removeAt(i));
        }
      }

      permute([], groups);
    }
    return best;
  }

  EmbPattern build(String name) {
    final members = <int, List<ShapeInfo>>{};
    for (final s in a.shapes) {
      if (!s.excluded) (members[s.group] ??= []).add(s);
    }
    final chains = {for (final e in members.entries) e.key: _chain(e.value)};
    final order = _colorOrder(chains);
    colorOrder = order;

    // Rang de couture de chaque forme ; les chaînes s'enchaînent bout à bout.
    final plan = <List<ShapeInfo>>[];
    var lastPos = pixelCenter(0, 0);
    var r = 0;
    for (final g in order) {
      var ch = chains[g]!;
      if (ch.isEmpty) continue;
      final f = pixelCenter(ch.first.cx.round(), ch.first.cy.round());
      final l = pixelCenter(ch.last.cx.round(), ch.last.cy.round());
      if (l.dist(lastPos) < f.dist(lastPos)) ch = ch.reversed.toList();
      for (final s in ch) {
        _rank[s.id] = r++;
      }
      plan.add(ch);
      lastPos = pixelCenter(ch.last.cx.round(), ch.last.cy.round());
    }

    final colors = <int>[];
    var firstGroup = true;
    for (final seq in plan) {
      final g = seq.first.group;
      if (!firstGroup) {
        _lockOff();
        out.add(Stitch(cur.x.round(), cur.y.round(), StitchType.trim));
        out.add(Stitch(cur.x.round(), cur.y.round(), StitchType.colorChange));
        _fresh = true;
      }
      colors.add(o.groupColors.isEmpty
          ? defaultPalette[g % defaultPalette.length]
          : o.groupColors[g % o.groupColors.length]);
      for (var i = 0; i < seq.length; i++) {
        final sh = seq[i];
        if (i > 0 && !_fresh) {
          // Forme proche : simple saut court (pas de coupe).
          // Forme éloignée : point droit entièrement caché sous une couleur à venir, sinon saut + coupe.
          final target = _nearestPixel(sh, cur);
          if (cur.dist(target) > o.jumpMaxMm * 10) _hiddenRun(target, seq[i - 1].id);
        }
        final next = i + 1 < seq.length
            ? _nearestPixel(seq[i + 1], pixelCenter(sh.cx.round(), sh.cy.round()))
            : null;
        final satin = sh.isSatin(a.pxMm) &&
            _satinShape(sh, next: next, auto: sh.mode == StitchMode.auto);
        if (!satin) _shape(sh, next: next);
        _sewnUpTo = _rank[sh.id]!;
      }
      firstGroup = false;
    }
    if (out.isNotEmpty) {
      _lockOff();
      out.add(Stitch(cur.x.round(), cur.y.round(), StitchType.trim));
    }
    out.add(Stitch(cur.x.round(), cur.y.round(), StitchType.end));
    return EmbPattern(name: name, stitches: out, colors: colors);
  }

  List<int> colorOrder = const [];
}

/// Tas binaire minimal (priorité, valeur) pour Dijkstra.
class _Heap {
  final _k = <double>[];
  final _v = <int>[];
  bool get isNotEmpty => _k.isNotEmpty;

  void push(double k, int v) {
    _k.add(k);
    _v.add(v);
    var i = _k.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_k[p] <= _k[i]) break;
      _swap(i, p);
      i = p;
    }
  }

  (double, int) pop() {
    final top = (_k[0], _v[0]);
    final lk = _k.removeLast(), lv = _v.removeLast();
    if (_k.isNotEmpty) {
      _k[0] = lk;
      _v[0] = lv;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _k.length && _k[l] < _k[m]) m = l;
        if (r < _k.length && _k[r] < _k[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int i, int j) {
    final tk = _k[i];
    _k[i] = _k[j];
    _k[j] = tk;
    final tv = _v[i];
    _v[i] = _v[j];
    _v[j] = tv;
  }
}
