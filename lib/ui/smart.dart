import 'dart:async';

import 'package:flutter/material.dart';

import '../data.dart';
import 'cases.dart';
import 'common.dart';

// ───────────────────────── Compréhension de la requête ─────────────────────────

/// Mots vides ignorés (déjà normalisés).
const _stop = {
  'هل', 'هو', 'هي', 'عن', 'في', 'من', 'علي', 'الي', 'ان', 'ام', 'او', 'لا', 'ما', 'كل', 'الرسول', 'النبي', 'رسول',
  'الله', 'محمد', 'كان', 'يكون', 'قال', 'التي', 'الذي', 'هذا', 'هذه', 'ثم', 'قد', 'لم', 'كامل', 'كله', 'كاملا',
  'احاديث', 'حديث', 'الاحاديث', 'اريد', 'ابحث', 'موضوع', 'وهل', 'انه', 'لان',
};

/// Groupes de synonymes : un mot de la requête s'élargit à tout son groupe.
const _syn = <List<String>>[
  ['الغيب', 'غيب', 'كائن', 'ما يكون', 'ادري', 'تدري', 'غد'],
  ['يعلم', 'علم', 'ادري', 'تدري', 'اعلم'],
  ['القران', 'كتاب الله', 'المصحف', 'مصحف', 'سوره', 'ايه'],
  ['بين', 'يبين', 'بيان', 'فسر', 'يفسر', 'يعهد', 'عهد', 'بلغ', 'بلغت', 'تبيان'],
  ['الصلاه', 'صلي', 'يصلي', 'ركعه', 'ركعتين', 'ركعات'],
  ['المراه', 'النساء', 'امراه', 'الزوجه', 'المراه'],
  ['الزنا', 'زني', 'الرجم', 'رجم', 'محصن'],
  ['الخمر', 'نبيذ', 'مسكر', 'سكر'],
  ['القتال', 'قاتل', 'اقاتل', 'قتال', 'الجهاد', 'غزوه', 'غزا'],
  ['الشفاعه', 'شفاعه', 'يشفع', 'اشفع', 'شفاعتي'],
  ['القبر', 'قبره', 'قبور', 'القبور', 'قبرين'],
  ['الدجال', 'الاعور', 'المسيح الدجال'],
  ['عيسي', 'ابن مريم'],
  ['المهدي', 'رجل من اهل بيتي', 'يواطئ'],
  ['الشيطان', 'شيطان', 'الجن', 'ابليس', 'قرينه'],
  ['الكتابه', 'اكتب', 'يكتب', 'تكتبوا', 'اكتبوا', 'كتب عني'],
  ['الرده', 'بدل دينه', 'التارك لدينه', 'ارتد', 'ارتدوا'],
  ['السبي', 'سبي', 'السبايا', 'سبايا', 'الجاريه', 'العزل', 'جاريه'],
  ['الحاكم', 'الامير', 'السلطان', 'امير', 'اميره', 'الولاه'],
  ['الساعه', 'قيام الساعه', 'تقوم الساعه'],
  ['السحر', 'سحر', 'مسحور'],
  ['الصحابه', 'اصحابي', 'اصحابه', 'الصحابه'],
  ['الحوض', 'حوضي', 'الحوض'],
  ['الربا', 'ربا'],
  ['الكلاله', 'كلاله'],
  ['النسيان', 'نسي', 'انسي', 'نسيت', 'انسيتها'],
  ['الوصيه', 'اوصي', 'وصيه'],
  ['القدر', 'قدر', 'الكتاب', 'كتبه'],
];

List<String> _words(String q) =>
    queryWords(q).where((w) => w.length > 1 && !_stop.contains(w)).toList();

