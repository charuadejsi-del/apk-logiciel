import 'package:flutter/material.dart';

import '../data.dart';
import '../state.dart';
import 'common.dart';
import 'pages2.dart';
import 'cases.dart';
import 'extra.dart';
import 'links.dart';
import 'fatwas.dart';
import 'smart.dart';

/// Navigation globale entre sections.
final ValueNotifier<String> shellNav = ValueNotifier('home');
final ValueNotifier<String> debateQuery = ValueNotifier('');

const sectionInfo = <String, (String, IconData)>{
  'home': ('الرئيسية', Icons.home_rounded),
  'debate': ('المناظرة', Icons.bolt_rounded),
  'smart': ('البحث الذكي', Icons.manage_search_rounded),
  'cases': ('ملفات القضايا', Icons.folder_special_rounded),
  'objections': ('الردود', Icons.forum_rounded),
  'contra': ('التناقضات', Icons.compare_arrows_rounded),
  'chains': ('سلاسل الحجج', Icons.account_tree_rounded),
  'hadiths': ('الأحاديث', Icons.menu_book_rounded),
  'arguments': ('الحجج', Icons.verified_rounded),
  'fatwas': ('فتاوى تخالف القرآن', Icons.gavel_rounded),
  'narrators': ('الرواة', Icons.people_alt_rounded),
  'timeline': ('الخط الزمني', Icons.timeline_rounded),
  'quran': ('المصحف', Icons.auto_stories_rounded),
  'books': ('الصحيحان', Icons.library_books_rounded),
  'training': ('التدريب', Icons.school_rounded),
  'favorites': ('المفضلة', Icons.star_rounded),
  'mine': ('حججي وملاحظاتي', Icons.edit_note_rounded),
  'settings': ('الإعدادات', Icons.settings_rounded),
};

Widget pageFor(String id) => switch (id) {
      'home' => const HomePage(),
      'debate' => const DebatePage(),
      'cases' => const CasesPage(),
      'narrators' => const NarratorsPage(),
      'fatwas' => const FatwasPage(),
      'smart' => const SmartSearchPage(),
      'timeline' => const TimelinePage(),
      'objections' => const ObjectionsPage(),
      'contra' => const ContradictionsPage(),
      'chains' => const ChainsPage(),
      'hadiths' => const HadithsPage(),
      'arguments' => const ArgumentsPage(),
      'quran' => const QuranPage(),
      'books' => const BooksPage(),
      'training' => const TrainingPage(),
      'favorites' => const FavoritesPage(),
      'mine' => const MinePage(),
      'settings' => const SettingsPage(),
      _ => const HubPage(title: 'المزيد', ids: [
          'smart', 'contra', 'chains', 'hadiths', 'fatwas', 'objections', 'arguments', 'narrators', 'timeline', 'books', 'training',
          'favorites', 'mine', 'settings'
        ]),
    };

const bottomIds = ['home', 'debate', 'cases', 'quran', 'more'];

void openSection(BuildContext context, String id) {
  if (isWide(context) || bottomIds.contains(id)) {
    shellNav.value = id;
  } else {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pageFor(id)));
  }
}

// ───────────────────────── Hub (mobile) ─────────────────────────

