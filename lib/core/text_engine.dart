import 'dart:math' as math;

import 'font_block.dart';
import 'pattern.dart';

/// Tissus : chaque profil ajuste la densité, la compensation de traction et la couche de soutien.
enum Fabric { coton, jean, polo, serviette, casquette, cuir }

extension FabricInfo on Fabric {
  String get label => switch (this) {
        Fabric.coton => 'Coton',
        Fabric.jean => 'Jean',
        Fabric.polo => 'Polo / maille',
        Fabric.serviette => 'Serviette',
        Fabric.casquette => 'Casquette',
        Fabric.cuir => 'Cuir',
      };

  /// Écart entre deux points satin (mm).
  double get densityMm => switch (this) {
        Fabric.coton => 0.40,
        Fabric.jean => 0.42,
        Fabric.polo => 0.38,
        Fabric.serviette => 0.36,
        Fabric.casquette => 0.40,
        Fabric.cuir => 0.50,
      };

  /// Élargissement de chaque côté de la colonne pour compenser la traction du fil (mm).
  double get pullCompMm => switch (this) {
        Fabric.coton => 0.20,
        Fabric.jean => 0.15,
        Fabric.polo => 0.35,
        Fabric.serviette => 0.30,
        Fabric.casquette => 0.25,
        Fabric.cuir => 0.10,
      };

  /// Passage central sous le satin.
  bool get centerUnderlay => this != Fabric.cuir;

  /// Zigzag de soutien supplémentaire (colonnes larges, tissus souples ou épais).
  bool get zigzagUnderlay =>
      this == Fabric.coton ||
      this == Fabric.polo ||
      this == Fabric.serviette ||
      this == Fabric.casquette;
}

/// Coupe du fil entre les lettres.
enum TrimMode { none, auto, all }

extension TrimModeInfo on TrimMode {
  String get label => switch (this) {
        TrimMode.none => 'Aucune',
        TrimMode.auto => 'Selon la distance',
        TrimMode.all => 'Entre chaque lettre',
      };
}

/// Paramètres d'un texte brodé. Tout le motif est recalculé à partir d'eux.
class TextDesign {
  final String text;
  final double heightMm;
  final double letterSpacingMm;
  final bool autoWidth;
  final double columnWidthMm;
  final bool autoDensity;
  final double densityMm;
  final Fabric fabric;
  final int color;

  /// Coupe du fil : jamais, au-delà de [jumpMaxMm], ou entre chaque lettre.
  final TrimMode trimMode;

  /// Distance au-delà de laquelle le fil est coupé (mode « selon la distance »).
  final double jumpMaxMm;

  const TextDesign({
    this.text = 'FARES',
    this.heightMm = 20,
    this.letterSpacingMm = 2.0,
    this.autoWidth = true,
    this.columnWidthMm = 3,
    this.autoDensity = true,
    this.densityMm = 0.40,
    this.fabric = Fabric.coton,
    this.color = 0xFFD4AF37,
    this.trimMode = TrimMode.auto,
    this.jumpMaxMm = 5,
  });

  TextDesign copyWith({
    String? text,
    double? heightMm,
    double? letterSpacingMm,
    bool? autoWidth,
    double? columnWidthMm,
    bool? autoDensity,
    double? densityMm,
    Fabric? fabric,
    int? color,
    TrimMode? trimMode,
    double? jumpMaxMm,
  }) =>
      TextDesign(
        text: text ?? this.text,
        heightMm: heightMm ?? this.heightMm,
        letterSpacingMm: letterSpacingMm ?? this.letterSpacingMm,
        autoWidth: autoWidth ?? this.autoWidth,
        columnWidthMm: columnWidthMm ?? this.columnWidthMm,
        autoDensity: autoDensity ?? this.autoDensity,
        densityMm: densityMm ?? this.densityMm,
        fabric: fabric ?? this.fabric,
        color: color ?? this.color,
        trimMode: trimMode ?? this.trimMode,
        jumpMaxMm: jumpMaxMm ?? this.jumpMaxMm,
      );

  String get normalized => text.toUpperCase();

  double get effectiveWidthMm =>
      autoWidth ? (heightMm * 0.15).clamp(1.2, 7.0).toDouble() : columnWidthMm;

  double get effectiveDensityMm => autoDensity ? fabric.densityMm : densityMm;

  /// Caractères que la police ne sait pas broder.
  List<String> get unsupported {
    final set = <String>{};
    for (final r in normalized.runes) {
      final c = String.fromCharCode(r);
      if (!blockFont.containsKey(c)) set.add(c);
    }
    return set.toList();
  }

  EmbPattern generate() => _TextBuilder(this).build();
}

// ───────────────────────── Géométrie ─────────────────────────

class _V {
  final double x, y;
  const _V(this.x, this.y);
  _V operator +(_V o) => _V(x + o.x, y + o.y);
  _V operator -(_V o) => _V(x - o.x, y - o.y);
  _V operator *(double k) => _V(x * k, y * k);
  double get len => math.sqrt(x * x + y * y);
  _V get unit {
    final l = len;
    return l < 1e-9 ? const _V(0, 0) : _V(x / l, y / l);
  }

  double dot(_V o) => x * o.x + y * o.y;
  double dist(_V o) => (this - o).len;
}

