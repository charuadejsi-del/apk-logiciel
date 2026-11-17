import 'package:flutter/material.dart';

import '../data.dart';
import 'common.dart';

// ───────────────────────── Rapporteurs ─────────────────────────

class NarratorsPage extends StatelessWidget {
  const NarratorsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    final entries = d.byNarrator.entries.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('الرواة')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 30), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
          child: Text(
            'الصحابي الذي تنتهي إليه سلسلة الرواية، مستخرج آلياً من الإسناد. ما لم يتبيّن فيه الراوي بوضوح تُرك بلا نسبة.',
            style: TextStyle(color: s.onSurfaceVariant, height: 1.6),
          ),
        ),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 620 ? 2 : 1);
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final e in entries)
              SizedBox(
                width: (c.maxWidth - (cols - 1) * 10) / cols,
                child: AppCard(
                  margin: EdgeInsets.zero,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NarratorDetail(e.key))),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: C.goldPale,
                      child: Text(e.key.characters.first,
                          style: const TextStyle(color: C.goldDeep, fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('${arNum(e.value.length)} رواية في البرنامج • ${arNum(_contraCount(e.value))} تناقض',
                            style: TextStyle(color: s.onSurfaceVariant)),
                      ]),
                    ),
                    const Icon(Icons.chevron_left_rounded),
                  ]),
                ),
              ),
          ]);
        }),
      ]),
    );
  }

  static int _contraCount(List<Hadith> hs) {
    final d = AppData.I;
    final ids = hs.map((h) => h.id).toSet();
    return d.contradictions.where((c) => [...c.a, ...c.b].any(ids.contains)).length;
  }
}

class NarratorDetail extends StatelessWidget {
  final String name;
  const NarratorDetail(this.name, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final hs = d.byNarrator[name] ?? const <Hadith>[];
    final ids = hs.map((h) => h.id).toSet();
    final contras = d.contradictions.where((c) => [...c.a, ...c.b].any(ids.contains)).toList();
    final chains = d.chains.where((s) => s.steps.any((st) => st.refs.any(ids.contains))).toList();
    final cats = <String, int>{};
    for (final h in hs) {
      cats[h.cat] = (cats[h.cat] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: OrnateBanner(
            child: Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: C.gold,
                child: Text(name.characters.first,
                    style: const TextStyle(color: C.greenDark, fontWeight: FontWeight.w800, fontSize: 24)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      style: const TextStyle(fontFamily: 'Amiri', color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
                  Text('${arNum(hs.length)} رواية • ${arNum(contras.length)} تناقض • ${arNum(chains.length)} سلسلة',
                      style: const TextStyle(color: C.goldLight, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in cats.entries) Pill('${d.catTitle(e.key)} (${arNum(e.value)})', color: C.goldDeep),
          ]),
        ),
        if (contras.isNotEmpty) ...[
          const SectionHeader('تناقضات في رواياته', icon: Icons.compare_arrows_rounded),
          for (final c in contras) tileFor('c:${c.id}'),
        ],
        if (chains.isNotEmpty) ...[
          const SectionHeader('سلاسل تستعمل رواياته', icon: Icons.account_tree_rounded),
          for (final s in chains) tileFor('s:${s.id}'),
        ],
        const SectionHeader('رواياته في البرنامج', icon: Icons.menu_book_rounded),
        for (final h in hs) tileFor('h:${h.id}'),
      ]),
    );
  }
}

// ───────────────────────── Chronologie ─────────────────────────

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الخط الزمني')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
                child: Text(
                  'من نزول القرآن إلى تدوين كتب الحديث: بين وفاة النبي ووفاة البخاري نحو قرنين ونصف.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: s.onSurfaceVariant, fontSize: 15.5, height: 1.6),
                ),
              ),
              for (var i = 0; i < d.timeline.length; i++)
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(
                      width: 110,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(d.timeline[i].h, style: TextStyle(fontWeight: FontWeight.w800, color: s.primary, fontSize: 15)),
                          Text(d.timeline[i].g, style: TextStyle(color: s.onSurfaceVariant, fontSize: 12.5)),
                        ]),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Column(children: [
                        Container(width: 3, height: 18, color: i == 0 ? Colors.transparent : C.gold.withAlpha(120)),
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: i >= 8 ? C.amber : C.gold,
                            shape: BoxShape.circle,
                            border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                          ),
                        ),
                        Expanded(
                          child: Container(
                              width: 3, color: i == d.timeline.length - 1 ? Colors.transparent : C.gold.withAlpha(120)),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: AppCard(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d.timeline[i].title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
                          const SizedBox(height: 4),
                          Text(d.timeline[i].text, style: TextStyle(color: s.onSurfaceVariant, height: 1.6)),
                        ]),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ───────────────────────── Palette de commandes (Ctrl+K) ─────────────────────────

Future<void> showCommandPalette(BuildContext context) => showDialog(
      context: context,
      barrierColor: Colors.black38,
      builder: (ctx) => _Palette(host: context),
    );

class _Palette extends StatefulWidget {
  final BuildContext host;
  const _Palette({required this.host});
  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final ref = q.trim().isEmpty ? null : d.parseRefQuery(q);
    final hits = d.searchAll(q).take(30).toList();
    return Align(
      alignment: const Alignment(0, -0.6),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 760, maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => q = v),
                decoration: const InputDecoration(
                  hintText: 'ابحث في القضايا والتناقضات والسلاسل والأحاديث… أو 24:2',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 10), children: [
                if (ref != null) VerseCard(ref.key),
                for (final h in hits)
                  tileFor('${h.kind}:${h.id}', onTap: () {
                    Navigator.pop(context);
                    if (widget.host.mounted) openTag(widget.host, '${h.kind}:${h.id}');
                  }),
                if (q.trim().isNotEmpty && hits.isEmpty && ref == null) const EmptyState('لا توجد نتائج'),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