class HubPage extends StatelessWidget {
  final String title;
  final List<String> ids;
  const HubPage({super.key, required this.title, required this.ids});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    String sub(String id) => switch (id) {
          'objections' => '${arNum(d.objections.length)} اعتراضاً مع الرد والأدلة',
          'contra' => '${arNum(d.contradictions.length)} تناقضاً: حديث ضد حديث وحديث ضد آية',
          'chains' => '${arNum(d.chains.length)} سلسلة تربط الأحداث حتى الخلاصة',
          'hadiths' => '${arNum(d.hadiths.length)} حديثاً بنصوصها ومصادرها',
          'arguments' => '${arNum(d.arguments.length)} حجة لكفاية القرآن',
          'books' => 'بحث في صحيحي البخاري ومسلم كاملين بدون إنترنت',
          'training' => 'البرنامج يلعب دور المحاور',
          'favorites' => 'ما حفظته للرجوع إليه',
          'mine' => 'أضف حججك وملاحظاتك الخاصة',
          'settings' => 'الخط والمظهر وتحديث المحتوى',
          'narrators' => 'الصحابة الرواة وتناقضات رواياتهم',
          'fatwas' => 'أقوال فقهية موثقة من كتبها تخالف العقل والقرآن',
          'smart' => 'اكتب موضوعاً فتظهر أحاديث نعم ولا وشهادة الصحابة والآيات',
          'timeline' => 'من نزول القرآن إلى تدوين الحديث',
          _ => '',
        };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        for (final id in ids)
          AppCard(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => pageFor(id))),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: C.green.withAlpha(30), borderRadius: BorderRadius.circular(14)),
                child: Icon(sectionInfo[id]!.$2, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(sectionInfo[id]!.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
                  const SizedBox(height: 2),
                  Text(sub(id), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
              const Icon(Icons.chevron_left_rounded),
            ]),
          ),
      ]),
    );
  }
}

// ───────────────────────── Accueil ─────────────────────────

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    final day = DateTime.now().difference(DateTime(2026)).inDays;
    final chain = d.chains[day % d.chains.length];
    final contra = d.contradictions[(day * 7) % d.contradictions.length];
    final stats = [
      ('hadiths', d.hadiths.length, 'حديث موثّق بالرقم'),
      ('contra', d.contradictions.length, 'تناقضاً'),
      ('chains', d.chains.length, 'سلسلة حجج'),
      ('cases', d.cases.length, 'ملف قضية'),
      ('quran', d.totalAyat, 'آية'),
    ];
    final wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      body: ListView(padding: EdgeInsets.fromLTRB(wide ? 26 : 12, MediaQuery.of(context).padding.top + 14, wide ? 26 : 12, 30), children: [
        OrnateBanner(
          padding: EdgeInsets.all(wide ? 30 : 18),
          child: Wrap(spacing: 24, runSpacing: 18, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('أداة المناظرة — القرآن وحده',
                    style: TextStyle(color: C.goldLight, fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 4),
                Text(Brand.name,
                    style: TextStyle(fontFamily: 'Amiri', color: Colors.white, fontWeight: FontWeight.w700, fontSize: wide ? 46 : 34, height: 1.25)),
                const SizedBox(height: 8),
                Text('﴿ ${AppData.I.verseTextS('29:51')} ﴾',
                    style: quranStyle.copyWith(color: const Color(0xFFF3E7C1), fontSize: wide ? 25 : 20)),
                const Text(Brand.verseRef, style: TextStyle(color: Color(0xFFC9D6CF), fontSize: 12.5)),
              ]),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => wide ? showCommandPalette(context) : openSection(context, 'smart'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Row(children: [
                        const Icon(Icons.bolt_rounded, color: C.green),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('اكتب اعتراض المحاور…', style: TextStyle(color: C.muted))),
                        if (wide)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(4)),
                            child: const Text('Ctrl K', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11, color: C.muted)),
                          ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: C.goldLight,
                    side: const BorderSide(color: C.gold),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.slideshow_rounded),
                  label: const Text('وضع العرض للبث المباشر', style: TextStyle(fontWeight: FontWeight.w800)),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => PresentationPage.forChain(chain))),
                ),
              ]),
            ),
          ]),
        ),
        if (d.fromUpdate)
          AppCard(
            margin: const EdgeInsets.only(top: 12),
            color: s.secondaryContainer,
            child: const Row(children: [
              Icon(Icons.cloud_done_rounded),
              SizedBox(width: 8),
              Expanded(child: Text('المحتوى محدّث من الإنترنت')),
            ]),
          ),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 5 : (c.maxWidth >= 520 ? 3 : 2);
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final st in stats)
              SizedBox(
                width: (c.maxWidth - (cols - 1) * 10) / cols,
                child: AppCard(
                  margin: EdgeInsets.zero,
                  onTap: () => openSection(context, st.$1),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(arNum(st.$2), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: s.primary)),
                    Text(st.$3, style: TextStyle(color: s.onSurfaceVariant)),
                  ]),
                ),
              ),
          ]);
        }),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('ملفات القضايا', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            if (wide)
              Expanded(
                child: Text('الدعوى، حكم القرآن، التناقضات، الإلزام، الأسئلة، وردودهم المتوقعة',
                    style: TextStyle(color: s.onSurfaceVariant, fontSize: 13)),
              )
            else
              const Spacer(),
            TextButton(onPressed: () => openSection(context, 'cases'), child: const Text('الكل')),
          ]),
        ),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
          final list = d.cases.take(cols == 1 ? 3 : 6).toList();
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final k in list) SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: CaseCard(k)),
          ]);
        }),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, c) {
          final two = c.maxWidth >= 800;
          final a = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionHeader('سلسلة اليوم', icon: Icons.account_tree_rounded),
            tileFor('s:${chain.id}'),
          ]);
          final b = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionHeader('تناقض اليوم', icon: Icons.compare_arrows_rounded),
            tileFor('c:${contra.id}'),
          ]);
          return two
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), Expanded(child: b)])
              : Column(children: [a, b]);
        }),
      ]),
    );
  }
}