/// Échantillonneur le long d'une ligne (ouverte ou fermée), avec normales lissées.
class _Sampler {
  final List<_V> p;
  final List<double> cum = [0];
  final List<_V> vn = [];

  _Sampler(List<_V> pts, bool closed) : p = closed ? [...pts, pts.first] : pts {
    final m = p.length - 1;
    final segN = <_V>[];
    for (var i = 0; i < m; i++) {
      final d = p[i + 1] - p[i];
      cum.add(cum.last + d.len);
      final u = d.unit;
      segN.add(_V(-u.y, u.x));
    }
    _V combine(_V a, _V b) {
      final s = a + b;
      if (s.len < 1e-6) return a;
      final v = s.unit;
      final c = math.max(v.dot(b), 0.5);
      return v * (1 / c);
    }

    for (var j = 0; j <= m; j++) {
      if (closed && (j == 0 || j == m)) {
        vn.add(combine(segN[m - 1], segN[0]));
      } else if (j == 0) {
        vn.add(segN[0]);
      } else if (j == m) {
        vn.add(segN[m - 1]);
      } else {
        vn.add(combine(segN[j - 1], segN[j]));
      }
    }
  }

  double get length => cum.last;
  _V get start => p.first;

  int _seg(double d) {
    var lo = 0, hi = cum.length - 2;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cum[mid] <= d) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  (_V, _V) at(double d) {
    final dd = d.clamp(0.0, length).toDouble();
    final i = _seg(dd);
    final segLen = cum[i + 1] - cum[i];
    final t = segLen < 1e-9 ? 0.0 : (dd - cum[i]) / segLen;
    final pos = p[i] + (p[i + 1] - p[i]) * t;
    final nrm = vn[i] * (1 - t) + vn[i + 1] * t;
    return (pos, nrm);
  }

  _V dirAt(double d) {
    final i = _seg(d.clamp(0.0, length).toDouble());
    return (p[i + 1] - p[i]).unit;
  }
}

List<_V> _dedupe(List<_V> pts) {
  final out = <_V>[];
  for (final q in pts) {
    if (out.isEmpty || out.last.dist(q) > 0.01) out.add(q);
  }
  return out;
}

// ───────────────────────── Extrémités des lignes ─────────────────────────

enum _EndMode {
  /// Prolongée d'une demi-colonne, coupe perpendiculaire (extrémité libre, angle droit).
  extend,

  /// Coupée à l'horizontale sur la ligne de base ou la ligne des capitales.
  cap,

  /// Raccourcie : la ligne entre à peine dans celle qu'elle rejoint (pas de double épaisseur).
  shorten,

  /// Laissée telle quelle.
  none,
}

class _EndSpec {
  final _EndMode mode;

  /// Ligne de coupe (unités de police) pour [_EndMode.cap] : 0 = haut, 100 = base.
  final double capY;
  const _EndSpec(this.mode, [this.capY = 0]);
}

const _free = _EndSpec(_EndMode.extend);

double _distToSegment(_V p, _V a, _V b) {
  final ab = b - a;
  final l2 = ab.dot(ab);
  if (l2 < 1e-9) return p.dist(a);
  final t = ((p - a).dot(ab) / l2).clamp(0.0, 1.0).toDouble();
  return p.dist(a + ab * t);
}

/// Règles de jonction, calculées une fois par lettre (en unités de police).
List<(_EndSpec, _EndSpec)> _endSpecs(List<GlyphStroke> strokes) {
  _V v(Pt p) => _V(p.$1, p.$2);

  _V dirInto(int i, bool start) {
    final pts = strokes[i].points;
    return start
        ? (v(pts[1]) - v(pts[0])).unit
        : (v(pts[pts.length - 2]) - v(pts[pts.length - 1])).unit;
  }

  bool axisAligned(_V d) => d.x.abs() < 0.18 || d.y.abs() < 0.18;

  /// Le point est-il posé sur le milieu d'une autre ligne (jonction en T) ?
  bool onInterior(_V p, int self, Set<int> partners) {
    for (var j = 0; j < strokes.length; j++) {
      if (j == self || partners.contains(j)) continue;
      final q = strokes[j].points;
      if (q.length < 2) continue;
      final pts = [for (final x in q) v(x)];
      if (strokes[j].closed) pts.add(pts.first);
      for (var k = 0; k + 1 < pts.length; k++) {
        if (_distToSegment(p, pts[k], pts[k + 1]) < 3) {
          if (!strokes[j].closed &&
              (p.dist(pts.first) < 1.5 || p.dist(pts.last) < 1.5)) {
            continue;
          }
          return true;
        }
      }
    }
    return false;
  }

  _EndSpec decide(int i, bool start) {
    final pts = strokes[i].points;
    final p = v(start ? pts.first : pts.last);
    final d = dirInto(i, start);
    final double? lineY =
        (p.y - 7).abs() < 1.5 ? 0 : ((p.y - 93).abs() < 1.5 ? 100 : null);
    final steep = d.y.abs() > 0.35;

    final group = <(int, bool)>[(i, start)];
    for (var j = 0; j < strokes.length; j++) {
      if (j == i || strokes[j].closed || strokes[j].points.length < 2) continue;
      final q = strokes[j].points;
      if (v(q.first).dist(p) < 0.5) group.add((j, true));
      if (v(q.last).dist(p) < 0.5) group.add((j, false));
    }
    final partners = {for (final g in group) g.$1};

    if (onInterior(p, i, partners)) return const _EndSpec(_EndMode.shorten);
    if (group.length == 1) {
      return lineY != null && steep ? _EndSpec(_EndMode.cap, lineY) : _free;
    }
    group.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (j, st) in group) {
      if (axisAligned(dirInto(j, st))) {
        return j == i && st == start
            ? (lineY != null && steep ? _EndSpec(_EndMode.cap, lineY) : _free)
            : const _EndSpec(_EndMode.shorten);
      }
    }
    // Pointe sans ligne droite (sommet du A, bas du V) : coupe à plat sur la ligne.
    return lineY != null ? _EndSpec(_EndMode.cap, lineY) : const _EndSpec(_EndMode.none);
  }

  return [
    for (var i = 0; i < strokes.length; i++)
      strokes[i].closed || strokes[i].points.length < 2
          ? (const _EndSpec(_EndMode.none), const _EndSpec(_EndMode.none))
          : (decide(i, true), decide(i, false)),
  ];
}

