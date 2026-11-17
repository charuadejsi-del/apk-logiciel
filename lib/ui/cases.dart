import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import 'common.dart';
import 'extra.dart';

// ───────────────────────── Liste des dossiers ─────────────────────────

class CasesPage extends StatelessWidget {
  const CasesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    return Scaffold(
      appBar: AppBar(title: const Text('ملفات القضايا')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 30), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
          child: Text(
            'كل قضية: الدعوى، حكم القرآن، الروايات ضد بعضها وضد القرآن، الإلزام، الأسئلة، وردودهم المتوقعة.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 1100 ? 3 : (c.maxWidth >= 680 ? 2 : 1);
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final k in d.cases)
              SizedBox(width: (c.maxWidth - (cols - 1) * 10) / cols, child: CaseCard(k)),
          ]);
        }),
      ]),
    );
  }
}

class CaseCard extends StatelessWidget {
  final CaseFile k;
  const CaseCard(this.k, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final d = AppData.I;
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      onTap: () => openTag(context, 'k:${k.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: s.primary.withAlpha(28), borderRadius: BorderRadius.circular(11)),
            child: Icon(Icons.folder_special_rounded, color: s.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(k.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 10),
        Text(k.desc, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.onSurfaceVariant, height: 1.6)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in k.tags) Pill(t, color: C.goldDeep),
          Pill('${arNum(k.hh.length + k.hq.length)} تناقض', color: C.amber),
          Pill('${arNum(d.caseHadiths(k).length)} حديث', color: s.tertiary),
        ]),
      ]),
    );
  }
}

// ───────────────────────── Détail d'un dossier ─────────────────────────

class CaseDetail extends StatefulWidget {
  final CaseFile k;
  const CaseDetail(this.k, {super.key});
  @override
  State<CaseDetail> createState() => _CaseDetailState();
}

class _CaseDetailState extends State<CaseDetail> {
  final keys = List.generate(7, (_) => GlobalKey());
  static const toc = ['الدعوى', 'حكم القرآن', 'الروايات تناقض بعضها', 'الروايات تناقض القرآن', 'الإلزام', 'أسئلة للمحاور', 'ردودهم وجوابها'];

