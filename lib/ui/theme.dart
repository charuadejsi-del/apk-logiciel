import 'package:flutter/material.dart';

/// Identité visuelle : noir profond, or brossé, surfaces satinées.
class AppColors {
  static const bg = Color(0xFF09090D);
  static const surface = Color(0xFF14141B);
  static const surface2 = Color(0xFF1C1C26);
  static const gold = Color(0xFFD4AF37);
  static const goldLight = Color(0xFFF3D98B);
  static const goldDark = Color(0xFF8C6A12);
  static const text = Color(0xFFF5F1E6);
  static const muted = Color(0xFF9A968C);
  static const border = Color(0x33D4AF37);
  static const success = Color(0xFF4ADE80);
  static const danger = Color(0xFFF87171);
}

const goldGradient = LinearGradient(
  colors: [Color(0xFFF7E3A1), Color(0xFFD4AF37), Color(0xFF9C7A1C)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const surfaceGradient = LinearGradient(
  colors: [Color(0xFF1D1D27), Color(0xFF121218)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.gold,
    onPrimary: Colors.black,
    secondary: AppColors.goldLight,
    onSecondary: Colors.black,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    dividerColor: AppColors.border,
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.gold,
      inactiveTrackColor: Color(0x26FFFFFF),
      thumbColor: AppColors.goldLight,
      overlayColor: Color(0x22D4AF37),
      trackHeight: 3,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
      contentTextStyle: TextStyle(color: AppColors.text),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      showDragHandle: true,
    ),
  );
}

/// Carte satinée bordée d'or, cliquable si [onTap] est fourni.
class LuxCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool highlighted;

  const LuxCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: highlighted ? goldGradient : surfaceGradient,
        borderRadius: r,
        border: Border.all(
            color: highlighted ? const Color(0x00000000) : AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Bouton principal doré.
class GoldButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  const GoldButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: LuxCard(
        highlighted: true,
        radius: 16,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        onTap: enabled ? onPressed : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
              )
            else
              Icon(icon, color: Colors.black),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Petit badge « Bientôt ».
class SoonBadge extends StatelessWidget {
  const SoonBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text('Bientôt',
          style: TextStyle(color: AppColors.goldLight, fontSize: 11)),
    );
  }
}
