import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/demo.dart';
import '../core/formats.dart';
import 'theme.dart';
import 'viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _busy = true);
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
      if (bytes == null) throw const FormatException('Impossible de lire le fichier.');
      final p = loadPattern(bytes, f.name);
      final dot = f.name.lastIndexOf('.');
      final ext = dot >= 0 ? f.name.substring(dot + 1).toLowerCase() : '';
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ViewerScreen(pattern: p, sourceBytes: bytes, sourceFormat: ext),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is FormatException ? e.message : 'Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openDemo() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ViewerScreen(pattern: demoPattern())));
  }

  void _soon(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what arrive dans la prochaine version.')),
    );
  }

  Widget _logo() {
    return AnimatedBuilder(
      animation: _ring,
      builder: (_, child) => Container(
        width: 132,
        height: 132,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: const [
              Color(0xFF9C7A1C), Color(0xFFF7E3A1), Color(0xFFD4AF37),
              Color(0xFF5E4710), Color(0xFF9C7A1C),
            ],
            transform: GradientRotation(_ring.value * 2 * math.pi),
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x55D4AF37), blurRadius: 40, spreadRadius: 2),
          ],
        ),
        child: child,
      ),
      child: Container(
        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.bg),
        child: ShaderMask(
          shaderCallback: (r) => goldGradient.createShader(r),
          child: const Icon(Icons.gesture, size: 64, color: Colors.white),
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String title, String sub, VoidCallback onTap,
      {bool soon = false}) {
    return LuxCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: soon ? AppColors.muted : AppColors.gold),
              const Spacer(),
              if (soon) const SoonBadge(),
            ],
          ),
          const SizedBox(height: 14),
          Text(title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: soon ? AppColors.muted : AppColors.text,
              )),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _BackdropPainter())),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 36, 22, 24),
                  children: [
                    Center(child: _logo()),
                    const SizedBox(height: 22),
                    ShaderMask(
                      shaderCallback: (r) => goldGradient.createShader(r),
                      child: const Text(
                        'BRODERIE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'STUDIO DE BRODERIE MACHINE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.muted, letterSpacing: 3, fontSize: 12),
                    ),
                    const SizedBox(height: 40),
                    GoldButton(
                      label: 'Ouvrir un fichier',
                      icon: Icons.folder_open,
                      busy: _busy,
                      onPressed: _pickFile,
                    ),
                    const SizedBox(height: 8),
                    const Text('DST · PES · PEC',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    const SizedBox(height: 26),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.35,
                      children: [
                        _tile(Icons.auto_awesome, 'Démonstration',
                            'Voir un motif complet', _openDemo),
                        _tile(Icons.text_fields, 'Texte brodé', 'Noms et lettres',
                            () => _soon('Le texte brodé'),
                            soon: true),
                        _tile(Icons.dashboard_customize_outlined, 'Modèles',
                            'Motifs prêts', () => _soon('La bibliothèque de modèles'),
                            soon: true),
                        _tile(Icons.calculate_outlined, 'Calcul du prix',
                            'Prix au point', () => _soon('Le calcul du prix'),
                            soon: true),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text('Version prototype · phase 0',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF5C5A55), fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fond : halo doré et lignes de points de couture discrètes.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = AppColors.bg);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.55),
          radius: 0.85,
          colors: [Color(0x33D4AF37), Color(0x00D4AF37)],
        ).createShader(rect),
    );
    final stitch = Paint()
      ..color = const Color(0x10F3D98B)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const gap = 46.0, dash = 7.0, space = 6.0;
    for (var start = -size.height; start < size.width; start += gap) {
      var t = 0.0;
      while (t < size.height * 1.5) {
        final a = Offset(start + t, t);
        final b = Offset(start + t + dash * 0.7, t + dash * 0.7);
        canvas.drawLine(a, b, stitch);
        t += dash + space;
      }
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) => false;
}