  void _go(int i) {
    final c = keys[i].currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 350), alignment: 0.05);
  }

  Widget _head(int i, Color color, {Color fg = Colors.white}) => Padding(
        key: keys[i],
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          StepBadge(arNum(i + 1), color: color, fg: fg),
          const SizedBox(width: 10),
          Expanded(child: Text(toc[i], style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: fg == Colors.white ? null : fg))),
        ]),
      );

  Widget _section(Widget child, {Color? color, Color? border}) => AppCard(
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.all(18),
        color: color,
        border: border,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final k = widget.k;
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    final wide = MediaQuery.of(context).size.width >= 1000;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final main = <Widget>[
      // En-tête
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ملف القضية', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.goldDeep)),
          Text(k.title, style: const TextStyle(fontFamily: 'Amiri', fontSize: 40, fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final t in k.tags) Pill(t)]),
        ]),
      ),
      // 1
      _section(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _head(0, s.error),
        SelectableText(k.claim, style: const TextStyle(fontSize: 17, height: 1.8)),
      ])),
      // 2
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: OrnateBanner(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _head(1, C.gold, fg: C.goldLight),
            for (final v in k.quran) ...[
              InkWell(
                onTap: () => openTag(context, 'v:${v.ref}'),
                child: Text('﴿ ${d.verseTextS(v.ref)} ﴾',
                    style: quranStyle.copyWith(color: Colors.white, fontSize: 23, height: 2.0)),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('${d.refLabelS(v.ref)} — ${v.note}', style: const TextStyle(color: Color(0xFFC9D6CF), fontSize: 13.5)),
              ),
            ],
          ]),
        ),
      ),
      // 3
      if (k.hh.isNotEmpty)
        _section(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _head(2, C.amber),
          for (final cid in k.hh)
            if (d.contraById[cid] != null) _ContraBlock(d.contraById[cid]!),
        ])),
      // 4
      if (k.hq.isNotEmpty)
        _section(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _head(3, C.amber),
          for (final cid in k.hq)
            if (d.contraById[cid] != null) _ContraBlock(d.contraById[cid]!),
        ])),
      // 5
      _section(
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _head(4, C.goldDeep),
          LayoutBuilder(builder: (context, c) {
            final row = c.maxWidth >= 560;
            final a = _IlzamBox('إمّا', k.either);
            final b = _IlzamBox('وإمّا', k.orr);
            return row
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: a),
                    const SizedBox(width: 10),
                    Expanded(child: b),
                  ])
                : Column(children: [a, const SizedBox(height: 10), b]);
          }),
        ]),
        color: dark ? const Color(0xFF2A2410) : const Color(0xFFFBF4DD),
        border: C.gold,
      ),
      // 6
      _section(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _head(5, s.primary),
        for (var i = 0; i < k.questions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${arNum(i + 1)}. ', style: TextStyle(fontWeight: FontWeight.w800, color: s.primary, fontSize: 16)),
              Expanded(child: SelectableText(k.questions[i], style: const TextStyle(fontSize: 16, height: 1.7))),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'نسخ السؤال',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () => copyText(context, k.questions[i]),
              ),
            ]),
          ),
      ])),
      // 7
      _section(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _head(6, s.primary),
        for (final r in k.replies)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: LayoutBuilder(builder: (context, c) {
              final a = _ReplyBox('يقولون:', r.q, s.error);
              final b = _ReplyBox('الجواب:', r.a, s.primary);
              return c.maxWidth >= 560
                  ? IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: a),
                        const SizedBox(width: 10),
                        Expanded(child: b),
                      ]),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 6), b]);
            }),
          ),
      ])),
      if (k.chains.isNotEmpty) ...[
        const SectionHeader('سلاسل مرتبطة', icon: Icons.account_tree_rounded),
        for (final sid in k.chains)
          if (d.chainById[sid] != null) tileFor('s:$sid'),
      ],
      if (k.objections.isNotEmpty) ...[
        const SectionHeader('ردود مرتبطة', icon: Icons.forum_rounded),
        for (final oid in k.objections)
          if (d.objectionById[oid] != null) tileFor('o:$oid'),
      ],
      const SectionHeader('ملاحظتي', icon: Icons.edit_note_rounded),
      NoteSection('k:${k.id}'),
    ];

    final side = _CaseSide(k: k, onToc: _go, toc: toc);

    return Scaffold(
      appBar: AppBar(
        title: Text('ملف القضية: ${k.title}'),
        actions: [
          IconButton(
            tooltip: 'وضع العرض',
            icon: const Icon(Icons.slideshow_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PresentationPage.forCase(k))),
          ),
          ...detailActions(context,
              tag: 'k:${k.id}',
              text: d.caseToText(k),
              onImage: () => showShareImage(context, kind: 'ملف القضية', title: k.title, blocks: [
                    ShareBlock('الدعوى', k.claim, color: const Color(0xFFFFB4A9)),
                    ...versesBlocks(k.quran.map((v) => v.ref).toList(), max: 2),
                    ShareBlock('إمّا', k.either),
                    ShareBlock('وإمّا', k.orr),
                  ])),
        ],
      ),
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(22, 10, 22, 40), children: main),
              ),
              SizedBox(
                width: 320,
                child: ListView(padding: const EdgeInsets.fromLTRB(4, 14, 16, 40), children: [side]),
              ),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [...main, side]),
    );
  }
}

