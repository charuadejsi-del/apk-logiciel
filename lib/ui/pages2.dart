import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data.dart';
import '../state.dart';
import 'common.dart';
import 'mushaf.dart';

// ───────────────────────── Coran ─────────────────────────

class QuranPage extends StatelessWidget {
  const QuranPage({super.key});
  @override
  Widget build(BuildContext context) => const MushafHome();
}

/// Compatibilité : ouvre le mushaf à la page du verset demandé.
class SurahReader extends StatelessWidget {
  final int surah;
  final int ayah;
  const SurahReader({super.key, required this.surah, this.ayah = 1});
  @override
  Widget build(BuildContext context) => MushafReader(
        page: AppData.I.pageOf(surah, ayah),
        highlight: ayah > 1 ? VerseRef(surah, ayah) : null,
      );
}

class VersePanel extends StatelessWidget {
  final VerseRef ref;
  final BuildContext host;
  const VersePanel({super.key, required this.ref, required this.host});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final text = d.verseText(ref);
    final label = d.refLabel(ref);
    final usage = d.verseUsage[ref.key] ?? const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppCard(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('الآية المحددة — $label', style: const TextStyle(fontWeight: FontWeight.w800, color: C.gold, fontSize: 13)),
            const SizedBox(height: 8),
            Text('﴿ $text ﴾', style: quranStyle.copyWith(fontSize: 20)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('نسخ'),
                  onPressed: () => copyText(host, '﴿$text﴾ [$label]')),
              OutlinedButton.icon(
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('مشاركة'),
                  onPressed: () => shareText(host, '﴿$text﴾ [$label]')),
              ListenableBuilder(
                listenable: AppState.I,
                builder: (c2, _) {
                  final f = AppState.I.isFav('v:${ref.key}');
                  return OutlinedButton.icon(
                    icon: Icon(f ? Icons.star_rounded : Icons.star_border_rounded, size: 18),
                    label: Text(f ? 'في المفضلة' : 'مفضلة'),
                    onPressed: () => AppState.I.toggleFav('v:${ref.key}'),
                  );
                },
              ),
              FilledButton.icon(
                icon: const Icon(Icons.image_rounded, size: 18),
                label: const Text('بطاقة صورة'),
                onPressed: () => showShareImage(host, kind: 'آية', title: label, blocks: [ShareBlock('', '﴿$text﴾', quran: true)]),
              ),
            ]),
          ]),
        ),
        if (usage.isNotEmpty) ...[
          SectionHeader('استُعملت هذه الآية في (${arNum(usage.length)})', icon: Icons.link_rounded),
          for (final t in usage) tileFor(t),
        ] else
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('لم تُستعمل هذه الآية بعد في الردود أو التناقضات.'),
          ),
        const SectionHeader('تدبّري وملاحظتي', icon: Icons.edit_note_rounded),
        NoteSection('v:${ref.key}'),
      ]),
    );
  }
}

// ───────────────────────── Recherche dans les deux Sahih ─────────────────────────

class BooksPage extends StatefulWidget {
  final String initial;
  const BooksPage({super.key, this.initial = ''});
  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage> {
  String book = 'bukhari';
  late final ctrl = TextEditingController(text: widget.initial);
  late String q = widget.initial;
  List<BookHadith>? list;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      list = null;
    });
    final l = await Books.load(book);
    if (!mounted) return;
    setState(() {
      list = l;
      loading = false;
    });
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final res = list == null ? <BookHadith>[] : Books.search(list!, q);
    return Scaffold(
      appBar: AppBar(title: const Text('البحث في الصحيحين')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'bukhari', label: Text('صحيح البخاري')),
              ButtonSegment(value: 'muslim', label: Text('صحيح مسلم')),
            ],
            selected: {book},
            onSelectionChanged: (v) {
              book = v.first;
              _load();
            },
          ),
        ),
        SearchField(
            controller: ctrl,
            hint: 'كلمة من الحديث، أو رقمه',
            onChanged: (v) => setState(() => q = v)),
        if (loading) const LinearProgressIndicator(),
        Expanded(
          child: list == null
              ? const SizedBox.shrink()
              : q.trim().isEmpty
                  ? EmptyState(
                      '${arNum(list!.length)} رواية في ${Books.names[book]}.\nاكتب جزءاً من الحديث الذي يذكره المحاور لتجده فوراً.',
                      icon: Icons.library_books_rounded)
                  : res.isEmpty
                      ? const EmptyState('لا توجد نتائج')
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 30),
                          itemCount: res.length,
                          itemBuilder: (context, i) => _BookTile(book: book, h: res[i]),
                        ),
        ),
      ]),
    );
  }
}