/// Sujets correspondant à la requête, triés par pertinence.
List<SmartTopic> matchTopics(String q) {
  final nq = norm(q);
  final words = _words(q);
  if (words.isEmpty) return [];
  final scored = <(SmartTopic, int)>[];
  for (final t in AppData.I.smart) {
    var s = 0;
    for (final tr in t.kTriggers) {
      if (nq.contains(tr)) s += 3 * tr.split(' ').length;
      for (final w in words) {
        if (w.length >= 3 && tr.contains(w)) s += 1;
      }
    }
    for (final w in words) {
      if (w.length >= 3 && norm(t.title).contains(w)) s += 2;
    }
    if (s >= 2) scored.add((t, s));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.map((e) => e.$1).toList();
}

/// Requête élargie : liste de groupes (ET entre groupes, OU dans un groupe).
List<List<String>> expandQuery(String q) {
  final out = <List<String>>[];
  for (final w in _words(q)) {
    List<String>? g;
    for (final grp in _syn) {
      final n = grp.map(norm).toList();
      if (n.any((m) => w == m || (m.length >= 3 && w.contains(m)) || (w.length >= 4 && m.contains(w)))) {
        g = n;
        break;
      }
    }
    out.add(g ?? [w]);
  }
  return out;
}

List<BookHadith> expandedSearch(List<BookHadith> list, List<List<String>> groups, {int limit = 300}) {
  if (groups.isEmpty) return [];
  final out = <BookHadith>[];
  for (final h in list) {
    if (groups.every((g) => g.any(h.key.contains))) {
      out.add(h);
      if (out.length >= limit) break;
    }
  }
  return out;
}

// ───────────────────────── Page de recherche ─────────────────────────

class SmartSearchPage extends StatefulWidget {
  final String initial;
  const SmartSearchPage({super.key, this.initial = ''});
  @override
  State<SmartSearchPage> createState() => _SmartSearchPageState();
}

class _SmartSearchPageState extends State<SmartSearchPage> {
  late final ctrl = TextEditingController(text: widget.initial);
  late String q = widget.initial;
  Timer? _deb;
  late final Future<List<List<BookHadith>>> books =
      Future.wait([Books.load('bukhari'), Books.load('muslim'), Books.load('tabari')]);
  String book = 'all';

  @override
  void dispose() {
    _deb?.cancel();
    ctrl.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => q = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    final topics = q.trim().isEmpty ? <SmartTopic>[] : matchTopics(q);
    final groups = q.trim().isEmpty ? <List<String>>[] : expandQuery(q);
    return Scaffold(
      appBar: AppBar(title: const Text('البحث الذكي في الصحيحين')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: TextField(
            controller: ctrl,
            autofocus: widget.initial.isEmpty,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.manage_search_rounded),
              hintText: 'اكتب موضوعاً: الرسول يعلم الغيب، هل بيّن القرآن كله…',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        ctrl.clear();
                        setState(() => q = '');
                      }),
            ),
            onChanged: _changed,
            onSubmitted: (v) => setState(() => q = v),
          ),
        ),
        Expanded(
          child: q.trim().isEmpty
              ? _TopicGrid(onPick: (t) => _open(context, t))
              : ListView(padding: const EdgeInsets.only(bottom: 30), children: [
                  if (topics.isNotEmpty) ...[
                    const SectionHeader('موضوع مُحلَّل جاهز', icon: Icons.auto_awesome_rounded),
                    for (final t in topics.take(3)) _TopicCard(t, onTap: () => _open(context, t)),
                  ] else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text('لا يوجد موضوع مُحلَّل لهذا السؤال بعد. إليك كل الأحاديث المتعلقة به في الصحيحين:',
                          style: TextStyle(color: s.onSurfaceVariant)),
                    ),
                  if (groups.isNotEmpty) ...[
                    const SectionHeader('بحث موسّع: البخاري ومسلم وتاريخ الطبري', icon: Icons.travel_explore_rounded),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (var i = 0; i < groups.length; i++) ...[
                          if (i > 0) const Text('و', style: TextStyle(fontWeight: FontWeight.w800)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: s.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(groups[i].take(5).join(' أو '), style: const TextStyle(fontSize: 12.5)),
                          ),
                        ],
                      ]),
                    ),
                    FutureBuilder<List<List<BookHadith>>>(
                      future: books,
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                        }
                        final bk = expandedSearch(snap.data![0], groups);
                        final ms = expandedSearch(snap.data![1], groups);
                        final tb = expandedSearch(snap.data![2], groups);
                        final list = [
                          if (book == 'all' || book == 'bukhari') ...bk.map((h) => ('bukhari', h)),
                          if (book == 'all' || book == 'muslim') ...ms.map((h) => ('muslim', h)),
                          if (book == 'all' || book == 'tabari') ...tb.map((h) => ('tabari', h)),
                        ];
                        final words = groups.expand((g) => g).toList();
                        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Wrap(spacing: 6, children: [
                              ChoiceChip(
                                  label: Text('الكل (${arNum(bk.length + ms.length + tb.length)})'),
                                  selected: book == 'all',
                                  onSelected: (_) => setState(() => book = 'all')),
                              ChoiceChip(
                                  label: Text('البخاري (${arNum(bk.length)})'),
                                  selected: book == 'bukhari',
                                  onSelected: (_) => setState(() => book = 'bukhari')),
                              ChoiceChip(
                                  label: Text('مسلم (${arNum(ms.length)})'),
                                  selected: book == 'muslim',
                                  onSelected: (_) => setState(() => book = 'muslim')),
                              ChoiceChip(
                                  label: Text('الطبري (${arNum(tb.length)})'),
                                  selected: book == 'tabari',
                                  onSelected: (_) => setState(() => book = 'tabari')),
                            ]),
                          ),
                          if (list.isEmpty)
                            const Padding(padding: EdgeInsets.all(20), child: Text('لا نتائج. جرّب كلمة أقصر أو مرادفاً.')),
                          for (final e in list.take(150)) _BookHit(book: e.$1, h: e.$2, words: words),
                          if (list.length > 150)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('تُعرض أول ١٥٠ نتيجة. أضف كلمة لتضييق البحث.',
                                  style: TextStyle(color: s.onSurfaceVariant)),
                            ),
                        ]);
                      },
                    ),
                  ],
                ]),
        ),
      ]),
    );
  }

  void _open(BuildContext context, SmartTopic t) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => SmartTopicPage(t)));
}

