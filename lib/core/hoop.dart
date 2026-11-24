import 'dart:math' as math;
import 'dart:typed_data';

import 'pattern.dart';
import 'transform.dart';

/// Cadre (tambour) d'une machine. Dimensions en mm.
class Hoop {
  final String name;
  final double widthMm, heightMm;
  const Hoop(this.name, this.widthMm, this.heightMm);
  String get label => '$name · ${_n(widthMm / 10)} × ${_n(heightMm / 10)} cm';
  static String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

const hoopPresets = <Hoop>[
  Hoop('Brother V3', 180, 280),
  Hoop('Petit', 100, 100),
  Hoop('Moyen', 130, 180),
  Hoop('Grand', 200, 300),
  Hoop('Industriel', 300, 500),
];

/// Réglages de préparation pour la machine.
class PrepOptions {
  final double hoopWmm, hoopHmm;
  final bool split; // découper si le dessin dépasse le cadre
  final bool frame; // cadre en point droit cousu en premier
  final double marginMm; // espace entre le dessin et le cadre
  final double runMm; // longueur des points du cadre
  final double overlapMm; // recouvrement entre morceaux voisins
  final bool marks; // croix de repérage sur les lignes de coupe
  final StartAnchor anchor; // point de départ de chaque morceau
  final Map<int, StartAnchor> pieceAnchors; // départ choisi pour un morceau (n° → départ)
  const PrepOptions({
    required this.hoopWmm,
    required this.hoopHmm,
    this.split = true,
    this.frame = true,
    this.marginMm = 5,
    this.runMm = 5.8,
    this.overlapMm = 2.5,
    this.marks = true,
    this.anchor = StartAnchor.center,
    this.pieceAnchors = const {},
  });

  PrepOptions withPieceAnchor(int piece, StartAnchor a) => PrepOptions(
        hoopWmm: hoopWmm,
        hoopHmm: hoopHmm,
        split: split,
        frame: frame,
        marginMm: marginMm,
        runMm: runMm,
        overlapMm: overlapMm,
        marks: marks,
        anchor: anchor,
        pieceAnchors: {...pieceAnchors, piece: a},
      );
}

class PrepPiece {
  final int index, col, row;
  final Bounds window; // zone du dessin d'origine couverte par ce morceau
  final EmbPattern pattern; // prêt à coudre (cadre, repères, dessin, départ)
  final int wholeObjects; // éléments gardés entiers (non coupés) au-delà de la ligne
  final int cutObjects; // éléments coupés à la ligne
  final int originX, originY; // position du départ dans le dessin d'origine
  const PrepPiece(this.index, this.col, this.row, this.window, this.pattern, this.wholeObjects,
      this.cutObjects,
      [this.originX = 0, this.originY = 0]);
}

class PrepResult {
  final List<int> xs, ys; // lignes de coupe (bords compris), unités 0,1 mm
  final List<PrepPiece> pieces;
  final String? error;
  const PrepResult(this.xs, this.ys, this.pieces, [this.error]);
  int get cols => xs.length - 1;
  int get rows => ys.length - 1;
}

class PrepRequest {
  final EmbPattern pattern;
  final PrepOptions options;
  const PrepRequest(this.pattern, this.options);
}

/// Point d'entrée pour un isolat (`compute`).
PrepResult prepareRequest(PrepRequest r) => prepareForHoop(r.pattern, r.options);

// ─────────────────────────── Éléments ───────────────────────────

/// Suite de points cousus sans saut, coupe ni changement de couleur.
class _Obj {
  final List<Stitch> pts;
  final int block; // bloc de couleur d'origine
  final bool trimBefore; // l'original coupait avant cet élément
  int minX = 1 << 30, minY = 1 << 30, maxX = -(1 << 30), maxY = -(1 << 30);
  double cx = 0, cy = 0;
  _Obj(this.pts, this.block, this.trimBefore) {
    for (final p in pts) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
      cx += p.x;
      cy += p.y;
    }
    cx /= pts.length;
    cy /= pts.length;
  }
}

List<_Obj> _objects(EmbPattern p) {
  final out = <_Obj>[];
  var block = 0;
  var cur = <Stitch>[];
  var trim = true;
  var pendingTrim = true;
  void flush() {
    if (cur.isNotEmpty) out.add(_Obj(cur, block, trim));
    cur = <Stitch>[];
  }

  for (final s in p.stitches) {
    switch (s.type) {
      case StitchType.stitch:
        if (cur.isEmpty) trim = pendingTrim;
        pendingTrim = false;
        cur.add(s);
      case StitchType.jump:
        if (cur.isNotEmpty && (s.x != cur.last.x || s.y != cur.last.y)) flush();
      case StitchType.trim:
        flush();
        pendingTrim = true;
      case StitchType.colorChange:
        flush();
        block++;
        pendingTrim = true;
      case StitchType.end:
        flush();
    }
  }
  flush();
  return out;
}

