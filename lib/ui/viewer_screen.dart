import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/dst.dart';
import '../core/edits.dart';
import '../core/pattern.dart';
import 'pattern_painter.dart';

class ViewerScreen extends StatefulWidget {
  final EmbPattern pattern;
  const ViewerScreen({super.key, required this.pattern});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late EmbPattern _pattern;
  late PatternGeometry _geo;
  late int _progress;
  Timer? _timer;
  int _speed = 200; // instructions par seconde
  static const int _machineSpm = 800;

  @override
  void initState() {
    super.initState();
    _setPattern(widget.pattern);
  }

  void _setPattern(EmbPattern p) {
    _pattern = p;
    _geo = PatternGeometry.from(p);
    _progress = _geo.total - 1;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _playing => _timer != null;

  void _togglePlay() {
    if (_playing) {
      setState(() {
        _timer?.cancel();
        _timer = null;
      });
      return;
    }
    if (_progress >= _geo.total - 1) _progress = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      setState(() {
        _progress += (_speed * 0.033).ceil();
        if (_progress >= _geo.total - 1) {
          _progress = _geo.total - 1;
          _timer?.cancel();
          _timer = null;
        }
      });
    });
    setState(() {});
  }

  Future<void> _smallStitches() async {
    var threshold = 0.4;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final count = countSmallStitches(_pattern, threshold);
          return AlertDialog(
            title: const Text('Supprimer les petits points'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Moins de fils cassés. Les points de début et de fin '
                    'de chaque segment sont toujours gardés.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in const [0.3, 0.4, 0.5, 0.6])
                      ChoiceChip(
                        label: Text('${t.toStringAsFixed(1)} mm'),
                        selected: threshold == t,
                        onSelected: (_) => setD(() => threshold = t),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Points concernés : $count',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(
                onPressed: count == 0 ? null : () => Navigator.pop(ctx, threshold),
                child: Text(count == 0 ? 'Propre ✓' : 'Supprimer $count points'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    final r = removeSmallStitches(_pattern, result);
    setState(() => _setPattern(r.pattern));
    _snack('${r.removed} petits points supprimés ✓');
  }

  Future<void> _exportDst() async {
    try {
      final bytes = writeDst(_pattern);
      final name = '${_pattern.name.replaceAll(RegExp(r'[^\w\-]+'), '_')}.dst';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter en DST',
        fileName: name,
        bytes: bytes,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes);
      }
      _snack('Fichier DST exporté ✓');
    } catch (e) {
      _snack('Échec de l\'export : $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _duration(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return m > 0 ? '$m min ${s.toString().padLeft(2, '0')} s' : '$s s';
  }

  @override
  Widget build(BuildContext context) {
    final p = _pattern;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Supprimer les petits points',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: _smallStitches,
          ),
          IconButton(
            tooltip: 'Exporter en DST',
            icon: const Icon(Icons.save_alt),
            onPressed: _exportDst,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _info(Icons.grain, '${p.stitchCount} points'),
                  _info(Icons.straighten,
                      '${p.widthMm.toStringAsFixed(1)} × ${p.heightMm.toStringAsFixed(1)} mm'),
                  _info(Icons.palette_outlined, '${p.colorBlockCount} couleurs'),
                  _info(Icons.call_split, '${p.jumpCount} sauts'),
                  _info(Icons.content_cut, '${p.trimCount} coupes'),
                  _info(Icons.timer_outlined,
                      '${_duration(p.estimate(_machineSpm))} à $_machineSpm pts/min'),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF15171C),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: InteractiveViewer(
                  maxScale: 20,
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: PatternPainter(_geo, _progress, showNeedle: _playing),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  IconButton.filled(
                    onPressed: _togglePlay,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                    tooltip: 'Simuler',
                  ),
                  Expanded(
                    child: Slider(
                      value: _progress.clamp(0, _geo.total - 1).toDouble(),
                      min: 0,
                      max: (_geo.total - 1).clamp(1, 1 << 30).toDouble(),
                      onChanged: (v) => setState(() => _progress = v.round()),
                    ),
                  ),
                  Text('${_progress + 1}/${_geo.total}',
                      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                  PopupMenuButton<int>(
                    tooltip: 'Vitesse',
                    icon: const Icon(Icons.speed),
                    initialValue: _speed,
                    onSelected: (v) => setState(() => _speed = v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 50, child: Text('Lente')),
                      PopupMenuItem(value: 200, child: Text('Normale')),
                      PopupMenuItem(value: 1000, child: Text('Rapide')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(IconData icon, String text) => Chip(
        avatar: Icon(icon, size: 16),
        label: Text(text),
        visualDensity: VisualDensity.compact,
      );
}
