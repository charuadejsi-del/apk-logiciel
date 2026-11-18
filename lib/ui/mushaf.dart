import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../state.dart';
import 'common.dart';
import 'pages2.dart';

/// Palette d'un thème du mushaf.
class MTheme {
  final String name;
  final Color bg, page, ink, gold, head, soft;
  final bool dark;
  const MTheme(this.name, this.bg, this.page, this.ink, this.gold, this.head, this.soft, this.dark);
}

const mThemes = [
  MTheme('ورقي', Color(0xFFE9DFC8), Color(0xFFFCF6E6), Color(0xFF1A1712), Color(0xFFA8841E), Color(0xFF0F4D3A),
      Color(0xFF6B5E45), false),
  MTheme('أبيض', Color(0xFFE6EAE8), Color(0xFFFFFFFF), Color(0xFF111111), Color(0xFF0F4D3A), Color(0xFF0F4D3A),
      Color(0xFF5B6662), false),
  MTheme('ليلي', Color(0xFF060D0A), Color(0xFF0D1814), Color(0xFFE9E3CF), Color(0xFFC9A227), Color(0xFFE9CF7A),
      Color(0xFF8FA39A), true),
];

MTheme get curMTheme => mThemes[AppState.I.mushafTheme];

// ───────────────────────── Lecteur page par page ─────────────────────────

class MushafReader extends StatefulWidget {
  final int page;
  final VerseRef? highlight;
  const MushafReader({super.key, required this.page, this.highlight});
  @override
  State<MushafReader> createState() => _MushafReaderState();
}

class _MushafReaderState extends State<MushafReader> {
  late int page = widget.page.clamp(1, 604).toInt();
  late VerseRef? sel = widget.highlight;
  PageController? ctrl;
  bool? spreadMode;

  @override
  void dispose() {
    ctrl?.dispose();
    super.dispose();
  }

  int _index(int p, bool spread) => spread ? (p - 1) ~/ 2 : p - 1;

