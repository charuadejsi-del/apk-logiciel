import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:munazir/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normalisation arabe', () {
    expect(norm('ٱلرَّحْمَٰنِ'), norm('الرحمن'));
    expect(norm('الصَّلَاةَ'), norm('الصلاه'));
    expect(norm('إِيَّاكَ'), norm('اياك'));
  });

  test('contenu complet et références valides', () async {
    await AppData.load();
    final d = AppData.I;
    expect(d.surahs.length, 114);
    expect(d.totalAyat, 6236);
    expect(d.hadiths.length, greaterThanOrEqualTo(190));
    expect(d.contradictions.length, greaterThanOrEqualTo(60));
    expect(d.chains.length, greaterThanOrEqualTo(30));
    expect(d.objections.length, greaterThanOrEqualTo(60));

    void checkRef(String r, String where) {
      if (isVerseRef(r)) {
        expect(d.validRef(VerseRef.parse(r)), isTrue, reason: '$where: $r');
      } else {
        expect(d.hadithById.containsKey(r), isTrue, reason: '$where: $r');
      }
    }

    for (final o in d.objections) {
      for (final r in o.refs) {
        checkRef(r, o.id);
      }
    }
    for (final h in d.hadiths) {
      expect(h.text.isNotEmpty, isTrue, reason: h.id);
      for (final r in h.refs) {
        checkRef(r, h.id);
      }
    }
    for (final c in d.contradictions) {
      for (final r in [...c.a, ...c.b]) {
        checkRef(r, c.id);
      }
    }
    for (final s in d.chains) {
      for (final st in s.steps) {
        for (final r in st.refs) {
          checkRef(r, s.id);
        }
      }
      expect(d.chainToText(s).isNotEmpty, isTrue);
    }
    for (final c in d.contradictions) {
      expect(d.contradictionToText(c).isNotEmpty, isTrue);
    }

    expect(d.cases.length, greaterThanOrEqualTo(16));
    expect(d.hadiths.length, greaterThanOrEqualTo(320));
    for (final h in d.hadiths) {
      for (final l in d.hadithLinks(h)) {
        for (final it in l.items) {
          expect(isVerseRef(it) || d.hadithById.containsKey(it), isTrue, reason: '${h.id} -> $it');
        }
      }
    }
    for (final k in d.cases) {
      for (final v in k.quran) {
        checkRef(v.ref, k.id);
      }
      for (final c in [...k.hh, ...k.hq]) {
        expect(d.contraById.containsKey(c), isTrue, reason: '${k.id}: $c');
      }
      expect(d.caseToText(k).isNotEmpty, isTrue);
    }
    expect(d.byNarrator.isNotEmpty, isTrue);
    expect(d.timeline.length, greaterThanOrEqualTo(10));
    expect(d.surah(2).uth.length, 286);
    expect(d.fatwas.length, greaterThanOrEqualTo(16));
    for (final f in d.fatwas) {
      for (final r in f.refs) {
        checkRef(r, f.id);
      }
      for (final h in f.related) {
        expect(d.hadithById.containsKey(h), isTrue, reason: '${f.id}: $h');
      }
      expect(f.source.isNotEmpty && f.url.startsWith('https://'), isTrue, reason: f.id);
    }
    expect(d.smart.length, greaterThanOrEqualTo(20));
    for (final t in d.smart) {
      expect(t.side('y').isNotEmpty, isTrue, reason: t.id);
      for (final v in t.verses) {
        checkRef(v.ref, t.id);
      }
      for (final i in t.items) {
        if (i.hid.isNotEmpty) expect(d.hadithById.containsKey(i.hid), isTrue);
      }
    }
    expect(AppData.contentSchema, greaterThanOrEqualTo(3));
    // Un contenu mal décodé (latin-1) doit être refusé.
    final good = await rootBundle.loadString('assets/data/content.json');
    expect(() => AppData.parseContent(latin1.decode(utf8.encode(good))), throwsFormatException);
    expect(AppData.parseContent(good), isNotEmpty);
    final tb = await Books.load('tabari');
    expect(tb.length, greaterThanOrEqualTo(20000));
    expect(tb.first.vol, 1);
    expect(Books.search(tb, 'فما يكن في كتابي هذا').isNotEmpty || Books.search(tb, 'وليعلم الناظر في كتابنا').isNotEmpty, isTrue);
    expect(d.hasPages, isTrue);
    expect(d.pageOf(2, 255), 42);
    expect(d.pageOf(114, 1), 604);
    expect(d.juzStarts.length, 30);
    expect(d.pages.every((p) => p.isNotEmpty), isTrue);
    expect(d.parseRefQuery('2:255')?.ayah, 255);
    expect(d.parseRefQuery('البقرة 255')?.surah, 2);
    expect(d.searchQuran('اتخذوا هذا القرآن مهجورا').first.surah, 25);
    expect(d.searchAll('الرجم').isNotEmpty, isTrue);
    expect(d.verseUsage['15:9']!.isNotEmpty, isTrue);
  });

  test('recherche dans al-Bukhari', () async {
    final l = await Books.load('bukhari');
    expect(l.length, greaterThan(7000));
    expect(Books.search(l, 'حسبنا كتاب الله').isNotEmpty, isTrue);
  });
}
