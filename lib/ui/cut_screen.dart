import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/hoop.dart';
import '../core/pattern.dart';
import '../core/transform.dart';
import 'pattern_painter.dart';
import 'pieces_panel.dart';
import 'theme.dart';

/// Couleurs des zones (morceaux).
const _zoneColors = <Color>[
  Color(0xFF60A5FA), Color(0xFF34D399), Color(0xFFF472B6), Color(0xFFFBBF24),
  Color(0xFFA78BFA), Color(0xFF22D3EE), Color(0xFFFB923C), Color(0xFF4ADE80),
];

/// Découpe : l'utilisateur trace lui-même les lignes de coupe (libres, tordues),
/// au doigt ou à la souris ; règles en haut et à gauche ; chaque zone devient
/// un morceau, contrôlé par rapport au cadre de la machine.
class CutScreen extends StatefulWidget {
  final EmbPattern pattern;
  const CutScreen({super.key, required this.pattern});

  @override
  State<CutScreen> createState() => _CutScreenState();
}

class _CutScreenState extends State<CutScreen> {
  late final PatternGeometry _geo = PatternGeometry.from(widget.pattern);
  late final Bounds _b = widget.pattern.bounds;
  final _tc = TransformationController();

  Hoop _hoop = hoopPresets.first;
  bool _custom = false;
  double _cw = 180, _ch = 280;
  double _overlap = 2.5;
  bool _marks = true;
  bool _frame = true;
  double _margin = 5;
  StartAnchor _anchor = StartAnchor.center;
  final Map<int, StartAnchor> _pieceAnchors = {};

  final List<List<(double, double)>> _lines = [];
  List<(double, double)>? _drawing;
  bool _drawMode = true;

  CutResult? _res;
  ui.Image? _zones;
  final Map<PrepPiece, PatternGeometry> _geoCache = {};
  int? _sel;
  bool _busy = false;
  int _job = 0;
  Timer? _debounce;