  void _ensure(bool spread) {
    if (spreadMode == spread && ctrl != null) return;
    final old = ctrl;
    spreadMode = spread;
    ctrl = PageController(initialPage: _index(page, spread));
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void goTo(int p, {VerseRef? h}) {
    p = p.clamp(1, 604).toInt();
    setState(() {
      page = p;
      sel = h;
    });
    AppState.I.setLastPage(p);
    ctrl?.jumpToPage(_index(p, spreadMode ?? false));
  }

  void _step(int delta) {
    final spread = spreadMode ?? false;
    goTo(page + delta * (spread ? 2 : 1));
  }

  void _tapVerse(VerseRef r, bool panel) {
    setState(() => sel = r);
    if (panel) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        builder: (ctx, sc) => ListView(controller: sc, children: [VersePanel(ref: r, host: context)]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final t = curMTheme;
        final first = d.pages[page - 1].isEmpty ? VerseRef(1, 1) : d.pages[page - 1].first;
        final marked = AppState.I.bookmarks.contains(page);
        return Theme(
          data: buildTheme(t.dark ? Brightness.dark : Brightness.light),
          child: CallbackShortcuts(
            bindings: {
              // En RTL : flèche gauche = page suivante.
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(1),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(-1),
              const SingleActivator(LogicalKeyboardKey.pageDown): () => _step(1),
              const SingleActivator(LogicalKeyboardKey.pageUp): () => _step(-1),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                backgroundColor: t.bg,
                appBar: AppBar(
                  backgroundColor: t.bg,
                  title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('سورة ${d.surah(first.surah).name}',
                        style: const TextStyle(fontFamily: 'Amiri', fontWeight: FontWeight.w700, fontSize: 21)),
                    Text('الجزء ${arNum(d.juzOf(first))} • صفحة ${arNum(page)}',
                        style: TextStyle(fontSize: 12, color: t.soft)),
                  ]),
                  actions: [
                    IconButton(
                        tooltip: 'الفهرس',
                        icon: const Icon(Icons.menu_book_rounded),
                        onPressed: () => showMushafIndex(context, onGo: goTo)),
                    IconButton(
                        tooltip: 'البحث في القرآن',
                        icon: const Icon(Icons.search_rounded),
                        onPressed: () => showMushafSearch(context, onGo: goTo)),
                    IconButton(
                        tooltip: marked ? 'إزالة العلامة' : 'وضع علامة على الصفحة',
                        icon: Icon(marked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                            color: marked ? t.gold : null),
                        onPressed: () => AppState.I.toggleBookmark(page)),
                    IconButton(
                        tooltip: 'الخط والمظهر',
                        icon: const Icon(Icons.text_fields_rounded),
                        onPressed: () => _settings(context)),
                  ],
                ),
                body: LayoutBuilder(builder: (context, c) {
                  final spread = c.maxWidth >= 1400;
                  final panel = !spread && c.maxWidth >= 1050;
                  _ensure(spread);
                  final count = spread ? 302 : 604;
                  Widget pg(int p) => MushafPage(
                        page: p,
                        theme: t,
                        font: AppState.I.mushafFont,
                        selected: sel,
                        onTap: (r) => _tapVerse(r, panel),
                      );
                  final viewer = PageView.builder(
                    key: ValueKey(spread),
                    controller: ctrl,
                    itemCount: count,
                    onPageChanged: (i) {
                      final p = spread ? i * 2 + 1 : i + 1;
                      setState(() => page = p);
                      AppState.I.setLastPage(p);
                    },
                    itemBuilder: (context, i) => spread
                        ? Row(children: [
                            Expanded(child: pg(i * 2 + 1)),
                            if (i * 2 + 2 <= 604) Expanded(child: pg(i * 2 + 2)) else const Spacer(),
                          ])
                        : pg(i + 1),
                  );
                  if (!panel) return viewer;
                  return Row(children: [
                    Expanded(child: viewer),
                    Container(
                      width: 370,
                      color: t.page.withAlpha(150),
                      child: sel == null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text('اضغط على أي آية لترى أين استُعملت، ولتكتب تدبّرك عليها.',
                                    textAlign: TextAlign.center, style: TextStyle(color: t.soft)),
                              ),
                            )
                          : ListView(children: [VersePanel(key: ValueKey(sel!.key), ref: sel!, host: context)]),
                    ),
                  ]);
                }),
              ),
            ),
          ),
        );
      },
    );
  }

  void _settings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: AppState.I,
        builder: (ctx, _) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('حجم الخط', style: TextStyle(fontWeight: FontWeight.w800)),
            Row(children: [
              const Text('أ', style: TextStyle(fontSize: 14)),
              Expanded(
                child: Slider(
                  min: 16,
                  max: 44,
                  divisions: 14,
                  value: AppState.I.mushafFont,
                  label: arNum(AppState.I.mushafFont.round()),
                  onChanged: AppState.I.setMushafFont,
                ),
              ),
              const Text('أ', style: TextStyle(fontSize: 26)),
            ]),
            const SizedBox(height: 8),
            const Text('لون الصفحة', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [for (var i = 0; i < mThemes.length; i++) ButtonSegment(value: i, label: Text(mThemes[i].name))],
              selected: {AppState.I.mushafTheme},
              onSelectionChanged: (v) => AppState.I.setMushafTheme(v.first),
            ),
            const SizedBox(height: 10),
            Text('على الحاسوب: الأسهم أو PageUp/PageDown لتقليب الصفحات.',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

/// Une page du mushaf de Médine.
class MushafPage extends StatefulWidget {
  final int page;
  final MTheme theme;
  final double font;
  final VerseRef? selected;
  final void Function(VerseRef) onTap;
  const MushafPage(
      {super.key, required this.page, required this.theme, required this.font, required this.selected, required this.onTap});
  @override
  State<MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<MushafPage> {
  late final List<VerseRef> verses = AppData.I.pages[widget.page - 1];
  late final Map<String, TapGestureRecognizer> taps = {
    for (final r in verses) r.key: TapGestureRecognizer()..onTap = () => widget.onTap(r),
  };

  @override
  void dispose() {
    for (final t in taps.values) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final t = widget.theme;
    if (verses.isEmpty) return const Center(child: Text('بيانات الصفحات غير متوفرة'));
    final first = verses.first;
    final names = verses.map((r) => r.surah).toSet().map((s) => d.surah(s).name).join(' • ');
    final quarter = d.quarterOf(first);
    final base = quranStyle.copyWith(fontSize: widget.font, height: 2.05, color: t.ink);

    // Segments : en-tête de sourate quand un verset 1 commence, puis texte continu justifié.
    final blocks = <Widget>[];
    var spans = <InlineSpan>[];
    void flush() {
      if (spans.isEmpty) return;
      blocks.add(Text.rich(TextSpan(children: spans), textAlign: TextAlign.justify, style: base));
      spans = [];
    }

    for (var i = 0; i < verses.length; i++) {
      final r = verses[i];
      final su = d.surah(r.surah);
      if (r.ayah == 1) {
        flush();
        blocks.add(_SurahHeader(su, t));
        if (r.surah != 1 && r.surah != 9) {
          blocks.add(Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
                textAlign: TextAlign.center, style: base.copyWith(color: t.head)),
          ));
        }
      }
      // Début d'un quart de hizb : ۞
      final prevQ = r.ayah > 1 ? d.quarterOf(VerseRef(r.surah, r.ayah - 1)) : (i > 0 ? d.quarterOf(verses[i - 1]) : 0);
      final q = d.quarterOf(r);
      final sel = widget.selected?.key == r.key;
      if (q != prevQ && !(r.surah == 1 && r.ayah == 1)) {
        spans.add(TextSpan(text: '۞ ', style: TextStyle(color: t.gold)));
      }
      spans.add(TextSpan(
        text: su.uth[r.ayah - 1],
        recognizer: taps[r.key],
        style: sel ? TextStyle(backgroundColor: t.gold.withAlpha(t.dark ? 60 : 50)) : null,
      ));
      if (su.sajda.contains(r.ayah)) spans.add(TextSpan(text: ' ۩', style: TextStyle(color: t.gold)));
      spans.add(TextSpan(
        text: ' ۝${arNum(r.ayah)} ',
        recognizer: taps[r.key],
        style: TextStyle(color: t.gold),
      ));
    }
    flush();

    final hizb = (quarter - 1) ~/ 4 + 1;
    final qInHizb = (quarter - 1) % 4;
    final hizbLabel = qInHizb == 0 ? 'الحزب ${arNum(hizb)}' : '${['', 'ربع', 'نصف', 'ثلاثة أرباع'][qInHizb]} الحزب ${arNum(hizb)}';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 4, 10, 12),
          decoration: BoxDecoration(
            color: t.page,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(t.dark ? 120 : 35), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          padding: const EdgeInsets.all(7),
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: t.gold, width: 1.6)),
            padding: const EdgeInsets.all(3),
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: t.gold.withAlpha(120), width: 0.8)),
              child: Column(children: [
                // En-tête de page : sourates à droite, juz/hizb à gauche.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Row(children: [
                    Expanded(
                      child: Text(names,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'Amiri', fontWeight: FontWeight.w700, fontSize: 15, color: t.head)),
                    ),
                    Text('الجزء ${arNum(d.juzOf(first))} — $hizbLabel',
                        style: TextStyle(fontFamily: 'Amiri', fontSize: 14, color: t.soft)),
                  ]),
                ),
                Container(height: 0.8, margin: const EdgeInsets.symmetric(horizontal: 12), color: t.gold.withAlpha(140)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks),
                  ),
                ),
                // Numéro de page.
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: t.gold.withAlpha(160)),
                    ),
                    child: Text(arNum(widget.page), style: TextStyle(fontFamily: 'Amiri', fontSize: 15, color: t.head)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartouche de début de sourate.
class _SurahHeader extends StatelessWidget {
  final Surah s;
  final MTheme t;
  const _SurahHeader(this.s, this.t);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(0, 8, 0, 6),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: t.gold.withAlpha(t.dark ? 30 : 26),
          border: Border.all(color: t.gold, width: 1.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          Text('${s.meccan ? 'مكية' : 'مدنية'}', style: TextStyle(fontSize: 12, color: t.soft)),
          Expanded(
            child: Text('سورة ${s.name}',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Amiri', fontSize: 22, fontWeight: FontWeight.w700, color: t.head)),
          ),
          Text('${arNum(s.uth.length)} آية', style: TextStyle(fontSize: 12, color: t.soft)),
        ]),
      );
}

