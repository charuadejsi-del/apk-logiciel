import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

// ───────────────────────── Normalisation arabe ─────────────────────────

final RegExp _marks = RegExp(r'[ؐ-ًؚ-ٰٟۖ-ۭـ‎‏]');
final RegExp _alefs = RegExp(r'[اأإآٱء]');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _verseRe = RegExp(r'^\d{1,3}:\d{1,3}$');

String norm(String s) => s
    .replaceAll(_marks, '')
    .replaceAll(_alefs, '')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll(_spaces, ' ')
    .trim();

bool isVerseRef(String s) => _verseRe.hasMatch(s);

List<String> queryWords(String q) => norm(q).split(' ').where((w) => w.isNotEmpty).toList();

/// Score : nombre de mots trouvés (titre compte double). 0 si un mot manque.
int scoreOf(String title, String body, List<String> words) {
  if (words.isEmpty) return 0;
  var s = 0;
  for (final w in words) {
    final inT = title.contains(w);
    final inB = body.contains(w);
    if (!inT && !inB) return 0;
    s += inT ? 3 : 1;
  }
  return s;
}

// ───────────────────────── Modèles ─────────────────────────

class VerseRef {
  final int surah, ayah;
  const VerseRef(this.surah, this.ayah);
  static VerseRef parse(String s) {
    final p = s.split(':');
    return VerseRef(int.parse(p[0]), int.parse(p[1]));
  }

  String get key => '$surah:$ayah';
}

class Surah {
  final int n;
  final String name;
  final bool meccan;
  final List<String> ayat; // texte simple (copie, compatibilité)
  final List<String> uth; // rasm uthmani (affichage)
  final List<String> search;
  Surah(this.n, this.name, this.meccan, this.ayat, this.uth, this.search);
}

class Topic {
  final String id, title;
  Topic(this.id, this.title);
}

class Objection {
  final String id, topic, objection, answer;
  final List<String> refs;
  final String kTitle, kBody;
  Objection(this.id, this.topic, this.objection, this.answer, this.refs)
      : kTitle = norm(objection),
        kBody = norm(answer);
}

class Argument {
  final String id, title, text;
  final List<String> refs;
  final String kTitle, kBody;
  Argument(this.id, this.title, this.text, this.refs)
      : kTitle = norm(title),
        kBody = norm(text);
}

class HCategory {
  final String id, title;
  HCategory(this.id, this.title);
}

class Hadith {
  final String id, cat, title, book, bookKey, number, grade, text, comment, note, url, kw, narrator;
  final List<String> refs;
  final String kTitle, kBody;
  Hadith(this.id, this.cat, this.title, this.book, this.bookKey, this.number, this.grade, this.text,
      this.comment, this.note, this.url, this.kw, this.refs, this.narrator)
      : kTitle = norm(title),
        kBody = norm('$text $comment $book');
  String get reference => '$book — رقم $number';
  String get dorarUrl => 'https://dorar.net/hadith/search?q=${Uri.encodeComponent(kw)}';
}

class Contradiction {
  final String id, kind, title, text;
  final List<String> a, b;
  final String kTitle, kBody;
  Contradiction(this.id, this.kind, this.title, this.a, this.b, this.text)
      : kTitle = norm(title),
        kBody = norm(text);
  bool get hadithVsHadith => kind == 'hh';
}

class ChainStep {
  final String type;
  final List<String> refs;
  final String note;
  ChainStep(this.type, this.refs, this.note);
}

class Chain {
  final String id, title, summary, conclusion;
  final List<ChainStep> steps;
  final String kTitle, kBody;
  Chain(this.id, this.title, this.summary, this.steps, this.conclusion)
      : kTitle = norm(title),
        kBody = norm('$summary $conclusion ${steps.map((s) => s.note).join(' ')}');
}

class CaseVerse {
  final String ref, note;
  CaseVerse(this.ref, this.note);
}

class CaseReply {
  final String q, a;
  CaseReply(this.q, this.a);
}

