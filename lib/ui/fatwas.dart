import 'package:flutter/material.dart';

import '../data.dart';
import 'common.dart';

const _fc = Color(0xFF8E3B5A);

/// Liste des fatwas, avec recherche et vue liste + détail sur grand écran.
class FatwasPage extends StatefulWidget {
  const FatwasPage({super.key});
  @override
  State<FatwasPage> createState() => _FatwasPageState();
}

class _FatwasPageState extends State<FatwasPage> {
  final ctrl = TextEditingController();
  String q = '';
  String? sel;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final w = queryWords(q);
    final list = w.isEmpty ? d.fatwas : d.fatwas.where((f) => scoreOf(f.kTitle, f.kBody, w) > 0).toList();
    final cur = sel ?? (list.isEmpty ? null : list.first.id);
    return Scaffold(
      appBar: AppBar(title: const Text('فتاوى تخالف القرآن والعقل')),
      body: MasterDetail(
        detail: cur == null ? null : FatwaDetail(d.fatwaById[cur]!, key: ValueKey(cur)),
        list: Column(children: [
          SearchField(controller: ctrl, hint: 'ابحث: فقيه، مذهب، موضوع…', onChanged: (v) => setState(() => q = v)),
          const _Warning(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 30),
              itemCount: list.length,
              itemBuilder: (context, i) => tileFor('f:${list[i].id}',
                  selected: splitView(context) && cur == list[i].id,
                  onTap: splitView(context) ? () => setState(() => sel = list[i].id) : null),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
        child: Text('أقوال فقهاء ومذاهب، لا إجماع. كل فتوى معها مصدرها: افتح المصدر قبل أن تستشهد بها.',
            style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class FatwaDetail extends StatelessWidget {
  final Fatwa f;
  const FatwaDetail(this.f, {super.key});

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('فتوى'),
        actions: detailActions(context,
            tag: 'f:${f.id}',
            text: d.fatwaToText(f),
            onImage: () => showShareImage(context, kind: 'فتوى', title: f.title, blocks: [
                  ShareBlock('${f.scholar} — ${f.source}', f.isQuote ? '«${f.quote}»' : f.quote),
                  ShareBlock('وجه المخالفة', f.comment, color: const Color(0xFFFFB4A9)),
                  ...versesBlocks(f.refs, max: 2),
                ])),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Text(f.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, height: 1.4)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            Pill(f.scholar, icon: Icons.person_rounded, color: _fc),
            Pill(f.madhab, icon: Icons.account_balance_rounded, color: s.tertiary),
          ]),
        ),
        ColoredBlock(
          label: f.isQuote ? 'النص من الكتاب' : 'خلاصة القول',
          text: f.isQuote ? '«${f.quote}»' : f.quote,
          color: _fc,
          icon: Icons.format_quote_rounded,
          style: f.isQuote ? hadithStyle : null,
        ),
        ColoredBlock(label: 'المصدر', text: f.source, color: s.outline, icon: Icons.menu_book_rounded),
        ColoredBlock(label: 'وجه المخالفة', text: f.comment, color: s.error, icon: Icons.report_rounded),
        if (f.refs.isNotEmpty) ...[
          const SectionHeader('ما يقوله القرآن', icon: Icons.auto_stories_rounded),
          for (final r in f.refs.where(isVerseRef)) VerseCard(r),
        ],
        if (f.related.isNotEmpty) ...[
          const SectionHeader('الأحاديث التي بُنيت عليها', icon: Icons.link_rounded),
          for (final t in f.related) tileFor('h:$t'),
        ],
        if (f.url.isNotEmpty) ...[
          const SectionHeader('التحقق من المصدر', icon: Icons.fact_check_rounded),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(Uri.tryParse(f.url)?.host ?? 'المصدر'),
                onPressed: () => openUrl(context, f.url),
              ),
            ),
          ),
        ],
        const SectionHeader('ملاحظتي', icon: Icons.edit_note_rounded),
        NoteSection('f:${f.id}'),
      ]),
    );
  }
}