class _TopicGrid extends StatelessWidget {
  final void Function(SmartTopic) onPick;
  const _TopicGrid({required this.onPick});
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(8, 4, 8, 30), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        child: Text(
            'اكتب سؤالك بكلامك. إن كان من المواضيع المُحلَّلة ظهرت الأحاديث مصنّفة (نعم / لا / شهادة الصحابة) مع الآيات، '
            'وإلا بحث البرنامج في البخاري ومسلم كاملين بالكلمة ومرادفاتها.',
            style: TextStyle(color: s.onSurfaceVariant, height: 1.6)),
      ),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 600 ? 2 : 1);
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in AppData.I.smart)
            SizedBox(width: (c.maxWidth - (cols - 1) * 8) / cols, child: _TopicCard(t, onTap: () => onPick(t), margin: EdgeInsets.zero)),
        ]);
      }),
    ]);
  }
}

class _TopicCard extends StatelessWidget {
  final SmartTopic t;
  final VoidCallback onTap;
  final EdgeInsetsGeometry? margin;
  const _TopicCard(this.t, {required this.onTap, this.margin});
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    int n(String x) => t.side(x).length;
    return AppCard(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(t.question, style: TextStyle(color: s.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _Count('✅', n('y'), const Color(0xFF2E7D32)),
          _Count('❌', n('n'), const Color(0xFFC62828)),
          if (n('s') > 0) _Count('👥', n('s'), const Color(0xFF1565C0)),
          _Count('📖', t.verses.length, C.goldDeep),
        ]),
      ]),
    );
  }
}

class _Count extends StatelessWidget {
  final String icon;
  final int n;
  final Color color;
  const _Count(this.icon, this.n, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withAlpha(24), borderRadius: BorderRadius.circular(20)),
        child: Text('$icon ${arNum(n)}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
      );
}