class _ContraBlock extends StatelessWidget {
  final Contradiction c;
  const _ContraBlock(this.c);
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF231A10) : const Color(0xFFFFF8F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0D9C4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          TextButton(onPressed: () => openTag(context, 'c:${c.id}'), child: const Text('التفاصيل')),
        ]),
        LayoutBuilder(builder: (context, box) {
          final a = RefList(c.a);
          final b = RefList(c.b);
          return box.maxWidth >= 620
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: a),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 20),
                    child: Icon(Icons.compare_arrows_rounded, color: C.gold),
                  ),
                  Expanded(child: b),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  a,
                  const Center(child: Icon(Icons.swap_vert_rounded, color: C.gold)),
                  b,
                ]);
        }),
        const SizedBox(height: 6),
        Text(c.text, style: TextStyle(color: s.onSurfaceVariant, height: 1.7)),
      ]),
    );
  }
}

class _IlzamBox extends StatelessWidget {
  final String label, text;
  const _IlzamBox(this.label, this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: C.goldDeep, fontSize: 16)),
          const SizedBox(height: 4),
          SelectableText(text, style: const TextStyle(height: 1.8, fontSize: 15.5)),
        ]),
      );
}

class _ReplyBox extends StatelessWidget {
  final String label, text;
  final Color color;
  const _ReplyBox(this.label, this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withAlpha(24), borderRadius: BorderRadius.circular(10)),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$label ', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            TextSpan(text: text),
          ]),
          style: const TextStyle(height: 1.7, fontSize: 15),
        ),
      );
}

class _CaseSide extends StatelessWidget {
  final CaseFile k;
  final void Function(int) onToc;
  final List<String> toc;
  const _CaseSide({required this.k, required this.onToc, required this.toc});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    for (final h in d.caseHadiths(k)) {
      if (h.narrator.isNotEmpty) counts[h.narrator] = (counts[h.narrator] ?? 0) + 1;
    }
    final narr = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('فهرس الملف', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (var i = 0; i < toc.length; i++)
            InkWell(
              onTap: () => onToc(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  SizedBox(width: 22, child: Text(arNum(i + 1), style: const TextStyle(color: C.goldDeep, fontWeight: FontWeight.w800))),
                  Expanded(child: Text(toc[i])),
                ]),
              ),
            ),
        ]),
      ),
      if (narr.isNotEmpty)
        AppCard(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('الرواة في هذا الملف', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final e in narr.take(8))
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NarratorDetail(e.key))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: C.goldPale,
                      child: Text(e.key.characters.first, style: const TextStyle(color: C.goldDeep, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text('${arNum(e.value)} رواية', style: TextStyle(color: s.onSurfaceVariant, fontSize: 12.5)),
                  ]),
                ),
              ),
          ]),
        ),
      AppCard(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('مرتبط بهذه القضية', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final sid in k.chains)
            if (d.chainById[sid] != null)
              TextButton(
                style: TextButton.styleFrom(alignment: AlignmentDirectional.centerStart),
                onPressed: () => openTag(context, 's:$sid'),
                child: Text('سلسلة: ${d.chainById[sid]!.title}'),
              ),
          TextButton(
            style: TextButton.styleFrom(alignment: AlignmentDirectional.centerStart),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TimelinePage())),
            child: const Text('الخط الزمني للأحداث'),
          ),
        ]),
      ),
    ]);
  }
}

// ───────────────────────── Mode présentation ─────────────────────────

class Slide {
  final String kicker, title, body;
  final bool quran;
  const Slide(this.kicker, this.title, this.body, {this.quran = false});
}

class PresentationPage extends StatefulWidget {
  final String heading;
  final List<Slide> slides;
  const PresentationPage({super.key, required this.heading, required this.slides});