class CaseFile {
  final String id, title, desc, claim, either, orr;
  final List<String> tags, hh, hq, questions, chains, objections;
  final List<CaseVerse> quran;
  final List<CaseReply> replies;
  final String kTitle, kBody;
  CaseFile(this.id, this.title, this.desc, this.tags, this.claim, this.quran, this.hh, this.hq, this.either, this.orr,
      this.questions, this.replies, this.chains, this.objections)
      : kTitle = norm(title),
        kBody = norm('$desc $claim $either $orr ${questions.join(' ')} ${replies.map((r) => '${r.q} ${r.a}').join(' ')}');
}

/// Lien typé d'un hadith vers un verset, un hadith, une chaîne, un dossier ou un rapporteur.
class HLink {
  final String type; // q, hq, hh, same, s, k, n
  final String title, why;
  final List<String> items;
  final String? open;
  final Chain? chain;
  final int step;
  HLink(this.type, this.title, this.why, this.items, {this.open, this.chain, this.step = 0});
}

class TimelineEvent {
  final String h, g, title, text;
  TimelineEvent(this.h, this.g, this.title, this.text);
}

/// Élément trouvé par la recherche globale.
class Hit {
  final String kind; // o, h, c, s, a
  final String id;
  final int score;
  Hit(this.kind, this.id, this.score);
}

// ───────────────────────── Dépôt de données ─────────────────────────

class AppData {
  static late AppData I;

  final List<Surah> surahs;
  final List<Topic> topics;
  final List<Objection> objections;
  final List<Argument> arguments;
  final List<HCategory> hcats;
  final List<Hadith> hadiths;
  final List<Contradiction> contradictions;
  final List<Chain> chains;
  final List<CaseFile> cases;
  final List<TimelineEvent> timeline;
  final bool fromUpdate;

  late final Map<String, Hadith> hadithById = {for (final h in hadiths) h.id: h};
  late final Map<String, Objection> objectionById = {for (final o in objections) o.id: o};
  late final Map<String, Contradiction> contraById = {for (final c in contradictions) c.id: c};
  late final Map<String, Chain> chainById = {for (final c in chains) c.id: c};
  late final Map<String, Argument> argumentById = {for (final a in arguments) a.id: a};
  late final Map<String, CaseFile> caseById = {for (final c in cases) c.id: c};

  /// Rapporteurs : nom -> hadiths.
  late final Map<String, List<Hadith>> byNarrator = () {
    final m = <String, List<Hadith>>{};
    for (final h in hadiths) {
      if (h.narrator.isNotEmpty) (m[h.narrator] ??= []).add(h);
    }
    final keys = m.keys.toList()..sort((a, b) => m[b]!.length.compareTo(m[a]!.length));
    return {for (final k in keys) k: m[k]!};
  }();

  /// Hadiths cités dans un dossier (via ses contradictions et chaînes).
  List<Hadith> caseHadiths(CaseFile k) {
    final ids = <String>{};
    for (final cid in [...k.hh, ...k.hq]) {
      final c = contraById[cid];
      if (c != null) ids.addAll([...c.a, ...c.b].where((x) => !isVerseRef(x)));
    }
    for (final sid in k.chains) {
      final s = chainById[sid];
      if (s != null) {
        for (final st in s.steps) {
          ids.addAll(st.refs.where((x) => !isVerseRef(x)));
        }
      }
    }
    return ids.map((i) => hadithById[i]).whereType<Hadith>().toList();
  }

