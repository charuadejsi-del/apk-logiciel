import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/edits.dart';
import '../core/pattern.dart';
import '../core/text_engine.dart';
import '../core/transform.dart';
import 'export_sheet.dart';
import 'pattern_painter.dart';
import 'theme.dart';

class ViewerScreen extends StatefulWidget {
  final EmbPattern pattern;
  final Uint8List? sourceBytes;
  final String sourceFormat; // 'dst', 'pes', 'pec', 'texte' ou 'demo'

  /// Présent si le motif vient du générateur de texte : tailles et densités
  /// sont alors recalculées entièrement au lieu d'être approchées.
  final TextDesign? textDesign;

  const ViewerScreen({
    super.key,
    required this.pattern,
    this.sourceBytes,
    this.sourceFormat = 'demo',
    this.textDesign,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> with SingleTickerProviderStateMixin {
  late EmbPattern _base; // motif sans réglage du point de départ
  TextDesign? _design;
  late StartAnchor _anchor;
  bool _returnToStart = false;
  late EmbPattern _pattern;
  late PatternGeometry _geo;
  final ValueNotifier<int> _prog = ValueNotifier<int>(0);
  int get _progress => _prog.value;
  set _progress(int v) => _prog.value = v;
  late final Ticker _ticker = createTicker(_onTick);
  int _playFrom = 0;
  int _speed = 300; // instructions par seconde
  bool _realistic = true;
  bool _showJumps = false;
  bool _modified = false;
  static const int _machineSpm = 800;

  @override
  void initState() {
    super.initState();
    _design = widget.textDesign;
    _anchor = _design != null ? StartAnchor.center : StartAnchor.original;
    _setBase(widget.pattern);
  }

  void _setBase(EmbPattern p) {
    _base = p;
    _rebuild();
  }

  void _rebuild() {
    if (_ticker.isActive) _ticker.stop();
    _pattern = applyStart(_base, _anchor, returnToStart: _returnToStart);
    _geo = PatternGeometry.from(_pattern);
    _progress = _geo.total - 1;
  }

  void _setDesign(TextDesign d) {
    setState(() {
      _design = d;
      _modified = true;
      _setBase(d.generate());
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _prog.dispose();
    super.dispose();
  }

  bool get _playing => _ticker.isActive;

  /// Avance de la simulation, synchronisée sur l'écran : seule la toile est redessinée.
  void _onTick(Duration elapsed) {
    final p = _playFrom + (elapsed.inMicroseconds * _speed / 1e6).round();
    if (p >= _geo.total - 1) {
      _progress = _geo.total - 1;
      _ticker.stop();
      setState(() {});
    } else {
      _progress = p;
    }
  }

  void _togglePlay() {
    if (_playing) {
      _ticker.stop();
      setState(() {});
      return;
    }
    if (_progress >= _geo.total - 1) _progress = 0;
    _playFrom = _progress;
    _ticker.start();
    setState(() {});
  }

  Future<void> _smallStitches() async {
    var threshold = 0.4;
    final result = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final count = countSmallStitches(_base, threshold);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Supprimer les petits points',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text(
                    'Moins de fils cassés. Le premier et le dernier point de chaque '
                    'segment sont toujours gardés.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      for (final t in const [0.3, 0.4, 0.5, 0.6])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text('${t.toStringAsFixed(1)} mm'),
                              selected: threshold == t,
                              selectedColor: AppColors.gold,
                              labelStyle: TextStyle(
                                color: threshold == t ? Colors.black : AppColors.text,
                                fontWeight: FontWeight.w600,
                              ),
                              showCheckmark: false,
                              onSelected: (_) => setD(() => threshold = t),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LuxCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Text('$count',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: count == 0 ? AppColors.success : AppColors.goldLight,
                            )),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            count == 0
                                ? 'Aucun petit point : le motif est propre.'
                                : 'points plus courts que ${threshold.toStringAsFixed(1)} mm',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GoldButton(
                    label: count == 0 ? 'Propre ✓' : 'Supprimer $count points',
                    icon: Icons.cleaning_services_outlined,
                    onPressed: count == 0 ? null : () => Navigator.pop(ctx, threshold),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    final r = removeSmallStitches(_base, result);
    setState(() {
      _setBase(r.pattern);
      _modified = true;
    });
    _snack('${r.removed} petits points supprimés ✓');
  }

  // ───────────── Outils : en-tête commun des feuilles ─────────────

  Widget _sheetTitle(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
        ],
      );

  Widget _infoLine(IconData icon, String text, {Color color = AppColors.muted}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13))),
          ],
        ),
      );

  Widget _pill(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: selected ? goldGradient : null,
              color: selected ? null : AppColors.surface2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? AppColors.gold : AppColors.border),
            ),
            child: Text(label,
                style: TextStyle(
                    color: selected ? Colors.black : AppColors.text,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      );

  // ───────────── Taille ─────────────

  Future<void> _resize() async {
    final design = _design;
    if (design != null) {
      var h = design.heightMm;
      final v = await showModalBottomSheet<double>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) {
            final preview = design.copyWith(heightMm: h).generate();
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sheetTitle('Taille', 'Recalcul complet des points : qualité identique à toute taille.'),
                    Row(children: [
                      const Text('Hauteur des lettres'),
                      const Spacer(),
                      Text('${h.toStringAsFixed(0)} mm',
                          style: const TextStyle(
                              color: AppColors.goldLight, fontWeight: FontWeight.w800)),
                    ]),
                    Slider(
                      value: h,
                      min: 8,
                      max: 80,
                      divisions: 72,
                      onChanged: (x) => setD(() => h = x),
                    ),
                    _infoLine(Icons.straighten,
                        'Résultat : ${preview.widthMm.toStringAsFixed(1)} × ${preview.heightMm.toStringAsFixed(1)} mm · ${preview.stitchCount} points'),
                    const SizedBox(height: 16),
                    GoldButton(
                      label: 'Appliquer',
                      icon: Icons.check,
                      onPressed: () => Navigator.pop(ctx, h),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      if (v != null && mounted) _setDesign(design.copyWith(heightMm: v));
      return;
    }

    var pct = 100.0;
    final base = _base;
    final v = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final f = pct / 100;
          final risky = sizeChangePercent(f) > 20;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sheetTitle('Taille',
                      'Fichier déjà en points : les longs points sont divisés, les petits supprimés.'),
                  Row(children: [
                    Text('${pct.toStringAsFixed(0)} %',
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.goldLight)),
                    const Spacer(),
                    Text('${(base.widthMm * f).toStringAsFixed(1)} × ${(base.heightMm * f).toStringAsFixed(1)} mm',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  Slider(
                    value: pct,
                    min: 50,
                    max: 200,
                    divisions: 150,
                    onChanged: (x) => setD(() => pct = x),
                  ),
                  Wrap(children: [
                    for (final q in const [80.0, 90.0, 100.0, 110.0, 120.0])
                      _pill('${q.toStringAsFixed(0)} %', pct == q, () => setD(() => pct = q)),
                  ]),
                  if (risky)
                    _infoLine(Icons.warning_amber_rounded,
                        'Au-delà de ±20 %, la densité et la couverture d\'un fichier DST changent. '
                        'Pour un texte, utilisez « Texte brodé » qui recalcule tout.',
                        color: const Color(0xFFFBBF24))
                  else
                    _infoLine(Icons.check_circle_outline,
                        'Variation sûre pour un fichier déjà en points.',
                        color: AppColors.success),
                  const SizedBox(height: 16),
                  GoldButton(
                    label: 'Appliquer',
                    icon: Icons.check,
                    onPressed: pct == 100 ? null : () => Navigator.pop(ctx, f),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (v == null || !mounted) return;
    final r = scalePattern(_base, v);
    setState(() {
      _setBase(r.pattern);
      _modified = true;
    });
    _snack('Nouvelle taille ✓'
        '${r.split > 0 ? ' · ${r.split} points ajoutés (longs points divisés)' : ''}'
        '${r.removed > 0 ? ' · ${r.removed} petits points supprimés' : ''}');
  }

  // ───────────── Densité ─────────────

  Future<void> _density() async {
    final design = _design;
    if (design != null) {
      var auto = design.autoDensity;
      var val = design.densityMm;
      final ok = await showModalBottomSheet<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) {
            final d2 = design.copyWith(autoDensity: auto, densityMm: val);
            final count = d2.generate().stitchCount;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sheetTitle('Densité',
                        'Écart entre deux points satin. Plus petit = plus couvrant, plus de points.'),
                    Wrap(children: [
                      _pill('Auto · ${design.fabric.label} (${design.fabric.densityMm.toStringAsFixed(2)})',
                          auto, () => setD(() => auto = true)),
                      for (final x in const [0.30, 0.35, 0.40, 0.45, 0.50, 0.60])
                        _pill('${x.toStringAsFixed(2)} mm', !auto && (val - x).abs() < 0.001,
                            () => setD(() {
                                  auto = false;
                                  val = x;
                                })),
                    ]),
                    _infoLine(Icons.grain, 'Résultat : $count points (actuellement ${_base.stitchCount})'),
                    const SizedBox(height: 16),
                    GoldButton(
                      label: 'Appliquer',
                      icon: Icons.check,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      if (ok == true && mounted) {
        _setDesign(design.copyWith(autoDensity: auto, densityMm: val));
      }
      return;
    }

    final current = estimateSatinDensity(_base);
    double? target;
    final v = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final options = [
            for (final x in const [0.40, 0.45, 0.50, 0.55, 0.60])
              if (current == null || x > current + 0.02) x,
          ];
          final removed = target == null ? 0 : thinDensity(_base, target!).removed;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sheetTitle('Densité',
                      'Allège les colonnes satin d\'un fichier déjà en points.'),
                  LuxCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      const Text('Densité actuelle estimée'),
                      const Spacer(),
                      Text(current == null ? 'pas de satin' : '${current.toStringAsFixed(2)} mm',
                          style: const TextStyle(
                              color: AppColors.goldLight, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (options.isEmpty)
                    _infoLine(Icons.info_outline, 'La densité est déjà légère.')
                  else
                    Wrap(children: [
                      for (final x in options)
                        _pill('${x.toStringAsFixed(2)} mm', target == x,
                            () => setD(() => target = x)),
                    ]),
                  _infoLine(
                    Icons.info_outline,
                    'Un fichier DST ne garde que les points, pas les formes : on peut alléger, '
                    'pas densifier. Les remplissages et les passages ne sont pas modifiés.',
                  ),
                  if (target != null)
                    _infoLine(Icons.grain, '$removed points retirés',
                        color: AppColors.goldLight),
                  const SizedBox(height: 16),
                  GoldButton(
                    label: 'Appliquer',
                    icon: Icons.check,
                    onPressed: target == null || removed == 0
                        ? null
                        : () => Navigator.pop(ctx, target),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (v == null || !mounted) return;
    final r = thinDensity(_base, v);
    setState(() {
      _setBase(r.pattern);
      _modified = true;
    });
    _snack('Densité allégée ✓ · ${r.removed} points retirés');
  }

  // ───────────── Point de départ ─────────────

  void _startPoint() {
    final hasOrigin = _design == null;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          void pick(StartAnchor a) {
            setD(() {});
            setState(() {
              _anchor = a;
              _modified = true;
              _rebuild();
            });
          }

          Widget cell(StartAnchor a) {
            final sel = _anchor == a;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => pick(a),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: sel ? goldGradient : null,
                      color: sel ? null : AppColors.surface2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sel ? AppColors.gold : AppColors.border),
                    ),
                    child: Icon(Icons.adjust,
                        color: sel ? Colors.black : AppColors.muted, size: 20),
                  ),
                ),
              ),
            );
          }

          const grid = [
            [StartAnchor.topLeft, StartAnchor.topCenter, StartAnchor.topRight],
            [StartAnchor.middleLeft, StartAnchor.center, StartAnchor.middleRight],
            [StartAnchor.bottomLeft, StartAnchor.bottomCenter, StartAnchor.bottomRight],
          ];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sheetTitle('Point de début et de fin',
                      'Où la machine se place au départ (anneau vert). La fin est le point rouge.'),
                  for (final row in grid) Row(children: [for (final a in row) cell(a)]),
                  if (hasOrigin)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(children: [
                        _pill(StartAnchor.original.label, _anchor == StartAnchor.original,
                            () => pick(StartAnchor.original)),
                      ]),
                    ),
                  const SizedBox(height: 4),
                  Text('Départ : ${_anchor.label}',
                      style: const TextStyle(color: AppColors.goldLight)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _returnToStart,
                    activeThumbColor: AppColors.gold,
                    title: const Text('Revenir au point de départ à la fin'),
                    subtitle: const Text('Utile pour enchaîner les pièces sur la machine',
                        style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    onChanged: (v) {
                      setD(() {});
                      setState(() {
                        _returnToStart = v;
                        _modified = true;
                        _rebuild();
                      });
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showColors() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Couleurs',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${_geo.colors.length} passages de fil, dans l\'ordre de la machine',
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _geo.colors.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: LuxCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: _geo.colors[i],
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24, width: 2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text('Couleur ${i + 1}')),
                          Text('${_geo.segmentsOfBlock(i)} points',
                              style: const TextStyle(color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _export() {
    final canReuse =
        !_modified && widget.sourceFormat == 'dst' && widget.sourceBytes != null;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExportSheet(
        pattern: _pattern,
        originalDst: canReuse ? widget.sourceBytes : null,
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _duration(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    if (h > 0) return '$h h ${m.toString().padLeft(2, '0')}';
    return m > 0 ? '$m min ${s.toString().padLeft(2, '0')}' : '$s s';
  }

  String _thousands(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  Widget _circleButton(IconData icon, String tip, VoidCallback onTap, {bool active = false}) {
    return Tooltip(
      message: tip,
      child: Material(
        color: active ? AppColors.gold : AppColors.surface2,
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: active ? Colors.black : AppColors.text),
          ),
        ),
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 88,
        child: LuxCard(
          radius: 16,
          padding: const EdgeInsets.symmetric(vertical: 10),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: AppColors.gold),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: surfaceGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.gold),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _pattern;
    final fmt = switch (widget.sourceFormat) {
      'demo' => 'DÉMO',
      'image' => 'IMAGE · TATAMI',
      'texte' => 'TEXTE BRODÉ · ${_design?.fabric.label ?? ''}',
      _ => widget.sourceFormat.toUpperCase(),
    };
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // En-tête
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  _circleButton(Icons.arrow_back, 'Retour', () => Navigator.pop(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('$fmt${_modified ? ' · modifié' : ''}',
                            style: const TextStyle(
                                color: AppColors.goldLight, fontSize: 12, letterSpacing: 1)),
                      ],
                    ),
                  ),
                  _circleButton(Icons.view_in_ar, 'Rendu fil réaliste',
                      () => setState(() => _realistic = !_realistic),
                      active: _realistic),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 42,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: goldGradient,
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: TextButton.icon(
                        onPressed: _export,
                        icon: const Icon(Icons.download, color: Colors.black, size: 18),
                        label: const Text('Exporter',
                            style: TextStyle(
                                color: Colors.black, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Statistiques
            SizedBox(
              height: 62,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  _stat(Icons.grain, _thousands(p.stitchCount), 'points'),
                  _stat(Icons.straighten,
                      '${p.widthMm.toStringAsFixed(1)} × ${p.heightMm.toStringAsFixed(1)}',
                      'mm'),
                  _stat(Icons.palette_outlined, '${p.colorBlockCount}', 'couleurs'),
                  _stat(Icons.timer_outlined, _duration(p.estimate(_machineSpm)),
                      'à $_machineSpm pts/min'),
                  _stat(Icons.call_split, '${p.jumpCount}', 'sauts'),
                  _stat(Icons.content_cut, '${p.trimCount}', 'coupes'),
                ],
              ),
            ),
            // Toile
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(color: Color(0x88000000), blurRadius: 24, offset: Offset(0, 10)),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: InteractiveViewer(
                  maxScale: 25,
                  child: RepaintBoundary(
                    child: SizedBox.expand(
                      child: CustomPaint(
                        isComplex: true,
                        willChange: _playing,
                        painter: PatternPainter(_geo,
                            progress: _prog,
                            showNeedle: _playing,
                            realistic: _realistic,
                            showStartEnd: !_playing,
                            showJumps: _showJumps),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Outils
            SizedBox(
              height: 74,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _tool(Icons.open_in_full, 'Taille', _resize),
                  _tool(Icons.density_medium, 'Densité', _density),
                  _tool(Icons.my_location, 'Départ', _startPoint),
                  _tool(Icons.cleaning_services_outlined, 'Petits points', _smallStitches),
                  _tool(Icons.palette_outlined, 'Couleurs', _showColors),
                  _tool(_showJumps ? Icons.visibility_off_outlined : Icons.call_split,
                      _showJumps ? 'Masquer sauts' : 'Voir sauts', () {
                    setState(() => _showJumps = !_showJumps);
                    if (_showJumps) {
                      _snack('${_pattern.jumpCount} sauts (rouge) · ${_pattern.trimCount} coupes (croix)');
                    }
                  }),
                ],
              ),
            ),
            // Simulation
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
              decoration: BoxDecoration(
                gradient: surfaceGradient,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _togglePlay,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        gradient: goldGradient,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_playing ? Icons.pause : Icons.play_arrow,
                          color: Colors.black, size: 28),
                    ),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _prog,
                      builder: (_, v, __) => Slider(
                        value: v.clamp(0, _geo.total - 1).toDouble(),
                        min: 0,
                        max: (_geo.total - 1).clamp(1, 1 << 30).toDouble(),
                        onChanged: (x) {
                          if (_playing) _ticker.stop();
                          _progress = x.round();
                        },
                        onChangeEnd: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: _prog,
                    builder: (_, v, __) => Text('${v + 1}/${_geo.total}',
                        style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                  PopupMenuButton<int>(
                    tooltip: 'Vitesse',
                    icon: const Icon(Icons.speed, color: AppColors.gold),
                    initialValue: _speed,
                    onSelected: (v) => setState(() {
                      _speed = v;
                      if (_playing) {
                        _ticker.stop();
                        _playFrom = _progress;
                        _ticker.start();
                      }
                    }),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 80, child: Text('Lente')),
                      PopupMenuItem(value: 300, child: Text('Normale')),
                      PopupMenuItem(value: 1500, child: Text('Rapide')),
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
}
