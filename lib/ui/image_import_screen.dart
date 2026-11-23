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

/// Image noir et blanc → broderie : formes détectées, sélection, satin/tatami,
/// couleurs par groupe, ordre de couture optimisé.
class ImageImportScreen extends StatefulWidget {
  const ImageImportScreen({super.key});

  @override
  State<ImageImportScreen> createState() => _ImageImportScreenState();
}

String _modeLabel(StitchMode m) => switch (m) {
      StitchMode.auto => 'Auto',
      StitchMode.satin => 'Satin',
      StitchMode.tatami => 'Tatami',
    };

class _ImageImportScreenState extends State<ImageImportScreen> {
  ImageAnalysis? _a;
  ui.Image? _overlay;
  String? _busy; // message pendant un calcul
  String _name = 'IMAGE';

  double _widthCm = 30;
  int _groups = 2;
  final List<int> _colors = [0xFFD4AF37, 0xFFC8102E, 0xFF1E7A46, 0xFF0B3D91, 0xFF7B2CBF, 0xFFF0F0F0];
  final List<StitchMode> _groupMode = List.filled(6, StitchMode.auto);
  double _density = 0.40;
  double _angle = 45;
  TrimMode _trim = TrimMode.auto;
  double _jumpMax = 5;

  final Set<int> _sel = {}; // formes sélectionnées (id)
  bool _similar = false; // la sélection ajoute les formes semblables
  Offset? _dragA, _dragB; // sélection par zone (appui long puis glisser)

  @override
  void dispose() {
    _overlay?.dispose();
    super.dispose();
  }

