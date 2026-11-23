import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/dst.dart';
import '../core/hoop.dart';
import '../core/pattern.dart';
import '../core/transform.dart';
import 'export_sheet.dart';
import 'pattern_painter.dart';
import 'theme.dart';

/// Préparer pour ma machine : cadre en point droit, découpe pour petits
/// tambours, croix de repérage, point de départ par morceau, export.
class MachineScreen extends StatefulWidget {
  final EmbPattern pattern;
  const MachineScreen({super.key, required this.pattern});

  @override
  State<MachineScreen> createState() => _MachineScreenState();
}

class _MachineScreenState extends State<MachineScreen> {
  Hoop _hoop = hoopPresets.first;
  bool _custom = false;
  double _cw = 180, _ch = 280;
  bool _frame = true;
  double _margin = 5;
  double _overlap = 2.5;
  bool _marks = true;
  StartAnchor _anchor = StartAnchor.center;
  final Map<int, StartAnchor> _pieceAnchors = {};
  PrepResult? _res;
  bool _busy = false;
  int? _sel; // morceau affiché en grand
  late final PatternGeometry _geo = PatternGeometry.from(widget.pattern);
  int _job = 0;
  final Map<PrepPiece, PatternGeometry> _geoCache = {};

  double get _hw => _custom ? _cw : _hoop.widthMm;
  double get _hh => _custom ? _ch : _hoop.heightMm;

  @override
  void initState() {
    super.initState();
    _run();
  }

  PrepOptions get _opts => PrepOptions(
        hoopWmm: _hw,
        hoopHmm: _hh,
        frame: _frame,
        marginMm: _margin,
        overlapMm: _overlap,
        marks: _marks,
        anchor: _anchor,
        pieceAnchors: Map.of(_pieceAnchors),
      );

  Future<void> _run() async {
    final job = ++_job;
    setState(() => _busy = true);
    final r = await compute(prepareRequest, PrepRequest(widget.pattern, _opts));
    if (!mounted || job != _job) return;
    setState(() {
      _busy = false;
      _res = r;
      _geoCache.clear();
      if (_sel != null && _sel! > r.pieces.length) _sel = null;
    });
  }

  void _set(VoidCallback f, {bool keepAnchors = false}) {
    setState(() {
      f();
      if (!keepAnchors) _pieceAnchors.clear();
    });
    _run();
  }

  String _fileName(int i, int n) {
    var base = widget.pattern.name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (base.isEmpty) base = 'DESIGN';
    if (n == 1) return machineFileName(base, 'dst');
    if (base.length > 6) base = base.substring(0, 6);
    return '$base${i.toString().padLeft(2, '0')}.DST';
  }

  Future<void> _exportAll() async {
    final r = _res;
    if (r == null || r.pieces.isEmpty) return;
    final n = r.pieces.length;
    try {
      final files = <(String, List<int>)>[
        for (final p in r.pieces) (_fileName(p.index, n), writeDst(p.pattern)),
      ];
      // Contrôle : chaque fichier relu doit avoir le même nombre de points.
      for (var i = 0; i < n; i++) {
        final back = readDst(Uint8List.fromList(files[i].$2));
        if (back.stitchCount != r.pieces[i].pattern.stitchCount) {
          _snack('Contrôle échoué sur ${files[i].$1}');
          return;
        }
      }
      if (Platform.isAndroid || Platform.isIOS) {
        final dir = await getTemporaryDirectory();
        final xf = <XFile>[];
        for (final (name, bytes) in files) {
          final f = File('${dir.path}/$name');
          await f.writeAsBytes(bytes, flush: true);
          xf.add(XFile(f.path, mimeType: 'application/octet-stream', name: name));
        }
        await Share.shareXFiles(xf, subject: '${widget.pattern.name} · $n morceaux');
      } else {
        final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Dossier pour les fichiers DST');
        if (dir == null) return;
        for (final (name, bytes) in files) {
          await File('$dir${Platform.pathSeparator}$name').writeAsBytes(bytes, flush: true);
        }
        _snack('$n fichier(s) enregistré(s) ✓ $dir');
      }
    } catch (e) {
      _snack('Échec : $e');
    }
  }

