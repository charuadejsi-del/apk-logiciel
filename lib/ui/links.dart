import 'package:flutter/material.dart';

import '../data.dart';
import 'common.dart';

/// Métadonnées d'affichage par type de lien.
(String, IconData, Color) linkStyle(String type, bool dark) => switch (type) {
      'q' || 'hq' => ('يخالف القرآن', Icons.auto_stories_rounded, dark ? const Color(0xFFFF8A80) : C.red),
      'hh' => ('يناقضه حديث', Icons.compare_arrows_rounded, dark ? const Color(0xFFFFB74D) : C.amber),
      'same' => ('روايات في صفّه', Icons.library_books_rounded, dark ? const Color(0xFF90CAF9) : const Color(0xFF1E5AA8)),
      's' => ('حلقة في سلسلة', Icons.account_tree_rounded, dark ? const Color(0xFF80CBC4) : C.greenLight),
      'k' => ('ملف قضية', Icons.folder_special_rounded, dark ? const Color(0xFFCE93D8) : const Color(0xFF6A3A9A)),
      _ => ('نفس الراوي', Icons.person_rounded, dark ? const Color(0xFFB0BEC5) : C.muted),
    };

/// Résumé chiffré + carte des liens d'un hadith.
class HadithLinkMap extends StatelessWidget {
  final Hadith h;
  const HadithLinkMap(this.h, {super.key});

  @override
  Widget build(BuildContext context) {
    final links = AppData.I.hadithLinks(h);
    if (links.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    int count(bool Function(HLink) f) => links.where(f).fold(0, (a, l) => a + (l.items.isEmpty ? 1 : l.items.length));
    final verses = links.where((l) => l.type == 'q' || l.type == 'hq').expand((l) => l.items).toSet().length;
    final summary = [
      if (verses > 0) ('q', '$verses آية تخالفه'),
      if (links.any((l) => l.type == 'hh')) ('hh', '${count((l) => l.type == 'hh')} حديث يناقضه'),
      if (links.any((l) => l.type == 's')) ('s', '${links.where((l) => l.type == 's').length} سلسلة'),
      if (links.any((l) => l.type == 'k')) ('k', '${links.where((l) => l.type == 'k').length} قضية'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('خريطة الربط', icon: Icons.hub_rounded),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in summary)
            Builder(builder: (context) {
              final st = linkStyle(x.$1, dark);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: st.$3.withAlpha(28),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: st.$3.withAlpha(90)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(st.$2, size: 15, color: st.$3),
                  const SizedBox(width: 6),
                  Text(x.$2, style: TextStyle(color: st.$3, fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
              );
            }),
        ]),
      ),
      // Tronc : chaque branche reliée par une ligne verticale au hadith.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(children: [
          for (var i = 0; i < links.length; i++) _Branch(link: links[i], last: i == links.length - 1),
        ]),
      ),
    ]);
  }
}

class _Branch extends StatelessWidget {
  final HLink link;
  final bool last;
  const _Branch({required this.link, required this.last});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = Theme.of(context).colorScheme;
    final st = linkStyle(link.type, dark);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 28,
          child: Column(children: [
            Container(width: 2, height: 14, color: s.outlineVariant),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: st.$3, shape: BoxShape.circle),
              child: Icon(st.$2, size: 14, color: Colors.white),
            ),
            Expanded(child: Container(width: 2, color: last ? Colors.transparent : s.outlineVariant)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(top: 6, bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: st.$3.withAlpha(dark ? 22 : 14),
              borderRadius: BorderRadius.circular(12),
              border: BorderDirectional(start: BorderSide(color: st.$3, width: 3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text(st.$1, style: TextStyle(color: st.$3, fontWeight: FontWeight.w800, fontSize: 12.5)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(link.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                if (link.open != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'فتح',
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    onPressed: () => openTag(context, link.open!),
                  ),
              ]),
              const SizedBox(height: 4),
              Text.rich(TextSpan(children: [
                TextSpan(text: 'وجه الربط: ', style: TextStyle(color: st.$3, fontWeight: FontWeight.w800)),
                TextSpan(text: link.why),
              ]), style: const TextStyle(height: 1.6)),
              if (link.chain != null) ...[const SizedBox(height: 8), _ChainPath(chain: link.chain!, step: link.step, color: st.$3)],
              for (final it in link.items) ...[const SizedBox(height: 8), _Item(it, color: st.$3)],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Un élément lié : verset (texte court) ou hadith (titre + référence), cliquable.
class _Item extends StatelessWidget {
  final String tag;
  final Color color;
  const _Item(this.tag, {required this.color});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    final verse = isVerseRef(tag);
    final hh = verse ? null : d.hadithById[tag];
    if (!verse && hh == null) return const SizedBox.shrink();
    return Material(
      color: s.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => openTag(context, verse ? 'v:$tag' : 'h:$tag'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: verse
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('﴿ ${d.verseTextS(tag)} ﴾', maxLines: 4, overflow: TextOverflow.ellipsis, style: quranStyle.copyWith(fontSize: 18)),
                  const SizedBox(height: 2),
                  Text(d.refLabelS(tag), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(hh!.title, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5)),
                  Text(hh.reference, style: TextStyle(color: s.onSurfaceVariant, fontSize: 12)),
                ]),
        ),
      ),
    );
  }
}

/// Position du hadith dans sa chaîne : étapes numérotées, étape courante en évidence.
class _ChainPath extends StatelessWidget {
  final Chain chain;
  final int step;
  final Color color;
  const _ChainPath({required this.chain, required this.step, required this.color});
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('الحلقة ${arNum(step + 1)} من ${arNum(chain.steps.length)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
      const SizedBox(height: 6),
      for (var i = 0; i < chain.steps.length; i++)
        if ((i - step).abs() <= 1)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: i == step ? color.withAlpha(40) : s.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${arNum(i + 1)}. ', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              Expanded(
                child: Text(
                  (i < step ? 'قبله: ' : i > step ? 'بعده: ' : 'هنا: ') + chain.steps[i].note,
                  maxLines: i == step ? 4 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: i == step ? FontWeight.w700 : FontWeight.w400, height: 1.5),
                ),
              ),
            ]),
          ),
      Text('الخلاصة: ${chain.conclusion}', maxLines: 3, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: s.onSurfaceVariant, fontSize: 13, height: 1.5)),
    ]);
  }
}
