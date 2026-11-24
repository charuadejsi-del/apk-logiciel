import 'dart:math' as math;

import 'pattern.dart';

/// Résultat d'un réglage du nombre de points.
class CountResult {
  final EmbPattern pattern;
  final int achieved;
  final int min, max; // bornes atteignables
  final String? note;
  const CountResult(this.pattern, this.achieved, this.min, this.max, [this.note]);
}

/// Règle un dessin (fichier DST/PES déjà fait) pour qu'il ait environ [target]
/// points, en changeant la densité :
/// - satin (zigzag) : ajout ou retrait de « barreaux » entre les barreaux existants ;
/// - tatami (rangées aller-retour) : ajout de deux rangées intermédiaires entre
///   deux rangées, ou retrait de deux rangées sur trois.
/// Le fichier ne contient pas les formes d'origine : c'est une approximation
/// soignée, pas une nouvelle numérisation.
CountResult adjustStitchCount(EmbPattern p, int target) {
  final cur = p.stitchCount;
  if (target == cur || cur == 0) return CountResult(p, cur, cur, cur);
  final add = target > cur;
  final full = _apply(p, 1, add);
  final bound = full.stitchCount;
  if (add ? target >= bound : target <= bound) {
    return CountResult(full, bound, add ? cur : bound, add ? bound : cur,
        add ? 'Maximum atteignable : $bound points.' : 'Minimum atteignable : $bound points.');
  }
  // Recherche de la proportion d'ajouts / retraits qui donne le bon nombre.
  var lo = 0.0, hi = 1.0;
  var best = p;
  for (var it = 0; it < 18; it++) {
    final mid = (lo + hi) / 2;
    final q = _apply(p, mid, add);
    best = q;
    final n = q.stitchCount;
    if ((n - target).abs() <= math.max(3, target ~/ 400)) break;
    if ((n < target) == add) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  String? note;
  if (add && target > cur * 2) note = 'Plus du double des points : la broderie risque d\'être dure.';
  return CountResult(best, best.stitchCount, add ? cur : bound, add ? bound : cur, note);
}

class _V {
  final double x, y;
  const _V(this.x, this.y);
  double get len => math.sqrt(x * x + y * y);
}

_V _seg(Stitch a, Stitch b) => _V((b.x - a.x).toDouble(), (b.y - a.y).toDouble());
double _cos(_V a, _V b) {
  final l = a.len * b.len;
  return l == 0 ? 0 : (a.x * b.x + a.y * b.y) / l;
}

Stitch _lerp(Stitch a, Stitch b, double t) =>
    Stitch((a.x + (b.x - a.x) * t).round(), (a.y + (b.y - a.y) * t).round(), StitchType.stitch);

EmbPattern _apply(EmbPattern p, double frac, bool add) {
  final src = p.stitches;
  final out = <Stitch>[];
  var acc = 0.0;
  bool take() {
    acc += frac;
    if (acc >= 1 - 1e-9) {
      acc -= 1;
      return true;
    }
    return false;
  }

  var i = 0;
  while (i < src.length) {
    if (!src[i].isStitch) {
      out.add(src[i++]);
      continue;
    }
    var j = i;
    while (j < src.length && src[j].isStitch) {
      j++;
    }
    final run = src.sublist(i, j);
    out.addAll(run.length < 5 ? run : _run(run, add, take));
    i = j;
  }
  return p.copyWith(stitches: out);
}

/// Une suite de points cousus sans saut.
List<Stitch> _run(List<Stitch> r, bool add, bool Function() take) {
  final n = r.length;
  // Zigzag : chaque point repart en sens inverse (satin).
  final rev = List<bool>.filled(n, false);
  var zig = 0;
  for (var k = 0; k + 2 < n; k++) {
    final a = _seg(r[k], r[k + 1]), b = _seg(r[k + 1], r[k + 2]);
    if (a.len >= 8 && b.len >= 8 && _cos(a, b) < -0.5) {
      rev[k] = true;
      zig++;
    }
  }
  if (zig >= (n - 2) * 0.5) return _satin(r, rev, add, take);
  return _tatami(r, add, take);
}

List<Stitch> _satin(List<Stitch> r, List<bool> rev, bool add, bool Function() take) {
  final out = <Stitch>[];
  final n = r.length;
  var k = 0;
  while (k < n) {
    out.add(r[k]);
    // Barreaux k→k+1, k+1→k+2, k+2→k+3 alternés : on peut insérer / retirer.
    final ok = k + 3 < n && rev[k] && rev[k + 1];
    if (ok) {
      out.add(r[k + 1]);
      if (add) {
        if (take()) {
          out.add(_lerp(r[k], r[k + 2], 0.5));
          out.add(_lerp(r[k + 1], r[k + 3], 0.5));
        }
        k += 2;
      } else {
        // Retirer la paire k+2, k+3 (garder les bords de la colonne).
        if (k + 5 < n && rev[k + 2] && rev[k + 3] && take()) {
          k += 4;
        } else {
          k += 2;
        }
      }
      continue;
    }
    k++;
  }
  return out;
}

/// Rangées : suites de points alignés dans le même sens.
List<Stitch> _tatami(List<Stitch> r, bool add, bool Function() take) {
  final n = r.length;
  final rows = <(int, int)>[]; // (premier point, dernier point), rangées d'au moins 3 mm
  var k0 = 0;
  while (k0 < n - 1) {
    final d0 = _seg(r[k0], r[k0 + 1]);
    if (d0.len < 5) {
      k0++;
      continue;
    }
    var e = k0 + 1;
    while (e < n - 1) {
      final d = _seg(r[e], r[e + 1]);
      if (d.len < 5 || _cos(d, d0) < 0.95) break;
      e++;
    }
    if (_seg(r[k0], r[e]).len >= 30) rows.add((k0, e));
    k0 = e;
  }
  // Paires de rangées voisines aller-retour, proches.
  bool pair(int a, int b) {
    final ra = rows[a], rb = rows[b];
    final da = _seg(r[ra.$1], r[ra.$2]), db = _seg(r[rb.$1], r[rb.$2]);
    if (da.len < 30 || db.len < 30 || _cos(da, db) > -0.9) return false;
    final gap = _seg(r[ra.$2], r[rb.$1]).len;
    return gap <= 25 && rb.$1 - ra.$2 <= 1;
  }

  final insertAfter = <int, List<Stitch>>{}; // index de point → points ajoutés
  final skip = <int>{}; // points retirés
  if (add) {
    for (var k = 0; k + 1 < rows.length; k++) {
      if (!pair(k, k + 1) || !take()) continue;
      final a = rows[k], b = rows[k + 1];
      final pa = r.sublist(a.$1, a.$2 + 1), pb = r.sublist(b.$1, b.$2 + 1);
      final step = _seg(pa.first, pa.last).len / math.max(1, pa.length - 1);
      final row1 = _between(pa.reversed.toList(), pb, 1 / 3, step, 1 / 3);
      final row2 = _between(pa, pb.reversed.toList(), 2 / 3, step, 2 / 3);
      insertAfter[a.$2] = [...row1, ...row2];
    }
  } else {
    for (var k = 0; k + 3 < rows.length; k++) {
      if (!pair(k, k + 1) || !pair(k + 1, k + 2) || !pair(k + 2, k + 3) || !take()) continue;
      // Retirer les rangées k+1 et k+2 : de la fin de k on passe au début de k+3.
      for (var q = rows[k].$2 + 1; q < rows[k + 3].$1; q++) {
        skip.add(q);
      }
      k += 2;
    }
  }
  final out = <Stitch>[];
  for (var k = 0; k < n; k++) {
    if (!skip.contains(k)) out.add(r[k]);
    final ins = insertAfter[k];
    if (ins != null) out.addAll(ins);
  }
  return out;
}

/// Rangée intermédiaire entre deux rangées parcourues dans le même sens.
List<Stitch> _between(List<Stitch> a, List<Stitch> b, double t, double step, double phase) {
  Stitch at(List<Stitch> l, double u) {
    // Position à la fraction u de la longueur de la polyligne.
    var total = 0.0;
    final lens = <double>[];
    for (var k = 1; k < l.length; k++) {
      final d = _seg(l[k - 1], l[k]).len;
      lens.add(d);
      total += d;
    }
    var want = u * total;
    for (var k = 1; k < l.length; k++) {
      if (want <= lens[k - 1] || k == l.length - 1) {
        final f = lens[k - 1] == 0 ? 0.0 : (want / lens[k - 1]).clamp(0.0, 1.0);
        return _lerp(l[k - 1], l[k], f);
      }
      want -= lens[k - 1];
    }
    return l.last;
  }

  final s = _lerp(at(a, 0), at(b, 0), t), e = _lerp(at(a, 1), at(b, 1), t);
  final len = _seg(s, e).len;
  final m = math.max(1, (len / math.max(10, step)).round());
  final out = <Stitch>[s];
  for (var k = 1; k < m; k++) {
    final u = ((k - phase) / m).clamp(0.0, 1.0);
    out.add(_lerp(at(a, u), at(b, u), t));
  }
  out.add(e);
  return out;
}