class _BookTile extends StatelessWidget {
  final String book;
  final BookHadith h;
  const _BookTile({required this.book, required this.h});
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final ref = '${Books.names[book]} — رقم ${h.num}';
    final url = 'https://sunnah.com/$book:${h.num}';
    return AppCard(
      onTap: () => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ref),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(child: SelectableText(h.text, style: hadithStyle)),
          ),
          actions: [
            TextButton(onPressed: () => openUrl(context, url), child: const Text('sunnah.com')),
            TextButton(onPressed: () => copyText(context, '${h.text}\n\n$ref\n$url'), child: const Text('نسخ')),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          ],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Pill(ref, color: s.tertiary),
        const SizedBox(height: 6),
        Text(h.text, maxLines: 4, overflow: TextOverflow.ellipsis, style: hadithStyle.copyWith(fontSize: 16.5)),
      ]),
    );
  }
}

// ───────────────────────── Entraînement ─────────────────────────

class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key});
  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  final rnd = Random();
  late Objection o = _pick();
  bool revealed = false;
  String mode = 'o';
  late Contradiction c = AppData.I.contradictions[rnd.nextInt(AppData.I.contradictions.length)];

  Objection _pick() => AppData.I.objections[rnd.nextInt(AppData.I.objections.length)];

  void next(bool? known) {
    if (known != null) AppState.I.train(known);
    setState(() {
      revealed = false;
      o = _pick();
      c = AppData.I.contradictions[rnd.nextInt(AppData.I.contradictions.length)];
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('وضع التدريب'), actions: [
        IconButton(
          tooltip: 'تصفير النتيجة',
          icon: const Icon(Icons.restart_alt_rounded),
          onPressed: AppState.I.resetTraining,
        ),
      ]),
      body: ListenableBuilder(
        listenable: AppState.I,
        builder: (context, _) {
          final st = AppState.I;
          final total = st.trainKnown + st.trainUnknown;
          final pct = total == 0 ? 0 : (st.trainKnown * 100 / total).round();
          return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'o', label: Text('اعتراض المحاور'), icon: Icon(Icons.record_voice_over_rounded)),
                  ButtonSegment(value: 'c', label: Text('اكتشف التناقض'), icon: Icon(Icons.compare_arrows_rounded)),
                ],
                selected: {mode},
                onSelectionChanged: (v) => setState(() {
                  mode = v.first;
                  revealed = false;
                }),
              ),
            ),
            AppCard(
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _Stat('أجبت', st.trainKnown, s.primary),
                _Stat('لم أعرف', st.trainUnknown, s.error),
                _Stat('النسبة %', pct, s.secondary),
              ]),
            ),
            if (mode == 'o') ...[
              ColoredBlock(
                  label: 'المحاور يقول', text: o.objection, color: s.error, icon: Icons.record_voice_over_rounded),
              if (!revealed)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    const Text('فكّر في ردّك أولاً، ثم اكشف الرد الجاهز.', textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                        icon: const Icon(Icons.visibility_rounded),
                        label: const Text('أظهر الرد'),
                        onPressed: () => setState(() => revealed = true)),
                  ]),
                )
              else ...[
                ColoredBlock(label: 'الرد', text: o.answer, color: s.primary, icon: Icons.check_circle_rounded),
                for (final r in o.refs.where(isVerseRef).take(3)) VerseCard(r),
              ],
            ] else ...[
              ColoredBlock(
                  label: 'ما وجه التناقض في: ${c.title}؟',
                  text: c.a.map((x) => isVerseRef(x) ? x : AppData.I.hadithById[x]?.title ?? x).join('\n'),
                  color: const Color(0xFFB26A00),
                  icon: Icons.help_rounded),
              if (!revealed)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: FilledButton.icon(
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('أظهر ما يقابلها'),
                      onPressed: () => setState(() => revealed = true)),
                )
              else ...[
                Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: RefList(c.b)),
                ColoredBlock(label: 'وجه التناقض', text: c.text, color: s.primary, icon: Icons.balance_rounded),
              ],
            ],
            if (revealed)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('عرفت الرد'),
                        onPressed: () => next(true)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('لم أعرفه'),
                        onPressed: () => next(false)),
                  ),
                ]),
              )
            else
              Center(child: TextButton(onPressed: () => next(null), child: const Text('تخطّي'))),
          ]);
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int v;
  final Color color;
  const _Stat(this.label, this.v, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(arNum(v), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
        Text(label),
      ]);
}