/// Résultat brut d'un des deux Sahih.
class _BookHit extends StatelessWidget {
  final String book;
  final BookHadith h;
  final List<String> words;
  const _BookHit({required this.book, required this.h, required this.words});
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final name = Books.names[book] ?? book;
    final t = h.text.length > 420 ? '…${h.text.substring(h.text.length - 420)}' : h.text;
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      onTap: () => showBookHadith(context, name, h),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('$name — ${h.ref}', style: TextStyle(color: s.tertiary, fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 4),
        HighlightedText(text: t, words: words, color: s.primary, style: hadithStyle.copyWith(fontSize: 16.5)),
      ]),
    );
  }
}

void showBookHadith(BuildContext context, String name, BookHadith h) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(18, 0, 18, 24), children: [
        Text('$name — ${h.ref}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        if (h.section.isNotEmpty) Text(h.section, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 10),
        SelectableText(h.text, style: hadithStyle),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded),
              label: const Text('نسخ'),
              onPressed: () => copyText(context, '${h.text}\n[$name ${h.ref}]')),
          OutlinedButton.icon(
              icon: const Icon(Icons.share_rounded),
              label: const Text('مشاركة'),
              onPressed: () => shareText(context, '${h.text}\n[$name ${h.ref}]')),
        ]),
      ]),
    ),
  );
}

/// Texte avec les mots cherchés en couleur (comparaison sans diacritiques).
class HighlightedText extends StatelessWidget {
  final String text;
  final List<String> words;
  final Color color;
  final TextStyle? style;
  const HighlightedText({super.key, required this.text, required this.words, required this.color, this.style});
  @override
  Widget build(BuildContext context) {
    final single = words.where((w) => !w.contains(' ')).toList();
    return Text.rich(
      TextSpan(children: [
        for (final w in text.split(' '))
          TextSpan(
            text: '$w ',
            style: single.any((q) => q.length > 1 && norm(w).contains(q))
                ? TextStyle(color: color, fontWeight: FontWeight.w700, backgroundColor: color.withAlpha(28))
                : null,
          ),
      ]),
      style: style,
    );
  }
}

// ───────────────────────── Page d'un sujet ─────────────────────────

class SmartTopicPage extends StatelessWidget {
  final SmartTopic t;
  const SmartTopicPage(this.t, {super.key});