// ─────────────────────────── Lignes de coupe ───────────────────────────

/// Choisit les lignes de coupe sur un axe : nombre minimal de morceaux,
/// puis lignes qui traversent le moins de points (passages dans le vide).
List<int> _cuts(List<_Obj> objs, int lo, int hi, int span, bool horiz) {
  if (hi - lo <= span) return [lo, hi];
  const res = 10; // 1 mm
  final n = ((hi - lo) / res).ceil();
  final cost = List<double>.filled(n + 2, 0);
  // Chaque segment cousu ajoute 1 sur les positions qu'il traverse.
  final diff = List<double>.filled(n + 3, 0);
  for (final o in objs) {
    for (var i = 1; i < o.pts.length; i++) {
      final a = horiz ? o.pts[i - 1].x : o.pts[i - 1].y;
      final b = horiz ? o.pts[i].x : o.pts[i].y;
      final i0 = ((math.min(a, b) - lo) / res).floor() + 1;
      final i1 = ((math.max(a, b) - lo) / res).ceil() - 1;
      if (i1 < i0) continue;
      diff[i0.clamp(0, n + 1)] += 1;
      diff[(i1 + 1).clamp(0, n + 2)] -= 1;
    }
    // Couper un élément en deux coûte aussi (feuille, lettre…).
    final a = horiz ? o.minX : o.minY, b = horiz ? o.maxX : o.maxY;
    final i0 = ((a - lo) / res).floor() + 1, i1 = ((b - lo) / res).ceil() - 1;
    if (i1 >= i0) {
      diff[i0.clamp(0, n + 1)] += 5;
      diff[(i1 + 1).clamp(0, n + 2)] -= 5;
    }
  }
  var acc = 0.0;
  for (var i = 0; i <= n; i++) {
    acc += diff[i];
    cost[i] = acc;
  }
  final s = math.max(1, span ~/ res);
  // f[i] : (morceaux, coût) pour couvrir jusqu'à la position i.
  final cnt = List<int>.filled(n + 1, 1 << 30);
  final best = List<double>.filled(n + 1, double.infinity);
  final prev = List<int>.filled(n + 1, -1);
  cnt[0] = 0;
  best[0] = 0;
  for (var i = 1; i <= n; i++) {
    final c = i == n ? 0.0 : cost[i];
    for (var j = math.max(0, i - s); j < i; j++) {
      if (cnt[j] >= 1 << 30) continue;
      final k = cnt[j] + 1;
      final v = best[j] + c;
      if (k < cnt[i] || (k == cnt[i] && v < best[i])) {
        cnt[i] = k;
        best[i] = v;
        prev[i] = j;
      }
    }
  }
  final out = <int>[];
  for (var i = n; i > 0; i = prev[i]) {
    out.add(i == n ? hi : lo + i * res);
  }
  out.add(lo);
  return out.reversed.toList();
}

// ─────────────────────────── Découpe d'un élément ───────────────────────────

/// Garde la partie d'une ligne de points située dans le rectangle ;
/// les points de bord sont recalculés exactement sur la limite.
List<List<Stitch>> _clip(List<Stitch> pts, double x0, double y0, double x1, double y1) {
  bool inside(Stitch p) => p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1;
  final out = <List<Stitch>>[];
  var cur = <Stitch>[];
  void close() {
    if (cur.length >= 2) out.add(cur);
    cur = <Stitch>[];
  }

  if (pts.length == 1) return inside(pts.first) ? [pts] : const [];
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    // Liang-Barsky.
    final dx = (b.x - a.x).toDouble(), dy = (b.y - a.y).toDouble();
    var t0 = 0.0, t1 = 1.0;
    var ok = true;
    for (final (pp, q) in [(-dx, a.x - x0), (dx, x1 - a.x), (-dy, a.y - y0), (dy, y1 - a.y)]) {
      if (pp == 0) {
        if (q < 0) ok = false;
      } else {
        final t = q / pp;
        if (pp < 0) {
          if (t > t1) ok = false;
          if (t > t0) t0 = t;
        } else {
          if (t < t0) ok = false;
          if (t < t1) t1 = t;
        }
      }
      if (!ok) break;
    }
    if (!ok || t0 > t1) {
      close();
      continue;
    }
    final e = t0 == 0 ? a : Stitch((a.x + dx * t0).round(), (a.y + dy * t0).round(), StitchType.stitch);
    final f = t1 == 1 ? b : Stitch((a.x + dx * t1).round(), (a.y + dy * t1).round(), StitchType.stitch);
    if (t0 > 0) close();
    if (cur.isEmpty) cur.add(e);
    if (f.x != cur.last.x || f.y != cur.last.y) cur.add(f);
    if (t1 < 1) close();
  }
  close();
  return out;
}