  double get _hw => _custom ? _cw : _hoop.widthMm;
  double get _hh => _custom ? _ch : _hoop.heightMm;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tc.dispose();
    _zones?.dispose();
    super.dispose();
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

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _run);
  }

  Future<void> _run() async {
    final job = ++_job;
    setState(() => _busy = true);
    final r = await compute(cutRequest, CutRequest(widget.pattern, List.of(_lines), _opts));
    if (!mounted || job != _job) return;
    final img = await _zoneImage(r);
    if (!mounted || job != _job) {
      img?.dispose();
      return;
    }
    setState(() {
      _busy = false;
      _res = r;
      _zones?.dispose();
      _zones = img;
      _geoCache.clear();
      if (_sel != null && _sel! > r.pieces.length) _sel = null;
    });
  }

  bool _fits(PrepPiece p) {
    final b = p.pattern.bounds;
    return b.width <= _hw * 10 && b.height <= _hh * 10;
  }

  /// Image des zones : une couleur par morceau, rouge si le morceau dépasse le cadre.
  Future<ui.Image?> _zoneImage(CutResult r) async {
    if (r.gw == 0 || r.pieces.isEmpty) return null;
    final colorOf = <int, int>{};
    for (var i = 0; i < r.pieces.length; i++) {
      final c = _fits(r.pieces[i]) ? _zoneColors[i % _zoneColors.length] : AppColors.danger;
      colorOf[r.pieceRegion[i]] = c.toARGB32();
    }
    final px = Uint8List(r.gw * r.gh * 4);
    for (var i = 0; i < r.labels.length; i++) {
      final c = colorOf[r.labels[i]];
      if (c == null) continue;
      px[i * 4] = (c >> 16) & 0xFF;
      px[i * 4 + 1] = (c >> 8) & 0xFF;
      px[i * 4 + 2] = c & 0xFF;
      px[i * 4 + 3] = 46;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, r.gw, r.gh, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  // ───────────── Coordonnées ─────────────

  (double, double, double) _base(Size s) {
    final w = math.max(_b.width, 10).toDouble(), h = math.max(_b.height, 10).toDouble();
    return (math.min(s.width / w, s.height / h) * 0.86, s.width / 2, s.height / 2);
  }

  (double, double) _toPattern(Offset o, Size s) {
    final (k, cx, cy) = _base(s);
    return ((o.dx - cx) / k + _b.minX + _b.width / 2, (o.dy - cy) / k + _b.minY + _b.height / 2);
  }

  // ───────────── Tracé ─────────────

  void _start(Offset o, Size s) {
    if (!_drawMode) return;
    setState(() => _drawing = [_toPattern(o, s)]);
  }

  void _move(Offset o, Size s) {
    final d = _drawing;
    if (d == null) return;
    final p = _toPattern(o, s);
    final (k, _, _) = _base(s);
    final zoom = _tc.value.getMaxScaleOnAxis();
    // Un point tous les ~3 px à l'écran : trait fluide sans surcharge.
    final minStep = 3 / (k * zoom);
    final l = d.last;
    if (math.sqrt(math.pow(p.$1 - l.$1, 2) + math.pow(p.$2 - l.$2, 2)) < minStep) return;
    setState(() => d.add(p));
  }

  void _end() {
    final d = _drawing;
    if (d == null) return;
    setState(() {
      _drawing = null;
      if (d.length >= 2) {
        _lines.add(_simplify(d, 4));
        _pieceAnchors.clear();
      }
    });
    _schedule();
  }

  /// Douglas-Peucker : garde la forme du trait (tolérance en 0,1 mm).
  static List<(double, double)> _simplify(List<(double, double)> pts, double tol) {
    if (pts.length < 3) return pts;
    final keep = List<bool>.filled(pts.length, false)
      ..[0] = true
      ..[pts.length - 1] = true;
    final stack = <(int, int)>[(0, pts.length - 1)];
    while (stack.isNotEmpty) {
      final (a, z) = stack.removeLast();
      var best = -1.0, bi = -1;
      final ax = pts[a].$1, ay = pts[a].$2, zx = pts[z].$1, zy = pts[z].$2;
      final dx = zx - ax, dy = zy - ay;
      final len = math.sqrt(dx * dx + dy * dy);
      for (var i = a + 1; i < z; i++) {
        final d = len < 1e-9
            ? math.sqrt(math.pow(pts[i].$1 - ax, 2) + math.pow(pts[i].$2 - ay, 2))
            : ((pts[i].$1 - ax) * dy - (pts[i].$2 - ay) * dx).abs() / len;
        if (d > best) {
          best = d;
          bi = i;
        }
      }
      if (best > tol && bi > 0) {
        keep[bi] = true;
        stack.add((a, bi));
        stack.add((bi, z));
      }
    }
    return [for (var i = 0; i < pts.length; i++) if (keep[i]) pts[i]];
  }

  void _undo() {
    if (_lines.isEmpty) return;
    setState(() {
      _lines.removeLast();
      _pieceAnchors.clear();
    });
    _schedule();
  }

  void _clear() {
    setState(() {
      _lines.clear();
      _pieceAnchors.clear();
    });
    _schedule();
  }

  Future<void> _auto() async {
    final o = _opts;
    final lines = await compute(_suggest, (widget.pattern, o));
    if (!mounted) return;
    setState(() {
      _lines
        ..clear()
        ..addAll(lines);
      _pieceAnchors.clear();
    });
    if (lines.isEmpty) _snack('Le dessin tient déjà dans le cadre : aucune coupe nécessaire.');
    _schedule();
  }

  static List<List<(double, double)>> _suggest((EmbPattern, PrepOptions) a) => suggestCutLines(a.$1, a.$2);

  void _set(VoidCallback f, {bool keepAnchors = false}) {
    setState(() {
      f();
      if (!keepAnchors) _pieceAnchors.clear();
    });
    _schedule();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _exportAll() async {
    final r = _res;
    if (r == null || r.pieces.isEmpty) return;
    final bad = r.pieces.where((p) => !_fits(p)).map((p) => p.index).toList();
    if (bad.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Morceaux trop grands'),
          content: Text('Morceau(x) ${bad.join(', ')} dépasse(nt) le cadre '
              '${(_hw / 10).toStringAsFixed(0)} × ${(_hh / 10).toStringAsFixed(0)} cm. '
              'Ajoutez une ligne de coupe dans la zone rouge.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Corriger')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Exporter quand même')),
          ],
        ),
      );
      if (go != true) return;
    }
    final msg = await exportPieces(widget.pattern.name, r.pieces);
    if (msg != null) _snack(msg);
  }

  // ───────────── Interface ─────────────

  Widget _workspace() {
    return LayoutBuilder(builder: (ctx, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      final selPiece = (_res != null && _sel != null && _sel! <= _res!.pieces.length)
          ? _res!.pieces[_sel! - 1]
          : null;
      final canvas = SizedBox.fromSize(
        size: size,
        child: Stack(children: [
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: PatternPainter(_geo, realistic: false))),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _CutOverlay(
                b: _b,
                res: _res,
                zones: _zones,
                lines: _lines,
                drawing: _drawing,
                selected: selPiece,
                hoopW: _hw * 10,
                hoopH: _hh * 10,
                zoom: _tc,
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _drawMode ? (d) => _start(d.localPosition, size) : null,
              onPanUpdate: _drawMode ? (d) => _move(d.localPosition, size) : null,
              onPanEnd: _drawMode ? (_) => _end() : null,
              onPanCancel: _drawMode ? _end : null,
              onTapUp: (d) => _tapPiece(d.localPosition, size),
            ),
          ),
        ]),
      );
      return InteractiveViewer(
        transformationController: _tc,
        minScale: 0.5,
        maxScale: 20,
        panEnabled: !_drawMode,
        scaleEnabled: !_drawMode,
        boundaryMargin: const EdgeInsets.all(400),
        child: canvas,
      );
    });
  }

  void _tapPiece(Offset o, Size s) {
    final r = _res;
    if (r == null || r.gw == 0) return;
    final (x, y) = _toPattern(o, s);
    final cx = ((x - r.gx0) / r.res).floor(), cy = ((y - r.gy0) / r.res).floor();
    if (cx < 0 || cy < 0 || cx >= r.gw || cy >= r.gh) return;
    final reg = r.labels[cy * r.gw + cx];
    final i = r.pieceRegion.indexOf(reg);
    if (i >= 0) setState(() => _sel = i + 1);
  }

  Widget _rulers(Widget child) {
    const t = 26.0;
    return LayoutBuilder(builder: (ctx, c) {
      final size = Size(c.maxWidth - t, c.maxHeight - t);
      return Column(children: [
        SizedBox(
          height: t,
          child: Row(children: [
            const SizedBox(width: t),
            Expanded(
              child: CustomPaint(
                size: Size.infinite,
                painter: _Ruler(horizontal: true, b: _b, view: size, tc: _tc),
              ),
            ),
          ]),
        ),
        Expanded(
          child: Row(children: [
            SizedBox(
              width: t,
              child: CustomPaint(
                size: Size.infinite,
                painter: _Ruler(horizontal: false, b: _b, view: size, tc: _tc),
              ),
            ),
            Expanded(child: ClipRect(child: child)),
          ]),
        ),
      ]);
    });
  }

  Widget _toolbar() {
    Widget btn(IconData i, String l, VoidCallback? f, {bool on = false}) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: on ? AppColors.gold : AppColors.surface2,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: f,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(i, size: 18, color: on ? Colors.black : AppColors.text),
                  const SizedBox(width: 6),
                  Text(l,
                      style: TextStyle(
                          color: on ? Colors.black : AppColors.text, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        );
    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        btn(Icons.draw, 'Tracer', () => setState(() => _drawMode = true), on: _drawMode),
        btn(Icons.pan_tool_alt, 'Déplacer / zoom', () => setState(() => _drawMode = false), on: !_drawMode),
        btn(Icons.undo, 'Annuler', _lines.isEmpty ? null : _undo),
        btn(Icons.delete_sweep, 'Tout effacer', _lines.isEmpty ? null : _clear),
        btn(Icons.auto_fix_high, 'Proposer', _auto),
        btn(Icons.center_focus_strong, 'Recentrer', () => _tc.value = Matrix4.identity()),
      ]),
    );
  }

  Widget _controls() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      luxSection(
        'Ma machine (cadre)',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(children: [
            for (final h in hoopPresets)
              luxChip(h.label, !_custom && h == _hoop, () => _set(() {
                    _hoop = h;
                    _custom = false;
                  }, keepAnchors: true)),
            luxChip('Autre…', _custom, () => _set(() => _custom = true, keepAnchors: true)),
          ]),
          if (_custom)
            Row(children: [
              Expanded(child: _num('Largeur (cm)', _cw / 10, (v) => _set(() => _cw = v * 10, keepAnchors: true))),
              const SizedBox(width: 10),
              Expanded(child: _num('Hauteur (cm)', _ch / 10, (v) => _set(() => _ch = v * 10, keepAnchors: true))),
            ]),
          Text('Dessin : ${(_b.width / 100).toStringAsFixed(1)} × ${(_b.height / 100).toStringAsFixed(1)} cm',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
      luxSection(
        'Coupe',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Recouvrement entre morceaux', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(children: [
            for (final v in [0.0, 2.0, 2.5, 3.0, 5.0])
              luxChip(v == 0 ? 'Aucun' : '${v.toString().replaceAll('.0', '')} mm', _overlap == v,
                  () => _set(() => _overlap = v, keepAnchors: true)),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _marks,
            activeThumbColor: AppColors.gold,
            title: const Text('Croix de repérage aux bouts de chaque ligne'),
            onChanged: (v) => _set(() => _marks = v, keepAnchors: true),
          ),
        ]),
      ),
      luxSection(
        'Cadre de chaque morceau (point droit 5,8 mm, cousu en premier)',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _frame,
            activeThumbColor: AppColors.gold,
            title: const Text('Cadre autour de chaque morceau'),
            onChanged: (v) => _set(() => _frame = v, keepAnchors: true),
          ),
          Wrap(children: [
            for (final v in [3.0, 5.0, 8.0, 10.0])
              luxChip('${v.toInt()} mm', _margin == v, () => _set(() => _margin = v, keepAnchors: true)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            AnchorGrid(value: _anchor, onChanged: (a) => _set(() => _anchor = a)),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Départ de tous les morceaux : ${_anchor.label}.\n'
                  'Chaque morceau peut avoir le sien (bouton sur sa carte).',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
          ]),
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

  Widget _summary() {
    final r = _res;
    if (r == null) return const SizedBox(height: 8);
    if (r.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(r.error!, style: const TextStyle(color: AppColors.danger)),
      );
    }
    final n = r.pieces.length;
    final bad = r.pieces.where((p) => !_fits(p)).length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n == 1 ? '1 morceau' : '$n morceaux',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.goldLight)),
        Text(
          bad == 0
              ? '✓ Tous les morceaux tiennent dans le cadre ${(_hw / 10).toStringAsFixed(0)} × ${(_hh / 10).toStringAsFixed(0)} cm'
              : '$bad morceau(x) trop grand(s) (en rouge) : tracez une ligne dedans.',
          style: TextStyle(color: bad == 0 ? AppColors.success : AppColors.danger, fontSize: 13),
        ),
        if (_lines.isEmpty)
          const Text('Tracez une ligne au doigt ou à la souris, d\'un bord à l\'autre du dessin.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ]),
    );
  }

  List<Widget> _pieceList() {
    final r = _res;
    if (r == null) return const [];
    final n = r.pieces.length;
    return [
      for (var i = 0; i < n; i++)
        PieceCard(
          piece: r.pieces[i],
          geo: _geoCache.putIfAbsent(r.pieces[i], () => PatternGeometry.from(r.pieces[i].pattern)),
          fileName: pieceFileName(widget.pattern.name, r.pieces[i].index, n),
          anchor: _pieceAnchors[r.pieces[i].index] ?? _anchor,
          hoopWmm: _hw,
          hoopHmm: _hh,
          tint: _fits(r.pieces[i]) ? _zoneColors[i % _zoneColors.length] : AppColors.danger,
          selected: _sel == r.pieces[i].index,
          onTap: () => setState(() => _sel = r.pieces[i].index),
          onAnchor: () async {
            final idx = r.pieces[i].index;
            final a = await pickAnchor(context, 'Départ du morceau $idx', _pieceAnchors[idx] ?? _anchor);
            if (a != null) _set(() => _pieceAnchors[idx] = a, keepAnchors: true);
          },
        ),
      if (n > 0)
        GoldButton(
          label: n == 1 ? 'Exporter le fichier DST' : 'Exporter les $n fichiers DST',
          icon: Icons.download,
          busy: _busy,
          onPressed: _exportAll,
        ),
      const SizedBox(height: 24),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final work = Column(children: [
      _toolbar(),
      const SizedBox(height: 8),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned.fill(child: _rulers(_workspace())),
            if (_busy)
              const Positioned(
                right: 10,
                top: 34,
                child: SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold)),
              ),
          ]),
        ),
      ),
    ]);
    return Scaffold(
      appBar: AppBar(title: const Text('Découpe')),
      body: SafeArea(
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: Padding(padding: const EdgeInsets.all(12), child: work)),
                SizedBox(
                  width: 430,
                  child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [_summary(), _controls(), ..._pieceList()]),
                ),
              ])
            : Column(children: [
                Expanded(flex: 58, child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 4), child: work)),
                Expanded(
                  flex: 42,
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      children: [_summary(), ..._pieceList(), _controls()]),
                ),
              ]),
      ),
    );
  }
}

