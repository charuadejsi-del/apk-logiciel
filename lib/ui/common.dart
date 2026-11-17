import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../state.dart';
import 'pages.dart';
import 'pages2.dart';

// ───────────────────────── Thème ─────────────────────────

class C {
  static const green = Color(0xFF0F4D3A);
  static const greenDark = Color(0xFF0A3327);
  static const greenLight = Color(0xFF1F7A5C);
  static const gold = Color(0xFFC9A227);
  static const goldLight = Color(0xFFE9CF7A);
  static const cream = Color(0xFFF7F4EC);
  static const night = Color(0xFF0C1613);
  static const red = Color(0xFFB3261E);
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: C.green,
    brightness: b,
    primary: dark ? const Color(0xFF7FD1AE) : C.green,
    secondary: dark ? C.goldLight : const Color(0xFF9A7A12),
    surface: dark ? const Color(0xFF111E1A) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    fontFamily: 'Tajawal',
    scaffoldBackgroundColor: dark ? C.night : C.cream,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? C.night : C.cream,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Tajawal',
        fontWeight: FontWeight.w800,
        fontSize: 20,
        color: dark ? Colors.white : C.greenDark,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF17261F) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary, width: 2)),
    ),
  );
}

const quranStyle = TextStyle(fontFamily: 'Amiri', fontSize: 22, height: 2.0);
const hadithStyle = TextStyle(fontFamily: 'Amiri', fontSize: 18, height: 1.9);

String arNum(int n) => n.toString().split('').map((d) => '٠١٢٣٤٥٦٧٨٩'[int.parse(d)]).join();

bool isWide(BuildContext context) => MediaQuery.of(context).size.width >= 900;

// ───────────────────────── Actions ─────────────────────────

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

void copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  toast(context, 'تم النسخ — الصقه في المناظرة');
}

Future<void> shareText(BuildContext context, String text) async {
  try {
    await Share.share(text);
  } catch (_) {
    if (context.mounted) copyText(context, text);
  }
}

Future<void> openUrl(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) copyText(context, url);
}

/// Ouvre un élément à partir de son étiquette « type:id ».
void openTag(BuildContext context, String tag) {
  final i = tag.indexOf(':');
  final k = tag.substring(0, i), id = tag.substring(i + 1);
  final d = AppData.I;
  Widget? page;
  switch (k) {
    case 'o':
      final o = d.objectionById[id];
      if (o != null) page = ObjectionDetail(o);
    case 'h':
      final h = d.hadithById[id];
      if (h != null) page = HadithDetail(h);
    case 'c':
      final c = d.contraById[id];
      if (c != null) page = ContradictionDetail(c);
    case 's':
      final s = d.chainById[id];
      if (s != null) page = ChainDetail(s);
    case 'a':
      final a = d.argumentById[id];
      if (a != null) page = ArgumentDetail(a);
    case 'v':
      final r = VerseRef.parse(id);
      page = SurahReader(surah: r.surah, ayah: r.ayah);
  }
  if (page != null) Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
}

String tagTitle(String tag) {
  final i = tag.indexOf(':');
  final k = tag.substring(0, i), id = tag.substring(i + 1);
  final d = AppData.I;
  return switch (k) {
    'o' => d.objectionById[id]?.objection ?? id,
    'h' => d.hadithById[id]?.title ?? id,
    'c' => d.contraById[id]?.title ?? id,
    's' => d.chainById[id]?.title ?? id,
    'a' => d.argumentById[id]?.title ?? id,
    'v' => d.refLabelS(id),
    _ => id,
  };
}

const kindInfo = {
  'o': ('رد', Icons.forum_rounded),
  'h': ('حديث', Icons.menu_book_rounded),
  'c': ('تناقض', Icons.compare_arrows_rounded),
  's': ('سلسلة', Icons.account_tree_rounded),
  'a': ('حجة', Icons.verified_rounded),
  'v': ('آية', Icons.auto_stories_rounded),
};

// ───────────────────────── Composants ─────────────────────────