  /// Carte de liaison d'un hadith : chaque lien avec son type et son explication.
  List<HLink> hadithLinks(Hadith h) {
    final out = <HLink>[];
    final own = h.refs.where(isVerseRef).toList();
    if (own.isNotEmpty) out.add(HLink('q', 'يخالف كلام الله', h.comment, own));
    for (final c in contradictions) {
      final inA = c.a.contains(h.id), inB = c.b.contains(h.id);
      if (!inA && !inB) continue;
      final other = inA ? c.b : c.a;
      final mates = (inA ? c.a : c.b).where((x) => x != h.id && !isVerseRef(x)).toList();
      final verses = other.where(isVerseRef).toList();
      final hads = other.where((x) => !isVerseRef(x)).toList();
      if (verses.isNotEmpty) out.add(HLink('hq', c.title, c.text, verses, open: 'c:${c.id}'));
      if (hads.isNotEmpty) out.add(HLink('hh', c.title, c.text, hads, open: 'c:${c.id}'));
      if (mates.isNotEmpty) out.add(HLink('same', 'في صفّه: ${c.title}', 'روايات تقول المعنى نفسه في هذا التناقض.', mates, open: 'c:${c.id}'));
    }
    for (final ch in chains) {
      final i = ch.steps.indexWhere((st) => st.refs.contains(h.id));
      if (i < 0) continue;
      out.add(HLink('s', ch.title, ch.steps[i].note, const [], open: 's:${ch.id}', chain: ch, step: i));
    }
    for (final k in cases) {
      if (caseHadiths(k).any((x) => x.id == h.id)) out.add(HLink('k', k.title, k.desc, const [], open: 'k:${k.id}'));
    }
    if (h.narrator.isNotEmpty) {
      final others = (byNarrator[h.narrator] ?? const <Hadith>[]).where((x) => x.id != h.id).map((x) => x.id).toList();
      if (others.isNotEmpty) {
        out.add(HLink('n', 'روايات أخرى لـ${h.narrator}', 'الراوي نفسه في بقية الملف: قارن ما يرويه هنا بما يرويه هناك.',
            others.take(8).toList()));
      }
    }
    return out;
  }

  /// Pour chaque hadith : contradictions et chaînes où il apparaît.
  late final Map<String, List<String>> hadithUsage = _buildHadithUsage();

  /// Pour chaque verset « s:a » : éléments qui le citent (o/a/h/c/s + id).
  late final Map<String, List<String>> verseUsage = _buildVerseUsage();

  AppData(this.surahs, this.topics, this.objections, this.arguments, this.hcats, this.hadiths,
      this.contradictions, this.chains, this.cases, this.timeline, this.fromUpdate);

  Map<String, List<String>> _buildHadithUsage() {
    final m = <String, List<String>>{};
    void add(String hid, String tag) => (m[hid] ??= []).add(tag);
    for (final c in contradictions) {
      for (final x in [...c.a, ...c.b]) {
        if (!isVerseRef(x)) add(x, 'c:${c.id}');
      }
    }
    for (final s in chains) {
      for (final st in s.steps) {
        for (final x in st.refs) {
          if (!isVerseRef(x)) add(x, 's:${s.id}');
        }
      }
    }
    return m.map((k, v) => MapEntry(k, v.toSet().toList()));
  }

  Map<String, List<String>> _buildVerseUsage() {
    final m = <String, List<String>>{};
    void add(String r, String tag) {
      if (isVerseRef(r)) (m[r] ??= []).add(tag);
    }
    for (final o in objections) {
      for (final r in o.refs) {
        add(r, 'o:${o.id}');
      }
    }
    for (final a in arguments) {
      for (final r in a.refs) {
        add(r, 'a:${a.id}');
      }
    }
    for (final h in hadiths) {
      for (final r in h.refs) {
        add(r, 'h:${h.id}');
      }
    }
    for (final c in contradictions) {
      for (final r in c.b) {
        add(r, 'c:${c.id}');
      }
    }
    for (final s in chains) {
      for (final st in s.steps) {
        for (final r in st.refs) {
          add(r, 's:${s.id}');
        }
      }
    }
    return m.map((k, v) => MapEntry(k, v.toSet().toList()));
  }