/// Une ligne de lettre en coordonnées de broderie (0,1 mm).
class _Stroke {
  final List<_V> pts;
  final bool closed;
  final _EndSpec startSpec, endSpec;
  final double capStartY, capEndY; // lignes de coupe déjà converties

  _Stroke(this.pts, this.closed, this.startSpec, this.endSpec, this.capStartY, this.capEndY);

  _Stroke reversed() => _Stroke(
      pts.reversed.toList(), closed, endSpec, startSpec, capEndY, capStartY);

  _Stroke rotatedTo(int k) => _Stroke(
      [...pts.sublist(k), ...pts.sublist(0, k)], closed, startSpec, endSpec, capStartY, capEndY);
}

// ───────────────────────── Colonne satin ─────────────────────────

/// Colonne satin prête à broder : coupes d'extrémité appliquées, densité mesurée
/// sur le bord extérieur, points courts à l'intérieur des courbes.
class _Column {
  final _Sampler s;
  final double half; // demi-largeur
  final bool closed;
  late final double l0, l1, r0, r1; // plage de chaque bord sur la ligne centrale
  late final double a, b; // plage commune

  _Column(_Stroke st, double width)
      : s = _Sampler(_dedupe(st.pts), st.closed),
        half = width / 2,
        closed = st.closed {
    final l = s.length;
    double startOf(double side) =>
        st.startSpec.mode == _EndMode.cap ? _capD(side, st.capStartY, true) : 0.0;
    double endOf(double side) =>
        st.endSpec.mode == _EndMode.cap ? _capD(side, st.capEndY, false) : l;
    l0 = startOf(1);
    l1 = endOf(1);
    r0 = startOf(-1);
    r1 = endOf(-1);
    a = math.max(l0, r0);
    b = math.min(l1, r1);
  }

  _V edge(double d, double side, [double k = 1]) {
    final (pos, nrm) = s.at(d);
    return pos + nrm * (side * half * k);
  }

  /// Position sur la ligne centrale où le bord [side] croise la ligne de coupe [y].
  double _capD(double side, double y, bool fromStart) {
    final l = s.length;
    final y0 = edge(fromStart ? 0 : l, side).y;
    final sign = (y0 - y).sign; // côté extérieur
    const step = 0.5;
    if (fromStart) {
      for (var d = 0.0; d <= l / 2; d += step) {
        if ((edge(d, side).y - y) * sign <= 0) return d;
      }
      return 0;
    }
    for (var d = l; d >= l / 2; d -= step) {
      if ((edge(d, side).y - y) * sign <= 0) return d;
    }
    return l;
  }

  /// Position centrale du bord [side] pour l'avancement [u] (0 → 1).
  double _dm(double side, double u) =>
      side > 0 ? l0 + (l1 - l0) * u : r0 + (r1 - r0) * u;

  /// Vitesse locale du bord [side] par rapport à l'autre (< 1 : bord intérieur d'une courbe).
  double localRatio(double d, double side) {
    const h = 3.0;
    final d0 = math.max(0.0, d - h), d1 = math.min(s.length, d + h);
    if (d1 - d0 < 1e-6) return 1.0;
    final mine = edge(d1, side).dist(edge(d0, side));
    final other = edge(d1, -side).dist(edge(d0, -side));
    return other < 1e-6 ? 1.0 : mine / other;
  }

  List<_V> satin(double spacing, {required bool forward}) {
    final out = <_V>[];
    var u = forward ? 0.0 : 1.0;
    var k = 0;
    const e = 0.002;
    while (true) {
      final side = k.isEven ? 1.0 : -1.0;
      final d = _dm(side, u);
      var p = edge(d, side);
      if ((k ~/ 2).isOdd && localRatio(d, side) < 0.65) {
        final c = s.at(d).$1;
        p = c + (p - c) * 0.45; // point court : évite l'entassement à l'intérieur
      }
      out.add(p);
      if (forward ? u >= 1 : u <= 0) break;
      // Pas réglé sur le bord qui avance le plus vite (bord extérieur).
      final un = forward ? math.min(1.0, u + e) : math.max(0.0, u - e);
      var speed = 1e-6;
      for (final sd in const [1.0, -1.0]) {
        final v = edge(_dm(sd, un), sd).dist(edge(_dm(sd, u), sd)) / e;
        if (v > speed) speed = v;
      }
      final du = spacing / speed;
      u = forward ? math.min(1.0, u + du) : math.max(0.0, u - du);
      k++;
      if (k > 200000) break;
    }
    return out;
  }

