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

class ShapeInfo {
  final int id; // étiquette dans [ImageAnalysis.labels]
  final int pixels;
  final int minX, minY, maxX, maxY;
  final double compactness; // 1 = disque, proche de 0 = forme fine
  int group = 0;
  bool excluded = false; // retirée par l'utilisateur
  ShapeInfo(this.id, this.pixels, this.minX, this.minY, this.maxX, this.maxY,
      this.compactness);
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
  groupShapes(shapes, input.groups);
  return ImageAnalysis(w, h, lab, shapes, w - 4, h - 4);
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
    this.densityMm = 0.40,
    this.stitchMm = 3.5,
    this.angleDeg = 45,
    this.pullCompMm = 0.2,
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

/// Point d'entrée utilisable dans un isolat (`compute`).
EmbPattern digitizeRequest(DigitizeRequest r) => digitize(r.analysis, r.options, name: r.name);

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
  late final double ca, sa; // rotation des rangées
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
    final minRun = 5.0; // 0,5 mm
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
          if (lastIn - start >= minRun) runs.add(_Row(k, start, lastIn));
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

  void _shape(ShapeInfo s) {
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

    // Cellule de départ : l'extrémité la plus proche de la position actuelle.
    var root = 0;
    var rootTop = true;
    var bd = double.infinity;
    for (var i = 0; i < cells.length; i++) {
      for (final top in const [true, false]) {
        final dd = endPoint(cells[i], top).dist(cur);
        if (dd < bd) {
          bd = dd;
          root = i;
          rootTop = top;
        }
      }
    }
    // Parcours en profondeur des cellules ; on retient le côté parent de chacune.
    final order = <int>[];
    final fromTop = <int, bool>{}; // la cellule est abordée par le haut ?
    final seen = <int>{};
    void visit(int c, bool top) {
      seen.add(c);
      order.add(c);
      fromTop[c] = top;
      final cell = cells[c];
      // Voisins : ceux du côté opposé d'abord (on avance), puis les autres.
      final far = top ? cell.below : cell.above;
      final nearSide = top ? cell.above : cell.below;
      for (final nb in far) {
        if (!seen.contains(nb)) visit(nb, top); // voisin en dessous abordé par le haut
      }
      for (final nb in nearSide) {
        if (!seen.contains(nb)) visit(nb, !top);
      }
    }

    visit(root, rootTop);
    for (var i = 0; i < cells.length; i++) {
      if (!seen.contains(i)) visit(i, true); // îlots (ne devrait pas arriver)
    }

    // Entrée dans la forme.
    final entry = endPoint(cells[root], rootTop);
    if (_fresh || cur.dist(entry) > 0.5) _jumpTo(entry);

    List<_Row> rowsFrom(_Cell c, bool top) => top ? c.rows : c.rows.reversed.toList();

    // 1. Soutien en point droit sur toute la forme (rangées espacées), en avançant.
    if (o.underlay) {
      final every = math.max(2, (25 / spacing).round()); // ≈ 2,5 mm
      for (final ci in order) {
        final rs = rowsFrom(cells[ci], fromTop[ci]!);
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

    // 2. Tatami en revenant (ordre inverse), qui couvre le soutien et les trajets.
    for (final ci in order.reversed) {
      final rs = rowsFrom(cells[ci], fromTop[ci]!).reversed.toList(); // du fond vers le parent
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

  EmbPattern build(String name) {
    final groups = <int>{for (final s in a.shapes) if (!s.excluded) s.group}.toList()..sort();
    final colors = <int>[];
    var firstGroup = true;
    for (final g in groups) {
      final members = [for (final s in a.shapes) if (s.group == g && !s.excluded) s];
      if (members.isEmpty) continue;
      if (!firstGroup) {
        _lockOff();
        out.add(Stitch(cur.x.round(), cur.y.round(), StitchType.trim));
        out.add(Stitch(cur.x.round(), cur.y.round(), StitchType.colorChange));
        _fresh = true;
      }
      colors.add(o.groupColors.isEmpty ? defaultPalette[g % defaultPalette.length]
          : o.groupColors[g % o.groupColors.length]);
      // Formes du groupe : la plus proche à chaque fois.
      final left = [...members];
      while (left.isNotEmpty) {
        var bi = 0;
        var bd = double.infinity;
        for (var i = 0; i < left.length; i++) {
          final c = pixelCenter(left[i].cx.round(), left[i].cy.round());
          final dd = out.isEmpty ? c.x + c.y : c.dist(cur); // 1re forme : en haut à gauche
          if (dd < bd) {
            bd = dd;
            bi = i;
          }
        }
        _shape(left.removeAt(bi));
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
}
