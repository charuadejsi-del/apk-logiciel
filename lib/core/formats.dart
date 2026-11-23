import 'dart:typed_data';

import 'dst.dart';
import 'pattern.dart';
import 'pes.dart';

/// Extensions lisibles par l'application.
const supportedExtensions = ['dst', 'pes', 'pec'];

/// Charge un motif en reconnaissant le format par son contenu puis par l'extension.
EmbPattern loadPattern(Uint8List bytes, String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot >= 0 ? fileName.substring(dot + 1).toLowerCase() : '';
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  final magic = bytes.length >= 8 ? String.fromCharCodes(bytes.sublist(0, 8)) : '';

  if (magic.startsWith('#PES')) return readPes(bytes, name: base);
  if (magic == '#PEC0001') return readPec(bytes, name: base);
  if (ext == 'dst' || magic.startsWith('LA:')) return readDst(bytes, name: base);
  throw FormatException(
      'Format « $ext » non pris en charge pour le moment (DST, PES, PEC).');
}