// ───────────────────────── Favoris ─────────────────────────

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المفضلة')),
      body: ListenableBuilder(
        listenable: AppState.I,
        builder: (context, _) {
          final favs = AppState.I.favorites.where(_valid).toList();
          if (favs.isEmpty) {
            return const EmptyState('لا شيء في المفضلة بعد.\nاضغط على النجمة في أي رد أو حديث أو تناقض أو آية.',
                icon: Icons.star_border_rounded);
          }
          const order = ['s', 'c', 'o', 'h', 'a', 'v'];
          favs.sort((a, b) => order.indexOf(a.split(':').first).compareTo(order.indexOf(b.split(':').first)));
          return ListView(padding: const EdgeInsets.only(top: 6, bottom: 30), children: [
            for (final t in favs)
              if (t.startsWith('v:')) VerseCard(t.substring(2)) else tileFor(t),
          ]);
        },
      ),
    );
  }

  static bool _valid(String t) {
    final d = AppData.I;
    final i = t.indexOf(':');
    if (i < 0) return false;
    final k = t.substring(0, i), id = t.substring(i + 1);
    return switch (k) {
      'o' => d.objectionById.containsKey(id),
      'h' => d.hadithById.containsKey(id),
      'c' => d.contraById.containsKey(id),
      's' => d.chainById.containsKey(id),
      'a' => d.argumentById.containsKey(id),
      'v' => isVerseRef(id) && d.validRef(VerseRef.parse(id)),
      _ => false,
    };
  }
}

// ───────────────────────── Mes arguments et notes ─────────────────────────

class MinePage extends StatelessWidget {
  const MinePage({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('حججي وملاحظاتي'),
          bottom: const TabBar(tabs: [Tab(text: 'حججي'), Tab(text: 'ملاحظاتي')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add_rounded),
          label: const Text('حجة جديدة'),
          onPressed: () => _edit(context, null),
        ),
        body: ListenableBuilder(
          listenable: AppState.I,
          builder: (context, _) {
            final st = AppState.I;
            return TabBarView(children: [
              st.myArgs.isEmpty
                  ? const EmptyState('أضف حججك الخاصة لتجدها وقت المناظرة.', icon: Icons.edit_rounded)
                  : ListView(padding: const EdgeInsets.only(top: 6, bottom: 90), children: [
                      for (final a in st.myArgs)
                        AppCard(
                          onTap: () => _edit(context, a),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                  child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                              IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 20),
                                  onPressed: () => copyText(context, '${a.title}\n\n${a.text}\n\n— ${Brand.name}')),
                              IconButton(
                                  icon: const Icon(Icons.share_rounded, size: 20),
                                  onPressed: () => shareText(context, '${a.title}\n\n${a.text}\n\n— ${Brand.name}')),
                            ]),
                            Text(a.text, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.6)),
                          ]),
                        ),
                    ]),
              st.notes.isEmpty
                  ? const EmptyState('ملاحظاتك على الردود والأحاديث والتناقضات تظهر هنا.', icon: Icons.edit_note_rounded)
                  : ListView(padding: const EdgeInsets.only(top: 6, bottom: 90), children: [
                      for (final e in st.notes.entries)
                        AppCard(
                          onTap: () => openTag(context, e.key),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_safeTitle(e.key), style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(e.value, style: const TextStyle(height: 1.6)),
                          ]),
                        ),
                    ]),
            ]);
          },
        ),
      ),
    );
  }

  static String _safeTitle(String tag) {
    try {
      return tagTitle(tag);
    } catch (_) {
      return tag;
    }
  }

  Future<void> _edit(BuildContext context, MyArg? a) async {
    final t = TextEditingController(text: a?.title ?? '');
    final x = TextEditingController(text: a?.text ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a == null ? 'حجة جديدة' : 'تعديل الحجة'),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: t, decoration: const InputDecoration(hintText: 'العنوان')),
            const SizedBox(height: 10),
            TextField(controller: x, maxLines: 10, minLines: 5, decoration: const InputDecoration(hintText: 'نص الحجة والأدلة')),
          ]),
        ),
        actions: [
          if (a != null)
            TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('حذف', style: TextStyle(color: C.red))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('حفظ')),
        ],
      ),
    );
    if (r == 'save' && t.text.trim().isNotEmpty) {
      AppState.I.saveArg(MyArg(a?.id ?? DateTime.now().microsecondsSinceEpoch.toString(), t.text.trim(), x.text.trim()));
    } else if (r == 'delete' && a != null) {
      AppState.I.deleteArg(a.id);
    }
  }
}

