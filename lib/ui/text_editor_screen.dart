import 'package:flutter/material.dart';

import '../core/pattern.dart';
import '../core/text_engine.dart';
import 'pattern_painter.dart';
import 'theme.dart';
import 'viewer_screen.dart';

/// Couleurs de fil proposées.
const threadColors = <int>[
  0xFFD4AF37, 0xFFF0F0F0, 0xFF111111, 0xFFC8102E, 0xFF0B3D91,
  0xFF1E7A46, 0xFFE91E63, 0xFF7B2CBF, 0xFFFF8C00, 0xFF8D99AE,
];

class TextEditorScreen extends StatefulWidget {
  final TextDesign initial;
  const TextEditorScreen({super.key, this.initial = const TextDesign()});

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  late TextDesign _d;
  late EmbPattern _p;
  late PatternGeometry _g;
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _d = widget.initial;
    _ctrl = TextEditingController(text: _d.text);
    _regen();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _regen() {
    _p = _d.generate();
    _g = PatternGeometry.from(_p);
  }

  void _update(TextDesign d) => setState(() {
        _d = d;
        _regen();
      });

  void _continue() {
    if (_p.stitchCount == 0) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ViewerScreen(pattern: _p, textDesign: _d, sourceFormat: 'texte'),
    ));
  }

  Widget _section(String title, Widget child, {String? value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LuxCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title.toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 11, letterSpacing: 1.5)),
                const Spacer(),
                if (value != null)
                  Text(value,
                      style: const TextStyle(
                          color: AppColors.goldLight, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
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
                fontWeight: FontWeight.w600,
                fontSize: 13,
              )),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bad = _d.unsupported;
    final p = _p;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Texte brodé',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  SizedBox(
                    height: 42,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: goldGradient,
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: TextButton.icon(
                        onPressed: p.stitchCount == 0 ? null : _continue,
                        icon: const Icon(Icons.arrow_forward, color: Colors.black, size: 18),
                        label: const Text('Atelier',
                            style: TextStyle(
                                color: Colors.black, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Aperçu en direct
            Container(
              height: 230,
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: p.stitchCount == 0
                  ? const Center(
                      child: Text('Tapez un nom',
                          style: TextStyle(color: AppColors.muted)))
                  : CustomPaint(
                      painter: PatternPainter(_g, _g.total - 1, realistic: true),
                      child: const SizedBox.expand(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${p.stitchCount} points',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${p.widthMm.toStringAsFixed(1)} × ${p.heightMm.toStringAsFixed(1)} mm',
                      style: const TextStyle(color: AppColors.muted)),
                  Text('${p.trimCount} coupes',
                      style: const TextStyle(color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                children: [
                  _section(
                    'Texte',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _ctrl,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 2),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'VOTRE NOM',
                          ),
                          onChanged: (v) => _update(_d.copyWith(text: v)),
                        ),
                        if (bad.isNotEmpty)
                          Text(
                            'Non brodés pour l\'instant : ${bad.join(' ')} '
                            '(lettres A-Z, chiffres, tiret, point).',
                            style: const TextStyle(color: AppColors.danger, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  _section(
                    'Hauteur des lettres',
                    Slider(
                      value: _d.heightMm,
                      min: 8,
                      max: 80,
                      divisions: 72,
                      onChanged: (v) => _update(_d.copyWith(heightMm: v)),
                    ),
                    value: '${_d.heightMm.toStringAsFixed(0)} mm',
                  ),
                  _section(
                    'Espacement',
                    Slider(
                      value: _d.letterSpacingMm,
                      min: -2,
                      max: 8,
                      divisions: 40,
                      onChanged: (v) => _update(_d.copyWith(letterSpacingMm: v)),
                    ),
                    value: '${_d.letterSpacingMm.toStringAsFixed(1)} mm',
                  ),
                  _section(
                    'Largeur du satin',
                    Column(
                      children: [
                        Row(
                          children: [
                            _chip('Auto', _d.autoWidth,
                                () => _update(_d.copyWith(autoWidth: true))),
                            _chip('Manuelle', !_d.autoWidth, () => _update(_d.copyWith(
                                autoWidth: false, columnWidthMm: _d.effectiveWidthMm))),
                          ],
                        ),
                        if (!_d.autoWidth)
                          Slider(
                            value: _d.columnWidthMm.clamp(1.2, 7.0).toDouble(),
                            min: 1.2,
                            max: 7,
                            divisions: 58,
                            onChanged: (v) => _update(_d.copyWith(columnWidthMm: v)),
                          ),
                      ],
                    ),
                    value: '${_d.effectiveWidthMm.toStringAsFixed(1)} mm',
                  ),
                  _section(
                    'Tissu',
                    Wrap(
                      children: [
                        for (final f in Fabric.values)
                          _chip(f.label, _d.fabric == f,
                              () => _update(_d.copyWith(fabric: f))),
                      ],
                    ),
                    value: 'compensation ${_d.fabric.pullCompMm.toStringAsFixed(2)} mm',
                  ),
                  _section(
                    'Densité du satin',
                    Wrap(
                      children: [
                        _chip('Auto (${_d.fabric.densityMm.toStringAsFixed(2)})',
                            _d.autoDensity, () => _update(_d.copyWith(autoDensity: true))),
                        for (final v in const [0.30, 0.35, 0.40, 0.45, 0.50, 0.60])
                          _chip(
                            v.toStringAsFixed(2),
                            !_d.autoDensity && (_d.densityMm - v).abs() < 0.001,
                            () => _update(_d.copyWith(autoDensity: false, densityMm: v)),
                          ),
                      ],
                    ),
                    value: '${_d.effectiveDensityMm.toStringAsFixed(2)} mm',
                  ),
                  _section(
                    'Couleur du fil',
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final c in threadColors)
                          GestureDetector(
                            onTap: () => _update(_d.copyWith(color: c)),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color(c),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _d.color == c ? AppColors.goldLight : Colors.white24,
                                  width: _d.color == c ? 3 : 1.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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
