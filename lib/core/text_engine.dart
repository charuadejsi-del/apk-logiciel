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

  const TextDesign({
    this.text = 'FARES',
    this.heightMm = 20,
    this.letterSpacingMm = 1.5,
    this.autoWidth = true,
    this.columnWidthMm = 3,
    this.autoDensity = true,
    this.densityMm = 0.40,
    this.fabric = Fabric.coton,
    this.color = 0xFFD4AF37,
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

/// Une ligne de la lettre, prête à broder dans un sens donné.
class _Stroke {
  final List<_V> pts;
  final bool closed;
  _Stroke(this.pts, this.closed);

  /// Variante qui commence le plus près de [from] (inversée ou tournée si besoin).
  _Stroke orientedFrom(_V from) {
    if (closed) {
      var best = 0;
      for (var i = 1; i < pts.length; i++) {
        if (pts[i].dist(from) < pts[best].dist(from)) best = i;
      }
      return _Stroke([...pts.sublist(best), ...pts.sublist(0, best)], true);
    }
    return pts.last.dist(from) < pts.first.dist(from)
        ? _Stroke(pts.reversed.toList(), false)
        : this;
  }

  /// Prolonge les extrémités d'une ligne ouverte pour fermer les angles.
  _Stroke extended(double ext) {
    if (closed || pts.length < 2) return this;
    final d0 = (pts[1] - pts[0]).unit;
    final d1 = (pts[pts.length - 1] - pts[pts.length - 2]).unit;
    return _Stroke([
      pts.first - d0 * ext,
      ...pts.sublist(1, pts.length - 1),
      pts.last + d1 * ext,
    ], false);
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
  static const double zigSpacing = 25; // 2,5 mm
  static const double lockLen = 5; // 0,5 mm
  static const double connectMax = 20; // 2 mm

  _TextBuilder(this.d) {
    width = d.effectiveWidthMm * 10 + 2 * d.fabric.pullCompMm * 10;
    spacing = math.max(1.5, d.effectiveDensityMm * 10);
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
    if (sameLetter && p.dist(cur) <= connectMax) {
      _stitch(p);
      return;
    }
    _lockOff();
    out.add(Stitch(cur.x.round(), cur.y.round(), StitchType.trim));
    out.add(Stitch(p.x.round(), p.y.round(), StitchType.jump));
    cur = p;
    _lockIn(p, dir);
  }

  void _run(_Sampler s, {required bool forward}) {
    final n = math.max(1, (s.length / runLen).ceil());
    for (var k = 1; k <= n; k++) {
      final dd = forward ? s.length * k / n : s.length * (n - k) / n;
      _stitch(s.at(dd).$1);
    }
  }

  void _zigzag(_Sampler s, double w, double gap, {required bool forward}) {
    final n = math.max(2, (s.length / gap).ceil());
    for (var k = 0; k <= n; k++) {
      final dd = forward ? s.length * k / n : s.length * (n - k) / n;
      final (pos, nrm) = s.at(dd);
      final side = k.isEven ? 1.0 : -1.0;
      _stitch(pos + nrm * (side * w / 2));
    }
  }

  void _emitStroke(_Stroke st, {required bool sameLetter}) {
    final s = _Sampler(_dedupe(st.pts), st.closed);
    if (s.length < 1) return;
    _moveTo(s.start, s.dirAt(0), sameLetter: sameLetter);

    final fab = d.fabric;
    var satinForward = true;
    if (fab.centerUnderlay) {
      _run(s, forward: true); // on arrive au bout
      if (fab.zigzagUnderlay && width >= 30) {
        _zigzag(s, width * 0.6, zigSpacing, forward: false); // retour au début
        satinForward = true;
      } else {
        satinForward = false; // le satin revient vers le début
      }
    }
    if (!satinForward && st.closed) satinForward = true;
    _zigzag(s, width, spacing, forward: satinForward);
  }

  EmbPattern build() {
    final scale = d.heightMm * 10 / 100; // 0,1 mm par unité de police
    final gap = d.letterSpacingMm * 10;
    final ext = width / 2;

    // Mise en page des lettres.
    final letters = <List<_Stroke>>[];
    var cursor = 0.0;
    for (final r in d.normalized.runes) {
      final g = blockFont[String.fromCharCode(r)];
      if (g == null) continue;
      final strokes = <_Stroke>[
        for (final gs in g.strokes)
          _Stroke([for (final p in gs.points) _V(cursor + p.$1 * scale, p.$2 * scale)],
              gs.closed),
      ];
      if (strokes.isNotEmpty) letters.add(strokes);
      cursor += g.width * scale + gap;
    }
    if (letters.isEmpty) {
      return EmbPattern(name: _name(), stitches: const [Stitch(0, 0, StitchType.end)],
          colors: [d.color]);
    }
    final totalW = cursor - gap;
    final off = _V(-totalW / 2, -d.heightMm * 10 / 2);

    for (final strokes in letters) {
      final remaining = [
        for (final s in strokes) _Stroke([for (final p in s.pts) p + off], s.closed),
      ];
      var first = true;
      while (remaining.isNotEmpty) {
        // Ligne suivante : la plus proche de la position actuelle.
        var bestI = 0;
        _Stroke? best;
        var bestD = double.infinity;
        for (var i = 0; i < remaining.length; i++) {
          final o = remaining[i].orientedFrom(cur).extended(ext);
          final dd = o.pts.first.dist(cur);
          if (dd < bestD) {
            bestD = dd;
            best = o;
            bestI = i;
          }
        }
        remaining.removeAt(bestI);
        _emitStroke(best!, sameLetter: !first);
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