  /// Plage de soutien, en retrait des extrémités.
  (double, double) underlayRange() {
    if (closed) return (0.0, s.length);
    final inset = math.min(half * 0.6, (b - a) * 0.25);
    final u0 = a + inset, u1 = b - inset;
    return u1 > u0 ? (u0, u1) : ((a + b) / 2, (a + b) / 2);
  }
}

// ───────────────────────── Graphe de la lettre ─────────────────────────
//
// Chaque lettre devient un réseau : nœuds (extrémités, jonctions en T, croisements)
// et arêtes (morceaux de lignes). On peut ainsi circuler à l'intérieur de la lettre
// en point droit, toujours sur une ligne qui sera couverte par le satin.

double _polyLen(List<_V> p) {
  var l = 0.0;
  for (var i = 0; i + 1 < p.length; i++) {
    l += p[i].dist(p[i + 1]);
  }
  return l;
}

class _GEdge {
  final int a, b, piece;
  final List<_V> pts; // de a vers b
  final double len;
  _GEdge(this.a, this.b, this.piece, this.pts) : len = _polyLen(pts);
}

class _LetterGraph {
  final List<_V> nodes;
  final List<_GEdge> edges;
  final List<int> pieceStart, pieceEnd; // nœuds des extrémités (-1 si boucle)
  final List<List<int>> pieceNodes; // nœuds situés sur chaque ligne
  _LetterGraph(this.nodes, this.edges, this.pieceStart, this.pieceEnd, this.pieceNodes);

  /// Plus court chemin de [from] à [to] en n'empruntant que les lignes de [mask].
  /// Renvoie la longueur et la suite (arête, sens direct ?), ou null.
  (double, List<(int, bool)>)? path(int from, int to, int mask) {
    if (from == to) return (0.0, const <(int, bool)>[]);
    final n = nodes.length;
    final dist = List<double>.filled(n, double.infinity);
    final prevEdge = List<int>.filled(n, -1);
    final prevFwd = List<bool>.filled(n, true);
    final done = List<bool>.filled(n, false);
    dist[from] = 0;
    for (var it = 0; it < n; it++) {
      var u = -1;
      for (var i = 0; i < n; i++) {
        if (!done[i] && dist[i].isFinite && (u < 0 || dist[i] < dist[u])) u = i;
      }
      if (u < 0 || u == to) break;
      done[u] = true;
      for (var e = 0; e < edges.length; e++) {
        final ed = edges[e];
        if ((mask >> ed.piece) & 1 == 0) continue;
        if (ed.a == u && dist[u] + ed.len < dist[ed.b]) {
          dist[ed.b] = dist[u] + ed.len;
          prevEdge[ed.b] = e;
          prevFwd[ed.b] = true;
        }
        if (ed.b == u && dist[u] + ed.len < dist[ed.a]) {
          dist[ed.a] = dist[u] + ed.len;
          prevEdge[ed.a] = e;
          prevFwd[ed.a] = false;
        }
      }
    }
    if (!dist[to].isFinite) return null;
    final steps = <(int, bool)>[];
    var v = to;
    while (v != from) {
      final e = prevEdge[v];
      final fwd = prevFwd[v];
      steps.add((e, fwd));
      v = fwd ? edges[e].a : edges[e].b;
    }
    return (dist[to], steps.reversed.toList());
  }

  List<_V> polyline(int from, List<(int, bool)> steps) {
    final out = <_V>[nodes[from]];
    for (final (e, fwd) in steps) {
      final p = fwd ? edges[e].pts : edges[e].pts.reversed.toList();
      out.addAll(p.skip(1));
    }
    return out;
  }
}

final Map<String, _LetterGraph> _graphCache = {};

_LetterGraph _graphFor(String ch, List<GlyphStroke> strokes) =>
    _graphCache.putIfAbsent(ch, () => _buildGraph(strokes));