// ─────────────────────────── Assemblage ───────────────────────────

/// Points d'arrêt (3 petits points) pour qu'un bord coupé ne se défasse pas.
List<Stitch> _lock(Stitch at, Stitch toward) {
  final dx = toward.x - at.x, dy = toward.y - at.y;
  final d = math.sqrt(dx * dx + dy * dy);
  if (d < 1) return [at];
  final ux = (dx / d * 7).round(), uy = (dy / d * 7).round(); // 0,7 mm
  final q = Stitch(at.x + ux, at.y + uy, StitchType.stitch);
  return [at, q, at];
}

/// Ligne en point droit, points de longueur ≤ [len] répartis également.
List<Stitch> _run(List<(int, int)> poly, int len) {
  final out = <Stitch>[Stitch(poly.first.$1, poly.first.$2, StitchType.stitch)];
  for (var i = 1; i < poly.length; i++) {
    final a = poly[i - 1], b = poly[i];
    final d = math.sqrt(((b.$1 - a.$1) * (b.$1 - a.$1) + (b.$2 - a.$2) * (b.$2 - a.$2)).toDouble());
    final k = math.max(1, (d / len).ceil());
    for (var j = 1; j <= k; j++) {
      out.add(Stitch((a.$1 + (b.$1 - a.$1) * j / k).round(), (a.$2 + (b.$2 - a.$2) * j / k).round(),
          StitchType.stitch));
    }
  }
  return out;
}

/// Rectangle en point droit commençant au coin le plus proche de (sx, sy).
List<Stitch> frameStitches(Bounds b, int runLen, int sx, int sy) {
  final corners = [(b.minX, b.minY), (b.maxX, b.minY), (b.maxX, b.maxY), (b.minX, b.maxY)];
  var k = 0;
  for (var i = 1; i < 4; i++) {
    double d((int, int) c) => ((c.$1 - sx) * (c.$1 - sx) + (c.$2 - sy) * (c.$2 - sy)).toDouble();
    if (d(corners[i]) < d(corners[k])) k = i;
  }
  final poly = [for (var i = 0; i <= 4; i++) corners[(k + i) % 4]];
  return _run(poly, runLen);
}

/// Croix de repérage (branches de 1,5 mm), en point droit.
List<Stitch> _cross(int x, int y) {
  const a = 15;
  return _run([(x, y), (x - a, y), (x + a, y), (x, y), (x, y - a), (x, y + a), (x, y)], 15);
}

Bounds _union(Bounds a, Bounds b) => Bounds(math.min(a.minX, b.minX), math.min(a.minY, b.minY),
    math.max(a.maxX, b.maxX), math.max(a.maxY, b.maxY));

/// Ajoute un cadre (cousu en premier) autour d'un dessin, sans découpe.
EmbPattern addFrame(EmbPattern p, {double marginMm = 5, double runMm = 5.8}) {
  final b = p.bounds;
  final m = (marginMm * 10).round();
  final fb = Bounds(b.minX - m, b.minY - m, b.maxX + m, b.maxY + m);
  final first = p.stitches.firstWhere((s) => s.isStitch, orElse: () => const Stitch(0, 0, StitchType.stitch));
  final f = frameStitches(fb, (runMm * 10).round(), first.x, first.y);
  return p.copyWith(stitches: [
    Stitch(f.first.x, f.first.y, StitchType.jump),
    ...f,
    Stitch(f.last.x, f.last.y, StitchType.trim),
    ...p.stitches,
  ]);
}