  static Future<File> _overrideFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}content_update.json');
  }

  static Future<void> load() async {
    final qRaw = await rootBundle.loadString('assets/data/quran.json');
    String cRaw = await rootBundle.loadString('assets/data/content.json');
    var fromUpdate = false;
    try {
      final f = await _overrideFile();
      if (await f.exists()) {
        final txt = await f.readAsString();
        parseContent(txt); // valide le format
        cRaw = txt;
        fromUpdate = true;
      }
    } catch (_) {
      fromUpdate = false;
    }
    I = _build(qRaw, cRaw, fromUpdate);
  }

  /// Vérifie qu'un JSON de contenu est valide (lève une exception sinon).
  static Map<String, dynamic> parseContent(String raw) {
    final c = jsonDecode(raw) as Map<String, dynamic>;
    if ((c['version'] as num? ?? 0) < 2) throw const FormatException('نسخة المحتوى قديمة');
    for (final k in ['objections', 'hadiths', 'contradictions', 'chains', 'arguments']) {
      if (c[k] is! List) throw FormatException('حقل مفقود: $k');
    }
    return c;
  }

  /// Installe un nouveau contenu téléchargé.
  static Future<int> installUpdate(String raw) async {
    final c = parseContent(raw);
    final f = await _overrideFile();
    await f.writeAsString(raw);
    final qRaw = await rootBundle.loadString('assets/data/quran.json');
    I = _build(qRaw, raw, true);
    return (c['hadiths'] as List).length;
  }

  static Future<void> resetUpdate() async {
    final f = await _overrideFile();
    if (await f.exists()) await f.delete();
    await load();
  }

  static List<String> _sl(dynamic l) => List<String>.from((l ?? const []) as List);

  static AppData _build(String qRaw, String cRaw, bool fromUpdate) {
    final q = jsonDecode(qRaw) as List;
    final c = parseContent(cRaw);
    return AppData(
      q
          .map((s) => Surah(
                s['n'] as int,
                s['name'] as String,
                s['type'] == 'meccan',
                List<String>.from(s['ayat'] as List),
                List<String>.from((s['u'] ?? s['ayat']) as List),
                (s['clean'] as List).map((e) => norm(e as String)).toList(),
              ))
          .toList(),
      (c['topics'] as List).map((t) => Topic(t['id'], t['title'])).toList(),
      (c['objections'] as List)
          .map((o) => Objection(o['id'], o['topic'], o['objection'], o['answer'], _sl(o['refs'])))
          .toList(),
      (c['arguments'] as List).map((a) => Argument(a['id'], a['title'], a['text'], _sl(a['refs']))).toList(),
      (c['hadithCategories'] as List).map((h) => HCategory(h['id'], h['title'])).toList(),
      (c['hadiths'] as List)
          .map((h) => Hadith(
                h['id'],
                h['cat'],
                h['title'],
                h['book'],
                h['bookKey'] ?? '',
                '${h['number']}',
                h['grade'] ?? '',
                h['text'],
                h['comment'] ?? '',
                h['note'] ?? '',
                h['url'] ?? '',
                h['kw'] ?? h['title'],
                _sl(h['refs']),
                h['narrator'] ?? '',
              ))
          .toList(),
      (c['contradictions'] as List)
          .map((x) => Contradiction(x['id'], x['kind'], x['title'], _sl(x['a']), _sl(x['b']), x['text'] ?? ''))
          .toList(),
      (c['chains'] as List)
          .map((x) => Chain(
                x['id'],
                x['title'],
                x['summary'] ?? '',
                (x['steps'] as List).map((s) => ChainStep(s['type'], _sl(s['refs']), s['note'] ?? '')).toList(),
                x['conclusion'] ?? '',
              ))
          .toList(),
      ((c['cases'] ?? const []) as List)
          .map((k) => CaseFile(
                k['id'],
                k['title'],
                k['desc'] ?? '',
                _sl(k['tags']),
                k['claim'] ?? '',
                ((k['quran'] ?? const []) as List).map((v) => CaseVerse(v['ref'], v['note'] ?? '')).toList(),
                _sl(k['hh']),
                _sl(k['hq']),
                k['either'] ?? '',
                k['orr'] ?? '',
                _sl(k['questions']),
                ((k['replies'] ?? const []) as List).map((r) => CaseReply(r['q'], r['a'])).toList(),
                _sl(k['chains']),
                _sl(k['objections']),
              ))
          .toList(),
      ((c['timeline'] ?? const []) as List)
          .map((e) => TimelineEvent(e['h'] ?? '', e['g'] ?? '', e['title'] ?? '', e['text'] ?? ''))
          .toList(),
      fromUpdate,
    );
  }

  // ─── Coran
  Surah surah(int n) => surahs[n - 1];
  String verseText(VerseRef r) => surahs[r.surah - 1].uth[r.ayah - 1];
  String verseTextS(String r) => verseText(VerseRef.parse(r));
  String refLabel(VerseRef r) => '${surahs[r.surah - 1].name}: ${r.ayah}';
  String refLabelS(String r) => refLabel(VerseRef.parse(r));
  bool validRef(VerseRef r) =>
      r.surah >= 1 && r.surah <= 114 && r.ayah >= 1 && r.ayah <= surahs[r.surah - 1].ayat.length;
  int get totalAyat => surahs.fold(0, (a, s) => a + s.ayat.length);

  String topicTitle(String id) => topics.firstWhere((t) => t.id == id, orElse: () => Topic(id, id)).title;
  String catTitle(String id) => hcats.firstWhere((t) => t.id == id, orElse: () => HCategory(id, id)).title;

  List<VerseRef> searchQuran(String q, {int limit = 200}) {
    final w = queryWords(q);
    if (w.isEmpty) return [];
    final out = <VerseRef>[];
    for (final s in surahs) {
      for (var i = 0; i < s.search.length; i++) {
        if (w.every(s.search[i].contains)) {
          out.add(VerseRef(s.n, i + 1));
          if (out.length >= limit) return out;
        }
      }
    }
    return out;
  }

  VerseRef? parseRefQuery(String q) {
    final ascii = q.replaceAllMapped(RegExp(r'[٠-٩]'), (m) => (m.group(0)!.codeUnitAt(0) - 0x0660).toString());
    final m = RegExp(r'^\s*(\d{1,3})\s*[:\s/.-]\s*(\d{1,3})\s*$').firstMatch(ascii);
    if (m != null) {
      final r = VerseRef(int.parse(m.group(1)!), int.parse(m.group(2)!));
      return validRef(r) ? r : null;
    }
    final m2 = RegExp(r'^\s*(?:سورة\s+)?(.+?)\s+(\d{1,3})\s*$').firstMatch(ascii);
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

  /// Recherche globale classée.
  List<Hit> searchAll(String q) {
    final w = queryWords(q);
    if (w.isEmpty) return [];
    final hits = <Hit>[];
    for (final k in cases) {
      final s = scoreOf(k.kTitle, k.kBody, w);
      if (s > 0) hits.add(Hit('k', k.id, s + 3));
    }
    for (final o in objections) {
      final s = scoreOf(o.kTitle, o.kBody, w);
      if (s > 0) hits.add(Hit('o', o.id, s + 2));
    }
    for (final c in contradictions) {
      final s = scoreOf(c.kTitle, c.kBody, w);
      if (s > 0) hits.add(Hit('c', c.id, s + 1));
    }
    for (final c in chains) {
      final s = scoreOf(c.kTitle, c.kBody, w);
      if (s > 0) hits.add(Hit('s', c.id, s + 1));
    }
    for (final h in hadiths) {
      final s = scoreOf(h.kTitle, h.kBody, w);
      if (s > 0) hits.add(Hit('h', h.id, s));
    }
    for (final a in arguments) {
      final s = scoreOf(a.kTitle, a.kBody, w);
      if (s > 0) hits.add(Hit('a', a.id, s));
    }
    hits.sort((x, y) => y.score.compareTo(x.score));
    return hits;
  }

  // ─── Textes à copier / partager
  String _verses(List<String> refs) =>
      refs.where(isVerseRef).map((r) => '﴿${verseTextS(r)}﴾ [${refLabelS(r)}]').join('\n');

  String objectionToText(Objection o) =>
      '❖ يقولون: ${o.objection}\n\n✔ الرد: ${o.answer}\n\n${_verses(o.refs)}\n\n— ${Brand.name}';

  String argumentToText(Argument a) => '◆ ${a.title}\n${a.text}\n\n${_verses(a.refs)}\n\n— ${Brand.name}';

  String hadithToText(Hadith h, {bool full = true}) {
    final b = StringBuffer()
      ..writeln('● ${h.title}')
      ..writeln(h.reference + (h.grade.isNotEmpty ? ' • ${h.grade}' : ''))
      ..writeln();
    if (full) b..writeln(h.text)..writeln();
    b.writeln('وجه الاعتراض: ${h.comment}');
    final v = _verses(h.refs);
    if (v.isNotEmpty) b..writeln()..writeln(v);
    if (h.url.isNotEmpty) b..writeln()..writeln('للتحقق: ${h.url}');
    b..writeln()..write('— ${Brand.name}');
    return b.toString();
  }

  String _side(List<String> xs) => xs.map((x) {
        if (isVerseRef(x)) return '﴿${verseTextS(x)}﴾ [${refLabelS(x)}]';
        final h = hadithById[x];
        return h == null ? x : '«${h.title}» — ${h.reference}';
      }).join('\n');

  String contradictionToText(Contradiction c) =>
      '⚖ تناقض: ${c.title}\n\n▪ ${_side(c.a)}\n\n▪ ${c.hadithVsHadith ? '' : 'كلام الله:\n'}${_side(c.b)}\n\n${c.text}\n\n— ${Brand.name}';

  String chainToText(Chain s) {
    final b = StringBuffer()..writeln('🔗 ${s.title}');
    if (s.summary.isNotEmpty) b.writeln(s.summary);
    b.writeln();
    var i = 1;
    for (final st in s.steps) {
      b.writeln('${i++}. ${st.note}');
      for (final x in st.refs) {
        if (isVerseRef(x)) {
          b.writeln('   ﴿${verseTextS(x)}﴾ [${refLabelS(x)}]');
        } else {
          final h = hadithById[x];
          if (h != null) b.writeln('   ← ${h.reference}');
        }
      }
    }
    b..writeln()..writeln('⬅ الخلاصة: ${s.conclusion}')..writeln()..write('— ${Brand.name}');
    return b.toString();
  }
}

