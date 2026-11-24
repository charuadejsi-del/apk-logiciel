import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
  _Tool _tool = _Tool.line;
  // Trait en cours (aperçu) : seul le calque des lignes est redessiné.
  final ValueNotifier<List<(double, double)>?> _preview = ValueNotifier(null);
  final ValueNotifier<int?> _selLine = ValueNotifier(null);
  List<(double, double)>? _poly; // ligne brisée en cours
  (int, int)? _dragEnd; // (ligne, extrémité) déplacée
  Offset? _downAt;
  DateTime _lastDown = DateTime(0);
  bool _split = true; // vue des morceaux séparés

  CutResult? _res;
  ui.Image? _zones;
  ui.Image? _pieces; // morceaux séparés, déjà dessinés
  Size _canvasSize = Size.zero;
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
    _preview.dispose();
    _selLine.dispose();
    _pieces?.dispose();
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
    _rebuildPieces();
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

  // ───────────── Tracé : lignes droites (glisser) ou brisées (clics) ─────────────

  double _px() {
    final (k, _, _) = _base(_canvasSize);
    return 1 / (k * _tc.value.getMaxScaleOnAxis()); // 1 pixel écran en 0,1 mm
  }

  /// Aimant horizontal / vertical (à moins de 6°).
  (double, double) _snap((double, double) from, (double, double) to) {
    final dx = to.$1 - from.$1, dy = to.$2 - from.$2;
    final a = math.atan2(dy.abs(), dx.abs()) * 180 / math.pi;
    if (a < 6) return (to.$1, from.$2);
    if (a > 84) return (from.$1, to.$2);
    return to;
  }

  double _dist((double, double) a, (double, double) b) =>
      math.sqrt((a.$1 - b.$1) * (a.$1 - b.$1) + (a.$2 - b.$2) * (a.$2 - b.$2));

  /// Distance d'un point à une ligne brisée.
  double _distToLine((double, double) p, List<(double, double)> l) {
    var best = double.infinity;
    for (var i = 1; i < l.length; i++) {
      final a = l[i - 1], b = l[i];
      final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
      final len2 = dx * dx + dy * dy;
      var t = len2 == 0 ? 0.0 : ((p.$1 - a.$1) * dx + (p.$2 - a.$2) * dy) / len2;
      t = t.clamp(0.0, 1.0);
      best = math.min(best, _dist(p, (a.$1 + dx * t, a.$2 + dy * t)));
    }
    return best;
  }

  void _down(PointerDownEvent e) {
    if (_tool == _Tool.pan) return;
    if (e.buttons == kSecondaryMouseButton) {
      _finishPoly();
      return;
    }
    final p = _toPattern(e.localPosition, _canvasSize);
    final tol = 14 * _px();
    _downAt = e.localPosition;
    if (_tool == _Tool.line) {
      // Extrémité d'une ligne existante : on la déplace.
      for (var i = 0; i < _lines.length; i++) {
        final l = _lines[i];
        if (_dist(p, l.first) < tol) {
          _dragEnd = (i, 0);
          _selLine.value = i;
          return;
        }
        if (_dist(p, l.last) < tol) {
          _dragEnd = (i, l.length - 1);
          _selLine.value = i;
          return;
        }
      }
      _preview.value = [p, p];
      return;
    }
    // Ligne brisée : chaque clic pose un point, double-clic pour finir.
    final now = DateTime.now();
    final dbl = now.difference(_lastDown).inMilliseconds < 350;
    _lastDown = now;
    if (_poly == null) {
      _poly = [p, p];
    } else {
      final fixed = _snap(_poly![_poly!.length - 2], p);
      if (dbl || _dist(fixed, _poly![_poly!.length - 2]) < tol) {
        _finishPoly();
        return;
      }
      _poly![_poly!.length - 1] = fixed;
      _poly!.add(fixed);
    }
    _preview.value = List.of(_poly!);
  }

  void _moveTo(Offset pos) {
    if (_tool == _Tool.pan) return;
    final p = _toPattern(pos, _canvasSize);
    final de = _dragEnd;
    if (de != null) {
      final l = _lines[de.$1];
      final other = de.$2 == 0 ? l[1] : l[l.length - 2];
      l[de.$2] = _snap(other, p);
      _preview.value = null;
      _selLine.value = null;
      _selLine.value = de.$1; // redessine
      return;
    }
    if (_tool == _Tool.line) {
      final pv = _preview.value;
      if (pv == null) return;
      _preview.value = [pv.first, _snap(pv.first, p)];
      return;
    }
    final poly = _poly;
    if (poly == null) return;
    poly[poly.length - 1] = _snap(poly[poly.length - 2], p);
    _preview.value = List.of(poly);
  }

  void _up(PointerUpEvent e) {
    if (_tool == _Tool.pan) return;
    final tap = _downAt != null && (e.localPosition - _downAt!).distance < 6;
    if (_dragEnd != null) {
      _dragEnd = null;
      _changed();
      return;
    }
    if (_tool == _Tool.line) {
      final pv = _preview.value;
      _preview.value = null;
      if (tap || pv == null || _dist(pv.first, pv.last) < 20 * _px()) {
        _tapAt(e.localPosition);
        return;
      }
      _lines.add([pv.first, pv.last]);
      _selLine.value = null;
      _changed();
    }
  }

  void _finishPoly() {
    final poly = _poly;
    _poly = null;
    _preview.value = null;
    if (poly == null) return;
    // Le dernier point suit la souris : on le retire, ainsi que les doublons.
    final pts = <(double, double)>[];
    for (final q in poly.take(poly.length - 1)) {
      if (pts.isEmpty || _dist(pts.last, q) > 1) pts.add(q);
    }
    if (pts.length >= 2) {
      _lines.add(pts);
      _changed();
    } else {
      setState(() {});
    }
  }

  /// Clic simple : choisir une ligne (pour la supprimer) ou un morceau.
  void _tapAt(Offset pos) {
    final p = _toPattern(pos, _canvasSize);
    final tol = 10 * _px();
    for (var i = _lines.length - 1; i >= 0; i--) {
      if (_distToLine(p, _lines[i]) < tol) {
        _selLine.value = i;
        setState(() {});
        return;
      }
    }
    _selLine.value = null;
    _tapPiece(pos, _canvasSize);
  }

  void _deleteSelected() {
    final i = _selLine.value;
    if (i == null || i >= _lines.length) return;
    _lines.removeAt(i);
    _selLine.value = null;
    _changed();
  }

  void _changed() {
    setState(() => _pieceAnchors.clear());
    _schedule();
  }

  void _undo() {
    if (_lines.isEmpty) return;
    _selLine.value = null;
    setState(() {
      _lines.removeLast();
      _pieceAnchors.clear();
    });
    _schedule();
  }

  void _clear() {
    _selLine.value = null;
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
      if (size != _canvasSize) {
        _canvasSize = size;
        if (_res != null) WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildPieces());
      }
      final r = _res;
      final showSplit = _split && _pieces != null && r != null && r.pieces.length > 1;
      final canvas = SizedBox.fromSize(
        size: size,
        child: Stack(children: [
          // Dessin : image déjà calculée (morceaux séparés) ou motif d'origine en cache.
          Positioned.fill(
            child: RepaintBoundary(
              child: showSplit
                  ? CustomPaint(painter: _ImagePainter(_pieces!))
                  : CustomPaint(painter: PatternPainter(_geo, realistic: false)),
            ),
          ),
          if (!showSplit && _zones != null)
            Positioned.fill(
              child: RepaintBoundary(child: CustomPaint(painter: _ZonesPainter(_b, r!, _zones!))),
            ),
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _LinesPainter(
                  b: _b,
                  lines: _lines,
                  preview: _preview,
                  selLine: _selLine,
                  zoom: _tc,
                  res: r,
                  selected: _sel,
                  hoopW: _hw * 10,
                  hoopH: _hh * 10,
                  split: showSplit,
                  offsets: showSplit ? _offsets(r) : const {},
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Listener(
              behavior: _tool == _Tool.pan ? HitTestBehavior.translucent : HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: (e) => _moveTo(e.localPosition),
              onPointerHover: (e) {
                if (_poly != null) _moveTo(e.localPosition);
              },
              onPointerUp: _up,
              child: const SizedBox.expand(),
            ),
          ),
        ]),
      );
      return InteractiveViewer(
        transformationController: _tc,
        minScale: 0.5,
        maxScale: 20,
        panEnabled: _tool == _Tool.pan,
        scaleEnabled: true,
        boundaryMargin: const EdgeInsets.all(400),
        child: canvas,
      );
    });
  }

  /// Écart de chaque morceau dans la vue séparée (unités du dessin).
  Map<int, Offset> _offsets(CutResult r) {
    final cx = (_b.minX + _b.maxX) / 2, cy = (_b.minY + _b.maxY) / 2;
    final gap = math.max(60.0, 0.05 * math.max(_b.width, _b.height));
    return {
      for (final p in r.pieces)
        p.index: () {
          final w = p.window;
          final dx = (w.minX + w.maxX) / 2 - cx, dy = (w.minY + w.maxY) / 2 - cy;
          double sgn(double d, int span) => d.abs() < span * 0.08 ? 0 : d.sign;
          return Offset(sgn(dx, _b.width) * gap, sgn(dy, _b.height) * gap);
        }(),
    };
  }

  /// Dessine une fois les morceaux séparés (fils, cadres, numéros) dans une image.
  Future<void> _rebuildPieces() async {
    final r = _res;
    final size = _canvasSize;
    if (r == null || r.pieces.length < 2 || size.isEmpty) {
      setState(() {
        _pieces?.dispose();
        _pieces = null;
      });
      return;
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final q = math.min(dpr * 2, 3072 / math.max(size.width, size.height));
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(q);
    final (k, cx, cy) = _base(size);
    canvas.translate(cx, cy);
    canvas.scale(k);
    canvas.translate(-(_b.minX + _b.width / 2), -(_b.minY + _b.height / 2));
    final offs = _offsets(r);
    final line = Paint()
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < r.pieces.length; i++) {
      final pc = r.pieces[i];
      final o = offs[pc.index] ?? Offset.zero;
      canvas.save();
      canvas.translate(o.dx + pc.originX, o.dy + pc.originY);
      final g = _geoCache.putIfAbsent(pc, () => PatternGeometry.from(pc.pattern));
      for (var bl = 0; bl < g.points.length; bl++) {
        line.color = g.colors[bl];
        canvas.drawRawPoints(ui.PointMode.lines, g.points[bl], line);
      }
      // Cadre et contour du morceau, à la couleur de sa zone (rouge s'il dépasse).
      final pb = pc.pattern.bounds;
      final zc = _fits(pc) ? _zoneColors[i % _zoneColors.length] : AppColors.danger;
      canvas.drawRect(
        Rect.fromLTRB(pb.minX.toDouble(), pb.minY.toDouble(), pb.maxX.toDouble(), pb.maxY.toDouble()),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (_frame ? 5 : 2.5) / k
          ..color = zc.withValues(alpha: _frame ? 0.9 : 0.5),
      );
      canvas.restore();
    }
    final pic = rec.endRecording();
    final img = await pic.toImage((size.width * q).ceil(), (size.height * q).ceil());
    pic.dispose();
    if (!mounted || r != _res) {
      img.dispose();
      return;
    }
    setState(() {
      _pieces?.dispose();
      _pieces = img;
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
    Widget btn(IconData i, String l, VoidCallback? f, {bool on = false, Color? color}) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: on ? AppColors.gold : (color ?? AppColors.surface2),
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: f,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(i, size: 18, color: on ? Colors.black : (f == null ? AppColors.muted : AppColors.text)),
                  const SizedBox(width: 6),
                  Text(l,
                      style: TextStyle(
                          color: on ? Colors.black : (f == null ? AppColors.muted : AppColors.text),
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        );
    void tool(_Tool t) {
      _finishPoly();
      setState(() => _tool = t);
    }

    final multi = (_res?.pieces.length ?? 0) > 1;
    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        btn(Icons.horizontal_rule, 'Ligne droite', () => tool(_Tool.line), on: _tool == _Tool.line),
        btn(Icons.timeline, 'Ligne brisée', () => tool(_Tool.polyline), on: _tool == _Tool.polyline),
        if (_poly != null) btn(Icons.check, 'Terminer', _finishPoly, color: AppColors.goldDark),
        btn(Icons.pan_tool_alt, 'Déplacer', () => tool(_Tool.pan), on: _tool == _Tool.pan),
        ValueListenableBuilder<int?>(
          valueListenable: _selLine,
          builder: (_, v, __) => v == null
              ? const SizedBox.shrink()
              : btn(Icons.delete_outline, 'Supprimer la ligne', _deleteSelected, color: const Color(0x55F87171)),
        ),
        btn(Icons.undo, 'Annuler', _lines.isEmpty ? null : _undo),
        btn(Icons.delete_sweep, 'Tout effacer', _lines.isEmpty ? null : _clear),
        btn(Icons.auto_fix_high, 'Proposer', _auto),
        if (multi)
          btn(_split ? Icons.grid_view : Icons.view_quilt_outlined, _split ? 'Morceaux séparés' : 'Dessin entier',
              () => setState(() => _split = !_split),
              on: _split),
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

enum _Tool { line, polyline, pan }

/// Image déjà prête (morceaux séparés).
class _ImagePainter extends CustomPainter {
  final ui.Image img;
  _ImagePainter(this.img);
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Offset.zero & s, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(covariant _ImagePainter o) => o.img != img;
}

/// Zones colorées (une couleur par morceau, rouge s'il dépasse le cadre).
class _ZonesPainter extends CustomPainter {
  final Bounds b;
  final CutResult r;
  final ui.Image zones;
  _ZonesPainter(this.b, this.r, this.zones);

  @override
  void paint(Canvas canvas, Size s) {
    final w = math.max(b.width, 10).toDouble(), h = math.max(b.height, 10).toDouble();
    final k = math.min(s.width / w, s.height / h) * 0.86;
    canvas.translate(s.width / 2, s.height / 2);
    canvas.scale(k);
    canvas.translate(-(b.minX + b.width / 2), -(b.minY + b.height / 2));
    canvas.drawImageRect(
      zones,
      Rect.fromLTWH(0, 0, r.gw.toDouble(), r.gh.toDouble()),
      Rect.fromLTWH(r.gx0.toDouble(), r.gy0.toDouble(), r.gw * r.res.toDouble(), r.gh * r.res.toDouble()),
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _ZonesPainter o) => o.zones != zones;
}

/// Calque léger : lignes de coupe, trait en cours, ligne choisie, numéros,
/// cadre de la machine autour du morceau choisi. Seul ce calque suit la souris.
class _LinesPainter extends CustomPainter {
  final Bounds b;
  final List<List<(double, double)>> lines;
  final ValueNotifier<List<(double, double)>?> preview;
  final ValueNotifier<int?> selLine;
  final TransformationController zoom;
  final CutResult? res;
  final int? selected;
  final double hoopW, hoopH;
  final bool split;
  final Map<int, Offset> offsets;

  _LinesPainter({
    required this.b,
    required this.lines,
    required this.preview,
    required this.selLine,
    required this.zoom,
    required this.res,
    required this.selected,
    required this.hoopW,
    required this.hoopH,
    required this.split,
    required this.offsets,
  }) : super(repaint: Listenable.merge([preview, selLine, zoom]));

  @override
  void paint(Canvas canvas, Size s) {
    final w = math.max(b.width, 10).toDouble(), h = math.max(b.height, 10).toDouble();
    final k = math.min(s.width / w, s.height / h) * 0.86;
    final z = zoom.value.getMaxScaleOnAxis();
    canvas.save();
    canvas.translate(s.width / 2, s.height / 2);
    canvas.scale(k);
    canvas.translate(-(b.minX + b.width / 2), -(b.minY + b.height / 2));
    final px = 1 / (k * z);

    void path(List<(double, double)> pts, Color col, double width) {
      if (pts.length < 2) return;
      final p = Path()..moveTo(pts.first.$1, pts.first.$2);
      for (final q in pts.skip(1)) {
        p.lineTo(q.$1, q.$2);
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(p, paint..strokeWidth = (width + 3) * px..color = Colors.black54);
      canvas.drawPath(p, paint..strokeWidth = width * px..color = col);
      // Poignées aux extrémités.
      final dot = Paint()..color = col;
      canvas.drawCircle(Offset(pts.first.$1, pts.first.$2), 4.5 * px, dot);
      canvas.drawCircle(Offset(pts.last.$1, pts.last.$2), 4.5 * px, dot);
    }

    final sl = selLine.value;
    for (var i = 0; i < lines.length; i++) {
      path(lines[i], i == sl ? AppColors.goldLight : AppColors.danger.withValues(alpha: split ? 0.55 : 1),
          i == sl ? 3.5 : 2.5);
    }
    final pv = preview.value;
    if (pv != null) path(pv, AppColors.goldLight, 2.5);

    final r = res;
    if (r != null && r.pieces.length > 1) {
      for (final pc in r.pieces) {
        final wb = pc.window;
        final c = Offset((wb.minX + wb.maxX) / 2, (wb.minY + wb.maxY) / 2) + (offsets[pc.index] ?? Offset.zero);
        if (pc.index == selected) {
          // Cadre de la machine centré sur le morceau choisi.
          final pb = pc.pattern.bounds;
          final o = (offsets[pc.index] ?? Offset.zero) + Offset(pc.originX.toDouble(), pc.originY.toDouble());
          final pc0 = Offset((pb.minX + pb.maxX) / 2, (pb.minY + pb.maxY) / 2) + o;
          canvas.drawRect(
            Rect.fromCenter(center: pc0, width: hoopW, height: hoopH),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 * px
              ..color = AppColors.goldLight,
          );
        }
        canvas.drawCircle(c, 13 * px, Paint()..color = AppColors.gold);
        final tp = TextPainter(
          text: TextSpan(
              text: '${pc.index}',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14 * px)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LinesPainter o) => true;
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