class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final Color? border;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.border,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? s.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border ?? s.outlineVariant.withAlpha(110)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Widget? trailing;
  const SectionHeader(this.text, {super.key, this.icon, this.trailing});
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 20, color: s.secondary), const SizedBox(width: 8)],
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: s.primary)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  const Pill(this.text, {super.key, this.color, this.icon});
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withAlpha(30), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 4)],
        Flexible(
          child: Text(text,
              style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5), overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyState(this.text, {super.key, this.icon = Icons.search_off_rounded});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ]),
      );
}

class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  const SearchField(
      {super.key, required this.controller, required this.hint, required this.onChanged, this.autofocus = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, v, _) => v.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      }),
            ),
          ),
        ),
      );
}

class FavButton extends StatelessWidget {
  final String tag;
  const FavButton(this.tag, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppState.I,
        builder: (context, _) {
          final f = AppState.I.isFav(tag);
          return IconButton(
            tooltip: f ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
            icon: Icon(f ? Icons.star_rounded : Icons.star_border_rounded,
                color: f ? Theme.of(context).colorScheme.secondary : null),
            onPressed: () => AppState.I.toggleFav(tag),
          );
        },
      );
}

/// Barre d'actions d'un détail : copier, partager le texte, partager une image, favori.
List<Widget> detailActions(BuildContext context,
    {required String tag, required String text, required VoidCallback onImage}) {
  return [
    FavButton(tag),
    IconButton(tooltip: 'نسخ', icon: const Icon(Icons.copy_rounded), onPressed: () => copyText(context, text)),
    IconButton(tooltip: 'مشاركة كنص', icon: const Icon(Icons.share_rounded), onPressed: () => shareText(context, text)),
    IconButton(tooltip: 'بطاقة صورة', icon: const Icon(Icons.image_rounded), onPressed: onImage),
  ];
}

class ColoredBlock extends StatelessWidget {
  final String label;
  final String text;
  final Color color;
  final IconData icon;
  final TextStyle? style;
  const ColoredBlock(
      {super.key, required this.label, required this.text, required this.color, required this.icon, this.style});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppCard(
      color: Color.alphaBlend(color.withAlpha(dark ? 40 : 22), Theme.of(context).colorScheme.surface),
      border: color.withAlpha(90),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        const SizedBox(height: 8),
        SelectableText(text, style: style ?? const TextStyle(fontSize: 16.5, height: 1.75)),
      ]),
    );
  }
}

class VerseCard extends StatelessWidget {
  final String r;
  final bool compact;
  const VerseCard(this.r, {super.key, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final s = Theme.of(context).colorScheme;
    final text = d.verseTextS(r);
    final label = d.refLabelS(r);
    return AppCard(
      margin: compact ? const EdgeInsets.symmetric(vertical: 4) : const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      onTap: () => openTag(context, 'v:$r'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('﴿ $text ﴾', style: quranStyle.copyWith(fontSize: compact ? 19 : 21), textAlign: TextAlign.justify),
        Row(children: [
          Icon(Icons.bookmark_rounded, size: 16, color: s.secondary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: s.secondary, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'نسخ الآية',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () => copyText(context, '﴿$text﴾ [$label]'),
          ),
        ]),
      ]),
    );
  }
}

/// Hadith en bloc dépliable (dans les contradictions et chaînes).
class HadithPanel extends StatefulWidget {
  final Hadith h;
  final bool initiallyOpen;
  const HadithPanel(this.h, {super.key, this.initiallyOpen = false});
  @override
  State<HadithPanel> createState() => _HadithPanelState();
}