/// Zones colorées, lignes tracées, trait en cours, cadre de la machine
/// autour du morceau choisi (même cadrage que PatternPainter).
class _CutOverlay extends CustomPainter {
  final Bounds b;
  final CutResult? res;
  final ui.Image? zones;
  final List<List<(double, double)>> lines;
  final List<(double, double)>? drawing;
  final PrepPiece? selected;
  final double hoopW, hoopH;
  final TransformationController zoom;

  _CutOverlay({
    required this.b,
    required this.res,
    required this.zones,
    required this.lines,
    required this.drawing,
    required this.selected,
    required this.hoopW,
    required this.hoopH,
    required this.zoom,
  }) : super(repaint: zoom);

  @override
  void paint(Canvas canvas, Size s) {
    final w = math.max(b.width, 10).toDouble(), h = math.max(b.height, 10).toDouble();
    final k = math.min(s.width / w, s.height / h) * 0.86;
    final z = zoom.value.getMaxScaleOnAxis();
    canvas.save();
    canvas.translate(s.width / 2, s.height / 2);
    canvas.scale(k);
    canvas.translate(-(b.minX + b.width / 2), -(b.minY + b.height / 2));
    final px = 1 / (k * z); // un pixel écran en unités du dessin

    final r = res;
    if (zones != null && r != null) {
      canvas.drawImageRect(
        zones!,
        Rect.fromLTWH(0, 0, r.gw.toDouble(), r.gh.toDouble()),
        Rect.fromLTWH(r.gx0.toDouble(), r.gy0.toDouble(), r.gw * r.res.toDouble(), r.gh * r.res.toDouble()),
        Paint()..filterQuality = FilterQuality.none,
      );
    }

    // Cadre de la machine centré sur le morceau choisi.
    final sp = selected;
    if (sp != null) {
      final wb = sp.window;
      final c = Offset((wb.minX + wb.maxX) / 2, (wb.minY + wb.maxY) / 2);
      canvas.drawRect(
        Rect.fromCenter(center: c, width: hoopW, height: hoopH),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * px
          ..color = AppColors.goldLight,
      );
    }

    void path(List<(double, double)> pts, Color col, double width) {
      if (pts.length < 2) return;
      final p = Path()..moveTo(pts.first.$1, pts.first.$2);
      for (final q in pts.skip(1)) {
        p.lineTo(q.$1, q.$2);
      }
      canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (width + 2.5) * px
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..color = Colors.black54);
      canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width * px
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..color = col);
    }

    for (final l in lines) {
      path(l, AppColors.danger, 2.5);
    }
    if (drawing != null) path(drawing!, AppColors.goldLight, 2.5);

    // Numéros des morceaux.
    if (r != null) {
      for (var i = 0; i < r.pieces.length; i++) {
        final wb = r.pieces[i].window;
        final c = Offset((wb.minX + wb.maxX) / 2, (wb.minY + wb.maxY) / 2);
        final rad = 13 * px;
        canvas.drawCircle(c, rad, Paint()..color = AppColors.gold);
        final tp = TextPainter(
          text: TextSpan(
              text: '${r.pieces[i].index}',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14 * px)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CutOverlay o) => true;
}

/// Règle graduée en cm (zéro au bord du dessin), suit le zoom et le déplacement.
class _Ruler extends CustomPainter {
  final bool horizontal;
  final Bounds b;
  final Size view;
  final TransformationController tc;
  _Ruler({required this.horizontal, required this.b, required this.view, required this.tc})
      : super(repaint: tc);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = AppColors.surface2);
    final w = math.max(b.width, 10).toDouble(), h = math.max(b.height, 10).toDouble();
    final k = math.min(view.width / w, view.height / h) * 0.86;
    final m = tc.value;
    final z = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    // Position écran d'une coordonnée du dessin (unités 0,1 mm).
    double scr(double u) => horizontal
        ? t.x + z * (view.width / 2 + (u - (b.minX + b.width / 2)) * k)
        : t.y + z * (view.height / 2 + (u - (b.minY + b.height / 2)) * k);
    final origin = horizontal ? b.minX.toDouble() : b.minY.toDouble();
    final pxPerMm = z * k * 10;
    var step = 1.0; // mm
    for (final c in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]) {
      step = c;
      if (c * pxPerMm >= 6) break;
    }
    final label = step <= 2 ? 10.0 : (step <= 10 ? 50.0 : 100.0);
    final len = horizontal ? s.width : s.height;
    final first = ((-(scr(origin)) / pxPerMm) / step).floor() * step;
    final tick = Paint()
      ..color = AppColors.muted
      ..strokeWidth = 1;
    final across = horizontal ? s.height : s.width;
    for (var mm = first; ; mm += step) {
      final p = scr(origin + mm * 10);
      if (p > len) break;
      if (p < 0) continue;
      final major = (mm / label).round() * label == mm;
      final mid = !major && (mm / (label / 2)).round() * (label / 2) == mm;
      final l = major ? across * 0.62 : (mid ? across * 0.4 : across * 0.22);
      if (horizontal) {
        canvas.drawLine(Offset(p, across), Offset(p, across - l), tick);
      } else {
        canvas.drawLine(Offset(across, p), Offset(across - l, p), tick);
      }
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
              text: (mm / 10).toStringAsFixed(0),
              style: TextStyle(
                  color: mm == 0 ? AppColors.gold : AppColors.text, fontSize: 9, fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
        )..layout();
        if (horizontal) {
          tp.paint(canvas, Offset(p + 2, 1));
        } else {
          canvas.save();
          canvas.translate(1, p - 2);
          canvas.rotate(-math.pi / 2);
          tp.paint(canvas, Offset.zero);
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Ruler o) => o.view != view || o.b != b;
}