extension CaseText on AppData {
  String caseToText(CaseFile k) {
    final b = StringBuffer()
      ..writeln('📁 ملف القضية: ${k.title}')
      ..writeln()
      ..writeln('١. الدعوى: ${k.claim}')
      ..writeln()
      ..writeln('٢. حكم القرآن:');
    for (final v in k.quran) {
      b.writeln('﴿${verseTextS(v.ref)}﴾ [${refLabelS(v.ref)}] — ${v.note}');
    }
    b
      ..writeln()
      ..writeln('٥. الإلزام:')
      ..writeln('إمّا ${k.either}')
      ..writeln('وإمّا ${k.orr}')
      ..writeln()
      ..writeln('٦. أسئلة للمحاور:');
    for (final q in k.questions) {
      b.writeln('• $q');
    }
    b..writeln()..writeln('٧. ردودهم وجوابها:');
    for (final r in k.replies) {
      b.writeln('— يقولون: ${r.q}\n  الجواب: ${r.a}');
    }
    b..writeln()..write('— ${Brand.name}');
    return b.toString();
  }
}

class Brand {
  static const name = 'حسبنا كتاب الله';
  static const tagline = 'أداة المناظرة: القرآن وحده';
  static const verse = 'أَوَلَمْ يَكْفِهِمْ أَنَّا أَنزَلْنَا عَلَيْكَ الْكِتَابَ يُتْلَىٰ عَلَيْهِمْ';
  static const verseRef = 'العنكبوت: 51';
  static const defaultUpdateUrl =
      'https://raw.githubusercontent.com/charuadejsi-del/apk-logiciel/main/assets/data/content.json';
}