// ───────────────────────── Fiches : index, recherche ─────────────────────────

void showMushafIndex(BuildContext context, {required void Function(int, {VerseRef? h}) onGo}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.85,
      child: MushafIndex(onGo: (p, {h}) {
        Navigator.pop(ctx);
        onGo(p, h: h);
      }),
    ),
  );
}

void showMushafSearch(BuildContext context, {required void Function(int, {VerseRef? h}) onGo}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.9,
      child: QuranSearchPanel(onGo: (p, {h}) {
        Navigator.pop(ctx);
        onGo(p, h: h);
      }),
    ),
  );
}

/// Index : sourates, juz, signets, aller à une page.
class MushafIndex extends StatelessWidget {
  final void Function(int, {VerseRef? h}) onGo;
  const MushafIndex({super.key, required this.onGo});

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.numbers_rounded),
              hintText: 'اذهب إلى صفحة (١ – ٦٠٤)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (v) {
              final n = int.tryParse(toLatinDigits(v.trim()));
              if (n != null) onGo(n);
            },
          ),
        ),
        const TabBar(tabs: [Tab(text: 'السور'), Tab(text: 'الأجزاء'), Tab(text: 'العلامات')]),
        Expanded(
          child: TabBarView(children: [
            ListView.builder(
              itemCount: d.surahs.length,
              itemBuilder: (context, i) {
                final su = d.surahs[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 16, child: Text(arNum(su.n), style: const TextStyle(fontSize: 12))),
                  title: Text('سورة ${su.name}', style: const TextStyle(fontFamily: 'Amiri', fontSize: 18, fontWeight: FontWeight.w700)),
                  subtitle: Text('${su.meccan ? 'مكية' : 'مدنية'} • ${arNum(su.uth.length)} آية'),
                  trailing: Text('ص ${arNum(d.pageOf(su.n, 1))}', style: TextStyle(color: s.onSurfaceVariant)),
                  onTap: () => onGo(d.pageOf(su.n, 1)),
                );
              },
            ),
            ListView.builder(
              itemCount: d.juzStarts.length,
              itemBuilder: (context, i) {
                final r = d.juzStarts[i];
                final txt = d.surah(r.surah).uth[r.ayah - 1];
                return ListTile(
                  leading: CircleAvatar(radius: 16, child: Text(arNum(i + 1), style: const TextStyle(fontSize: 12))),
                  title: Text('الجزء ${arNum(i + 1)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(txt, maxLines: 1, overflow: TextOverflow.ellipsis, style: quranStyle.copyWith(fontSize: 16)),
                  trailing: Text('${d.surah(r.surah).name} ${arNum(r.ayah)}\nص ${arNum(d.pageOf(r.surah, r.ayah))}',
                      textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: s.onSurfaceVariant)),
                  onTap: () => onGo(d.pageOf(r.surah, r.ayah)),
                );
              },
            ),
            ListenableBuilder(
              listenable: AppState.I,
              builder: (context, _) {
                final pages = AppState.I.bookmarks.toList()..sort();
                final favs = AppState.I.favorites.where((f) => f.startsWith('v:')).map((f) => f.substring(2)).toList();
                if (pages.isEmpty && favs.isEmpty) {
                  return const Center(child: Text('لا علامات بعد. ضع علامة على صفحة أو أضف آية إلى المفضلة.'));
                }
                return ListView(children: [
                  for (final p in pages)
                    ListTile(
                      leading: const Icon(Icons.bookmark_rounded),
                      title: Text('صفحة ${arNum(p)}'),
                      subtitle: Text(d.pages[p - 1].isEmpty ? '' : 'سورة ${d.surah(d.pages[p - 1].first.surah).name}'),
                      onTap: () => onGo(p),
                    ),
                  for (final k in favs)
                    if (isVerseRef(k))
                      ListTile(
                        leading: const Icon(Icons.star_rounded),
                        title: Text(d.verseTextS(k), maxLines: 2, overflow: TextOverflow.ellipsis, style: quranStyle.copyWith(fontSize: 17)),
                        subtitle: Text(d.refLabelS(k)),
                        onTap: () {
                          final r = VerseRef.parse(k);
                          onGo(d.pageOf(r.surah, r.ayah), h: r);
                        },
                      ),
                ]);
              },
            ),
          ]),
        ),
      ]),
    );
  }
}

String toLatinDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  return s.split('').map((c) {
    final i = ar.indexOf(c);
    return i < 0 ? c : '$i';
  }).join();
}

/// Recherche : mot ou référence, nombre d'occurrences, répartition par sourate, filtre.
class QuranSearchPanel extends StatefulWidget {
  final void Function(int, {VerseRef? h}) onGo;
  const QuranSearchPanel({super.key, required this.onGo});
  @override
  State<QuranSearchPanel> createState() => _QuranSearchPanelState();
}

class _QuranSearchPanelState extends State<QuranSearchPanel> {
  final ctrl = TextEditingController();
  String q = '';
  int? filter;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    final ref = q.trim().isEmpty ? null : d.parseRefQuery(toLatinDigits(q));
    final all = (norm(q).length < 2 || ref != null) ? <VerseRef>[] : d.searchQuran(q, limit: 2000);
    final per = <int, int>{};
    for (final r in all) {
      per[r.surah] = (per[r.surah] ?? 0) + 1;
    }
    final list = filter == null ? all : all.where((r) => r.surah == filter).toList();
    final words = queryWords(q);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'كلمة بالتشكيل أو بدونه، أو مرجع مثل 2:255',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() {
            q = v;
            filter = null;
          }),
        ),
      ),
      if (ref != null)
        ListTile(
          leading: const Icon(Icons.arrow_forward_rounded),
          title: Text(d.refLabel(ref)),
          subtitle: Text(d.verseText(ref), maxLines: 2, overflow: TextOverflow.ellipsis, style: quranStyle.copyWith(fontSize: 17)),
          onTap: () => widget.onGo(d.pageOf(ref.surah, ref.ayah), h: ref),
        ),
      if (all.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            Text('${arNum(all.length)} آية في ${arNum(per.length)} سورة',
                style: TextStyle(fontWeight: FontWeight.w800, color: s.primary)),
          ]),
        ),
        SizedBox(
          height: 42,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(label: const Text('الكل'), selected: filter == null, onSelected: (_) => setState(() => filter = null)),
            ),
            for (final e in (per.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(
                  label: Text('${d.surah(e.key).name} (${arNum(e.value)})'),
                  selected: filter == e.key,
                  onSelected: (_) => setState(() => filter = e.key),
                ),
              ),
          ]),
        ),
      ],
      Expanded(
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final r = list[i];
            return ListTile(
              title: _Highlighted(text: d.surah(r.surah).ayat[r.ayah - 1], words: words, color: s.primary),
              subtitle: Text('${d.refLabel(r)} • ص ${arNum(d.pageOf(r.surah, r.ayah))}'),
              onTap: () => widget.onGo(d.pageOf(r.surah, r.ayah), h: r),
            );
          },
        ),
      ),
    ]);
  }
}