  void _exportOne(PrepPiece p) {
    final n = _res!.pieces.length;
    final name = _fileName(p.index, n).replaceAll('.DST', '');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExportSheet(pattern: p.pattern.copyWith(name: name)),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ───────────── Interface ─────────────

  Widget _chip(String l, bool on, VoidCallback f) => Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 6),
        child: ChoiceChip(
          label: Text(l),
          selected: on,
          onSelected: (_) => f(),
          selectedColor: AppColors.gold,
          labelStyle: TextStyle(color: on ? Colors.black : AppColors.text, fontWeight: FontWeight.w600),
          backgroundColor: AppColors.surface2,
          side: const BorderSide(color: AppColors.border),
        ),
      );

  Widget _section(String t, Widget c) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: LuxCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            c,
          ]),
        ),
      );

  Widget _anchorGrid(StartAnchor cur, ValueChanged<StartAnchor> on) {
    return SizedBox(
      width: 132,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: [
          for (final a in StartAnchor.values.skip(1))
            InkWell(
              onTap: () => on(a),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  color: a == cur ? AppColors.gold : AppColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(Icons.circle, size: 10, color: a == cur ? Colors.black : AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controls() {
    final b = widget.pattern.bounds;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section(
        'Ma machine (cadre)',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(children: [
            for (final h in hoopPresets) _chip(h.label, !_custom && h == _hoop, () => _set(() {
                  _hoop = h;
                  _custom = false;
                })),
            _chip('Autre…', _custom, () => _set(() => _custom = true)),
          ]),
          if (_custom)
            Row(children: [
              Expanded(child: _num('Largeur (cm)', _cw / 10, (v) => _set(() => _cw = v * 10))),
              const SizedBox(width: 10),
              Expanded(child: _num('Hauteur (cm)', _ch / 10, (v) => _set(() => _ch = v * 10))),
            ]),
          Text('Dessin : ${(b.width / 100).toStringAsFixed(1)} × ${(b.height / 100).toStringAsFixed(1)} cm',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
      _section(
        'Cadre en point droit (cousu en premier · points de 5,8 mm)',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _frame,
            activeThumbColor: AppColors.gold,
            title: const Text('Cadre autour du dessin'),
            onChanged: (v) => _set(() => _frame = v, keepAnchors: true),
          ),
          const Text('Distance cadre ↔ dessin', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(children: [
            for (final v in [3.0, 5.0, 8.0, 10.0])
              _chip('${v.toInt()} mm', _margin == v, () => _set(() => _margin = v)),
          ]),
        ]),
      ),
      _section(
        'Découpe (si le dessin dépasse le cadre)',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Recouvrement entre morceaux', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(children: [
            for (final v in [0.0, 2.0, 2.5, 3.0, 5.0])
              _chip(v == 0 ? 'Aucun' : '${v.toString().replaceAll('.0', '')} mm', _overlap == v,
                  () => _set(() => _overlap = v)),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _marks,
            activeThumbColor: AppColors.gold,
            title: const Text('Croix de repérage sur les lignes de coupe'),
            onChanged: (v) => _set(() => _marks = v, keepAnchors: true),
          ),
        ]),
      ),
      _section(
        'Point de départ (tous les morceaux)',
        Row(children: [
          _anchorGrid(_anchor, (a) => _set(() => _anchor = a)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(
                  '${_anchor.label}\nLe cadre commence au coin le plus proche. Touchez un morceau pour lui donner son propre départ.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12))),
        ]),
      ),
    ]);
  }

  Widget _num(String label, double v, ValueChanged<double> on) => TextFormField(
        initialValue: v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, isDense: true),
        onFieldSubmitted: (s) {
          final x = double.tryParse(s.replaceAll(',', '.'));
          if (x != null && x >= 5 && x <= 200) on(x);
        },
      );

  Widget _overview() {
    final r = _res;
    return LuxCard(
      padding: const EdgeInsets.all(8),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(children: [
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: PatternPainter(_geo, realistic: true))),
          ),
          if (r != null && r.pieces.isNotEmpty)
            Positioned.fill(
              child: LayoutBuilder(builder: (ctx, c) {
                return GestureDetector(
                  onTapUp: (d) {
                    final i = _OverlayPainter.hit(widget.pattern.bounds, r, c.biggest, d.localPosition);
                    if (i != null) setState(() => _sel = i);
                  },
                  child: CustomPaint(painter: _OverlayPainter(widget.pattern.bounds, r, _sel)),
                );
              }),
            ),
          if (_busy) const Center(child: CircularProgressIndicator(color: AppColors.gold)),
        ]),
      ),
    );
  }

  Widget _summary() {
    final r = _res;
    if (r == null) return const SizedBox.shrink();
    if (r.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(r.error!, style: const TextStyle(color: AppColors.danger)),
      );
    }
    final n = r.pieces.length;
    final whole = r.pieces.fold(0, (s, p) => s + p.wholeObjects);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n == 1 ? 'Le dessin tient dans le cadre : 1 morceau' : '$n morceaux (${r.cols} × ${r.rows})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.goldLight)),
        if (n > 1)
          Text(
              'Coupes placées dans les vides · $whole élément(s) gardé(s) entier(s) au lieu d\'être coupés',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ]),
    );
  }

  Widget _pieceCard(PrepPiece p) {
    final g = _geoCache.putIfAbsent(p, () => PatternGeometry.from(p.pattern));
    final b = p.pattern.bounds;
    final sel = _sel == p.index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LuxCard(
        highlighted: sel,
        onTap: () => setState(() => _sel = p.index),
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          SizedBox(
            width: 96,
            height: 96,
            child: RepaintBoundary(child: CustomPaint(painter: PatternPainter(g, showStartEnd: true))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Morceau ${p.index} · ${_fileName(p.index, _res!.pieces.length)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${(b.width / 100).toStringAsFixed(1)} × ${(b.height / 100).toStringAsFixed(1)} cm · '
                  '${p.pattern.stitchCount} points',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              Text('Départ : ${(_pieceAnchors[p.index] ?? _anchor).label}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 6),
              Row(children: [
                TextButton.icon(
                  onPressed: () => _pickPieceAnchor(p.index),
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('Départ'),
                ),
                TextButton.icon(
                  onPressed: () => _exportOne(p),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Exporter'),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _pickPieceAnchor(int i) async {
    final a = await showModalBottomSheet<StartAnchor>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Départ du morceau $i', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 14),
          _anchorGrid(_pieceAnchors[i] ?? _anchor, (a) => Navigator.pop(ctx, a)),
        ]),
      ),
    );
    if (a != null) _set(() => _pieceAnchors[i] = a, keepAnchors: true);
  }

  @override
  Widget build(BuildContext context) {
    final r = _res;
    final pieces = r?.pieces ?? const <PrepPiece>[];
    final wide = MediaQuery.of(context).size.width >= 900;
    final list = <Widget>[
      _summary(),
      for (final p in pieces) _pieceCard(p),
      if (pieces.isNotEmpty)
        GoldButton(
          label: pieces.length == 1 ? 'Exporter le fichier DST' : 'Exporter les ${pieces.length} fichiers DST',
          icon: Icons.download,
          busy: _busy,
          onPressed: _exportAll,
        ),
      const SizedBox(height: 24),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Préparer pour ma machine')),
      body: SafeArea(
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 430,
                  child: ListView(padding: const EdgeInsets.all(12), children: [_controls()]),
                ),
                Expanded(
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720), child: _overview()),
                    ),
                    ...list,
                  ]),
                ),
              ])
            : ListView(padding: const EdgeInsets.all(12), children: [
                _overview(),
                ...list.take(1),
                _controls(),
                ...list.skip(1),
              ]),
      ),
    );
  }
}