// ───────────────────────── Mode débat ─────────────────────────

class DebatePage extends StatefulWidget {
  const DebatePage({super.key});
  @override
  State<DebatePage> createState() => _DebatePageState();
}

class _DebatePageState extends State<DebatePage> {
  final ctrl = TextEditingController();
  String q = '';

  static const quick = [
    'الصلاة', 'طاعة الرسول', 'الحكمة', 'البيان', 'الحفظ', 'الإسناد', 'الرجم', 'الردة', 'الشفاعة', 'عائشة',
    'السحر', 'الغيب', 'الإجماع', 'النسخ', 'الميراث', 'المرأة', 'ابن مسعود', 'أبو هريرة', 'عمر', 'الصحابة',
    'المعازف', 'اللحية', 'الوصية', 'البلاغ', 'عيسى', 'القدر',
  ];

  @override
  void initState() {
    super.initState();
    debateQuery.addListener(_ext);
    _ext();
  }

  void _ext() {
    final v = debateQuery.value;
    if (v.isNotEmpty) {
      setQuery(v);
      debateQuery.value = '';
    }
  }

  void setQuery(String v) {
    ctrl.text = v;
    ctrl.selection = TextSelection.collapsed(offset: v.length);
    setState(() => q = v);
  }

  @override
  void dispose() {
    debateQuery.removeListener(_ext);
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final ref = q.trim().isEmpty ? null : d.parseRefQuery(q);
    final hits = d.searchAll(q);
    final verses = (q.trim().length < 2 || ref != null) ? <VerseRef>[] : d.searchQuran(q, limit: 25);
    final empty = q.trim().isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('وضع المناظرة')),
      body: Column(children: [
        SearchField(
          controller: ctrl,
          autofocus: isWide(context),
          hint: 'اعتراض المحاور، كلمة، اسم صحابي… أو رقم آية 6:38',
          onChanged: (v) => setState(() => q = v),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (final k in quick)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ActionChip(label: Text(k), onPressed: () => setQuery(k)),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(top: 6, bottom: 30), children: [
            if (empty) ...[
              const EmptyState('اكتب ما يقوله المحاور، فتظهر الردود والتناقضات والسلاسل والآيات مرتّبة حسب القوة.',
                  icon: Icons.bolt_rounded),
            ],
            if (ref != null) ...[const SectionHeader('الآية', icon: Icons.bookmark_rounded), VerseCard(ref.key)],
            if (!empty && hits.isEmpty && verses.isEmpty && ref == null) const EmptyState('لا توجد نتائج. جرّب كلمة أخرى.'),
            if (hits.isNotEmpty) ...[
              SectionHeader('النتائج (${arNum(hits.length)})', icon: Icons.bolt_rounded),
              for (final h in hits.take(60)) tileFor('${h.kind}:${h.id}'),
            ],
            if (verses.isNotEmpty) ...[
              SectionHeader('آيات فيها «${q.trim()}»', icon: Icons.auto_stories_rounded),
              for (final v in verses) VerseCard(v.key),
            ],
            if (!empty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.library_books_rounded),
                  label: Text('ابحث عن «${q.trim()}» في صحيحي البخاري ومسلم'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BooksPage(initial: q))),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── Objections ─────────────────────────

class ObjectionsPage extends StatefulWidget {
  const ObjectionsPage({super.key});
  @override
  State<ObjectionsPage> createState() => _ObjectionsPageState();
}

class _ObjectionsPageState extends State<ObjectionsPage> {
  String? sel;
  String? topic;
  String q = '';
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final w = queryWords(q);
    final list = d.objections
        .where((o) => (topic == null || o.topic == topic) && (w.isEmpty || scoreOf(o.kTitle, o.kBody, w) > 0))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('الاعتراضات والردود')),
      body: MasterDetail(
        detail: (sel ?? (list.isEmpty ? null : list.first.id)) == null ? null : ObjectionDetail(d.objectionById[sel ?? list.first.id]!, key: ValueKey(sel ?? list.first.id)),
        list: Column(children: [
        SearchField(controller: ctrl, hint: 'ابحث في الاعتراضات…', onChanged: (v) => setState(() => q = v)),
        _Chips(
          all: 'الكل (${arNum(d.objections.length)})',
          items: [for (final t in d.topics) (t.id, t.title)],
          selected: topic,
          onSelect: (v) => setState(() => topic = v),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState('لا توجد نتائج')
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 6, bottom: 30),
                  itemCount: list.length,
                  itemBuilder: (context, i) => tileFor('o:${list[i].id}',
                      selected: splitView(context) && (sel ?? list.first.id) == list[i].id,
                      onTap: splitView(context) ? () => setState(() => sel = list[i].id) : null),
                ),
        ),
      ]),
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  final String all;
  final List<(String, String)> items;
  final String? selected;
  final ValueChanged<String?> onSelect;
  const _Chips({required this.all, required this.items, required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(label: Text(all), selected: selected == null, onSelected: (_) => onSelect(null)),
            ),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  label: Text(it.$2),
                  selected: selected == it.$1,
                  onSelected: (_) => onSelect(selected == it.$1 ? null : it.$1),
                ),
              ),
          ];
    if (isWide(context)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
        child: Wrap(runSpacing: 6, children: chips),
      );
    }
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: chips,
      ),
    );
  }
}