_LetterGraph _buildGraph(List<GlyphStroke> strokes) {
  final polys = <List<_V>>[
    for (final s in strokes)
      [
        for (final p in s.points) _V(p.$1, p.$2),
        if (s.closed && s.points.isNotEmpty) _V(s.points.first.$1, s.points.first.$2),
      ],
  ];
  final cums = <List<double>>[
    for (final p in polys)
      () {
        final c = <double>[0];
        for (var i = 0; i + 1 < p.length; i++) {
          c.add(c.last + p[i].dist(p[i + 1]));
        }
        return c;
      }(),
  ];
  final nodes = <_V>[];
  int nodeAt(_V p) {
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].dist(p) < 1.0) return i;
    }
    nodes.add(p);
    return nodes.length - 1;
  }

  _V pointAt(int i, double t) {
    final p = polys[i], c = cums[i];
    for (var k = 0; k + 1 < p.length; k++) {
      if (t <= c[k + 1] || k + 2 == p.length) {
        final seg = c[k + 1] - c[k];
        final f = seg < 1e-9 ? 0.0 : ((t - c[k]) / seg).clamp(0.0, 1.0).toDouble();
        return p[k] + (p[k + 1] - p[k]) * f;
      }
    }
    return p.last;
  }

  List<_V> sub(int i, double t0, double t1) {
    final p = polys[i], c = cums[i];
    final out = <_V>[pointAt(i, t0)];
    for (var k = 1; k + 1 < p.length; k++) {
      if (c[k] > t0 + 1e-6 && c[k] < t1 - 1e-6) out.add(p[k]);
    }
    out.add(pointAt(i, t1));
    return out;
  }

  final n = strokes.length;
  final cuts = [for (var i = 0; i < n; i++) <(double, int)>[]];
  final alias = <String, int>{};
  bool isOpen(int i) => !strokes[i].closed && polys[i].length >= 2;

  // Jonctions en T : extrémité d'une ligne posée sur le milieu d'une autre.
  for (var i = 0; i < n; i++) {
    if (polys[i].length < 2) continue;
    for (var j = 0; j < n; j++) {
      if (j == i || !isOpen(j)) continue;
      for (final start in const [true, false]) {
        final q = start ? polys[j].first : polys[j].last;
        var best = double.infinity, bestT = 0.0;
        _V bestP = q;
        for (var k = 0; k + 1 < polys[i].length; k++) {
          final a = polys[i][k], b = polys[i][k + 1];
          final ab = b - a;
          final l2 = ab.dot(ab);
          final f = l2 < 1e-9 ? 0.0 : ((q - a).dot(ab) / l2).clamp(0.0, 1.0).toDouble();
          final pr = a + ab * f;
          final dd = pr.dist(q);
          if (dd < best) {
            best = dd;
            bestT = cums[i][k] + (cums[i][k + 1] - cums[i][k]) * f;
            bestP = pr;
          }
        }
        if (best >= 3) continue;
        final li = cums[i].last;
        if (isOpen(i) && (bestT < 1.5 || bestT > li - 1.5)) continue; // extrémités partagées
        final id = nodeAt(bestP);
        cuts[i].add((bestT, id));
        alias['$j:$start'] = id;
      }
    }
  }

  // Croisements (X, Q, 4, 8…).
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      for (var k = 0; k + 1 < polys[i].length; k++) {
        for (var m = 0; m + 1 < polys[j].length; m++) {
          final p = polys[i][k], r = polys[i][k + 1] - p;
          final q = polys[j][m], s = polys[j][m + 1] - q;
          final den = r.x * s.y - r.y * s.x;
          if (den.abs() < 1e-9) continue;
          final qp = q - p;
          final u = (qp.x * s.y - qp.y * s.x) / den;
          final v = (qp.x * r.y - qp.y * r.x) / den;
          if (u <= 0 || u >= 1 || v <= 0 || v >= 1) continue;
          final x = p + r * u;
          bool nearEnd(int t) =>
              isOpen(t) && (x.dist(polys[t].first) < 1.5 || x.dist(polys[t].last) < 1.5);
          if (nearEnd(i) || nearEnd(j)) continue;
          final id = nodeAt(x);
          cuts[i].add((cums[i][k] + r.len * u, id));
          cuts[j].add((cums[j][m] + s.len * v, id));
        }
      }
    }
  }

  // Extrémités.
  final pieceStart = List<int>.filled(n, -1), pieceEnd = List<int>.filled(n, -1);
  for (var i = 0; i < n; i++) {
    if (!isOpen(i)) continue;
    final s = alias['$i:true'] ?? nodeAt(polys[i].first);
    final e = alias['$i:false'] ?? nodeAt(polys[i].last);
    cuts[i]
      ..add((0.0, s))
      ..add((cums[i].last, e));
    pieceStart[i] = s;
    pieceEnd[i] = e;
  }

  // Découpe en arêtes.
  final edges = <_GEdge>[];
  final pieceNodes = [for (var i = 0; i < n; i++) <int>[]];
  for (var i = 0; i < n; i++) {
    if (polys[i].length < 2) continue;
    final l = cums[i].last;
    final cs = [...cuts[i]]..sort((a, b) => a.$1.compareTo(b.$1));
    final clean = <(double, int)>[];
    for (final c in cs) {
      if (clean.isNotEmpty && (c.$1 - clean.last.$1).abs() < 0.5) continue;
      clean.add(c);
    }
    if (strokes[i].closed) {
      if (clean.isEmpty) clean.add((0.0, nodeAt(polys[i].first)));
      for (var k = 0; k < clean.length; k++) {
        final (t0, a) = clean[k];
        final last = k + 1 == clean.length;
        final (t1raw, b) = last ? clean[0] : clean[k + 1];
        final pts = last
            ? [...sub(i, t0, l), ...sub(i, 0, t1raw).skip(1)]
            : sub(i, t0, t1raw);
        edges.add(_GEdge(a, b, i, pts));
      }
    } else {
      for (var k = 0; k + 1 < clean.length; k++) {
        edges.add(_GEdge(clean[k].$2, clean[k + 1].$2, i, sub(i, clean[k].$1, clean[k + 1].$1)));
      }
    }
    for (final c in clean) {
      if (!pieceNodes[i].contains(c.$2)) pieceNodes[i].add(c.$2);
    }
  }
  return _LetterGraph(nodes, edges, pieceStart, pieceEnd, pieceNodes);
}