/// Prépare un dessin pour un cadre de machine : découpe intelligente si besoin
/// (lignes dans les vides, éléments gardés entiers quand ils tiennent),
/// recouvrement, croix de repérage, cadre en point droit cousu en premier
/// et point de départ choisi pour chaque morceau.
PrepResult prepareForHoop(EmbPattern p, PrepOptions o) {
  final b = p.bounds;
  if (p.stitchCount == 0) return const PrepResult([], [], [], 'Dessin vide.');
  const safety = 20; // 2 mm de sécurité contre le bord du cadre
  final m = (o.frame || o.marks) ? math.max(30, (o.marginMm * 10).round()) : 0; // ≥ 3 mm pour loger les croix
  final maxW = (o.hoopWmm * 10).round() - 2 * (m + safety);
  final maxH = (o.hoopHmm * 10).round() - 2 * (m + safety);
  if (maxW < 100 || maxH < 100) {
    return const PrepResult([], [], [], 'Cadre trop petit pour ces marges.');
  }
  final ov = o.overlapMm <= 0 ? 0 : (o.overlapMm * 10).round();
  final fits = b.width <= maxW && b.height <= maxH;
  if (!fits && !o.split) {
    return PrepResult(const [], const [], const [],
        'Le dessin (${(b.width / 100).toStringAsFixed(1)} × ${(b.height / 100).toStringAsFixed(1)} cm) '
        'dépasse le cadre. Activez la découpe.');
  }
  final objs = _objects(p);
  final xs = _cuts(objs, b.minX, b.maxX, maxW - ov, true);
  final ys = _cuts(objs, b.minY, b.maxY, maxH - ov, false);
  final cols = xs.length - 1, rows = ys.length - 1;
  final half = ov / 2;

  // Fenêtres (avec recouvrement) et contenu de chaque morceau.
  final windows = <Bounds>[];
  final boxes = <Bounds?>[];
  final content = <List<(_Obj, List<List<Stitch>>, bool)>>[];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      windows.add(Bounds((xs[c] - (c > 0 ? half : 0)).round(), (ys[r] - (r > 0 ? half : 0)).round(),
          (xs[c + 1] + (c < cols - 1 ? half : 0)).round(), (ys[r + 1] + (r < rows - 1 ? half : 0)).round()));
      boxes.add(null);
      content.add([]);
    }
  }
  int cellOf(double v, List<int> cuts) {
    for (var i = 0; i < cuts.length - 2; i++) {
      if (v < cuts[i + 1]) return i;
    }
    return cuts.length - 2;
  }

  final whole = List<int>.filled(windows.length, 0), cut = List<int>.filled(windows.length, 0);
  for (final ob in objs) {
    final home = cellOf(ob.cy, ys) * cols + cellOf(ob.cx, xs);
    final w = windows[home];
    final ob0 = Bounds(ob.minX, ob.minY, ob.maxX, ob.maxY);
    final insideHome =
        ob.minX >= w.minX && ob.maxX <= w.maxX && ob.minY >= w.minY && ob.maxY <= w.maxY;
    if (insideHome || cols * rows == 1) {
      content[home].add((ob, [ob.pts], false));
      boxes[home] = boxes[home] == null ? ob0 : _union(boxes[home]!, ob0);
      continue;
    }
    // Garder l'élément entier si le morceau tient encore dans le cadre.
    final grown = _union(boxes[home] ?? ob0, _union(ob0, w));
    if (grown.width <= maxW && grown.height <= maxH) {
      content[home].add((ob, [ob.pts], false));
      boxes[home] = _union(boxes[home] ?? ob0, ob0);
      whole[home]++;
      continue;
    }
    // Sinon : coupé à la ligne, avec recouvrement.
    for (var i = 0; i < windows.length; i++) {
      final wi = windows[i];
      if (ob.maxX < wi.minX || ob.minX > wi.maxX || ob.maxY < wi.minY || ob.minY > wi.maxY) continue;
      final parts = _clip(ob.pts, wi.minX.toDouble(), wi.minY.toDouble(), wi.maxX.toDouble(),
          wi.maxY.toDouble());
      if (parts.isEmpty) continue;
      content[i].add((ob, parts, true));
      for (final part in parts) {
        for (final s in part) {
          final pb = Bounds(s.x, s.y, s.x, s.y);
          boxes[i] = boxes[i] == null ? pb : _union(boxes[i]!, pb);
        }
      }
      cut[i]++;
    }
  }

  final pieces = <PrepPiece>[];
  for (var i = 0; i < windows.length; i++) {
    if (content[i].isEmpty) continue;
    final r = i ~/ cols, c = i % cols;
    final w = windows[i];
    final box = boxes[i]!;
    // Repères sur les lignes de coupe partagées, dans la marge (hors dessin).
    final marks = <(int, int)>[];
    if (o.marks && m > 0) {
      final rowTop = math.max(w.minY, b.minY), rowBot = math.min(w.maxY, b.maxY);
      final colL = math.max(w.minX, b.minX), colR = math.min(w.maxX, b.maxX);
      final inner = Bounds(math.min(box.minX, colL), math.min(box.minY, rowTop), math.max(box.maxX, colR),
          math.max(box.maxY, rowBot));
      for (final x in [if (c > 0) xs[c], if (c < cols - 1) xs[c + 1]]) {
        marks.add((x, inner.minY - m ~/ 2));
        marks.add((x, inner.maxY + m ~/ 2));
      }
      for (final y in [if (r > 0) ys[r], if (r < rows - 1) ys[r + 1]]) {
        marks.add((inner.minX - m ~/ 2, y));
        marks.add((inner.maxX + m ~/ 2, y));
      }
    }
    // Les croix sont dans la marge (à m/2 du dessin) : le cadre les entoure déjà.
    var area = box;
    if (marks.isNotEmpty) {
      final rowTop = math.max(w.minY, b.minY), rowBot = math.min(w.maxY, b.maxY);
      final colL = math.max(w.minX, b.minX), colR = math.min(w.maxX, b.maxX);
      area = _union(box, Bounds(colL, rowTop, colR, rowBot));
    }

    final an = o.pieceAnchors[pieces.length + 1] ?? o.anchor;
    final (piece, ox, oy) = _assemble(p, content[i], area, marks, o, m, an,
        cols * rows == 1 ? p.name : '${p.name}_${pieces.length + 1}');
    pieces.add(PrepPiece(pieces.length + 1, c, r, w, piece, whole[i], cut[i], ox, oy));
  }
  return PrepResult(xs, ys, pieces);
}