class _HadithPanelState extends State<HadithPanel> {
  late bool open = widget.initiallyOpen;
  @override
  Widget build(BuildContext context) {
    final h = widget.h;
    final s = Theme.of(context).colorScheme;
    return AppCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      onTap: () => setState(() => open = !open),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.menu_book_rounded, size: 18, color: s.tertiary),
          const SizedBox(width: 6),
          Expanded(child: Text(h.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
          Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          Pill(h.reference, color: s.tertiary),
          if (h.grade.isNotEmpty) Pill(h.grade, color: s.secondary),
        ]),
        if (open) ...[
          const SizedBox(height: 8),
          SelectableText(h.text, style: hadithStyle.copyWith(fontSize: 17)),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('التفاصيل'),
              onPressed: () => openTag(context, 'h:${h.id}'),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Affiche une liste mixte de références (hadiths et versets).
class RefList extends StatelessWidget {
  final List<String> refs;
  final bool openFirst;
  const RefList(this.refs, {super.key, this.openFirst = false});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < refs.length; i++)
        if (isVerseRef(refs[i]))
          VerseCard(refs[i], compact: true)
        else if (d.hadithById[refs[i]] != null)
          HadithPanel(d.hadithById[refs[i]]!, initiallyOpen: openFirst && i == 0),
    ]);
  }
}

/// Tuile générique de résultat.
class ItemTile extends StatelessWidget {
  final String tag;
  final String title;
  final String? subtitle;
  final List<Widget> pills;
  final String? copy;
  const ItemTile({super.key, required this.tag, required this.title, this.subtitle, this.pills = const [], this.copy});
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final k = tag.substring(0, tag.indexOf(':'));
    final info = kindInfo[k]!;
    final color = switch (k) {
      'o' => s.error,
      'c' => const Color(0xFFB26A00),
      's' => s.primary,
      'h' => s.tertiary,
      _ => s.secondary,
    };
    return AppCard(
      onTap: () => openTag(context, tag),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(12)),
          child: Icon(info.$2, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, height: 1.4)),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: s.onSurfaceVariant, height: 1.5)),
            ],
            if (pills.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: pills),
            ],
          ]),
        ),
        if (copy != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'نسخ',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () => copyText(context, copy!),
          ),
      ]),
    );
  }
}

/// Tuile automatique à partir d'une étiquette.
Widget tileFor(String tag) {
  final i = tag.indexOf(':');
  final k = tag.substring(0, i), id = tag.substring(i + 1);
  final d = AppData.I;
  switch (k) {
    case 'o':
      final o = d.objectionById[id]!;
      return ItemTile(
          tag: tag,
          title: o.objection,
          subtitle: o.answer,
          pills: [Pill(d.topicTitle(o.topic))],
          copy: d.objectionToText(o));
    case 'h':
      final h = d.hadithById[id]!;
      return ItemTile(
          tag: tag,
          title: h.title,
          subtitle: h.comment,
          pills: [Pill(h.reference), Pill(d.catTitle(h.cat), color: const Color(0xFF7A5CC0))],
          copy: d.hadithToText(h));
    case 'c':
      final c = d.contraById[id]!;
      return ItemTile(
          tag: tag,
          title: c.title,
          subtitle: c.text,
          pills: [Pill(c.hadithVsHadith ? 'حديث ضد حديث' : 'حديث ضد آية', color: const Color(0xFFB26A00))],
          copy: d.contradictionToText(c));
    case 's':
      final s = d.chainById[id]!;
      return ItemTile(
          tag: tag,
          title: s.title,
          subtitle: s.summary.isNotEmpty ? s.summary : s.conclusion,
          pills: [Pill('${arNum(s.steps.length)} خطوات')],
          copy: d.chainToText(s));
    case 'a':
      final a = d.argumentById[id]!;
      return ItemTile(tag: tag, title: a.title, subtitle: a.text, copy: d.argumentToText(a));
  }
  return const SizedBox.shrink();
}

/// Section « ملاحظتي » éditable sur chaque élément.
class NoteSection extends StatelessWidget {
  final String tag;
  const NoteSection(this.tag, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppState.I,
        builder: (context, _) {
          final n = AppState.I.note(tag);
          return AppCard(
            onTap: () => editNote(context, tag),
            child: Row(children: [
              Icon(Icons.edit_note_rounded, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(n.isEmpty ? 'أضف ملاحظتك الخاصة…' : n,
                    style: TextStyle(
                        color: n.isEmpty ? Theme.of(context).colorScheme.outline : null, height: 1.6)),
              ),
            ]),
          );
        },
      );
}

