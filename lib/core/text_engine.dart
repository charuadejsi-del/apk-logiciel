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
  static const double connectMax = 20; // 2 mm

  _TextBuilder(this.d) {
    width = d.effectiveWidthMm * 10 + 2 * d.fabric.pullCompMm * 10;
    spacing = math.max(1.5, d.effectiveDensityMm * 10);
  }

  bool get _edgeWalk => d.fabric.centerUnderlay && d.fabric.zigzagUnderlay && width >= 30;

  /// Le satin finit-il au bout de la ligne (sinon il revient au début) ?
  bool _exitsAtEnd(bool closed) {
    if (closed) return false;
    if (!d.fabric.centerUnderlay) return true;
    return _edgeWalk;
  }

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

  void _moveTo(_V p, _V dir, {required bool sameLetter}) {
    if (out.isEmpty) {
      out.add(Stitch(p.x.round(), p.y.round(), StitchType.jump));
      cur = p;
      _lockIn(p, dir);
      return;
    }
    final dist = p.dist(cur);
    if (sameLetter && dist <= connectMax) {
      _stitch(p);
      return;
    }
    final limit = d.jumpMaxMm * 10;
    final cut = switch (d.trimMode) {
      TrimMode.none => false,
      TrimMode.auto => dist > limit,
      // Entre chaque lettre ; à l'intérieur d'une lettre, seulement si c'est loin.
      TrimMode.all => sameLetter ? dist > limit : true,
    };
    _lockOff();
    if (cut) out.add(Stitch(cur.x.round(), cur.y.round(), StitchType.trim));
    out.add(Stitch(p.x.round(), p.y.round(), StitchType.jump));
    cur = p;
    _lockIn(p, dir);
  }

  void _runCenter(_Column c, double d0, double d1) {
    final len = (d1 - d0).abs();
    final n = math.max(1, (len / runLen).ceil());
    for (var k = 1; k <= n; k++) {
      _stitch(c.s.at(d0 + (d1 - d0) * k / n).$1);
    }
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
    final s0 = adjust(p.first, d0.unit, d0.len, st.startSpec);
    final s1 = adjust(p.last, d1.unit, d1.len, st.endSpec);
    p[0] = s0;
    p[p.length - 1] = s1;
    return _Stroke(p, false, st.startSpec, st.endSpec, st.capStartY, st.capEndY);
  }

  void _emitStroke(_Stroke raw, {required bool sameLetter}) {
    final c = _Column(_shape(raw), width);
    if (c.s.length < 1) return;
    final (u0, u1) = c.underlayRange();
    final fab = d.fabric;

    if (!fab.centerUnderlay) {
      final pts = c.satin(spacing, forward: true);
      _moveTo(pts.first, c.s.dirAt(0), sameLetter: sameLetter);
      for (final q in pts.skip(1)) {
        _stitch(q);
      }
      return;
    }
    if (_edgeWalk && !c.closed) {
      // Soutien de bord : aller sur un bord, retour sur l'autre → bords nets.
      _moveTo(c.edge(u0, 1, 0.7), c.s.dirAt(u0), sameLetter: sameLetter);
      _runEdge(c, 1, u0, u1);
      _runEdge(c, -1, u1, u0);
      final pts = c.satin(spacing, forward: true);
      _stitch(pts.first);
      for (final q in pts.skip(1)) {
        _stitch(q);
      }
      return;
    }
    // Colonne étroite ou boucle : passage central puis satin.
    _moveTo(c.s.at(u0).$1, c.s.dirAt(u0), sameLetter: sameLetter);
    _runCenter(c, u0, u1);
    final forward = c.closed; // boucle : on refait le tour ; sinon retour vers le début
    final pts = c.satin(spacing, forward: forward);
    for (final q in pts) {
      _stitch(q);
    }
  }

  /// Meilleur ordre et sens des lignes d'une lettre : trajets courts,
  /// et fin au plus près de la lettre suivante.
  List<_Stroke> _order(List<_Stroke> strokes, _V? from, _V? next) {
    if (strokes.isEmpty) return strokes;
    var best = <_Stroke>[];
    var bestCost = double.infinity;

    double cost(List<_Stroke> seq) {
      var c = 0.0;
      var at = from;
      for (final s in seq) {
        final entry = s.pts.first;
        if (at != null) c += at.dist(entry);
        at = s.closed ? entry : (_exitsAtEnd(false) ? s.pts.last : entry);
      }
      if (next != null && at != null) c += 0.8 * at.dist(next);
      return c;
    }

    void search(List<_Stroke> done, List<_Stroke> rest) {
      if (rest.isEmpty) {
        final c = cost(done);
        if (c < bestCost) {
          bestCost = c;
          best = List.of(done);
        }
        return;
      }
      for (var i = 0; i < rest.length; i++) {
        final s = rest[i];
        final remaining = [...rest]..removeAt(i);
        final options = <_Stroke>[];
        if (s.closed) {
          final ref = done.isNotEmpty
              ? (done.last.closed || !_exitsAtEnd(false) ? done.last.pts.first : done.last.pts.last)
              : (from ?? s.pts.first);
          var k = 0;
          for (var j = 1; j < s.pts.length; j++) {
            if (s.pts[j].dist(ref) < s.pts[k].dist(ref)) k = j;
          }
          options.add(s.rotatedTo(k));
        } else {
          options
            ..add(s)
            ..add(s.reversed());
        }
        for (final o in options) {
          search([...done, o], remaining);
        }
      }
    }

    if (strokes.length <= 5) {
      search([], strokes);
      return best;
    }
    return strokes;
  }

  EmbPattern build() {
    final scale = d.heightMm * 10 / 100; // 0,1 mm par unité de police
    final gap = d.letterSpacingMm * 10;
    final inkPad = width * 0.55; // la colonne déborde du squelette

    // Mise en page : l'écart visible entre deux lettres vaut exactement [gap].
    final letters = <List<_Stroke>>[];
    final lettersLeft = <double>[];
    var cursor = 0.0;
    var placed = false;
    for (final r in d.normalized.runes) {
      final g = blockFont[String.fromCharCode(r)];
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
      final specs = _endSpecs(g.strokes);
      final strokes = <_Stroke>[
        for (var k = 0; k < g.strokes.length; k++)
          _Stroke(
            [for (final p in g.strokes[k].points) _V(originX + p.$1 * scale, p.$2 * scale)],
            g.strokes[k].closed,
            specs[k].$1,
            specs[k].$2,
            specs[k].$1.capY * scale,
            specs[k].$2.capY * scale,
          ),
      ];
      letters.add(strokes);
      lettersLeft.add(cursor);
      cursor = originX + maxX * scale + inkPad + gap;
      placed = true;
    }
    if (!placed) {
      return EmbPattern(
          name: _name(), stitches: const [Stitch(0, 0, StitchType.end)], colors: [d.color]);
    }
    final totalW = cursor - gap;
    final off = _V(-totalW / 2, -d.heightMm * 10 / 2);

    for (var li = 0; li < letters.length; li++) {
      final strokes = [
        for (final s in letters[li])
          _Stroke([for (final p in s.pts) p + off], s.closed, s.startSpec, s.endSpec,
              s.capStartY + off.y, s.capEndY + off.y),
      ];
      final next = li + 1 < letters.length
          ? _V(lettersLeft[li + 1] + off.x, d.heightMm * 10 + off.y)
          : null;
      final ordered = _order(strokes, out.isEmpty ? null : cur, next);
      var first = true;
      for (final s in ordered) {
        _emitStroke(s, sameLetter: !first);
        first = false;
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