/// Lignes de coupe et numéros des morceaux sur l'aperçu (même cadrage que PatternPainter).
class _OverlayPainter extends CustomPainter {
  final Bounds b;
  final PrepResult r;
  final int? sel;
  _OverlayPainter(this.b, this.r, this.sel);

  static (double, double, double) _tf(Bounds b, Size s) {
    final w = math.max(b.width, 10).toDouble(), h = math.max(b.height, 10).toDouble();
    return (math.min(s.width / w, s.height / h) * 0.86, s.width / 2, s.height / 2);
  }

  static Offset _map(Bounds b, Size s, double x, double y) {
    final (k, cx, cy) = _tf(b, s);
    return Offset(cx + (x - (b.minX + b.width / 2)) * k, cy + (y - (b.minY + b.height / 2)) * k);
  }

  static int? hit(Bounds b, PrepResult r, Size s, Offset p) {
    for (final pc in r.pieces) {
      final a = _map(b, s, r.xs[pc.col].toDouble(), r.ys[pc.row].toDouble());
      final c = _map(b, s, r.xs[pc.col + 1].toDouble(), r.ys[pc.row + 1].toDouble());
      if (Rect.fromPoints(a, c).contains(p)) return pc.index;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size s) {
    final line = Paint()
      ..color = AppColors.danger
      ..strokeWidth = 2;
    for (final x in r.xs.skip(1).take(math.max(0, r.xs.length - 2))) {
      canvas.drawLine(_map(b, s, x.toDouble(), b.minY - 40), _map(b, s, x.toDouble(), b.maxY + 40), line);
    }
    for (final y in r.ys.skip(1).take(math.max(0, r.ys.length - 2))) {
      canvas.drawLine(_map(b, s, b.minX - 40, y.toDouble()), _map(b, s, b.maxX + 40, y.toDouble()), line);
    }
    for (final pc in r.pieces) {
      final a = _map(b, s, r.xs[pc.col].toDouble(), r.ys[pc.row].toDouble());
      final c = _map(b, s, r.xs[pc.col + 1].toDouble(), r.ys[pc.row + 1].toDouble());
      final rect = Rect.fromPoints(a, c);
      if (pc.index == sel) {
        canvas.drawRect(rect, Paint()..color = AppColors.gold.withValues(alpha: 0.18));
      }
      if (r.pieces.length > 1) {
        final tp = TextPainter(
          text: TextSpan(
              text: '${pc.index}',
              style: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14)),
          textDirection: TextDirection.ltr,
        )..layout();
        final o = rect.topLeft + const Offset(6, 6);
        canvas.drawCircle(o + const Offset(11, 11), 13, Paint()..color = AppColors.gold);
        tp.paint(canvas, o + Offset(11 - tp.width / 2, 11 - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter o) => o.r != r || o.sel != sel;
}