/// Assemble un morceau : cadre (cousu en premier, depuis le coin le plus proche
/// du départ), croix de repérage, puis le dessin ; origine au point de départ.
(EmbPattern, int, int) _assemble(EmbPattern p, List<(_Obj, List<List<Stitch>>, bool)> content, Bounds area,
    List<(int, int)> marks, PrepOptions o, int m, StartAnchor an, String name) {
  final runLen = (o.runMm * 10).round();
  final out = <Stitch>[];
  var colors = <int>[];
  final blocks = <int>[];
  int? lastBlock;
  Stitch? last;
  void trimHere() {
    if (last != null && out.isNotEmpty && out.last.type != StitchType.trim) {
      out.add(Stitch(last!.x, last!.y, StitchType.trim));
    }
  }

  // Point de départ choisi : le cadre commence au coin le plus proche.
  final ax = [area.minX, (area.minX + area.maxX) ~/ 2, area.maxX];
  final ay = [area.minY, (area.minY + area.maxY) ~/ 2, area.maxY];
  final ai = an == StartAnchor.original ? 5 : an.index;
  final sx = ax[(ai - 1) % 3], sy = ay[(ai - 1) ~/ 3];

  void preamble() {
    if (o.frame) {
      final fb = Bounds(area.minX - m, area.minY - m, area.maxX + m, area.maxY + m);
      final f = frameStitches(fb, runLen, sx, sy);
      out.add(Stitch(f.first.x, f.first.y, StitchType.jump));
      out.addAll(f);
      last = f.last;
      trimHere();
    }
    for (final mk in marks) {
      final cr = _cross(mk.$1, mk.$2);
      out.add(Stitch(cr.first.x, cr.first.y, StitchType.jump));
      out.addAll(cr);
      last = cr.last;
      trimHere();
    }
  }

  preamble();
  for (final (ob, parts, isCut) in content) {
    if (lastBlock != null && ob.block != lastBlock) {
      out.add(Stitch(last!.x, last!.y, StitchType.colorChange));
    }
    if (lastBlock != ob.block) blocks.add(ob.block);
    lastBlock = ob.block;
    for (var k = 0; k < parts.length; k++) {
      final part = parts[k];
      final first = part.first;
      final far = last == null ||
          math.max((first.x - last!.x).abs(), (first.y - last!.y).abs()) > 70;
      final needTrim = isCut || ob.trimBefore || k > 0;
      if (last != null && (needTrim && far)) trimHere();
      if (last == null || out.last.type == StitchType.trim || out.last.type == StitchType.colorChange) {
        out.add(Stitch(first.x, first.y, StitchType.jump));
      } else if (first.x != last!.x || first.y != last!.y) {
        out.add(Stitch(first.x, first.y, StitchType.jump));
      }
      if (isCut && part.length > 1) {
        out.addAll(_lock(first, part[1]));
        out.addAll(part.skip(1).take(part.length - 2));
        out.addAll(_lock(part.last, part[part.length - 2]));
      } else {
        out.addAll(part);
      }
      last = out.last;
    }
  }
  trimHere();
  out.add(Stitch(last!.x, last!.y, StitchType.end));
  colors = [for (final bl in blocks) p.colorOfBlock(bl)];
  // Origine machine au point de départ choisi.
  return (
    EmbPattern(
    name: name,
    stitches: [for (final s in out) Stitch(s.x - sx, s.y - sy, s.type)],
    colors: colors,
    ),
    sx,
    sy,
  );
}

// ─────────────────────────── Découpe à la main ───────────────────────────

/// Lignes de coupe tracées à la main (polylignes en unités de 0,1 mm).
class CutRequest {
  final EmbPattern pattern;
  final List<List<(double, double)>> lines;
  final PrepOptions options;
  const CutRequest(this.pattern, this.lines, this.options);
}

class CutResult {
  final List<PrepPiece> pieces;
  final List<int> pieceRegion; // zone de la grille de chaque morceau
  final Int32List labels; // zone de chaque case (grille de [res])
  final int gw, gh, gx0, gy0, res;
  final String? error;
  const CutResult(this.pieces, this.pieceRegion, this.labels, this.gw, this.gh, this.gx0, this.gy0,
      this.res,
      [this.error]);
}

CutResult cutRequest(CutRequest r) => cutByLines(r.pattern, r.lines, r.options);

