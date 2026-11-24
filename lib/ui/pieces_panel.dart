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

/// Carte d'un morceau : aperçu, taille, cadre, état ; un appui l'ouvre.
class PieceCard extends StatelessWidget {
  final PrepPiece piece;
  final PatternGeometry geo;
  final double hoopWmm, hoopHmm;
  final Color tint;
  final bool saved;
  final VoidCallback onTap;

  const PieceCard({
    super.key,
    required this.piece,
    required this.geo,
    required this.hoopWmm,
    required this.hoopHmm,
    required this.tint,
    required this.saved,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = piece.pattern;
    final b = p.bounds;
    final w = b.width / 100, h = b.height / 100;
    final fits = fitsHoop(p, hoopWmm, hoopHmm);
    final fitsRot = !fits && fitsHoop(rotate90(p), hoopWmm, hoopHmm);
    final dur = p.estimate(800);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LuxCard(
        onTap: onTap,
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Stack(children: [
            SizedBox(
              width: 84,
              height: 84,
              child: RepaintBoundary(child: CustomPaint(painter: PatternPainter(geo, realistic: false))),
            ),
            Positioned(
              left: 2,
              top: 2,
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
              Row(children: [
                Text('Morceau ${piece.index}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(width: 8),
                if (saved)
                  const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                if (saved)
                  const Text(' Enregistré', style: TextStyle(color: AppColors.success, fontSize: 12)),
              ]),
              Text('${w.toStringAsFixed(1)} × ${h.toStringAsFixed(1)} cm · ${p.stitchCount} points',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              Text('${p.colorBlockCount} couleur(s) · ≈ ${dur.inMinutes} min',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              Text(
                fits
                    ? '✓ Tient dans le cadre'
                    : (fitsRot ? '↻ Tient en le tournant de 90°' : '✗ Trop grand pour le cadre'),
                style: TextStyle(
                    color: fits ? AppColors.success : (fitsRot ? AppColors.goldLight : AppColors.danger),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AppColors.gold),
        ]),
      ),
    );
  }
}

/// Enregistre des octets dans un dossier choisi (extension garantie) ; message de résultat.
Future<String?> saveBytesToFolder(String fileName, Uint8List bytes, String ext) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Enregistrer $fileName',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: [ext],
    bytes: bytes,
  );
  if (path == null) return null;
  final mobile = Platform.isAndroid || Platform.isIOS;
  final hasExt = path.toLowerCase().endsWith('.$ext');
  if (!mobile) {
    final target = hasExt ? path : '$path.${ext.toUpperCase()}';
    await File(target).writeAsBytes(bytes, flush: true);
    return 'Enregistré ✓ $target';
  }
  if (!hasExt && !path.startsWith('content://')) {
    return 'Attention : enregistré sans « .${ext.toUpperCase()} » — renommez le fichier.';
  }
  return 'Enregistré ✓';
}

/// Envoie un fichier (WhatsApp, Fichiers, USB…) en gardant son nom exact.
Future<void> shareBytes(String fileName, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$fileName');
  await f.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(f.path, mimeType: 'application/octet-stream', name: fileName)],
      subject: fileName);
}
