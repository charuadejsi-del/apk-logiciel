import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/dst.dart';
import '../core/hoop.dart';
import '../core/transform.dart';
import 'export_sheet.dart';
import 'pattern_painter.dart';
import 'theme.dart';

/// Nom machine d'un morceau : 6 caractères + numéro sur 2 chiffres.
String pieceFileName(String name, int i, int n) {
  var base = name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (base.isEmpty) base = 'DESIGN';
  if (n == 1) return machineFileName(base, 'dst');
  if (base.length > 6) base = base.substring(0, 6);
  return '$base${i.toString().padLeft(2, '0')}.DST';
}

/// Écrit, contrôle (relecture) puis envoie ou enregistre tous les morceaux.
Future<String?> exportPieces(String name, List<PrepPiece> pieces) async {
  final n = pieces.length;
  final files = <(String, Uint8List)>[
    for (final p in pieces) (pieceFileName(name, p.index, n), writeDst(p.pattern)),
  ];
  for (var i = 0; i < n; i++) {
    if (readDst(files[i].$2).stitchCount != pieces[i].pattern.stitchCount) {
      return 'Contrôle échoué sur ${files[i].$1}';
    }
  }
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final xf = <XFile>[];
    for (final (fn, bytes) in files) {
      final f = File('${dir.path}/$fn');
      await f.writeAsBytes(bytes, flush: true);
      xf.add(XFile(f.path, mimeType: 'application/octet-stream', name: fn));
    }
    await Share.shareXFiles(xf, subject: n == 1 ? files.first.$1 : '$name · $n morceaux');
    return null;
  }
  final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Dossier pour les fichiers DST');
  if (dir == null) return null;
  for (final (fn, bytes) in files) {
    await File('$dir${Platform.pathSeparator}$fn').writeAsBytes(bytes, flush: true);
  }
  return '$n fichier(s) enregistré(s) ✓ $dir';
}

/// Grille 3 × 3 de choix du point de départ.
class AnchorGrid extends StatelessWidget {
  final StartAnchor value;
  final ValueChanged<StartAnchor> onChanged;
  const AnchorGrid({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: [
          for (final a in StartAnchor.values.skip(1))
            InkWell(
              onTap: () => onChanged(a),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  color: a == value ? AppColors.gold : AppColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(Icons.circle, size: 9, color: a == value ? Colors.black : AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

Widget luxChip(String l, bool on, VoidCallback f) => Padding(
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

Widget luxSection(String t, Widget c) => Padding(
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

/// Carte d'un morceau : aperçu, taille (et si elle tient dans le cadre), départ, export.
class PieceCard extends StatelessWidget {
  final PrepPiece piece;
  final PatternGeometry geo;
  final String fileName;
  final StartAnchor anchor;
  final double? hoopWmm, hoopHmm;
  final Color? tint;
  final bool selected;
  final VoidCallback onTap, onAnchor;

  const PieceCard({
    super.key,
    required this.piece,
    required this.geo,
    required this.fileName,
    required this.anchor,
    this.hoopWmm,
    this.hoopHmm,
    this.tint,
    this.selected = false,
    required this.onTap,
    required this.onAnchor,
  });

  @override
  Widget build(BuildContext context) {
    final b = piece.pattern.bounds;
    final w = b.width / 100, h = b.height / 100;
    String? over;
    if (hoopWmm != null && hoopHmm != null) {
      final dw = w - hoopWmm! / 10, dh = h - hoopHmm! / 10;
      if (dw > 0 || dh > 0) {
        over = 'Trop grand de ${[if (dw > 0) '${dw.toStringAsFixed(1)} cm en largeur', if (dh > 0) '${dh.toStringAsFixed(1)} cm en hauteur'].join(' et ')}';
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LuxCard(
        highlighted: selected,
        onTap: onTap,
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Stack(children: [
            SizedBox(
              width: 92,
              height: 92,
              child: RepaintBoundary(child: CustomPaint(painter: PatternPainter(geo, showStartEnd: true))),
            ),
            if (tint != null)
              Positioned(
                left: 4,
                top: 4,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: tint,
                  child: Text('${piece.index}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black)),
                ),
              ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Morceau ${piece.index} · $fileName', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${w.toStringAsFixed(1)} × ${h.toStringAsFixed(1)} cm · ${piece.pattern.stitchCount} points',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              if (hoopWmm != null)
                Text(over ?? '✓ Tient dans le cadre',
                    style: TextStyle(
                        color: over == null ? AppColors.success : AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              if (piece.cutObjects > 0)
                Text('${piece.cutObjects} élément(s) coupé(s) sur la ligne (recouvrement + points d\'arrêt)',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              Row(children: [
                TextButton.icon(
                  onPressed: onAnchor,
                  icon: const Icon(Icons.my_location, size: 16),
                  label: Text(anchor.label, overflow: TextOverflow.ellipsis),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Exporter ce morceau',
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ExportSheet(
                        pattern: piece.pattern.copyWith(name: fileName.replaceAll('.DST', ''))),
                  ),
                  icon: const Icon(Icons.download, color: AppColors.gold),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

Future<StartAnchor?> pickAnchor(BuildContext context, String title, StartAnchor cur) =>
    showModalBottomSheet<StartAnchor>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 14),
          AnchorGrid(value: cur, onChanged: (a) => Navigator.pop(ctx, a)),
        ]),
      ),
    );
