import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/dst.dart';
import '../core/pattern.dart';
import 'theme.dart';

/// Nom compatible avec les machines (8 caractères maximum, extension en majuscules).
String machineFileName(String name, String ext) {
  var base = name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (base.isEmpty) base = 'DESIGN';
  if (base.length > 8) base = base.substring(0, 8);
  return '$base.${ext.toUpperCase()}';
}

/// Feuille d'export : choix du format, contrôle du fichier, envoi ou enregistrement.
class ExportSheet extends StatefulWidget {
  final EmbPattern pattern;

  /// Octets du fichier DST d'origine, si le motif n'a pas été modifié :
  /// on les renvoie tels quels (aucune perte possible).
  final Uint8List? originalDst;

  const ExportSheet({super.key, required this.pattern, this.originalDst});

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  late final Uint8List _bytes;
  late final String _fileName;
  String? _error;
  int _checked = 0;
  bool _busy = false;

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _fileName = machineFileName(widget.pattern.name, 'dst');
    _bytes = widget.originalDst ?? writeDst(widget.pattern);
    try {
      // Contrôle : on relit le fichier produit et on compare le nombre de points.
      final back = readDst(_bytes);
      _checked = back.stitchCount;
      if (_checked != widget.pattern.stitchCount) {
        _error = 'Contrôle échoué : ${widget.pattern.stitchCount} points attendus, '
            '$_checked relus.';
      }
    } catch (e) {
      _error = 'Contrôle échoué : $e';
    }
  }

  Future<File> _tempFile() async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$_fileName');
    await f.writeAsBytes(_bytes, flush: true);
    return f;
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final f = await _tempFile();
      await Share.shareXFiles(
        [XFile(f.path, mimeType: 'application/octet-stream', name: _fileName)],
        subject: _fileName,
      );
    } catch (e) {
      _done('Échec de l\'envoi : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer le fichier DST',
        fileName: _fileName,
        type: FileType.custom,
        allowedExtensions: const ['dst'],
        bytes: _bytes,
      );
      if (path == null) return;
      final hasExt = path.toLowerCase().endsWith('.dst');
      if (!_mobile) {
        // Sur ordinateur, on écrit nous-mêmes : on force l'extension .DST.
        final target = hasExt ? path : '$path.DST';
        await File(target).writeAsBytes(_bytes, flush: true);
        final size = await File(target).length();
        _done(size == _bytes.length
            ? 'Enregistré ✓ $target'
            : 'Attention : fichier écrit incomplet ($size / ${_bytes.length} octets).');
      } else if (!hasExt && !path.startsWith('content://')) {
        _warnNoExtension(path);
      } else {
        _done('Enregistré ✓');
      }
    } catch (e) {
      _done('Échec de l\'enregistrement : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _warnNoExtension(String path) {
    if (!mounted) return;
    final name = path.split('/').last;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 36),
        title: const Text('Extension .DST manquante'),
        content: Text(
          'Le fichier a été enregistré sous le nom « $name », sans « .DST » à la fin.\n\n'
          'La machine et Wilcom ne le reconnaîtront pas. Renommez-le en « $name.DST », '
          'ou utilisez le bouton « Envoyer », qui garde toujours le bon nom.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Compris')),
        ],
      ),
    );
  }

  void _done(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _formatTile(String code, String brand, {bool active = false}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: active ? goldGradient : null,
          color: active ? null : AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? AppColors.gold : AppColors.border),
        ),
        child: Column(
          children: [
            Text(code,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: active ? Colors.black : AppColors.muted,
                )),
            const SizedBox(height: 2),
            Text(active ? brand : 'Bientôt',
                style: TextStyle(
                  fontSize: 11,
                  color: active ? Colors.black87 : AppColors.muted,
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ok = _error == null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Exporter',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Choisissez le format de votre machine',
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            Row(children: [
              _formatTile('DST', 'Tajima', active: true),
              _formatTile('PES', 'Brother'),
              _formatTile('JEF', 'Janome'),
            ]),
            const SizedBox(height: 16),
            LuxCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(ok ? Icons.verified : Icons.error_outline,
                      color: ok ? AppColors.success : AppColors.danger),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_fileName,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          ok
                              ? 'Vérifié : relu sans erreur · $_checked points · '
                                  '${(_bytes.length / 1024).toStringAsFixed(1)} Ko'
                                  '${widget.originalDst != null ? ' · fichier d\'origine intact' : ''}'
                              : _error!,
                          style: TextStyle(
                              color: ok ? AppColors.muted : AppColors.danger,
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_mobile) ...[
              GoldButton(
                label: 'Envoyer (WhatsApp, Fichiers, USB…)',
                icon: Icons.ios_share,
                busy: _busy,
                onPressed: ok ? _share : null,
              ),
              const SizedBox(height: 6),
              const Text(
                'Recommandé : garde toujours le nom avec « .DST ».',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: ok && !_busy ? _save : null,
                icon: const Icon(Icons.folder_outlined),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Enregistrer dans un dossier'),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.goldLight,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Si vous changez le nom, gardez « .DST » à la fin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ] else
              GoldButton(
                label: 'Enregistrer sous…',
                icon: Icons.save_alt,
                busy: _busy,
                onPressed: ok ? _save : null,
              ),
          ],
        ),
      ),
    );
  }
}