class ObjectionDetail extends StatelessWidget {
  final Objection o;
  const ObjectionDetail(this.o, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    final text = d.objectionToText(o);
    return Scaffold(
      appBar: AppBar(
        title: Text(d.topicTitle(o.topic)),
        actions: detailActions(context,
            tag: 'o:${o.id}',
            text: text,
            onImage: () => showShareImage(context, kind: 'رد على اعتراض', title: o.objection, blocks: [
                  ShareBlock('الرد', o.answer),
                  ...versesBlocks(o.refs, max: 2),
                ])),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        ColoredBlock(label: 'يقولون', text: o.objection, color: s.error, icon: Icons.record_voice_over_rounded),
        ColoredBlock(label: 'الرد', text: o.answer, color: s.primary, icon: Icons.check_circle_rounded),
        const SectionHeader('الأدلة من القرآن', icon: Icons.auto_stories_rounded),
        for (final r in o.refs.where(isVerseRef)) VerseCard(r),
        const SectionHeader('ملاحظتي', icon: Icons.edit_note_rounded),
        NoteSection('o:${o.id}'),
      ]),
    );
  }
}

// ───────────────────────── Contradictions ─────────────────────────

class ContradictionsPage extends StatefulWidget {
  const ContradictionsPage({super.key});
  @override
  State<ContradictionsPage> createState() => _ContradictionsPageState();
}

