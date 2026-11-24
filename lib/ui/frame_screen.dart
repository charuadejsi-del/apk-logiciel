import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/hoop.dart';
import '../core/pattern.dart';
import '../core/transform.dart';
import 'pattern_painter.dart';
import 'pieces_panel.dart';
import 'theme.dart';

/// Cadre seul : point droit de 5,8 mm autour du dessin, cousu en premier,
/// et choix du point de départ. Aucune découpe.
class FrameScreen extends StatefulWidget {
  final EmbPattern pattern;
  const FrameScreen({super.key, required this.pattern});

  @override
  State<FrameScreen> createState() => _FrameScreenState();
}

class _FrameScreenState extends State<FrameScreen> {
  double _margin = 5;
  StartAnchor _anchor = StartAnchor.center;
  PrepPiece? _piece;
  PatternGeometry? _geo;
  bool _busy = false;
  int _job = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final job = ++_job;
    setState(() => _busy = true);
    final b = widget.pattern.bounds;
    final o = PrepOptions(
      hoopWmm: b.width / 10 + 2 * _margin + 100,
      hoopHmm: b.height / 10 + 2 * _margin + 100,
      split: false,
      marks: false,
      marginMm: _margin,
      anchor: _anchor,
    );
    final r = await compute(prepareRequest, PrepRequest(widget.pattern, o));
    if (!mounted || job != _job) return;
    final p = r.pieces.isEmpty ? null : r.pieces.first;
    setState(() {
      _busy = false;
      _piece = p;
      _geo = p == null ? null : PatternGeometry.from(p.pattern);
    });
  }

  void _set(VoidCallback f) {
    setState(f);
    _run();
  }

  Future<void> _export() async {
    final p = _piece;
    if (p == null) return;
    final msg = await exportPieces(widget.pattern.name, [p]);
    if (msg != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _piece;
    final b = p?.pattern.bounds;
    final wide = MediaQuery.of(context).size.width >= 900;
    final preview = LuxCard(
      padding: const EdgeInsets.all(6),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(children: [
          if (_geo != null)
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 12,
                child: Stack(children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                        child: CustomPaint(painter: PatternPainter(_geo!, showStartEnd: true))),
                  ),
                  // Le cadre, bien visible (il est cousu en premier, en point droit).
                  Positioned.fill(child: CustomPaint(painter: _FrameOutline(_geo!.bounds))),
                ]),
              ),
            ),
          if (_busy) const Center(child: CircularProgressIndicator(color: AppColors.gold)),
        ]),
      ),
    );
    final controls = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (b != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Avec cadre : ${(b.width / 100).toStringAsFixed(1)} × ${(b.height / 100).toStringAsFixed(1)} cm · '
            '${p!.pattern.stitchCount} points',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.goldLight),
          ),
        ),
      luxSection(
        'Distance cadre ↔ dessin (point droit de 5,8 mm, cousu en premier)',
        Wrap(children: [
          for (final v in [3.0, 5.0, 8.0, 10.0, 15.0])
            luxChip('${v.toInt()} mm', _margin == v, () => _set(() => _margin = v)),
        ]),
      ),
      luxSection(
        'Point de départ',
        Row(children: [
          AnchorGrid(value: _anchor, onChanged: (a) => _set(() => _anchor = a)),
          const SizedBox(width: 14),
          Expanded(
            child: Text('${_anchor.label}\nLe cadre commence au coin le plus proche du départ, puis le dessin.',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        ]),
      ),
      GoldButton(label: 'Exporter le fichier DST', icon: Icons.download, busy: _busy, onPressed: _export),
      const SizedBox(height: 20),
    ]);
    return Scaffold(
      appBar: AppBar(title: const Text('Cadre')),
      body: SafeArea(
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Padding(padding: const EdgeInsets.all(12), child: preview)),
                SizedBox(width: 420, child: ListView(padding: const EdgeInsets.all(12), children: [controls])),
              ])
            : ListView(padding: const EdgeInsets.all(12), children: [preview, controls]),
      ),
    );
  }
}

class _FrameOutline extends CustomPainter {
  final Bounds b;
  _FrameOutline(this.b);
  @override
  void paint(Canvas canvas, Size s) {
    final w = b.width < 10 ? 10.0 : b.width.toDouble(), h = b.height < 10 ? 10.0 : b.height.toDouble();
    final k = (s.width / w < s.height / h ? s.width / w : s.height / h) * 0.86;
    final r = Rect.fromCenter(center: s.center(Offset.zero), width: b.width * k, height: b.height * k);
    canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.goldLight.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(covariant _FrameOutline o) => o.b != b;
}