// ───────────────────────── Plan de broderie d'une lettre ─────────────────────────

/// Une colonne satin dans le plan : ligne, sens, nœud d'entrée et de sortie.
class _Piece {
  final int stroke;
  final bool reversed;
  final int entry, exit;
  const _Piece(this.stroke, this.reversed, this.entry, this.exit);
}

class _LetterPlan {
  final int entry; // nœud de départ de la lettre
  final List<(int, bool)> runWalk; // point droit sur toute la lettre (sous le satin)
  final List<_Piece> pieces;
  final List<List<(int, bool)>> links; // trajets entre colonnes (sous un satin à venir)
  const _LetterPlan(this.entry, this.runWalk, this.pieces, this.links);
}

/// Point droit d'un seul passage qui couvre toute la lettre, de [from] à [to].
(double, List<(int, bool)>) _coverWalk(_LetterGraph g, int from, int to, int allMask) {
  final covered = List<bool>.filled(g.edges.length, false);
  final steps = <(int, bool)>[];
  var at = from;
  var total = 0.0;
  int remaining() => covered.where((c) => !c).length;
  while (remaining() > 0) {
    // Arête libre au nœud courant : on préfère celle qui mène vers d'autres arêtes libres.
    var bestE = -1;
    var bestFwd = true;
    var bestScore = -double.infinity;
    for (var e = 0; e < g.edges.length; e++) {
      if (covered[e]) continue;
      final ed = g.edges[e];
      for (final fwd in const [true, false]) {
        if ((fwd ? ed.a : ed.b) != at) continue;
        final far = fwd ? ed.b : ed.a;
        var free = 0;
        for (var f = 0; f < g.edges.length; f++) {
          if (f != e && !covered[f] && (g.edges[f].a == far || g.edges[f].b == far)) free++;
        }
        final score = free * 1000 - ed.len;
        if (score > bestScore) {
          bestScore = score;
          bestE = e;
          bestFwd = fwd;
        }
      }
    }
    if (bestE >= 0) {
      covered[bestE] = true;
      steps.add((bestE, bestFwd));
      total += g.edges[bestE].len;
      at = bestFwd ? g.edges[bestE].b : g.edges[bestE].a;
      continue;
    }
    // Sinon : rejoindre la plus proche arête libre par le plus court chemin.
    (double, List<(int, bool)>)? bestPath;
    for (var e = 0; e < g.edges.length; e++) {
      if (covered[e]) continue;
      for (final target in [g.edges[e].a, g.edges[e].b]) {
        final p = g.path(at, target, allMask);
        if (p != null && (bestPath == null || p.$1 < bestPath.$1)) bestPath = p;
      }
    }
    if (bestPath == null) break; // morceau isolé (ne devrait pas arriver)
    for (final s in bestPath.$2) {
      covered[s.$1] = true;
      steps.add(s);
      at = s.$2 ? g.edges[s.$1].b : g.edges[s.$1].a;
    }
    total += bestPath.$1;
  }
  final back = g.path(at, to, allMask);
  if (back != null) {
    steps.addAll(back.$2);
    total += back.$1;
  }
  return (total, steps);
}

_LetterPlan _planLetter(_LetterGraph g, int entry, _V Function(int) pos, _V? next,
    {required bool runFirst}) {
  final n = g.pieceStart.length;
  final pieces = [for (var i = 0; i < n; i++) if (g.pieceNodes[i].isNotEmpty) i];
  var allMask = 0;
  for (final i in pieces) {
    allMask |= 1 << i;
  }
  final walkCache = <int, (double, List<(int, bool)>)>{};
  (double, List<(int, bool)>) walkTo(int t) => walkCache.putIfAbsent(
      t,
      () => runFirst
          ? _coverWalk(g, entry, t, allMask)
          : (g.path(entry, t, allMask) ?? (0.0, const <(int, bool)>[])));

  List<_Piece> options(int i) {
    if (g.pieceStart[i] >= 0) {
      return [
        _Piece(i, false, g.pieceStart[i], g.pieceEnd[i]),
        _Piece(i, true, g.pieceEnd[i], g.pieceStart[i]),
      ];
    }
    return [for (final nd in g.pieceNodes[i]) _Piece(i, false, nd, nd)];
  }

  var bestCost = double.infinity;
  List<_Piece> bestOrder = const [];
  List<List<(int, bool)>> bestLinks = const [];

  void search(List<_Piece> seq, List<List<(int, bool)>> links, int remainingMask, double cost) {
    if (cost >= bestCost) return;
    if (remainingMask == 0) {
      var c = cost + walkTo(seq.first.entry).$1;
      if (next != null) c += 0.8 * pos(seq.last.exit).dist(next);
      if (c < bestCost) {
        bestCost = c;
        bestOrder = List.of(seq);
        bestLinks = List.of(links);
      }
      return;
    }
    for (final i in pieces) {
      if ((remainingMask >> i) & 1 == 0) continue;
      for (final o in options(i)) {
        var add = 0.0;
        var link = const <(int, bool)>[];
        if (seq.isNotEmpty) {
          // Trajet caché : seulement sur des lignes pas encore brodées en satin.
          final hidden = g.path(seq.last.exit, o.entry, remainingMask);
          if (hidden != null) {
            add = hidden.$1;
            link = hidden.$2;
          } else {
            final any = g.path(seq.last.exit, o.entry, allMask);
            if (any == null) continue;
            add = any.$1 * 6 + 200; // visible sur le satin : fortement pénalisé
            link = any.$2;
          }
        }
        search([...seq, o], [...links, link], remainingMask & ~(1 << i), cost + add);
      }
    }
  }

  search([], [], allMask, 0);
  final walk = bestOrder.isEmpty ? const <(int, bool)>[] : walkTo(bestOrder.first.entry).$2;
  return _LetterPlan(entry, walk, bestOrder, bestLinks);
}