class _ContradictionsPageState extends State<ContradictionsPage> {
  String? sel;
  String? kind;
  String q = '';
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final w = queryWords(q);
    final list = d.contradictions
        .where((c) => (kind == null || c.kind == kind) && (w.isEmpty || scoreOf(c.kTitle, c.kBody, w) > 0))
        .toList();
    final hh = d.contradictions.where((c) => c.hadithVsHadith).length;
    return Scaffold(
      appBar: AppBar(title: const Text('التناقضات')),
      body: MasterDetail(
        detail: (sel ?? (list.isEmpty ? null : list.first.id)) == null ? null : ContradictionDetail(d.contraById[sel ?? list.first.id]!, key: ValueKey(sel ?? list.first.id)),
        list: Column(children: [
        SearchField(controller: ctrl, hint: 'ابحث في التناقضات…', onChanged: (v) => setState(() => q = v)),
        _Chips(
          all: 'الكل (${arNum(d.contradictions.length)})',
          items: [('hh', 'حديث ضد حديث (${arNum(hh)})'), ('hq', 'حديث ضد آية (${arNum(d.contradictions.length - hh)})')],
          selected: kind,
          onSelect: (v) => setState(() => kind = v),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState('لا توجد نتائج')
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 6, bottom: 30),
                  itemCount: list.length,
                  itemBuilder: (context, i) => tileFor('c:${list[i].id}',
                      selected: splitView(context) && (sel ?? list.first.id) == list[i].id,
                      onTap: splitView(context) ? () => setState(() => sel = list[i].id) : null),
                ),
        ),
      ]),
      ),
    );
  }
}

class ContradictionDetail extends StatelessWidget {
  final Contradiction c;
  const ContradictionDetail(this.c, {super.key});

  List<ShareBlock> _blocks(List<String> xs, String label) {
    final d = AppData.I;
    return xs.take(2).map((x) {
      if (isVerseRef(x)) return ShareBlock('كلام الله — ${d.refLabelS(x)}', '﴿${d.verseTextS(x)}﴾', quran: true);
      final h = d.hadithById[x];
      return ShareBlock('$label — ${h?.reference ?? ''}', '«${h?.title ?? x}»', hadith: true, color: const Color(0xFFFFB4A9));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    final wide = isWide(context);
    final sideA = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SideHeader(c.hadithVsHadith ? 'الرواية الأولى' : 'الرواية', s.error),
      RefList(c.a, openFirst: true),
    ]);
    final sideB = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SideHeader(c.hadithVsHadith ? 'الرواية المقابلة' : 'كلام الله', s.primary),
      RefList(c.b, openFirst: true),
    ]);
    return Scaffold(
      appBar: AppBar(
        title: const Text('تناقض'),
        actions: detailActions(context,
            tag: 'c:${c.id}',
            text: d.contradictionToText(c),
            onImage: () => showShareImage(context,
                kind: c.hadithVsHadith ? 'تناقض: حديث ضد حديث' : 'تناقض: حديث ضد آية',
                title: c.title,
                blocks: [..._blocks(c.a, 'الرواية'), ..._blocks(c.b, 'يقابلها'), ShareBlock('', c.text)])),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
          child: Text(c.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Pill(c.hadithVsHadith ? 'حديث ضد حديث' : 'حديث ضد آية', color: const Color(0xFFB26A00)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: sideA),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 30),
                    child: Icon(Icons.compare_arrows_rounded, size: 34, color: C.gold),
                  ),
                  Expanded(child: sideB),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  sideA,
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(child: Divider()),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.swap_vert_rounded, color: C.gold)),
                      Expanded(child: Divider()),
                    ]),
                  ),
                  sideB,
                ]),
        ),
        ColoredBlock(label: 'وجه التناقض', text: c.text, color: const Color(0xFFB26A00), icon: Icons.balance_rounded),
        const SectionHeader('ملاحظتي', icon: Icons.edit_note_rounded),
        NoteSection('c:${c.id}'),
      ]),
    );
  }
}

class _SideHeader extends StatelessWidget {
  final String text;
  final Color color;
  const _SideHeader(this.text, this.color);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Container(width: 6, height: 22, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      );
}

// ───────────────────────── Chaînes ─────────────────────────

class ChainsPage extends StatefulWidget {
  const ChainsPage({super.key});
  @override
  State<ChainsPage> createState() => _ChainsPageState();
}

