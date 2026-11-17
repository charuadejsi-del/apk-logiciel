import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Normalisation arabe pour la recherche : supprime diacritiques, tatweel,
/// toutes les formes d'alif et la hamza, unifie ي/ى et ه/ة.
final RegExp _marks = RegExp(r'[ؐ-ًؚ-ٰٟۖ-ۭـ]');
final RegExp _alefs = RegExp(r'[اأإآٱء]');
final RegExp _spaces = RegExp(r'\s+');

String norm(String s) => s
    .replaceAll(_marks, '')
    .replaceAll(_alefs, '')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll(_spaces, ' ')
    .trim();

class Surah {
  final int n;
  final String name;
  final bool meccan;
  final List<String> ayat;
  final List<String> search;
  Surah(this.n, this.name, this.meccan, this.ayat, this.search);
}

class VerseRef {
  final int surah;
  final int ayah;
  const VerseRef(this.surah, this.ayah);
  static VerseRef parse(String s) {
    final p = s.split(':');
    return VerseRef(int.parse(p[0]), int.parse(p[1]));
  }
}

class Topic {
  final String id, title;
  Topic(this.id, this.title);
}

class Objection {
  final String id, topic, objection, answer;
  final List<VerseRef> refs;
  final String key;
  Objection(this.id, this.topic, this.objection, this.answer, this.refs)
      : key = norm('$objection $answer');
}

class Argument {
  final String id, title, text;
  final List<VerseRef> refs;
  final String key;
  Argument(this.id, this.title, this.text, this.refs) : key = norm('$title $text');
}

class HCategory {
  final String id, title;
  HCategory(this.id, this.title);
}

class Hadith {
  final String id, cat, title, book, number, chapter, text, comment, url;
  final List<VerseRef> refs;
  final String key;
  Hadith(this.id, this.cat, this.title, this.book, this.number, this.chapter,
      this.text, this.comment, this.url, this.refs)
      : key = norm('$title $text $comment $book');
  String get reference => '$book — رقم $number';
}

class AppData {
  static late AppData I;

  final List<Surah> surahs;
  final List<Topic> topics;
  final List<Objection> objections;
  final List<Argument> arguments;
  final List<HCategory> hcats;
  final List<Hadith> hadiths;

  AppData(this.surahs, this.topics, this.objections, this.arguments, this.hcats,
      this.hadiths);

  static Future<void> load() async {
    final q = jsonDecode(await rootBundle.loadString('assets/data/quran.json')) as List;
    final c = jsonDecode(await rootBundle.loadString('assets/data/content.json'))
        as Map<String, dynamic>;
    List<VerseRef> refs(dynamic l) =>
        (l as List).map((e) => VerseRef.parse(e as String)).toList();
    I = AppData(
      q
          .map((s) => Surah(
                s['n'] as int,
                s['name'] as String,
                s['type'] == 'meccan',
                List<String>.from(s['ayat'] as List),
                (s['clean'] as List).map((e) => norm(e as String)).toList(),
              ))
          .toList(),
      (c['topics'] as List).map((t) => Topic(t['id'], t['title'])).toList(),
      (c['objections'] as List)
          .map((o) => Objection(o['id'], o['topic'], o['objection'], o['answer'], refs(o['refs'])))
          .toList(),
      (c['arguments'] as List)
          .map((a) => Argument(a['id'], a['title'], a['text'], refs(a['refs'])))
          .toList(),
      (c['hadithCategories'] as List).map((h) => HCategory(h['id'], h['title'])).toList(),
      (c['hadiths'] as List)
          .map((h) => Hadith(h['id'], h['cat'], h['title'], h['book'], h['number'],
              h['chapter'] ?? '', h['text'], h['comment'], h['url'], refs(h['refs'])))
          .toList(),
    );
  }

  Surah surah(int n) => surahs[n - 1];

  String verseText(VerseRef r) => surahs[r.surah - 1].ayat[r.ayah - 1];

  String refLabel(VerseRef r) => '${surahs[r.surah - 1].name}: ${r.ayah}';

  bool validRef(VerseRef r) =>
      r.surah >= 1 && r.surah <= 114 && r.ayah >= 1 && r.ayah <= surahs[r.surah - 1].ayat.length;

  String topicTitle(String id) =>
      topics.firstWhere((t) => t.id == id, orElse: () => Topic(id, id)).title;

  String catTitle(String id) =>
      hcats.firstWhere((t) => t.id == id, orElse: () => HCategory(id, id)).title;

  /// Recherche par mots : tous les mots de la requête doivent être présents.
  static bool matches(String key, List<String> words) => words.every(key.contains);

  static List<String> words(String q) =>
      norm(q).split(' ').where((w) => w.isNotEmpty).toList();

  /// Résultats coraniques (limités).
  List<VerseRef> searchQuran(String q, {int limit = 200}) {
    final w = words(q);
    if (w.isEmpty) return [];
    final out = <VerseRef>[];
    for (final s in surahs) {
      for (var i = 0; i < s.search.length; i++) {
        if (matches(s.search[i], w)) {
          out.add(VerseRef(s.n, i + 1));
          if (out.length >= limit) return out;
        }
      }
    }
    return out;
  }

  /// Reconnaît « 2:255 », « 2 255 » ou « البقرة 255 ».
  VerseRef? parseRefQuery(String q) {
    final ascii = q.replaceAllMapped(RegExp(r'[٠-٩]'),
        (m) => (m.group(0)!.codeUnitAt(0) - 0x0660).toString());
    final m = RegExp(r'^\s*(\d{1,3})\s*[:\s/.-]\s*(\d{1,3})\s*$').firstMatch(ascii);
    if (m != null) {
      final r = VerseRef(int.parse(m.group(1)!), int.parse(m.group(2)!));
      return validRef(r) ? r : null;
    }
    final m2 = RegExp(r'^\s*(.+?)\s+(\d{1,3})\s*$').firstMatch(ascii);
    if (m2 != null) {
      final name = norm(m2.group(1)!);
      for (final s in surahs) {
        if (norm(s.name) == name) {
          final r = VerseRef(s.n, int.parse(m2.group(2)!));
          return validRef(r) ? r : null;
        }
      }
    }
    return null;
  }

  String objectionToText(Objection o) {
    final b = StringBuffer()
      ..writeln('❖ يقولون: ${o.objection}')
      ..writeln()
      ..writeln('✔ الرد: ${o.answer}')
      ..writeln();
    for (final r in o.refs) {
      b.writeln('﴿${verseText(r)}﴾ [${refLabel(r)}]');
    }
    return b.toString().trim();
  }

  String argumentToText(Argument a) {
    final b = StringBuffer()..writeln('◆ ${a.title}')..writeln(a.text)..writeln();
    for (final r in a.refs) {
      b.writeln('﴿${verseText(r)}﴾ [${refLabel(r)}]');
    }
    return b.toString().trim();
  }

  String hadithToText(Hadith h) {
    final b = StringBuffer()
      ..writeln('● ${h.title}')
      ..writeln('${h.reference}${h.chapter.isNotEmpty ? ' (${h.chapter})' : ''}')
      ..writeln()
      ..writeln(h.text)
      ..writeln()
      ..writeln('وجه الاعتراض: ${h.comment}')
      ..writeln();
    for (final r in h.refs) {
      b.writeln('﴿${verseText(r)}﴾ [${refLabel(r)}]');
    }
    b
      ..writeln()
      ..writeln('للتحقق: ${h.url}');
    return b.toString().trim();
  }
}