// ───────────────────────── Réglages ─────────────────────────

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final urlCtrl = TextEditingController(text: AppState.I.updateUrl);
  bool busy = false;

  @override
  void dispose() {
    urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    setState(() => busy = true);
    try {
      AppState.I.setUpdateUrl(urlCtrl.text);
      final r = await http.get(Uri.parse(AppState.I.updateUrl)).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final n = await AppData.installUpdate(r.body);
      AppState.I.contentChanged();
      if (mounted) toast(context, 'تم تحديث المحتوى: ${arNum(n)} حديثاً');
    } catch (e) {
      if (mounted) toast(context, 'تعذّر التحديث: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final d = AppData.I;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListenableBuilder(
        listenable: st,
        builder: (context, _) => ListView(padding: const EdgeInsets.only(bottom: 30), children: [
          const SectionHeader('حجم الخط', icon: Icons.format_size_rounded),
          AppCard(
            child: Column(children: [
              Slider(
                value: st.fontScale,
                min: 0.8,
                max: 1.6,
                divisions: 8,
                label: '${(st.fontScale * 100).round()}%',
                onChanged: st.setFontScale,
              ),
              Text('﴿ ${Brand.verse} ﴾', style: quranStyle.copyWith(fontSize: 19), textAlign: TextAlign.center),
            ]),
          ),
          const SectionHeader('المظهر', icon: Icons.palette_rounded),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('فاتح'), icon: Icon(Icons.light_mode_rounded)),
                ButtonSegment(value: ThemeMode.system, label: Text('تلقائي')),
                ButtonSegment(value: ThemeMode.dark, label: Text('داكن'), icon: Icon(Icons.dark_mode_rounded)),
              ],
              selected: {st.themeMode},
              onSelectionChanged: (v) => st.setTheme(v.first),
            ),
          ),
          const SectionHeader('تحديث المحتوى', icon: Icons.cloud_download_rounded),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                d.fromUpdate ? 'تستعمل الآن محتوى محدّثاً من الإنترنت.' : 'تستعمل المحتوى المدمج في البرنامج.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text('يجلب البرنامج أحدث نسخة من الأحاديث والردود والتناقضات من الرابط التالي:'),
              const SizedBox(height: 8),
              TextField(controller: urlCtrl, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync_rounded),
                    label: const Text('تحديث الآن'),
                    onPressed: busy ? null : _update,
                  ),
                ),
                if (d.fromUpdate) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      await AppData.resetUpdate();
                      st.contentChanged();
                    },
                    child: const Text('الرجوع للمدمج'),
                  ),
                ],
              ]),
            ]),
          ),
          const SectionHeader('عن البرنامج', icon: Icons.info_outline_rounded),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/brand/icon.png', width: 48, height: 48)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(Brand.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    Text('${Brand.tagline} — الإصدار 2.0'),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                'المحتوى: ${arNum(d.hadiths.length)} حديثاً، ${arNum(d.contradictions.length)} تناقضاً، '
                '${arNum(d.chains.length)} سلسلة، ${arNum(d.objections.length)} رداً، ${arNum(d.arguments.length)} حجة.\n\n'
                'المصادر:\n'
                '• نص القرآن: مشروع Tanzil (tanzil.net)، رواية حفص، بدون تعديل.\n'
                '• نصوص الأحاديث: مستخرجة آلياً من قواعد sunnah.com، والأرقام بترقيم موقع sunnah.com، وأحكام الألباني على أحاديث السنن.\n'
                '• لكل حديث رابطان للتحقق: بالرقم في sunnah.com، وبالنص في الدرر السنية.\n'
                '• الخطوط: Amiri و Tajawal (رخصة SIL OFL).\n\n'
                'نصيحة: تحقّق دائماً من المصدر قبل الاستشهاد في مناظرة علنية.',
                style: const TextStyle(height: 1.7),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