/// Texte du verset avec les mots cherchés en couleur (comparaison sans diacritiques).
class _Highlighted extends StatelessWidget {
  final String text;
  final List<String> words;
  final Color color;
  const _Highlighted({required this.text, required this.words, required this.color});
  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    for (final w in text.split(' ')) {
      final n = norm(w);
      final hit = words.any((q) => q.isNotEmpty && n.contains(q));
      spans.add(TextSpan(
        text: '$w ',
        style: hit ? TextStyle(color: color, fontWeight: FontWeight.w700, backgroundColor: color.withAlpha(30)) : null,
      ));
    }
    return Text.rich(TextSpan(children: spans), style: quranStyle.copyWith(fontSize: 19));
  }
}

// ───────────────────────── Accueil du mushaf ─────────────────────────

class MushafHome extends StatelessWidget {
  const MushafHome({super.key});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    void open(int p, {VerseRef? h}) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => MushafReader(page: p, highlight: h)));
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final last = AppState.I.lastPage;
        final lr = d.pages[last - 1].isEmpty ? VerseRef(1, 1) : d.pages[last - 1].first;
        return Scaffold(
          appBar: AppBar(title: const Text('المصحف')),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: OrnateBanner(
                padding: const EdgeInsets.all(18),
                child: InkWell(
                  onTap: () => open(last),
                  child: Row(children: [
                    const Icon(Icons.auto_stories_rounded, color: C.goldLight, size: 34),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('متابعة القراءة', style: TextStyle(color: C.goldLight, fontWeight: FontWeight.w800)),
                        Text('سورة ${d.surah(lr.surah).name} — صفحة ${arNum(last)}',
                            style: const TextStyle(fontFamily: 'Amiri', color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                        Text('الجزء ${arNum(d.juzOf(lr))}', style: const TextStyle(color: Color(0xFFC9D6CF))),
                      ]),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: C.gold, foregroundColor: C.greenDark),
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('بحث'),
                      onPressed: () => showMushafSearch(context, onGo: open),
                    ),
                  ]),
                ),
              ),
            ),
            Expanded(child: MushafIndex(onGo: open)),
          ]),
        );
      },
    );
  }
}
