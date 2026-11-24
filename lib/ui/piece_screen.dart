import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/density.dart';
import '../core/dst.dart';
import '../core/hoop.dart';
import '../core/pattern.dart';
import '../core/pes.dart';
import '../core/transform.dart';
import 'pattern_painter.dart';
import 'pieces_panel.dart';
import 'theme.dart';

CountResult _adjust((EmbPattern, int) a) => adjustStitchCount(a.$1, a.$2);
PrepResult _frame(PrepRequest r) => prepareRequest(r);

/// Un morceau, étape par étape : 1. densité (nombre de points) →
/// 2. cadre en point droit et point de départ (rotation si besoin) →
/// 3. enregistrement sous un nom, puis retour à la coupe.
class PieceScreen extends StatefulWidget {
  final PrepPiece piece;
  final double hoopWmm, hoopHmm;
  final String suggestedName;
  final int startStep; // 1 : directement au cadre (dessin qui tient déjà)
  const PieceScreen({
    super.key,
    required this.piece,
    required this.hoopWmm,
    required this.hoopHmm,
    required this.suggestedName,
    this.startStep = 0,
  });

  @override
  State<PieceScreen> createState() => _PieceScreenState();
}

class _PieceScreenState extends State<PieceScreen> {
  late int _step = widget.startStep;
  late EmbPattern _base = widget.piece.pattern; // après réglage de densité
  CountResult? _count;
  final _target = TextEditingController();
  bool _busy = false;

  bool _frameOn = true;
  double _margin = 5;
  StartAnchor _anchor = StartAnchor.center;
  bool _rotate = false;
  EmbPattern? _final;
  PatternGeometry? _geo;