// ───────────────────────── Génération ─────────────────────────

class _TextBuilder {
  final TextDesign d;
  final out = <Stitch>[];
  _V cur = const _V(0, 0);
  _V lastDir = const _V(1, 0);

  late final double width; // largeur de colonne, en 0,1 mm
  late final double spacing; // écart satin, en 0,1 mm
  static const double runLen = 20; // 2 mm
  static const double lockLen = 5; // 0,5 mm

  _TextBuilder(this.d) {
    width = d.effectiveWidthMm * 10 + 2 * d.fabric.pullCompMm * 10;
    spacing = math.max(1.5, d.effectiveDensityMm * 10);
  }

  bool get _edgeWalk => d.fabric.centerUnderlay && d.fabric.zigzagUnderlay && width >= 30;

  void _stitch(_V p) {
    final moved = p - cur;
    if (moved.len > 0.5) lastDir = moved.unit;
    cur = p;
    out.add(Stitch(p.x.round(), p.y.round(), StitchType.stitch));
  }

  void _lockIn(_V p, _V dir) {
    _stitch(p);
    _stitch(p + dir * lockLen);
    _stitch(p);
  }

  void _lockOff() {
    final back = lastDir;
    final p = cur;
    _stitch(p - back * lockLen);
    _stitch(p);
  }

  /// Passage d'une lettre à la suivante : saut, avec ou sans coupe.
  void _jumpTo(_V p, _V dir) {
    if (out.isEmpty) {
      out.add(Stitch(p.x.round(), p.y.round(), StitchType.jump));
      cur = p;
      _lockIn(p, dir);
      return;
    }
    final dist = p.dist(cur);
    final cut = switch (d.trimMode) {
      TrimMode.none => false,
      TrimMode.auto => dist > d.jumpMaxMm * 10,
      TrimMode.all => true,
    };
    _lockOff();
    if (cut) out.add(Stitch(cur.x.round(), cur.y.round(), StitchType.trim));
    out.add(Stitch(p.x.round(), p.y.round(), StitchType.jump));
    cur = p;
    _lockIn(p, dir);
  }