  String _text(AppData d) {
    final b = StringBuffer()
      ..writeln('🔎 ${t.title}')
      ..writeln(t.question)
      ..writeln();
    void sec(String title, List<SmartItem> l) {
      if (l.isEmpty) return;
      b.writeln(title);
      for (final i in l) {
        b.writeln('• ${i.note} [${i.reference}]');
      }
      b.writeln();
    }

    sec('✅ ${t.yes}:', t.side('y'));
    sec('❌ ${t.no}:', t.side('n'));
    sec('👥 شهادة الصحابة:', t.side('s'));
    b.writeln('📖 القرآن:');
    for (final v in t.verses) {
      b.writeln('﴿${d.verseTextS(v.ref)}﴾ [${d.refLabelS(v.ref)}]');
    }
    b
      ..writeln()
      ..writeln('الخلاصة: ${t.conclusion}')
      ..write('— ${Brand.name}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.title), actions: [
        IconButton(
          tooltip: 'وضع العرض',
          icon: const Icon(Icons.slideshow_rounded),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _present(d))),
        ),
        IconButton(tooltip: 'نسخ الكل', icon: const Icon(Icons.copy_all_rounded), onPressed: () => copyText(context, _text(d))),
        IconButton(tooltip: 'مشاركة', icon: const Icon(Icons.share_rounded), onPressed: () => shareText(context, _text(d))),
      ]),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
          child: Text(t.question, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.4)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
          child: Text('كل حديث مُتحقَّق من رقمه ونصه في الكتاب. اضغط لعرض النص الكامل.',
              style: TextStyle(color: s.onSurfaceVariant, fontSize: 12.5)),
        ),
        _Side(title: '✅ ${t.yes}', color: const Color(0xFF2E7D32), items: t.side('y')),
        _Side(title: '❌ ${t.no}', color: const Color(0xFFC62828), items: t.side('n')),
        _Side(title: '👥 شهادة الصحابة', color: const Color(0xFF1565C0), items: t.side('s')),
        const SectionHeader('📖 ما يقوله القرآن', icon: Icons.auto_stories_rounded),
        for (final v in t.verses) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Text(v.note, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          VerseCard(v.ref),
        ],
        ColoredBlock(label: 'الخلاصة', text: t.conclusion, color: C.goldDeep, icon: Icons.gavel_rounded),
        if (t.cases.isNotEmpty) ...[
          const SectionHeader('ملفات قضايا مرتبطة', icon: Icons.folder_special_rounded),
          for (final k in t.cases)
            if (d.caseById.containsKey(k)) tileFor('k:$k'),
        ],
      ]),
    );
  }

  PresentationPage _present(AppData d) => PresentationPage(heading: t.title, slides: [
        Slide('سؤال', t.title, t.question),
        for (final i in t.side('y')) Slide('✅ ${t.yes}', i.note, i.reference),
        for (final i in t.side('n')) Slide('❌ ${t.no}', i.note, i.reference),
        for (final i in t.side('s')) Slide('👥 شهادة الصحابة', i.note, i.reference),
        for (final v in t.verses) Slide('📖 ${d.refLabelS(v.ref)}', v.note, '﴿ ${d.verseTextS(v.ref)} ﴾', quran: true),
        Slide('الخلاصة', t.title, t.conclusion),
      ]);
}

class _Side extends StatelessWidget {
  final String title;
  final Color color;
  final List<SmartItem> items;
  const _Side({required this.title, required this.color, required this.items});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Row(children: [
          Container(width: 4, height: 22, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color))),
          Text(arNum(items.length), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ]),
      ),
      for (final i in items) _ItemCard(i, color: color),
    ]);
  }
}

class _ItemCard extends StatefulWidget {
  final SmartItem i;
  final Color color;
  const _ItemCard(this.i, {required this.color});
  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool open = false;
  Future<String>? text;

  Future<String> _load() async {
    final i = widget.i;
    if (i.text.isNotEmpty) return i.text;
    final list = await Books.load(i.book);
    final k = norm(i.kw);
    final h = list.where((x) => x.num == i.number && x.key.contains(k)).firstOrNull ??
        list.where((x) => x.num == i.number).firstOrNull;
    return h?.text ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.i;
    final s = Theme.of(context).colorScheme;
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      border: widget.color.withAlpha(90),
      onTap: () => setState(() {
        open = !open;
        text ??= _load();
      }),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(i.note, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, height: 1.55)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Pill(i.reference, icon: Icons.library_books_rounded, color: s.tertiary),
          if (i.grade.isNotEmpty && !i.grade.contains('الصحيحين')) Pill(i.grade, icon: Icons.verified_rounded, color: s.secondary),
          Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: s.onSurfaceVariant),
        ]),
        if (open)
          FutureBuilder<String>(
            future: text,
            builder: (context, snap) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: !snap.hasData
                  ? const LinearProgressIndicator()
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SelectableText(snap.data!, style: hadithStyle.copyWith(fontSize: 16.5)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton.icon(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('نسخ'),
                            onPressed: () => copyText(context, '${snap.data}\n[${i.reference}]')),
                        if (i.hid.isNotEmpty)
                          FilledButton.tonalIcon(
                              icon: const Icon(Icons.hub_rounded, size: 18),
                              label: const Text('بطاقة الحديث وخريطة ربطه'),
                              onPressed: () => openTag(context, 'h:${i.hid}')),
                      ]),
                    ]),
            ),
          ),
      ]),
    );
  }
}
