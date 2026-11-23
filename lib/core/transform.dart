import 'dart:math' as math;

import 'edits.dart';
import 'pattern.dart';

// ───────────────────────── Taille ─────────────────────────

class ScaleResult {
  final EmbPattern pattern;
  final int split; // points ajoutés en divisant les points trop longs
  final int removed; // petits points supprimés
  const ScaleResult(this.pattern, this.split, this.removed);
}

/// Longueur maximale d'un point avant division automatique (8 mm).
const double maxStitchMm = 8.0;

/// Change la taille d'un motif déjà en points (fichier DST/PES).
/// Agrandissement : les points trop longs sont divisés. Réduction : les points
/// devenus trop courts (moins de 0,3 mm) sont supprimés.
ScaleResult scalePattern(EmbPattern p, double factor) {
  final scaled = p.copyWith(stitches: [
    for (final s in p.stitches)
      Stitch((s.x * factor).round(), (s.y * factor).round(), s.type),
  ]);
  if (factor > 1) {
    final r = splitLongStitches(scaled, maxStitchMm);
    return ScaleResult(r.pattern, r.removed, 0);
  }
  if (factor < 1) {
    final r = removeSmallStitches(scaled, 0.3);
    return ScaleResult(r.pattern, 0, r.removed);
  }
  return ScaleResult(scaled, 0, 0);
}

/// Divise les points plus longs que [maxMm]. `removed` contient ici le nombre de points ajoutés.
EditResult splitLongStitches(EmbPattern p, double maxMm) {
  final limit = maxMm * 10;
  final out = <Stitch>[];
  var added = 0;
  Stitch? prev;
  for (final s in p.stitches) {
    if (s.isStitch && prev != null && prev.isStitch) {
      final dist = distance(prev, s);
      if (dist > limit) {
        final parts = (dist / limit).ceil();
        for (var k = 1; k < parts; k++) {
          out.add(Stitch(
            (prev.x + (s.x - prev.x) * k / parts).round(),
            (prev.y + (s.y - prev.y) * k / parts).round(),
            StitchType.stitch,
          ));
          added++;
        }
      }
    }
    out.add(s);
    prev = s;
  }
  return EditResult(p.copyWith(stitches: out), added);
}

// ───────────────────────── Densité ─────────────────────────

/// Estime l'écart actuel entre deux lignes de satin (mm), ou null s'il n'y a pas de satin.
double? estimateSatinDensity(EmbPattern p) {
  final values = <double>[];
  final s = p.stitches;
  for (var i = 2; i < s.length; i++) {
    final a = s[i - 2], b = s[i - 1], c = s[i];
    if (!a.isStitch || !b.isStitch || !c.isStitch) continue;
    final stitchLen = distance(b, c);
    final sameSide = distance(a, c);
    if (stitchLen > 15 && sameSide < 15) values.add(sameSide / 2);
  }
  if (values.length < 20) return null;
  values.sort();
  return values[values.length ~/ 2] / 10;
}

/// Allège la densité des colonnes satin d'un motif déjà en points.
/// Les points sont retirés par paires pour garder l'alternance gauche/droite ;
/// les points de passage et de remplissage (longs) ne sont pas touchés.
EditResult thinDensity(EmbPattern p, double targetMm) {
  final minSameSide = 2 * targetMm * 10 * 0.95;
  final src = p.stitches;
  final out = <Stitch>[];
  var removed = 0;
  var i = 0;
  while (i < src.length) {
    if (!src[i].isStitch) {
      out.add(src[i]);
      i++;
      continue;
    }
    var j = i;
    while (j < src.length && src[j].isStitch) {
      j++;
    }
    final run = src.sublist(i, j);
    if (run.length < 6) {
      out.addAll(run);
    } else {
      final kept = <Stitch>[run[0], run[1]];
      var anchor = run[0];
      var k = 2;
      while (k + 1 < run.length - 2) {
        final a = run[k], b = run[k + 1];
        if (distance(a, anchor) >= minSameSide) {
          kept
            ..add(a)
            ..add(b);
          anchor = a;
        } else {
          removed += 2;
        }
        k += 2;
      }
      kept.addAll(run.sublist(k));
      out.addAll(kept);
    }
    i = j;
  }
  return EditResult(p.copyWith(stitches: out), removed);
}

// ───────────────────────── Point de départ ─────────────────────────

enum StartAnchor {
  original,
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  center,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

extension StartAnchorInfo on StartAnchor {
  String get label => switch (this) {
        StartAnchor.original => 'Origine du fichier',
        StartAnchor.topLeft => 'Haut gauche',
        StartAnchor.topCenter => 'Haut centre',
        StartAnchor.topRight => 'Haut droite',
        StartAnchor.middleLeft => 'Milieu gauche',
        StartAnchor.center => 'Centre',
        StartAnchor.middleRight => 'Milieu droite',
        StartAnchor.bottomLeft => 'Bas gauche',
        StartAnchor.bottomCenter => 'Bas centre',
        StartAnchor.bottomRight => 'Bas droite',
      };
}

/// Place le point de départ de la machine (origine) sur [anchor] et,
/// si demandé, ramène l'aiguille au départ à la fin.
EmbPattern applyStart(EmbPattern p, StartAnchor anchor, {bool returnToStart = false}) {
  var stitches = p.stitches;
  if (anchor != StartAnchor.original) {
    final b = p.bounds;
    final col = anchor.index == 0 ? 1 : (anchor.index - 1) % 3; // 0 gauche, 1 centre, 2 droite
    final row = anchor.index == 0 ? 1 : (anchor.index - 1) ~/ 3; // 0 haut, 1 milieu, 2 bas
    final ax = [b.minX, (b.minX + b.maxX) ~/ 2, b.maxX][col];
    final ay = [b.minY, (b.minY + b.maxY) ~/ 2, b.maxY][row];
    stitches = [for (final s in stitches) Stitch(s.x - ax, s.y - ay, s.type)];
  }
  if (returnToStart) {
    final body = [for (final s in stitches) if (s.type != StitchType.end) s];
    final last = body.isEmpty ? const Stitch(0, 0, StitchType.stitch) : body.last;
    if (last.x != 0 || last.y != 0) {
      if (last.type != StitchType.trim) {
        body.add(Stitch(last.x, last.y, StitchType.trim));
      }
      body.add(const Stitch(0, 0, StitchType.jump));
    }
    body.add(const Stitch(0, 0, StitchType.end));
    stitches = body;
  }
  return p.copyWith(stitches: stitches);
}

/// Position de fin (dernier point cousu).
(int, int) endPosition(EmbPattern p) {
  for (var i = p.stitches.length - 1; i >= 0; i--) {
    if (p.stitches[i].isStitch) return (p.stitches[i].x, p.stitches[i].y);
  }
  return (0, 0);
}

/// Utilitaire : pourcentage de variation de taille.
double sizeChangePercent(double factor) => ((factor - 1) * 100).abs();

/// Facteur pour obtenir une largeur cible.
double factorForWidth(EmbPattern p, double targetWidthMm) =>
    p.widthMm <= 0 ? 1 : targetWidthMm / p.widthMm;

/// Arrondi d'affichage.
String mm(double v) => v.toStringAsFixed(1);

/// Évite un avertissement d'import inutilisé si math n'est plus nécessaire.
double clampFactor(double f) => math.max(0.2, math.min(5.0, f));