  /// Point droit le long d'une ligne (points réguliers, angles respectés).
  void _runAlong(List<_V> pts) {
    if (pts.isEmpty) return;
    if (pts.first.dist(cur) > 0.5) _stitch(pts.first);
    var acc = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final segLen = a.dist(b);
      if (segLen < 1e-6) continue;
      var t = 0.0;
      while (acc + (segLen - t) >= runLen) {
        t += runLen - acc;
        acc = 0;
        _stitch(a + (b - a) * (t / segLen));
      }
      acc += segLen - t;
      // Angle marqué : on pique dans le coin.
      if (i + 1 < pts.length && acc > 1) {
        final d1 = (b - a).unit, d2 = (pts[i + 1] - b).unit;
        if (d1.dot(d2) < 0.85) {
          _stitch(b);
          acc = 0;
        }
      }
    }
    if (pts.last.dist(cur) > 0.5) _stitch(pts.last);
  }

  void _runEdge(_Column c, double side, double d0, double d1) {
    final len = (d1 - d0).abs();
    final n = math.max(1, (len / runLen).ceil());
    for (var k = 0; k <= n; k++) {
      _stitch(c.edge(d0 + (d1 - d0) * k / n, side, 0.7));
    }
  }

  /// Prépare la ligne selon ses extrémités (prolonger, raccourcir, préparer la coupe).
  _Stroke _shape(_Stroke st) {
    if (st.closed || st.pts.length < 2) return st;
    final p = [...st.pts];
    final half = width / 2;
    _V adjust(_V end, _V inward, double segLen, _EndSpec spec) => switch (spec.mode) {
          _EndMode.extend => end - inward * half,
          _EndMode.cap => end - inward * (width * 1.3),
          _EndMode.shorten => end + inward * math.min(width * 0.35, segLen * 0.45),
          _EndMode.none => end,
        };
    final d0 = (p[1] - p[0]);
    final d1 = (p[p.length - 2] - p[p.length - 1]);
    p[0] = adjust(p.first, d0.unit, d0.len, st.startSpec);
    p[p.length - 1] = adjust(p.last, d1.unit, d1.len, st.endSpec);
    return _Stroke(p, false, st.startSpec, st.endSpec, st.capStartY, st.capEndY);
  }

  /// Brode une colonne satin (soutien de bord éventuel, puis satin dans le sens prévu).
  void _satinPiece(_Stroke st) {
    final c = _Column(_shape(st), width);
    if (c.s.length < 1) return;
    if (_edgeWalk && !c.closed) {
      final (u0, u1) = c.underlayRange();
      _runEdge(c, 1, u0, u1);
      _runEdge(c, -1, u1, u0);
    }
    for (final q in c.satin(spacing, forward: true)) {
      _stitch(q);
    }
  }

  EmbPattern build() {
    final scale = d.heightMm * 10 / 100; // 0,1 mm par unité de police
    final gap = d.letterSpacingMm * 10;
    final inkPad = width * 0.55; // la colonne déborde du squelette

    // Mise en page : l'écart visible entre deux lettres vaut exactement [gap].
    final glyphs = <(String, Glyph, double)>[]; // caractère, dessin, origine X
    final lettersLeft = <double>[];
    var cursor = 0.0;
    for (final r in d.normalized.runes) {
      final ch = String.fromCharCode(r);
      final g = blockFont[ch];
      if (g == null) continue;
      if (g.strokes.isEmpty) {
        cursor += g.width * scale;
        continue;
      }
      var minX = double.infinity, maxX = -double.infinity;
      for (final s in g.strokes) {
        for (final p in s.points) {
          minX = math.min(minX, p.$1);
          maxX = math.max(maxX, p.$1);
        }
      }
      final originX = cursor - (minX * scale - inkPad);
      glyphs.add((ch, g, originX));
      lettersLeft.add(cursor);
      cursor = originX + maxX * scale + inkPad + gap;
    }
    if (glyphs.isEmpty) {
      return EmbPattern(
          name: _name(), stitches: const [Stitch(0, 0, StitchType.end)], colors: [d.color]);
    }
    final totalW = cursor - gap;
    final off = _V(-totalW / 2, -d.heightMm * 10 / 2);

    for (var li = 0; li < glyphs.length; li++) {
      final (ch, glyph, originX) = glyphs[li];
      _V toOut(_V p) => _V(originX + p.x * scale + off.x, p.y * scale + off.y);
      final graph = _graphFor(ch, glyph.strokes);
      final specs = _endSpecs(glyph.strokes);
      final strokes = <_Stroke>[
        for (var k = 0; k < glyph.strokes.length; k++)
          _Stroke(
            [for (final p in glyph.strokes[k].points) toOut(_V(p.$1, p.$2))],
            glyph.strokes[k].closed,
            specs[k].$1,
            specs[k].$2,
            specs[k].$1.capY * scale + off.y,
            specs[k].$2.capY * scale + off.y,
          ),
      ];

      // Entrée de la lettre : le nœud le plus proche de la fin de la lettre précédente
      // (ou du coin bas-gauche pour la première lettre).
      final ref = out.isEmpty
          ? toOut(const _V(-1000, 100))
          : cur;
      var entry = 0;
      for (var i = 1; i < graph.nodes.length; i++) {
        if (toOut(graph.nodes[i]).dist(ref) < toOut(graph.nodes[entry]).dist(ref)) entry = i;
      }
      final next = li + 1 < glyphs.length
          ? _V(lettersLeft[li + 1] + off.x, d.heightMm * 10 + off.y)
          : null;
      final plan = _planLetter(graph, entry, (i) => toOut(graph.nodes[i]), next,
          runFirst: d.fabric.centerUnderlay);

      // 1. Arrivée sur la lettre.
      final e0 = toOut(graph.nodes[plan.entry]);
      final firstDir = plan.runWalk.isNotEmpty
          ? (toOut(graph.polyline(plan.entry, plan.runWalk)[1]) - e0).unit
          : const _V(1, 0);
      _jumpTo(e0, firstDir);

      // 2. Point droit d'un seul passage sur toute la lettre (caché sous le satin).
      _runAlong([for (final p in graph.polyline(plan.entry, plan.runWalk)) toOut(p)]);

      // 3. Colonnes satin dans l'ordre qui cache tous les trajets.
      for (var k = 0; k < plan.pieces.length; k++) {
        final pc = plan.pieces[k];
        if (k > 0) {
          final from = plan.pieces[k - 1].exit;
          _runAlong([for (final p in graph.polyline(from, plan.links[k])) toOut(p)]);
        }
        var st = strokes[pc.stroke];
        if (st.closed) {
          final target = toOut(graph.nodes[pc.entry]);
          var best = 0;
          for (var j = 1; j < st.pts.length; j++) {
            if (st.pts[j].dist(target) < st.pts[best].dist(target)) best = j;
          }
          st = st.rotatedTo(best);
        } else if (pc.reversed) {
          st = st.reversed();
        }
        _satinPiece(st);
      }
    }
    _lockOff();
    out.add(Stitch(cur.x.round(), cur.y.round(), StitchType.trim));
    out.add(Stitch(cur.x.round(), cur.y.round(), StitchType.end));
    return EmbPattern(name: _name(), stitches: out, colors: [d.color]);
  }

  String _name() {
    final n = d.normalized.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return n.isEmpty ? 'TEXTE' : n;
  }
}
