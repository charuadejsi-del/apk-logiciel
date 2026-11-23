import 'pattern.dart';

/// Résultat d'une retouche : le nouveau motif et le nombre de points supprimés.
class EditResult {
  final EmbPattern pattern;
  final int removed;
  const EditResult(this.pattern, this.removed);
}

/// Supprime les points plus courts que [thresholdMm] (moins de fils cassés).
/// Le premier et le dernier point de chaque segment cousu sont toujours gardés,
/// pour que les nœuds de début et de fin restent sûrs.
EditResult removeSmallStitches(EmbPattern p, double thresholdMm) {
  final limit = thresholdMm * 10; // unité 0,1 mm
  final src = p.stitches;
  final out = <Stitch>[];
  var removed = 0;
  for (var i = 0; i < src.length; i++) {
    final s = src[i];
    if (!s.isStitch) {
      out.add(s);
      continue;
    }
    final prevKept = out.isEmpty ? null : out.last;
    final isFirstOfRun = prevKept == null || !prevKept.isStitch;
    final isLastOfRun = i + 1 >= src.length || !src[i + 1].isStitch;
    if (isFirstOfRun || isLastOfRun || distance(prevKept!, s) >= limit) {
      out.add(s);
    } else {
      removed++;
    }
  }
  return EditResult(p.copyWith(stitches: out), removed);
}

/// Compte les points qui seraient supprimés, sans modifier le motif.
int countSmallStitches(EmbPattern p, double thresholdMm) =>
    removeSmallStitches(p, thresholdMm).removed;