  late final _name = TextEditingController(text: widget.suggestedName);
  String _fmt = 'dst';
  String? _savedMsg;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _target.text = '${widget.piece.pattern.stitchCount}';
    final p = widget.piece.pattern;
    _rotate = !fitsHoop(p, widget.hoopWmm, widget.hoopHmm) &&
        fitsHoop(rotate90(p), widget.hoopWmm, widget.hoopHmm);
    _setPreview(p);
    if (_step == 1) WidgetsBinding.instance.addPostFrameCallback((_) => _buildFinal());
  }

  @override
  void dispose() {
    _target.dispose();
    _name.dispose();
    super.dispose();
  }

  void _setPreview(EmbPattern p) {
    _final = p;
    _geo = PatternGeometry.from(p);
  }

  // ───────────── 1. Densité ─────────────

  Future<void> _applyCount([int? v]) async {
    final t = v ?? int.tryParse(_target.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (t == null || t < 100) return;
    _target.text = '$t';
    setState(() => _busy = true);
    final r = await compute(_adjust, (widget.piece.pattern, t));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _count = r;
      _base = r.pattern;
      _setPreview(_base);
    });
  }

  void _resetCount() {
    setState(() {
      _count = null;
      _base = widget.piece.pattern;
      _target.text = '${_base.stitchCount}';
      _setPreview(_base);
    });
  }

  // ───────────── 2. Cadre et départ ─────────────

  Future<void> _buildFinal() async {
    setState(() => _busy = true);
    var p = _rotate ? rotate90(_base) : _base;
    if (_frameOn) {
      final b = p.bounds;
      final o = PrepOptions(
        hoopWmm: b.width / 10 + 2 * _margin + 100,
        hoopHmm: b.height / 10 + 2 * _margin + 100,
        split: false,
        marks: false,
        frame: true,
        marginMm: _margin,
        anchor: _anchor,
      );
      final r = await compute(_frame, PrepRequest(p, o));
      if (r.pieces.isNotEmpty) p = r.pieces.first.pattern;
    } else {
      p = applyStart(p, _anchor);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _setPreview(p.copyWith(name: _cleanName()));
    });
  }

  // ───────────── 3. Enregistrer ─────────────

  String _cleanName() {
    final n = _name.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '').replaceAll(' ', '_');
    return n.isEmpty ? 'MORCEAU' : n;
  }

  Uint8List _bytes() {
    final p = _final!.copyWith(name: _cleanName());
    return _fmt == 'pes' ? writePes(p) : writeDst(p);
  }

  String get _fileName => '${_cleanName()}.${_fmt.toUpperCase()}';

  Future<void> _save({bool share = false}) async {
    final bytes = _bytes();
    // Contrôle : relu sans perte.
    final back = _fmt == 'pes' ? readPes(bytes) : readDst(bytes);
    if (back.stitchCount != _final!.stitchCount) {
      setState(() => _savedMsg = 'Contrôle échoué : fichier non enregistré.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (share) {
        await shareBytes(_fileName, bytes);
        _savedMsg = 'Envoyé : $_fileName';
        _saved = true;
      } else {
        final m = await saveBytesToFolder(_fileName, bytes, _fmt);
        if (m != null) {
          _savedMsg = m;
          _saved = !m.startsWith('Attention');
        }
      }
    } catch (e) {
      _savedMsg = 'Échec : $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    if (_step == 0) {
      setState(() => _step = 1);
      _buildFinal();
    } else if (_step == 1) {
      setState(() => _step = 2);
    }
  }

  // ───────────── Interface ─────────────

  Widget _stepper() {
    Widget dot(int i, String l) {
      final on = _step == i, done = _step > i;
      return Expanded(
        child: InkWell(
          onTap: i < _step ? () => setState(() => _step = i) : null,
          child: Column(children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: on || done ? AppColors.gold : AppColors.surface2,
              child: done
                  ? const Icon(Icons.check, size: 16, color: Colors.black)
                  : Text('${i + 1}',
                      style: TextStyle(color: on ? Colors.black : AppColors.muted, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            Text(l,
                style: TextStyle(fontSize: 12, color: on ? AppColors.goldLight : AppColors.muted),
                textAlign: TextAlign.center),
          ]),
        ),
      );
    }

    return Row(children: [dot(0, 'Densité'), dot(1, 'Cadre et départ'), dot(2, 'Enregistrer')]);
  }

  Widget _preview() {
    final g = _geo;
    final p = _final;
    return LuxCard(
      padding: const EdgeInsets.all(6),
      child: AspectRatio(
        aspectRatio: 1.1,
        child: Stack(children: [
          if (g != null)
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 15,
                child: RepaintBoundary(child: CustomPaint(painter: PatternPainter(g, showStartEnd: true))),
              ),
            ),
          if (p != null)
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '${(p.bounds.width / 100).toStringAsFixed(1)} × ${(p.bounds.height / 100).toStringAsFixed(1)} cm · '
                  '${p.stitchCount} pts',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (_busy) const Center(child: CircularProgressIndicator(color: AppColors.gold)),
        ]),
      ),
    );
  }

  Widget _densityStep() {
    final cur = widget.piece.pattern.stitchCount;
    final r = _count;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      luxSection(
        'Nombre de points (densité)',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Actuellement : $cur points', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _target,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Points voulus', isDense: true),
                onSubmitted: (_) => _applyCount(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(onPressed: _busy ? null : () => _applyCount(), child: const Text('Appliquer')),
          ]),
          const SizedBox(height: 8),
          Wrap(children: [
            for (final f in [0.8, 1.2, 1.4, 1.7])
              luxChip('${f > 1 ? '+' : ''}${((f - 1) * 100).round()} %', false,
                  () => _applyCount((cur * f).round())),
          ]),
          if (r != null) ...[
            const SizedBox(height: 6),
            Text('Résultat : ${r.achieved} points (${r.achieved >= cur ? '+' : ''}${((r.achieved / cur - 1) * 100).round()} %)',
                style: const TextStyle(color: AppColors.goldLight, fontWeight: FontWeight.w700)),
            if (r.note != null) Text(r.note!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            TextButton(onPressed: _resetCount, child: const Text('Revenir à la densité d\'origine')),
          ],
          const Text(
            'Le fichier ne contient pas les formes d\'origine : les rangées et les barreaux sont '
            'ajoutés ou retirés entre ceux qui existent.',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ]),
      ),
      GoldButton(label: 'Suivant : cadre et départ', icon: Icons.arrow_forward, busy: _busy, onPressed: _next),
    ]);
  }

  Widget _frameStep() {
    final p = _final;
    final fits = p != null && fitsHoop(p, widget.hoopWmm, widget.hoopHmm);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      luxSection(
        'Cadre en point droit (5,8 mm), cousu en premier',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _frameOn,
            activeThumbColor: AppColors.gold,
            title: const Text('Ajouter le cadre autour du morceau'),
            onChanged: (v) {
              setState(() => _frameOn = v);
              _buildFinal();
            },
          ),
          if (_frameOn)
            Wrap(children: [
              for (final v in [3.0, 5.0, 8.0, 10.0])
                luxChip('${v.toInt()} mm', _margin == v, () {
                  setState(() => _margin = v);
                  _buildFinal();
                }),
            ]),
        ]),
      ),
      luxSection(
        'Point de départ',
        Row(children: [
          AnchorGrid(
              value: _anchor,
              onChanged: (a) {
                setState(() => _anchor = a);
                _buildFinal();
              }),
          const SizedBox(width: 12),
          Expanded(
            child: Text('${_anchor.label}\nLe cadre commence au coin le plus proche, puis le dessin.',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        ]),
      ),
      luxSection(
        'Cadre de la machine : ${(widget.hoopWmm / 10).toStringAsFixed(0)} × ${(widget.hoopHmm / 10).toStringAsFixed(0)} cm',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fits ? '✓ Le morceau tient dans le cadre' : '✗ Le morceau dépasse le cadre',
              style: TextStyle(color: fits ? AppColors.success : AppColors.danger, fontWeight: FontWeight.w700)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _rotate,
            activeThumbColor: AppColors.gold,
            title: const Text('Tourner de 90°'),
            onChanged: (v) {
              setState(() => _rotate = v);
              _buildFinal();
            },
          ),
        ]),
      ),
      GoldButton(label: 'Suivant : enregistrer', icon: Icons.arrow_forward, busy: _busy, onPressed: _next),
    ]);
  }

  Widget _saveStep() {
    final n = _cleanName();
    final mobile = Platform.isAndroid || Platform.isIOS;
    final p = _final;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      luxSection(
        'Nom du fichier',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(isDense: true, suffixText: '.${_fmt.toUpperCase()}'),
            onChanged: (_) => setState(() {}),
          ),
          if (n.length > 8)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Certaines machines n\'affichent que 8 caractères.',
                  style: TextStyle(color: AppColors.goldLight, fontSize: 12)),
            ),
          const SizedBox(height: 10),
          Wrap(children: [
            luxChip('DST · Tajima', _fmt == 'dst', () => setState(() => _fmt = 'dst')),
            luxChip('PES · Brother', _fmt == 'pes', () => setState(() => _fmt = 'pes')),
          ]),
          if (p != null)
            Text('${p.stitchCount} points · ${p.colorBlockCount} couleur(s) · ≈ ${p.estimate(800).inMinutes} min',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
      GoldButton(
        label: 'Enregistrer dans un dossier',
        icon: Icons.save_alt,
        busy: _busy,
        onPressed: p == null ? null : () => _save(),
      ),
      if (mobile) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: p == null || _busy ? null : () => _save(share: true),
          icon: const Icon(Icons.ios_share),
          label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Envoyer (WhatsApp, USB…)')),
        ),
      ],
      if (_savedMsg != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_savedMsg!,
              style: TextStyle(color: _saved ? AppColors.success : AppColors.danger, fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: () => Navigator.pop(context, _saved),
        icon: const Icon(Icons.arrow_back),
        label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Retour à la coupe')),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.goldLight,
          side: const BorderSide(color: AppColors.gold),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final panel = [
      _stepper(),
      const SizedBox(height: 12),
      switch (_step) { 0 => _densityStep(), 1 => _frameStep(), _ => _saveStep() },
      const SizedBox(height: 20),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) Navigator.pop(context, _saved);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Morceau ${widget.piece.index}')),
        body: SafeArea(
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Padding(padding: const EdgeInsets.all(12), child: _preview())),
                  SizedBox(width: 430, child: ListView(padding: const EdgeInsets.all(12), children: panel)),
                ])
              : ListView(padding: const EdgeInsets.all(12), children: [_preview(), const SizedBox(height: 12), ...panel]),
        ),
      ),
    );
  }
}