class _ChainsPageState extends State<ChainsPage> {
  String? sel;
  String q = '';
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final w = queryWords(q);
    final list = d.chains.where((c) => w.isEmpty || scoreOf(c.kTitle, c.kBody, w) > 0).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('سلاسل الحجج')),
      body: MasterDetail(
        detail: (sel ?? (list.isEmpty ? null : list.first.id)) == null ? null : ChainDetail(d.chainById[sel ?? list.first.id]!, key: ValueKey(sel ?? list.first.id)),
        list: Column(children: [
        SearchField(controller: ctrl, hint: 'ابحث في السلاسل…', onChanged: (v) => setState(() => q = v)),
        Expanded(
          child: list.isEmpty
              ? const EmptyState('لا توجد نتائج')
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 6, bottom: 30),
                  itemCount: list.length,
                  itemBuilder: (context, i) => tileFor('s:${list[i].id}',
                      selected: splitView(context) && (sel ?? list.first.id) == list[i].id,
                      onTap: splitView(context) ? () => setState(() => sel = list[i].id) : null),
                ),
        ),
      ]),
      ),
    );
  }
}

class ChainDetail extends StatelessWidget {
  final Chain c;
  const ChainDetail(this.c, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('سلسلة حجج'),
        actions: [
          presentChainButton(context, c),
          ...detailActions(context,
            tag: 's:${c.id}',
            text: d.chainToText(c),
            onImage: () => showShareImage(context, kind: 'سلسلة حجج', title: c.title, blocks: [
                  for (var i = 0; i < c.steps.length && i < 5; i++) ShareBlock('${arNum(i + 1)}', c.steps[i].note),
                  ShareBlock('الخلاصة', c.conclusion, color: C.goldLight),
                ])),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 2),
          child: Text(c.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        ),
        if (c.summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text(c.summary, style: TextStyle(color: s.onSurfaceVariant, fontSize: 15.5)),
          ),
        for (var i = 0; i < c.steps.length; i++)
          _StepView(index: i + 1, step: c.steps[i], last: i == c.steps.length - 1),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ColoredBlock(
              label: 'الخلاصة الإلزامية', text: c.conclusion, color: const Color(0xFF9A7A12), icon: Icons.gavel_rounded),
        ),
        const SectionHeader('ملاحظتي', icon: Icons.edit_note_rounded),
        NoteSection('s:${c.id}'),
      ]),
    );
  }
}

class _StepView extends StatelessWidget {
  final int index;
  final ChainStep step;
  final bool last;
  const _StepView({required this.index, required this.step, required this.last});
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 56,
          child: Column(children: [
            const SizedBox(height: 12),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: s.primary, shape: BoxShape.circle),
              child: Text(arNum(index), style: TextStyle(color: s.onPrimary, fontWeight: FontWeight.w800)),
            ),
            if (!last)
              Expanded(child: Container(width: 3, margin: const EdgeInsets.only(top: 4), color: s.primary.withAlpha(70))),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 14, top: 8, bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (step.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Text(step.note, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, height: 1.6)),
                ),
              RefList(step.refs),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ───────────────────────── Hadiths ─────────────────────────

class HadithsPage extends StatefulWidget {
  const HadithsPage({super.key});
  @override
  State<HadithsPage> createState() => _HadithsPageState();
}

class _HadithsPageState extends State<HadithsPage> {
  String? sel;
  String? cat;
  String q = '';
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final w = queryWords(q);
    final list = d.hadiths
        .where((h) => (cat == null || h.cat == cat) && (w.isEmpty || scoreOf(h.kTitle, h.kBody, w) > 0))
        .toList();
    int count(String id) => d.hadiths.where((h) => h.cat == id).length;
    return Scaffold(
      appBar: AppBar(title: const Text('مراجع الأحاديث')),
      body: MasterDetail(
        detail: (sel ?? (list.isEmpty ? null : list.first.id)) == null ? null : HadithDetail(d.hadithById[sel ?? list.first.id]!, key: ValueKey(sel ?? list.first.id)),
        list: Column(children: [
        SearchField(controller: ctrl, hint: 'ابحث في الأحاديث…', onChanged: (v) => setState(() => q = v)),
        _Chips(
          all: 'الكل (${arNum(d.hadiths.length)})',
          items: [for (final c in d.hcats) (c.id, '${c.title} (${arNum(count(c.id))})')],
          selected: cat,
          onSelect: (v) => setState(() => cat = v),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState('لا توجد نتائج')
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 6, bottom: 30),
                  itemCount: list.length,
                  itemBuilder: (context, i) => tileFor('h:${list[i].id}',
                      selected: splitView(context) && (sel ?? list.first.id) == list[i].id,
                      onTap: splitView(context) ? () => setState(() => sel = list[i].id) : null),
                ),
        ),
      ]),
      ),
    );
  }
}