/// Lignes droites proposées automatiquement (dans les vides), pour un cadre donné.
List<List<(double, double)>> suggestCutLines(EmbPattern p, PrepOptions o) {
  final r = prepareForHoop(p, o);
  final b = p.bounds;
  return [
    for (final x in r.xs.skip(1).take(math.max(0, r.xs.length - 2)))
      [(x.toDouble(), b.minY - 80.0), (x.toDouble(), b.maxY + 80.0)],
    for (final y in r.ys.skip(1).take(math.max(0, r.ys.length - 2)))
      [(b.minX - 80.0, y.toDouble()), (b.maxX + 80.0, y.toDouble())],
  ];
}

/// Découpe le dessin le long de lignes libres (même tordues) : les lignes
/// partagent le plan en zones, chaque zone devient un morceau. Un élément
/// traversé par une ligne est coupé exactement sur la ligne, avec recouvrement
/// et points d'arrêt ; les autres restent entiers.
CutResult cutByLines(EmbPattern p, List<List<(double, double)>> lines, PrepOptions o) {
  final b = p.bounds;
  if (p.stitchCount == 0) {
    return CutResult(const [], const [], Int32List(0), 0, 0, 0, 0, 10, 'Dessin vide.');
  }
  const pad = 60;
  var res = 10; // 1 mm
  while (((b.width + 2 * pad) / res) * ((b.height + 2 * pad) / res) > 3e6) {
    res += 5;
  }
  final gx0 = b.minX - pad, gy0 = b.minY - pad;
  final gw = ((b.width + 2 * pad) / res).ceil() + 1, gh = ((b.height + 2 * pad) / res).ceil() + 1;
  final barrier = Uint8List(gw * gh);
  final diag = math.sqrt(gw * gw + gh * gh.toDouble()) * res;

  // 1. Tracé des lignes (prolongées jusqu'au bord), barrière 4-connexe.
  final lineCells = <List<int>>[];
  final paths = <List<(double, double)>>[];
  for (final raw in lines) {
    if (raw.length < 2) continue;
    final pts = List.of(raw);
    (double, double) ext((double, double) a, (double, double) from) {
      final dx = a.$1 - from.$1, dy = a.$2 - from.$2;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < 1e-6) return a;
      return (a.$1 + dx / d * diag, a.$2 + dy / d * diag);
    }

    // Direction des extrémités : sur ~5 mm pour ignorer le tremblement du doigt.
    var i1 = 1;
    while (i1 < pts.length - 1 &&
        math.sqrt(math.pow(pts[i1].$1 - pts[0].$1, 2) + math.pow(pts[i1].$2 - pts[0].$2, 2)) < 50) {
      i1++;
    }
    var i2 = pts.length - 2;
    while (i2 > 0 &&
        math.sqrt(math.pow(pts[i2].$1 - pts.last.$1, 2) + math.pow(pts[i2].$2 - pts.last.$2, 2)) < 50) {
      i2--;
    }
    final full = [ext(pts.first, pts[i1]), ...pts, ext(pts.last, pts[i2])];
    paths.add(full);
    final cells = <int>[];
    int? last;
    void mark(int cx, int cy) {
      if (cx < 0 || cy < 0 || cx >= gw || cy >= gh) return;
      final c = cy * gw + cx;
      if (c == last) return;
      if (last != null) {
        final lx = last! % gw, ly = last! ~/ gw;
        if (lx != cx && ly != cy && lx >= 0) {
          final m = ly * gw + cx; // coin : ferme le passage en diagonale
          barrier[m] = 1;
          cells.add(m);
        }
      }
      barrier[c] = 1;
      cells.add(c);
      last = c;
    }

    for (var k = 1; k < full.length; k++) {
      final ax = (full[k - 1].$1 - gx0) / res, ay = (full[k - 1].$2 - gy0) / res;
      final bx = (full[k].$1 - gx0) / res, by = (full[k].$2 - gy0) / res;
      final n = math.max(1, (math.max((bx - ax).abs(), (by - ay).abs()) * 3).ceil());
      for (var j = 0; j <= n; j++) {
        final x = ax + (bx - ax) * j / n, y = ay + (by - ay) * j / n;
        if (x < -1 || y < -1 || x > gw || y > gh) {
          last = null;
          continue;
        }
        mark(x.floor(), y.floor());
      }
    }
    lineCells.add(cells);
  }

  // 2. Zones (remplissage 4-connexe), dans l'ordre de lecture.
  final labels = Int32List(gw * gh)..fillRange(0, gw * gh, -1);
  var regions = 0;
  final stack = <int>[];
  for (var c0 = 0; c0 < gw * gh; c0++) {
    if (barrier[c0] == 1 || labels[c0] >= 0) continue;
    final id = regions++;
    labels[c0] = id;
    stack.add(c0);
    while (stack.isNotEmpty) {
      final c = stack.removeLast();
      final x = c % gw, y = c ~/ gw;
      for (final n in [if (x > 0) c - 1, if (x < gw - 1) c + 1, if (y > 0) c - gw, if (y < gh - 1) c + gw]) {
        if (barrier[n] == 0 && labels[n] < 0) {
          labels[n] = id;
          stack.add(n);
        }
      }
    }
  }
  // Zones voisines de chaque ligne (pour les croix de repérage).
  final lineRegions = [
    for (final cells in lineCells)
      {
        for (final c in cells)
          for (final n in [c - 1, c + 1, c - gw, c + gw])
            if (n >= 0 && n < gw * gh && labels[n] >= 0) labels[n]
      }
  ];
  // Les cases de la ligne rejoignent une zone voisine.
  var changed = true;
  while (changed) {
    changed = false;
    for (var c = 0; c < gw * gh; c++) {
      if (labels[c] >= 0) continue;
      final x = c % gw;
      for (final n in [if (x > 0) c - 1, if (x < gw - 1) c + 1, c - gw, c + gw]) {
        if (n >= 0 && n < gw * gh && labels[n] >= 0) {
          labels[c] = labels[n];
          changed = true;
          break;
        }
      }
    }
  }
  if (regions > 60) {
    return CutResult(const [], const [], labels, gw, gh, gx0, gy0, res,
        'Trop de zones ($regions) : simplifiez les lignes.');
  }

  // 3. Appartenance élargie (recouvrement) : masque des zones à moins de ov/2.
  final rc = o.overlapMm <= 0 ? 0 : ((o.overlapMm * 5) / res).ceil();
  var mask = List<int>.generate(gw * gh, (c) => labels[c] < 0 ? 0 : 1 << labels[c]);
  if (rc > 0) {
    final tmp = List<int>.filled(gw * gh, 0);
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        var v = 0;
        for (var d = -rc; d <= rc; d++) {
          final xx = x + d;
          if (xx >= 0 && xx < gw) v |= mask[y * gw + xx];
        }
        tmp[y * gw + x] = v;
      }
    }
    final out = List<int>.filled(gw * gh, 0);
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        var v = 0;
        for (var d = -rc; d <= rc; d++) {
          final yy = y + d;
          if (yy >= 0 && yy < gh) v |= tmp[yy * gw + x];
        }
        out[y * gw + x] = v;
      }
    }
    mask = out;
  }
  int cellAt(num x, num y) {
    final cx = ((x - gx0) / res).floor().clamp(0, gw - 1);
    final cy = ((y - gy0) / res).floor().clamp(0, gh - 1);
    return cy * gw + cx;
  }

  // 4. Répartition des éléments.
  final objs = _objects(p);
  final content = List.generate(regions, (_) => <(_Obj, List<List<Stitch>>, bool)>[]);
  final whole = List<int>.filled(regions, 0), cutN = List<int>.filled(regions, 0);
  for (final ob in objs) {
    var own = -1;
    var single = true;
    var any = 0;
    for (final s in ob.pts) {
      final c = cellAt(s.x, s.y);
      final l = labels[c];
      if (own < 0) own = l;
      if (l != own) single = false;
      any |= mask[c];
    }
    // Segments longs : vérifier aussi entre les points.
    if (single) {
      for (var i = 1; i < ob.pts.length && single; i++) {
        final a = ob.pts[i - 1], q = ob.pts[i];
        final d = math.max((q.x - a.x).abs(), (q.y - a.y).abs());
        if (d <= res) continue;
        final n = (d / res).ceil();
        for (var j = 1; j < n; j++) {
          if (labels[cellAt(a.x + (q.x - a.x) * j / n, a.y + (q.y - a.y) * j / n)] != own) {
            single = false;
            break;
          }
        }
      }
    }
    if (single) {
      content[own].add((ob, [ob.pts], false));
      whole[own]++;
      continue;
    }
    for (var r = 0; r < regions; r++) {
      if (any & (1 << r) == 0) continue;
      final bit = 1 << r;
      bool inR(double x, double y) => mask[cellAt(x, y)] & bit != 0;
      final parts = <List<Stitch>>[];
      var cur = <Stitch>[];
      void add(int x, int y) {
        if (cur.isEmpty || cur.last.x != x || cur.last.y != y) cur.add(Stitch(x, y, StitchType.stitch));
      }

      void close() {
        if (cur.length >= 2) parts.add(cur);
        cur = <Stitch>[];
      }

      final f = ob.pts.first;
      var prevIn = inR(f.x.toDouble(), f.y.toDouble());
      if (prevIn) add(f.x, f.y);
      for (var i = 1; i < ob.pts.length; i++) {
        final a = ob.pts[i - 1], q = ob.pts[i];
        final len = math.max((q.x - a.x).abs(), (q.y - a.y).abs());
        final n = math.max(1, (len / 5).ceil()); // échantillons tous les 0,5 mm
        var px = a.x.toDouble(), py = a.y.toDouble();
        for (var j = 1; j <= n; j++) {
          final x = a.x + (q.x - a.x) * j / n, y = a.y + (q.y - a.y) * j / n;
          final inq = inR(x, y);
          if (inq && !prevIn) add(x.round(), y.round());
          if (!inq && prevIn) {
            add(px.round(), py.round());
            close();
          }
          if (inq && j == n) add(q.x, q.y);
          prevIn = inq;
          px = x;
          py = y;
        }
      }
      close();
      if (parts.isEmpty) continue;
      content[r].add((ob, parts, true));
      cutN[r]++;
    }
  }

  // 5. Croix de repérage : sur chaque ligne, juste hors du dessin.
  final m = (o.frame || o.marks) ? math.max(30, (o.marginMm * 10).round()) : 0;
  final marksOf = List.generate(regions, (_) => <(int, int)>[]);
  if (o.marks && m > 0) {
    final e = m ~/ 2;
    bool inB(double x, double y) =>
        x >= b.minX - e && x <= b.maxX + e && y >= b.minY - e && y <= b.maxY + e;
    for (var li = 0; li < paths.length; li++) {
      final pts = <(double, double)>[];
      final path = paths[li];
      for (var k = 1; k < path.length; k++) {
        final a = path[k - 1], q = path[k];
        final len = math.sqrt(math.pow(q.$1 - a.$1, 2) + math.pow(q.$2 - a.$2, 2));
        final n = math.max(1, (len / 5).ceil());
        for (var j = 0; j <= n; j++) {
          final x = a.$1 + (q.$1 - a.$1) * j / n, y = a.$2 + (q.$2 - a.$2) * j / n;
          if (inB(x, y)) pts.add((x, y));
        }
      }
      if (pts.isEmpty) continue;
      for (final pt in [pts.first, pts.last]) {
        for (final r in lineRegions[li]) {
          if (r < regions) marksOf[r].add((pt.$1.round(), pt.$2.round()));
        }
      }
    }
  }

  // 6. Assemblage des morceaux.
  final pieces = <PrepPiece>[];
  final pieceRegion = <int>[];
  for (var r = 0; r < regions; r++) {
    if (content[r].isEmpty) continue;
    Bounds? box;
    for (final (_, parts, _) in content[r]) {
      for (final part in parts) {
        for (final s in part) {
          final pb = Bounds(s.x, s.y, s.x, s.y);
          box = box == null ? pb : _union(box, pb);
        }
      }
    }
    var area = box!;
    for (final mk in marksOf[r]) {
      area = _union(area, Bounds(mk.$1 - 15, mk.$2 - 15, mk.$1 + 15, mk.$2 + 15));
    }
    final idx = pieces.length + 1;
    final an = o.pieceAnchors[idx] ?? o.anchor;
    final (piece, ox, oy) = _assemble(p, content[r], area, marksOf[r], o, m, an, '${p.name}_$idx');
    pieces.add(PrepPiece(idx, 0, 0, box, piece, whole[r], cutN[r], ox, oy));
    pieceRegion.add(r);
  }
  if (pieces.length == 1) {
    pieces[0] = PrepPiece(1, 0, 0, pieces[0].window, pieces[0].pattern.copyWith(name: p.name),
        pieces[0].wholeObjects, pieces[0].cutObjects, pieces[0].originX, pieces[0].originY);
  }
  return CutResult(pieces, pieceRegion, labels, gw, gh, gx0, gy0, res);
}

/// Rotation d'un quart de tour (sens horaire), pour faire tenir un morceau dans le cadre.
EmbPattern rotate90(EmbPattern p) =>
    p.copyWith(stitches: [for (final s in p.stitches) Stitch(-s.y, s.x, s.type)]);

/// Le dessin tient-il dans le cadre (dimensions en mm) ?
bool fitsHoop(EmbPattern p, double hoopWmm, double hoopHmm) {
  final b = p.bounds;
  return b.width <= hoopWmm * 10 && b.height <= hoopHmm * 10;
}

/// Rotation libre (degrés, sens horaire) autour du centre du dessin.
EmbPattern rotateDeg(EmbPattern p, double deg) {
  final d = deg % 360;
  if (d == 0) return p;
  final b = p.bounds;
  final cx = (b.minX + b.maxX) / 2, cy = (b.minY + b.maxY) / 2;
  final a = d * math.pi / 180, c = math.cos(a), s = math.sin(a);
  return p.copyWith(stitches: [
    for (final t in p.stitches)
      Stitch((cx + (t.x - cx) * c - (t.y - cy) * s).round(), (cy + (t.x - cx) * s + (t.y - cy) * c).round(),
          t.type)
  ]);
}
