import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/image_digitize.dart';
import '../core/text_engine.dart' show TrimMode, TrimModeInfo;
import 'text_editor_screen.dart' show threadColors;
import 'theme.dart';
import 'viewer_screen.dart';

/// Image noir et blanc → broderie : formes détectées, couleurs par groupe, tatami.
class ImageImportScreen extends StatefulWidget {
  const ImageImportScreen({super.key});

  @override
  State<ImageImportScreen> createState() => _ImageImportScreenState();
}

/// Effet d'un toucher sur une forme de l'aperçu.
enum _Tap { remove, satin, tatami, auto }

class _ImageImportScreenState extends State<ImageImportScreen> {
  _Tap _tap = _Tap.remove;
  ImageAnalysis? _a;
  ui.Image? _overlay;
  String? _busy; // message pendant un calcul
  String _name = 'IMAGE';

  double _widthCm = 30;
  int _groups = 2;
  final List<int> _colors = [0xFFD4AF37, 0xFFC8102E, 0xFF1E7A46, 0xFF0B3D91, 0xFF7B2CBF, 0xFFF0F0F0];
  double _density = 0.40;
  double _angle = 45;
  TrimMode _trim = TrimMode.auto;
  double _jumpMax = 5;

  @override
  void dispose() {
    _overlay?.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
      if (bytes == null) throw Exception('fichier illisible');
      setState(() => _busy = 'Analyse de l\'image…');
      final dot = f.name.lastIndexOf('.');
      _name = (dot > 0 ? f.name.substring(0, dot) : f.name).toUpperCase();

      // Décodage (limité à 2000 px pour rester rapide).
      var codec = await ui.instantiateImageCodec(bytes);
      var img = (await codec.getNextFrame()).image;
      final longest = math.max(img.width, img.height);
      if (longest > 2000) {
        final k = 2000 / longest;
        final tw = (img.width * k).round(), th = (img.height * k).round();
        img.dispose();
        codec = await ui.instantiateImageCodec(bytes, targetWidth: tw, targetHeight: th);
        img = (await codec.getNextFrame()).image;
      }
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = img.width, h = img.height;
      img.dispose();
      if (data == null) throw Exception('décodage impossible');

      final a = await compute(
          analyzeImage, DigitizeInput(data.buffer.asUint8List(), w, h, groups: _groups));
      if (!mounted) return;
      if (a.shapes.isEmpty) {
        setState(() => _busy = null);
        _snack('Aucune forme noire détectée dans cette image.');
        return;
      }
      a.setWidthMm(_widthCm * 10);
      _a = a;
      await _refreshOverlay();
      if (mounted) setState(() => _busy = null);
    } catch (e) {
      if (mounted) setState(() => _busy = null);
      _snack('Erreur : $e');
    }
  }

  Future<void> _refreshOverlay() async {
    final a = _a;
    if (a == null) return;
    final buf = Uint8List(a.w * a.h * 4);
    a.setWidthMm(_widthCm * 10);
    final colorOf = [
      for (final s in a.shapes) s.excluded ? 0xFFD9D9D9 : _colors[s.group % _colors.length],
    ];
    final satin = [for (final s in a.shapes) !s.excluded && s.isSatin(a.pxMm)];
    for (var i = 0; i < a.w * a.h; i++) {
      final l = a.labels[i];
      var c = l == 0 ? 0xFFFFFFFF : colorOf[l - 1];
      // Satin : hachures claires ; tatami : aplat.
      if (l != 0 && satin[l - 1] && ((i % a.w) + (i ~/ a.w)) % 8 < 3) {
        c = Color.lerp(Color(c), Colors.white, 0.55)!.toARGB32();
      }
      buf[i * 4] = (c >> 16) & 0xFF;
      buf[i * 4 + 1] = (c >> 8) & 0xFF;
      buf[i * 4 + 2] = c & 0xFF;
      buf[i * 4 + 3] = 0xFF;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(buf, a.w, a.h, ui.PixelFormat.rgba8888, done.complete);
    final img = await done.future;
    if (!mounted) {
      img.dispose();
      return;
    }
    setState(() {
      _overlay?.dispose();
      _overlay = img;
    });
  }

  void _toggleAt(Offset local, Size box) {
    final a = _a;
    if (a == null) return;
    final k = math.min(box.width / a.w, box.height / a.h);
    final dx = (box.width - a.w * k) / 2, dy = (box.height - a.h * k) / 2;
    final x = ((local.dx - dx) / k).floor(), y = ((local.dy - dy) / k).floor();
    // Forme la plus proche du doigt (rayon de quelques pixels).
    for (var r = 0; r <= 12; r += 3) {
      for (var oy = -r; oy <= r; oy += 3) {
        for (var ox = -r; ox <= r; ox += 3) {
          final xx = x + ox, yy = y + oy;
          if (xx < 0 || yy < 0 || xx >= a.w || yy >= a.h) continue;
          final l = a.labels[yy * a.w + xx];
          if (l > 0) {
            final s = a.shapes[l - 1];
            switch (_tap) {
              case _Tap.remove:
                s.excluded = !s.excluded;
              case _Tap.satin:
                s.excluded = false;
                s.mode = StitchMode.satin;
              case _Tap.tatami:
                s.excluded = false;
                s.mode = StitchMode.tatami;
              case _Tap.auto:
                s.excluded = false;
                s.mode = StitchMode.auto;
            }
            _refreshOverlay();
            setState(() {});
            return;
          }
        }
      }
    }
  }

  void _regroup(int k) {
    final a = _a;
    _groups = k;
    if (a != null) {
      groupShapes(a.shapes, k);
      _refreshOverlay();
    }
    setState(() {});
  }

  void _setModeForGroup(int? group, StitchMode m) {
    final a = _a;
    if (a == null) return;
    for (final s in a.shapes) {
      if (group == null || s.group == group) s.mode = m;
    }
    _refreshOverlay();
    setState(() {});
  }

  void _shuffleColors() {
    final rnd = math.Random();
    final pool = [...threadColors]..shuffle(rnd);
    setState(() {
      for (var i = 0; i < _colors.length; i++) {
        _colors[i] = pool[i % pool.length];
      }
    });
    _refreshOverlay();
  }

  Future<void> _pickColor(int group) async {
    final c = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in threadColors)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, c),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (c == null) return;
    setState(() => _colors[group] = c);
    _refreshOverlay();
  }

  Future<void> _create() async {
    final a = _a;
    if (a == null) return;
    setState(() => _busy = 'Création des points…');
    try {
      a.setWidthMm(_widthCm * 10);
      final req = DigitizeRequest(
        a,
        DigitizeOptions(
          groupColors: List.of(_colors),
          densityMm: _density,
          angleDeg: _angle,
          trimMode: _trim,
          jumpMaxMm: _jumpMax,
        ),
        _name,
      );
      final p = await compute(digitizeRequest, req);
      if (!mounted) return;
      setState(() => _busy = null);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ViewerScreen(pattern: p, sourceFormat: 'image'),
      ));
    } catch (e) {
      if (mounted) setState(() => _busy = null);
      _snack('Erreur : $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Widget _section(String title, Widget child, {String? value}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: LuxCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(title.toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 11, letterSpacing: 1.5)),
                const Spacer(),
                if (value != null)
                  Text(value,
                      style: const TextStyle(
                          color: AppColors.goldLight, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              child,
            ],
          ),
        ),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
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
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final heightCm = a == null || a.designW == 0 ? 0.0 : _widthCm * a.designH / a.designW;
    final counts = List<int>.filled(_groups, 0);
    var active = 0;
    if (a != null) {
      for (final s in a.shapes) {
        if (s.excluded) continue;
        active++;
        if (s.group < _groups) counts[s.group]++;
      }
    }
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(children: [
                    IconButton.filledTonal(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Image → broderie',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    if (a != null)
                      SizedBox(
                        height: 42,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: goldGradient,
                            borderRadius: BorderRadius.circular(21),
                          ),
                          child: TextButton.icon(
                            onPressed: _busy == null && active > 0 ? _create : null,
                            icon: const Icon(Icons.auto_fix_high, color: Colors.black, size: 18),
                            label: const Text('Créer',
                                style: TextStyle(
                                    color: Colors.black, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                  ]),
                ),
                Expanded(
                  child: a == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.image_outlined,
                                    size: 72, color: AppColors.gold),
                                const SizedBox(height: 16),
                                const Text(
                                  'Choisissez un dessin noir sur fond blanc (PNG ou JPG).\n'
                                  'Les formes fines passent en satin, les larges en tatami ; vous pouvez choisir forme par forme.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.muted),
                                ),
                                const SizedBox(height: 24),
                                GoldButton(
                                  label: 'Choisir une image',
                                  icon: Icons.photo_library_outlined,
                                  onPressed: _busy == null ? _pick : null,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          children: [
                            Container(
                              height: 320,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.border),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: LayoutBuilder(
                                builder: (ctx, cons) => GestureDetector(
                                  onTapUp: (d) => _toggleAt(
                                      d.localPosition, Size(cons.maxWidth, cons.maxHeight)),
                                  child: _overlay == null
                                      ? const SizedBox.expand()
                                      : RawImage(
                                          image: _overlay,
                                          fit: BoxFit.contain,
                                          width: cons.maxWidth,
                                          height: cons.maxHeight,
                                        ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                              child: Row(children: [
                                Text('$active formes',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                      switch (_tap) {
                                        _Tap.remove => 'Touchez une forme pour la retirer ou la remettre',
                                        _Tap.satin => 'Touchez les formes à broder en satin',
                                        _Tap.tatami => 'Touchez les formes à broder en tatami',
                                        _Tap.auto => 'Touchez une forme pour la remettre en auto',
                                      },
                                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                ),
                                TextButton(
                                  onPressed: _busy == null ? _pick : null,
                                  child: const Text('Autre image'),
                                ),
                              ]),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(children: [
                                for (final (t, label, icon) in const [
                                  (_Tap.remove, 'Retirer', Icons.remove_circle_outline),
                                  (_Tap.satin, 'Satin', Icons.format_align_justify),
                                  (_Tap.tatami, 'Tatami', Icons.grid_on),
                                  (_Tap.auto, 'Auto', Icons.auto_awesome),
                                ])
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 3),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () => setState(() => _tap = t),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          decoration: BoxDecoration(
                                            gradient: _tap == t ? goldGradient : null,
                                            color: _tap == t ? null : AppColors.surface2,
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(
                                                color: _tap == t ? AppColors.gold : AppColors.border),
                                          ),
                                          child: Column(children: [
                                            Icon(icon,
                                                size: 20,
                                                color: _tap == t ? Colors.black : AppColors.gold),
                                            const SizedBox(height: 2),
                                            Text(label,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: _tap == t ? Colors.black : AppColors.text)),
                                          ]),
                                        ),
                                      ),
                                    ),
                                  ),
                              ]),
                            ),
                            _section(
                              'Type de point',
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(children: [
                                    _chip('Tout auto', false,
                                        () => _setModeForGroup(null, StitchMode.auto)),
                                    _chip('Tout satin', false,
                                        () => _setModeForGroup(null, StitchMode.satin)),
                                    _chip('Tout tatami', false,
                                        () => _setModeForGroup(null, StitchMode.tatami)),
                                  ]),
                                  for (var g = 0; g < _groups; g++)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(children: [
                                        Container(
                                          width: 22,
                                          height: 22,
                                          margin: const EdgeInsets.only(right: 10, bottom: 8),
                                          decoration: BoxDecoration(
                                              color: Color(_colors[g]), shape: BoxShape.circle),
                                        ),
                                        Expanded(
                                          child: Wrap(children: [
                                            for (final m in StitchMode.values)
                                              _chip(
                                                switch (m) {
                                                  StitchMode.auto => 'Auto',
                                                  StitchMode.satin => 'Satin',
                                                  StitchMode.tatami => 'Tatami',
                                                },
                                                a.shapes
                                                    .where((x) => x.group == g)
                                                    .every((x) => x.mode == m),
                                                () => _setModeForGroup(g, m),
                                              ),
                                          ]),
                                        ),
                                      ]),
                                    ),
                                  Builder(builder: (_) {
                                    var nS = 0, nT = 0, wide = 0;
                                    for (final x in a.shapes) {
                                      if (x.excluded) continue;
                                      if (x.isSatin(_widthCm * 10 / math.max(1, a.designW))) {
                                        nS++;
                                        if (x.widthMm(_widthCm * 10 / math.max(1, a.designW)) > 10) {
                                          wide++;
                                        }
                                      } else {
                                        nT++;
                                      }
                                    }
                                    return Text(
                                      '$nS en satin (hachuré) · $nT en tatami (plein)'
                                      '${wide > 0 ? '\n$wide formes larges en satin : points longs divisés automatiquement' : ''}',
                                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            _section(
                              'Largeur du dessin',
                              Column(children: [
                                Slider(
                                  value: _widthCm,
                                  min: 3,
                                  max: 40,
                                  divisions: 74,
                                  onChanged: (v) => setState(() => _widthCm = v),
                                  onChangeEnd: (_) => _refreshOverlay(),
                                ),
                                if (_widthCm > 20 || heightCm > 20)
                                  const Text(
                                    'Grand format : vérifiez que votre cadre est assez grand.',
                                    style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12),
                                  ),
                              ]),
                              value:
                                  '${_widthCm.toStringAsFixed(1)} × ${heightCm.toStringAsFixed(1)} cm',
                            ),
                            _section(
                              'Couleurs selon les formes',
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(children: [
                                    for (var k = 1; k <= 4; k++)
                                      _chip('$k couleur${k > 1 ? 's' : ''}', _groups == k,
                                          () => _regroup(k)),
                                  ]),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 10,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      for (var g = 0; g < _groups; g++)
                                        GestureDetector(
                                          onTap: () => _pickColor(g),
                                          child: Column(children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: Color(_colors[g]),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: AppColors.goldLight, width: 2),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text('${counts[g]}',
                                                style: const TextStyle(
                                                    color: AppColors.muted, fontSize: 11)),
                                          ]),
                                        ),
                                      OutlinedButton.icon(
                                        onPressed: _shuffleColors,
                                        icon: const Icon(Icons.shuffle, size: 18),
                                        label: const Text('Aléatoire'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Les formes qui se ressemblent (taille, finesse) ont la même couleur. '
                                    'Touchez une pastille pour la changer.',
                                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            _section(
                              'Remplissage tatami',
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Angle des rangées',
                                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                  const SizedBox(height: 6),
                                  Wrap(children: [
                                    for (final x in const [0.0, 45.0, 90.0, 135.0])
                                      _chip('${x.toStringAsFixed(0)}°', _angle == x,
                                          () => setState(() => _angle = x)),
                                  ]),
                                  const Text('Densité',
                                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                  const SizedBox(height: 6),
                                  Wrap(children: [
                                    for (final x in const [0.35, 0.40, 0.45, 0.50])
                                      _chip('${x.toStringAsFixed(2)} mm', _density == x,
                                          () => setState(() => _density = x)),
                                  ]),
                                ],
                              ),
                            ),
                            _section(
                              'Coupes entre les formes',
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(children: [
                                    for (final m in TrimMode.values)
                                      _chip(m.label, _trim == m, () => setState(() => _trim = m)),
                                  ]),
                                  if (_trim == TrimMode.auto)
                                    Slider(
                                      value: _jumpMax,
                                      min: 1,
                                      max: 30,
                                      divisions: 29,
                                      onChanged: (v) => setState(() => _jumpMax = v),
                                    ),
                                ],
                              ),
                              value: _trim == TrimMode.auto
                                  ? 'coupe au-delà de ${_jumpMax.toStringAsFixed(0)} mm'
                                  : null,
                            ),
                          ],
                        ),
                ),
              ],
            ),
            if (_busy != null)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xAA000000),
                  child: Center(
                    child: LuxCard(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: AppColors.gold),
                          const SizedBox(height: 16),
                          Text(_busy!),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