  factory PresentationPage.forCase(CaseFile k) {
    final d = AppData.I;
    final s = <Slide>[
      Slide('ملف القضية', k.title, k.desc),
      Slide('الدعوى', 'يقولون', k.claim),
      for (final v in k.quran) Slide('حكم القرآن — ${d.refLabelS(v.ref)}', v.note, '﴿ ${d.verseTextS(v.ref)} ﴾', quran: true),
      for (final cid in [...k.hh, ...k.hq])
        if (d.contraById[cid] != null)
          Slide(d.contraById[cid]!.hadithVsHadith ? 'تناقض: رواية ضد رواية' : 'تناقض: رواية ضد آية',
              d.contraById[cid]!.title, d.contraById[cid]!.text),
      Slide('الإلزام', 'إمّا', k.either),
      Slide('الإلزام', 'وإمّا', k.orr),
      for (final q in k.questions) Slide('سؤال للمحاور', '', q),
    ];
    return PresentationPage(heading: k.title, slides: s);
  }

  factory PresentationPage.forChain(Chain c) {
    final d = AppData.I;
    final s = <Slide>[Slide('سلسلة حجج', c.title, c.summary)];
    var i = 1;
    for (final st in c.steps) {
      final verses = st.refs.where(isVerseRef).toList();
      final hs = st.refs.where((x) => !isVerseRef(x)).map((x) => d.hadithById[x]?.reference).whereType<String>();
      s.add(Slide('الخطوة ${arNum(i++)}${hs.isNotEmpty ? ' — ${hs.join('، ')}' : ''}', '',
          verses.isNotEmpty ? '${st.note}\n\n${verses.map((r) => '﴿ ${d.verseTextS(r)} ﴾').join('\n')}' : st.note));
    }
    s.add(Slide('الخلاصة', '', c.conclusion));
    return PresentationPage(heading: c.title, slides: s);
  }

  @override
  State<PresentationPage> createState() => _PresentationPageState();
}

class _PresentationPageState extends State<PresentationPage> {
  int i = 0;
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    focus.dispose();
    super.dispose();
  }

  void _move(int delta) => setState(() => i = (i + delta).clamp(0, widget.slides.length - 1).toInt());

  @override
  Widget build(BuildContext context) {
    final sl = widget.slides[i];
    final size = MediaQuery.of(context).size;
    final scale = (size.width / 1100).clamp(0.6, 1.6).toDouble();
    return Scaffold(
      backgroundColor: C.greenDark,
      body: Focus(
        focusNode: focus,
        autofocus: true,
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.pageDown) {
            _move(1);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.pageUp) {
            _move(-1);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.escape) {
            Navigator.maybePop(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _move(d.localPosition.dx < size.width / 2 ? 1 : -1),
          child: Stack(children: [
            const Positioned.fill(child: StarPattern(opacity: 0.07, cell: 90)),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.08, vertical: 60),
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(sl.kicker,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: C.goldLight, fontWeight: FontWeight.w800, fontSize: 22 * scale)),
                      if (sl.title.isNotEmpty) ...[
                        SizedBox(height: 14 * scale),
                        Text(sl.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: 'Amiri',
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 52 * scale,
                                height: 1.3)),
                      ],
                      SizedBox(height: 22 * scale),
                      Text(sl.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: sl.quran ? 'AmiriQuran' : 'Tajawal',
                            color: sl.quran ? const Color(0xFFF3E7C1) : Colors.white.withAlpha(235),
                            fontSize: (sl.quran ? 40 : 34) * scale,
                            height: sl.quran ? 2.0 : 1.6,
                          )),
                    ]),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: Row(children: [
                Image.asset('assets/brand/icon.png', width: 30, height: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${Brand.name} — ${widget.heading}',
                      style: const TextStyle(color: C.goldLight, fontWeight: FontWeight.w700)),
                ),
                Text('${arNum(i + 1)} / ${arNum(widget.slides.length)}', style: const TextStyle(color: Colors.white70)),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'خروج',
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ]),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: (i + 1) / widget.slides.length,
                minHeight: 3,
                backgroundColor: Colors.transparent,
                color: C.gold,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Raccourci : bouton « وضع العرض » pour une chaîne.
Widget presentChainButton(BuildContext context, Chain c) => IconButton(
      tooltip: 'وضع العرض',
      icon: const Icon(Icons.slideshow_rounded),
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PresentationPage.forChain(c))),
    );