Future<void> editNote(BuildContext context, String tag) async {
  final ctrl = TextEditingController(text: AppState.I.note(tag));
  final r = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('ملاحظتي'),
      content: SizedBox(
        width: 500,
        child: TextField(controller: ctrl, maxLines: 8, minLines: 4, autofocus: true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('حفظ')),
      ],
    ),
  );
  if (r != null) AppState.I.setNote(tag, r);
}

// ───────────────────────── Carte image partageable ─────────────────────────

class ShareBlock {
  final String label;
  final String text;
  final bool quran;
  final bool hadith;
  final Color? color;
  const ShareBlock(this.label, this.text, {this.quran = false, this.hadith = false, this.color});
}

class _ShareCardView extends StatelessWidget {
  final String kind;
  final String title;
  final List<ShareBlock> blocks;
  const _ShareCardView({required this.kind, required this.title, required this.blocks});
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: 440,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [C.greenDark, C.green], begin: Alignment.topRight, end: Alignment.bottomLeft),
        ),
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(20)),
              child: Text(kind,
                  style: const TextStyle(fontFamily: 'Tajawal', color: C.greenDark, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  fontFamily: 'Tajawal', color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.4)),
          const SizedBox(height: 14),
          for (final b in blocks)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(b.quran ? 30 : 18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: (b.color ?? C.goldLight).withAlpha(120)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (b.label.isNotEmpty)
                  Text(b.label,
                      style: TextStyle(
                          fontFamily: 'Tajawal', color: b.color ?? C.goldLight, fontWeight: FontWeight.w800, fontSize: 13.5)),
                if (b.label.isNotEmpty) const SizedBox(height: 4),
                Text(b.text,
                    style: TextStyle(
                      fontFamily: (b.quran || b.hadith) ? 'Amiri' : 'Tajawal',
                      color: Colors.white,
                      fontSize: b.quran ? 18 : 15,
                      height: b.quran || b.hadith ? 1.9 : 1.6,
                    )),
              ]),
            ),
          const SizedBox(height: 6),
          Row(children: [
            Image.asset('assets/brand/icon.png', width: 30, height: 30),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('${Brand.name} — ${Brand.tagline}',
                  style: TextStyle(fontFamily: 'Tajawal', color: C.goldLight, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ]),
        ]),
      ),
    );
  }
}

Future<void> showShareImage(BuildContext context,
    {required String kind, required String title, required List<ShareBlock> blocks}) async {
  final key = GlobalKey();
  await showDialog(
    context: context,
    builder: (dctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: FittedBox(
              child: RepaintBoundary(key: key, child: _ShareCardView(kind: kind, title: title, blocks: blocks)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                icon: Icon(Platform.isAndroid || Platform.isIOS ? Icons.share_rounded : Icons.save_alt_rounded),
                label: Text(Platform.isAndroid || Platform.isIOS ? 'مشاركة الصورة' : 'حفظ الصورة'),
                onPressed: () async {
                  final ok = await _exportCard(dctx, key);
                  if (ok && dctx.mounted) Navigator.pop(dctx);
                },
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('إغلاق')),
          ]),
        ),
      ]),
    ),
  );
}

Future<bool> _exportCard(BuildContext context, GlobalKey key) async {
  try {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 3);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    final name = 'hasbuna_${DateTime.now().millisecondsSinceEpoch}.png';
    if (Platform.isAndroid || Platform.isIOS) {
      await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'image/png', name: name)], text: Brand.name);
    } else {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      await f.writeAsBytes(bytes);
      if (context.mounted) toast(context, 'حُفظت الصورة في: ${f.path}');
      await launchUrl(Uri.file(dir.path));
    }
    return true;
  } catch (e) {
    if (context.mounted) toast(context, 'تعذّر إنشاء الصورة: $e');
    return false;
  }
}

List<ShareBlock> versesBlocks(List<String> refs, {int max = 3}) => refs
    .where(isVerseRef)
    .take(max)
    .map((r) => ShareBlock(AppData.I.refLabelS(r), '﴿${AppData.I.verseTextS(r)}﴾', quran: true))
    .toList();