// ───────────────────────── Recueils complets (recherche hors ligne) ─────────────────────────

class BookHadith {
  final int num;
  final String text;
  final String key;
  BookHadith(this.num, this.text, this.key);
}

List<BookHadith> _parseBook(String raw) {
  final rows = jsonDecode(raw) as List;
  return rows.map((r) {
    final t = r[1] as String;
    return BookHadith((r[0] as num).toInt(), t, norm(t));
  }).toList();
}

class Books {
  static const names = {'bukhari': 'صحيح البخاري', 'muslim': 'صحيح مسلم'};
  static final Map<String, List<BookHadith>> _cache = {};

  static Future<List<BookHadith>> load(String key) async {
    final c = _cache[key];
    if (c != null) return c;
    final raw = await rootBundle.loadString('assets/data/books/$key.json');
    final list = await compute(_parseBook, raw);
    _cache[key] = list;
    return list;
  }

  static List<BookHadith> search(List<BookHadith> list, String q, {int limit = 150}) {
    final w = queryWords(q);
    final n = int.tryParse(q.trim());
    if (n != null) return list.where((h) => h.num == n).toList();
    if (w.isEmpty) return [];
    final out = <BookHadith>[];
    for (final h in list) {
      if (w.every(h.key.contains)) {
        out.add(h);
        if (out.length >= limit) break;
      }
    }
    return out;
  }
}