  // ───────────── Chargement ─────────────

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
      _sel.clear();
      for (var i = 0; i < _groupMode.length; i++) {
        _groupMode[i] = StitchMode.auto;
      }
      await _refreshOverlay();
      if (mounted) setState(() => _busy = null);
    } catch (e) {
      if (mounted) setState(() => _busy = null);
      _snack('Erreur : $e');
    }
  }

  // ───────────── Aperçu ─────────────

  Future<void> _refreshOverlay() async {
    final a = _a;
    if (a == null) return;
    a.setWidthMm(_widthCm * 10);
    final buf = Uint8List(a.w * a.h * 4);
    final colorOf = [
      for (final s in a.shapes) s.excluded ? 0xFFD9D9D9 : _colors[s.group % _colors.length],
    ];
    final satin = [for (final s in a.shapes) !s.excluded && s.isSatin(a.pxMm)];
    final sel = [for (final s in a.shapes) _sel.contains(s.id)];
    for (var i = 0; i < a.w * a.h; i++) {
      final l = a.labels[i];
      var c = l == 0 ? 0xFFFFFFFF : colorOf[l - 1];
      if (l != 0) {
        final x = i % a.w, y = i ~/ a.w;
        // Satin : hachures claires ; tatami : aplat.
        if (satin[l - 1] && (x + y) % 8 < 3) {
          c = Color.lerp(Color(c), Colors.white, 0.55)!.toARGB32();
        }
        if (sel[l - 1]) {
          // Forme sélectionnée : bord épais cyan, intérieur teinté.
          final edge = x < 2 ||
              y < 2 ||
              x >= a.w - 2 ||
              y >= a.h - 2 ||
              a.labels[i - 2] != l ||
              a.labels[i + 2] != l ||
              a.labels[i - 2 * a.w] != l ||
              a.labels[i + 2 * a.w] != l;
          c = edge ? 0xFF00B8D9 : Color.lerp(Color(c), const Color(0xFF00E5FF), 0.35)!.toARGB32();
        }
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

  /// Pixel de l'image sous un point de l'aperçu.
  (int, int)? _toPixel(Offset local, Size box) {
    final a = _a;
    if (a == null) return null;
    final k = math.min(box.width / a.w, box.height / a.h);
    final dx = (box.width - a.w * k) / 2, dy = (box.height - a.h * k) / 2;
    return (((local.dx - dx) / k).floor(), ((local.dy - dy) / k).floor());
  }

  ShapeInfo? _shapeAt(Offset local, Size box) {
    final a = _a;
    final p = _toPixel(local, box);
    if (a == null || p == null) return null;
    final (x, y) = p;
    for (var r = 0; r <= 12; r += 3) {
      for (var oy = -r; oy <= r; oy += 3) {
        for (var ox = -r; ox <= r; ox += 3) {
          final xx = x + ox, yy = y + oy;
          if (xx < 0 || yy < 0 || xx >= a.w || yy >= a.h) continue;
          final l = a.labels[yy * a.w + xx];
          if (l > 0) return a.shapes[l - 1];
        }
      }
    }
    return null;
  }

  /// Formes semblables : taille proche, même finesse, même nombre de trous.
  bool _isSimilar(ShapeInfo p, ShapeInfo q) {
    final r = q.pixels / math.max(1, p.pixels);
    return r > 0.6 &&
        r < 1.67 &&
        (p.compactness - q.compactness).abs() < 0.15 &&
        math.min(p.holes, 2) == math.min(q.holes, 2);
  }

  void _tapAt(Offset local, Size box) {
    final a = _a;
    if (a == null) return;
    final s = _shapeAt(local, box);
    if (s == null) {
      if (_sel.isNotEmpty) {
        _sel.clear();
        _refreshOverlay();
        setState(() {});
      }
      return;
    }
    final adding = !_sel.contains(s.id);
    final targets = _similar ? a.shapes.where((x) => _isSimilar(s, x)).toList() : [s];
    for (final t in targets) {
      if (adding) {
        _sel.add(t.id);
      } else {
        _sel.remove(t.id);
      }
    }
    _refreshOverlay();
    setState(() {});
  }

  void _selectRect(Size box) {
    final a = _a, p = _dragA, q = _dragB;
    setState(() {
      _dragA = null;
      _dragB = null;
    });
    if (a == null || p == null || q == null) return;
    final p0 = _toPixel(Offset(math.min(p.dx, q.dx), math.min(p.dy, q.dy)), box);
    final p1 = _toPixel(Offset(math.max(p.dx, q.dx), math.max(p.dy, q.dy)), box);
    if (p0 == null || p1 == null) return;
    for (final s in a.shapes) {
      if (s.cx >= p0.$1 && s.cx <= p1.$1 && s.cy >= p0.$2 && s.cy <= p1.$2) _sel.add(s.id);
    }
    _refreshOverlay();
  }

  // ───────────── Actions ─────────────

  void _applyToSelection(StitchMode? mode, {bool toggleRemove = false}) {
    final a = _a;
    if (a == null) return;
    final chosen = a.shapes.where((s) => _sel.contains(s.id)).toList();
    if (toggleRemove) {
      final allOut = chosen.every((s) => s.excluded);
      for (final s in chosen) {
        s.excluded = !allOut;
      }
    } else {
      for (final s in chosen) {
        s.excluded = false;
        if (mode == null || mode == StitchMode.auto) {
          s.overridden = false; // retour au choix de sa couleur
          s.mode = _groupMode[s.group % _groupMode.length];
        } else {
          s.overridden = true;
          s.mode = mode;
        }
      }
    }
    _refreshOverlay();
    setState(() {});
  }

  void _setGroupMode(int g, StitchMode m) {
    final a = _a;
    _groupMode[g] = m;
    if (a != null) {
      for (final s in a.shapes) {
        if (s.group == g && !s.overridden) s.mode = m;
      }
    }
    _refreshOverlay();
    setState(() {});
  }

  void _clearOverrides() {
    final a = _a;
    if (a == null) return;
    for (final s in a.shapes) {
      s.overridden = false;
      s.mode = _groupMode[s.group % _groupMode.length];
    }
    _refreshOverlay();
    setState(() {});
  }

  void _regroup(int k) {
    final a = _a;
    _groups = k;
    if (a != null) {
      groupShapes(a.shapes, k);
      for (final s in a.shapes) {
        if (!s.overridden) s.mode = _groupMode[s.group % _groupMode.length];
      }
      _refreshOverlay();
    }
    setState(() {});
  }

  void _shuffleColors() {
    final pool = [...threadColors]..shuffle(math.Random());
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
          child: Wrap(spacing: 12, runSpacing: 12, children: [
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
          ]),
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
    setState(() => _busy = 'Création des points et optimisation de l\'ordre…');
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
      final r = await compute(digitizeRequest, req);
      if (!mounted) return;
      setState(() => _busy = null);
      final p = r.pattern;
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Bilan de la broderie'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ordre des couleurs', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (var i = 0; i < p.colors.length; i++)
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: Color(p.colors[i]),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38)),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black)),
                  ),
              ]),
              const SizedBox(height: 12),
              Text('${p.stitchCount} points'),
              Text('${p.trimCount} coupes · ${p.colorChangeCount} changements de fil'),
              Text('${r.hiddenRuns} liaisons en point droit cachées (sans coupe)'),
              Text('${p.jumpCount} sauts'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retour')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: const Text('Ouvrir l\'atelier')),
          ],
        ),
      );
      if (open == true && mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ViewerScreen(pattern: p, sourceFormat: 'image'),
        ));
      }
    } catch (e) {
      if (mounted) setState(() => _busy = null);
      _snack('Erreur : $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ───────────── Interface ─────────────

  Widget _section(String title, Widget child, {String? value}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: LuxCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(title.toUpperCase(),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11, letterSpacing: 1.5)),
              const Spacer(),
              if (value != null)
                Flexible(
                  child: Text(value,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: AppColors.goldLight, fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 6),
            child,
          ]),
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

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilledButton.tonalIcon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      );

  /// Aperçu zoomable : toucher = sélectionner, appui long + glisser = zone.
  Widget _preview() {
    return Column(children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(builder: (ctx, cons) {
            final box = Size(cons.maxWidth, cons.maxHeight);
            return InteractiveViewer(
              maxScale: 12,
              child: SizedBox(
                width: box.width,
                height: box.height,
                child: GestureDetector(
                  onTapUp: (d) => _tapAt(d.localPosition, box),
                  onLongPressStart: (d) => setState(() {
                    _dragA = d.localPosition;
                    _dragB = d.localPosition;
                  }),
                  onLongPressMoveUpdate: (d) => setState(() => _dragB = d.localPosition),
                  onLongPressEnd: (_) => _selectRect(box),
                  child: Stack(children: [
                    if (_overlay != null)
                      RawImage(
                          image: _overlay, fit: BoxFit.contain, width: box.width, height: box.height),
                    if (_dragA != null && _dragB != null)
                      Positioned.fromRect(
                        rect: Rect.fromPoints(_dragA!, _dragB!),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0x3300B8D9),
                            border: Border.all(color: const Color(0xFF00B8D9), width: 2),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            );
          }),
        ),
      ),
      const SizedBox(height: 8),
      if (_sel.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Touchez un motif pour le sélectionner · appui long puis glisser : zone · pincer : zoom',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        )
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text('${_sel.length} sélectionné${_sel.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF00B8D9))),
            ),
            _actionBtn(Icons.format_align_justify, 'Satin', () => _applyToSelection(StitchMode.satin)),
            _actionBtn(Icons.grid_on, 'Tatami', () => _applyToSelection(StitchMode.tatami)),
            _actionBtn(Icons.auto_awesome, 'Comme sa couleur', () => _applyToSelection(StitchMode.auto)),
            _actionBtn(Icons.remove_circle_outline, 'Retirer / remettre',
                () => _applyToSelection(null, toggleRemove: true)),
            IconButton(
              tooltip: 'Tout désélectionner',
              onPressed: () {
                _sel.clear();
                _refreshOverlay();
                setState(() {});
              },
              icon: const Icon(Icons.close),
            ),
          ]),
        ),
    ]);
  }

  List<Widget> _controls(ImageAnalysis a) {
    final heightCm = a.designW == 0 ? 0.0 : _widthCm * a.designH / a.designW;
    final pxMm = _widthCm * 10 / math.max(1, a.designW);
    final counts = List<int>.filled(_groups, 0);
    var nS = 0, nT = 0, wide = 0, exceptions = 0;
    for (final s in a.shapes) {
      if (s.excluded) continue;
      if (s.group < _groups) counts[s.group]++;
      if (s.overridden) exceptions++;
      if (s.isSatin(pxMm)) {
        nS++;
        if (s.widthMm(pxMm) > 10) wide++;
      } else {
        nT++;
      }
    }
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Switch(
            value: _similar,
            activeThumbColor: AppColors.gold,
            onChanged: (v) => setState(() => _similar = v),
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('Sélectionner aussi les motifs semblables',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
        ]),
      ),
      _section(
        'Couleurs et type de point',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(children: [
            for (var k = 1; k <= 4; k++)
              _chip('$k couleur${k > 1 ? 's' : ''}', _groups == k, () => _regroup(k)),
          ]),
          for (var g = 0; g < _groups; g++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GestureDetector(
                  onTap: () => _pickColor(g),
                  child: Column(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(_colors[g]),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.goldLight, width: 2),
                      ),
                    ),
                    Text('${counts[g]}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(children: [
                    for (final m in StitchMode.values)
                      _chip(_modeLabel(m), _groupMode[g] == m, () => _setGroupMode(g, m)),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 4),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(
              onPressed: _shuffleColors,
              icon: const Icon(Icons.shuffle, size: 18),
              label: const Text('Couleurs aléatoires'),
            ),
            const SizedBox(width: 8),
            if (exceptions > 0)
              TextButton(
                onPressed: _clearOverrides,
                child: Text('Annuler les $exceptions exceptions'),
              ),
          ]),
          const SizedBox(height: 6),
          Text(
            '${nS + nT} motifs : $nS en satin (hachuré) · $nT en tatami (plein)'
            '${exceptions > 0 ? '\n$exceptions motifs avec un choix à part' : ''}'
            '${wide > 0 ? '\n$wide motifs larges en satin : points longs divisés' : ''}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ]),
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
            const Text('Grand format : vérifiez que votre cadre est assez grand.',
                style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12)),
        ]),
        value: '${_widthCm.toStringAsFixed(1)} × ${heightCm.toStringAsFixed(1)} cm',
      ),
      _section(
        'Remplissage tatami',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Angle des rangées', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(children: [
            for (final x in const [0.0, 45.0, 90.0, 135.0])
              _chip('${x.toStringAsFixed(0)}°', _angle == x, () => setState(() => _angle = x)),
          ]),
          const Text('Densité', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(children: [
            for (final x in const [0.35, 0.40, 0.45, 0.50])
              _chip('${x.toStringAsFixed(2)} mm', _density == x, () => setState(() => _density = x)),
          ]),
        ]),
      ),
      _section(
        'Coupes',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          const Text(
            'Entre deux motifs, le fil passe d\'abord en point droit caché sous les motifs '
            'brodés ensuite ; sinon saut, coupé selon ce réglage.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ]),
        value: _trim == TrimMode.auto ? 'au-delà de ${_jumpMax.toStringAsFixed(0)} mm' : null,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy == null ? _pick : null,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choisir une autre image'),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    var active = 0;
    if (a != null) {
      for (final s in a.shapes) {
        if (!s.excluded) active++;
      }
    }
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
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
                          gradient: goldGradient, borderRadius: BorderRadius.circular(21)),
                      child: TextButton.icon(
                        onPressed: _busy == null && active > 0 ? _create : null,
                        icon: const Icon(Icons.auto_fix_high, color: Colors.black, size: 18),
                        label: const Text('Créer',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
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
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.image_outlined, size: 72, color: AppColors.gold),
                          const SizedBox(height: 16),
                          const Text(
                            'Choisissez un dessin noir sur fond blanc (PNG ou JPG).\n'
                            'Les formes fines passent en satin, les larges en tatami ; '
                            'vous choisissez ensuite motif par motif.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 24),
                          GoldButton(
                            label: 'Choisir une image',
                            icon: Icons.photo_library_outlined,
                            onPressed: _busy == null ? _pick : null,
                          ),
                        ]),
                      ),
                    )
                  : LayoutBuilder(builder: (ctx, cons) {
                      if (cons.maxWidth >= 900) {
                        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 6, 12),
                              child: _preview(),
                            ),
                          ),
                          SizedBox(
                            width: 430,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(6, 4, 12, 24),
                              children: _controls(a),
                            ),
                          ),
                        ]);
                      }
                      return Column(children: [
                        SizedBox(
                          height: cons.maxHeight * 0.58,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                            child: _preview(),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            children: _controls(a),
                          ),
                        ),
                      ]);
                    }),
            ),
          ]),
          if (_busy != null)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xAA000000),
                child: Center(
                  child: LuxCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(color: AppColors.gold),
                      const SizedBox(height: 16),
                      Text(_busy!),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