class HadithDetail extends StatelessWidget {
  final Hadith h;
  const HadithDetail(this.h, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    final text = h.text.length > 700 ? '${h.text.substring(0, 700)}…' : h.text;
    return Scaffold(
      appBar: AppBar(
        title: Text(d.catTitle(h.cat)),
        actions: detailActions(context,
            tag: 'h:${h.id}',
            text: d.hadithToText(h),
            onImage: () => showShareImage(context, kind: 'حديث ${d.catTitle(h.cat)}', title: h.title, blocks: [
                  ShareBlock(h.reference, text, hadith: true),
                  ShareBlock('وجه الاعتراض', h.comment, color: const Color(0xFFFFB4A9)),
                  ...versesBlocks(h.refs, max: 2),
                ])),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Text(h.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, height: 1.4)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            Pill(h.book, icon: Icons.library_books_rounded, color: s.tertiary),
            Pill('رقم ${h.number}', icon: Icons.tag_rounded, color: s.tertiary),
            if (h.grade.isNotEmpty) Pill(h.grade, icon: Icons.verified_rounded, color: s.secondary),
          ]),
        ),
        ColoredBlock(label: 'نص الرواية', text: h.text, color: s.tertiary, icon: Icons.format_quote_rounded, style: hadithStyle),
        if (h.note.isNotEmpty) ColoredBlock(label: 'التخريج', text: h.note, color: s.outline, icon: Icons.info_outline_rounded),
        ColoredBlock(label: 'وجه الاعتراض', text: h.comment, color: s.error, icon: Icons.report_rounded),
        HadithLinkMap(h),
        const SectionHeader('التحقق من المصدر', icon: Icons.fact_check_rounded),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            if (h.url.contains('sunnah.com'))
              OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text('sunnah.com — رقم ${h.number}'),
                  onPressed: () => openUrl(context, h.url)),
            OutlinedButton.icon(
                icon: const Icon(Icons.travel_explore_rounded),
                label: const Text('البحث بالنص في الدرر السنية'),
                onPressed: () => openUrl(context, h.dorarUrl)),
          ]),
        ),
        const SectionHeader('ملاحظتي', icon: Icons.edit_note_rounded),
        NoteSection('h:${h.id}'),
      ]),
    );
  }
}

// ───────────────────────── Arguments ─────────────────────────

class ArgumentsPage extends StatelessWidget {
  const ArgumentsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('حجج القرآن وحده')),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [for (final a in AppData.I.arguments) tileFor('a:${a.id}')],
        ),
      );
}

class ArgumentDetail extends StatelessWidget {
  final Argument a;
  const ArgumentDetail(this.a, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    return Scaffold(
      appBar: AppBar(
        title: Text(a.title),
        actions: detailActions(context,
            tag: 'a:${a.id}',
            text: d.argumentToText(a),
            onImage: () => showShareImage(context,
                kind: 'حجة', title: a.title, blocks: [ShareBlock('', a.text), ...versesBlocks(a.refs, max: 3)])),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        ColoredBlock(
            label: 'الحجة', text: a.text, color: Theme.of(context).colorScheme.primary, icon: Icons.verified_rounded),
        const SectionHeader('الآيات', icon: Icons.auto_stories_rounded),
        for (final r in a.refs.where(isVerseRef)) VerseCard(r),
        const SectionHeader('ملاحظتي', icon: Icons.edit_note_rounded),
        NoteSection('a:${a.id}'),
      ]),
    );
  }
}

/// Utilitaire : rafraîchit les listes après une mise à jour de contenu.
class ContentListener extends StatelessWidget {
  final Widget child;
  const ContentListener({super.key, required this.child});
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: AppState.I, builder: (context, _) => child);
}
