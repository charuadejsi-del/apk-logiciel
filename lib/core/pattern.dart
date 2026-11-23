import 'dart:math' as math;

/// Type d'une instruction machine.
enum StitchType { stitch, jump, trim, colorChange, end }

/// Une instruction en coordonnées absolues, unité = 0,1 mm, axe Y vers le bas.
class Stitch {
  final int x;
  final int y;
  final StitchType type;
  const Stitch(this.x, this.y, this.type);

  bool get isStitch => type == StitchType.stitch;

  @override
  String toString() => 'Stitch($x, $y, ${type.name})';
}

class Bounds {
  final int minX, minY, maxX, maxY;
  const Bounds(this.minX, this.minY, this.maxX, this.maxY);
  int get width => maxX - minX;
  int get height => maxY - minY;
  static const empty = Bounds(0, 0, 0, 0);
}

/// Un motif de broderie indépendant du format de fichier.
class EmbPattern {
  final String name;
  final List<Stitch> stitches;

  /// Couleur ARGB de chaque bloc de couleur (peut être vide : palette par défaut).
  final List<int> colors;

  EmbPattern({required this.name, required this.stitches, List<int>? colors})
      : colors = colors ?? <int>[];

  EmbPattern copyWith({String? name, List<Stitch>? stitches, List<int>? colors}) =>
      EmbPattern(
        name: name ?? this.name,
        stitches: stitches ?? this.stitches,
        colors: colors ?? this.colors,
      );

  int _count(StitchType t) => stitches.where((s) => s.type == t).length;
  int get stitchCount => _count(StitchType.stitch);
  int get jumpCount => _count(StitchType.jump);
  int get trimCount => _count(StitchType.trim);
  int get colorChangeCount => _count(StitchType.colorChange);
  int get colorBlockCount => colorChangeCount + 1;

  /// Bornes calculées sur les points cousus uniquement.
  Bounds get bounds {
    var first = true;
    var minX = 0, minY = 0, maxX = 0, maxY = 0;
    for (final s in stitches) {
      if (!s.isStitch) continue;
      if (first) {
        minX = maxX = s.x;
        minY = maxY = s.y;
        first = false;
      } else {
        minX = math.min(minX, s.x);
        maxX = math.max(maxX, s.x);
        minY = math.min(minY, s.y);
        maxY = math.max(maxY, s.y);
      }
    }
    return first ? Bounds.empty : Bounds(minX, minY, maxX, maxY);
  }

  double get widthMm => bounds.width / 10.0;
  double get heightMm => bounds.height / 10.0;

  /// Durée estimée pour une vitesse machine en points/minute.
  Duration estimate(int stitchesPerMinute) =>
      Duration(seconds: (stitchCount * 60 / stitchesPerMinute).round());

  int colorOfBlock(int block) {
    final list = colors.isEmpty ? defaultPalette : colors;
    return list[block % list.length];
  }
}

/// Palette utilisée quand le fichier ne contient pas de couleurs (cas du DST).
const List<int> defaultPalette = [
  0xFF1E5AA8, 0xFFD62828, 0xFF2A9D8F, 0xFFF4A261, 0xFF7B2CBF,
  0xFF2B9348, 0xFFE9C46A, 0xFF264653, 0xFFE76F51, 0xFF8D99AE,
];

double distance(Stitch a, Stitch b) {
  final dx = (a.x - b.x).toDouble();
  final dy = (a.y - b.y).toDouble();
  return math.sqrt(dx * dx + dy * dy);
}
