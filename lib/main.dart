import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';

final ValueNotifier<double> fontScale = ValueNotifier(1.0);
final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

const String appName = 'مُناظِر';
const String appTagline = 'القرآن وحده';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MunazirApp());
}

String arNum(int n) =>
    n.toString().split('').map((d) => '٠١٢٣٤٥٦٧٨٩'[int.parse(d)]).join();

void copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('تم النسخ — الصقه في المناظرة')));
}

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0F5132),
    brightness: b,
    secondary: const Color(0xFFB8860B),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    visualDensity: VisualDensity.standard,
  );
}

class MunazirApp extends StatefulWidget {
  const MunazirApp({super.key});
  @override
  State<MunazirApp> createState() => _MunazirAppState();
}

class _MunazirAppState extends State<MunazirApp> {
  late final Future<void> _loading = AppData.load();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => ValueListenableBuilder<double>(
        valueListenable: fontScale,
        builder: (context, scale, _) => MaterialApp(
          title: appName,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: mode,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: FutureBuilder<void>(
            future: _loading,
            builder: (context, snap) {
              if (snap.hasError) {
                return Scaffold(body: Center(child: Text('خطأ في تحميل البيانات:\n${snap.error}')));
              }
              if (snap.connectionState != ConnectionState.done) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              return const HomeShell();
            },
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Shell ─────────────────────────────

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  static const pages = <Widget>[
    DebatePage(),
    ObjectionsPage(),
    HadithsPage(),
    QuranPage(),
    ArgumentsPage(),
  ];

  static const dests = [
    (Icons.bolt_outlined, Icons.bolt, 'المناظرة'),
    (Icons.forum_outlined, Icons.forum, 'الردود'),
    (Icons.menu_book_outlined, Icons.menu_book, 'الأحاديث'),
    (Icons.auto_stories_outlined, Icons.auto_stories, 'القرآن'),
    (Icons.verified_outlined, Icons.verified, 'الحجج'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    final body = IndexedStack(index: index, children: pages);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Icon(Icons.shield_moon, size: 36, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 4),
                const Text(appName, style: TextStyle(fontWeight: FontWeight.bold)),
              ]),
            ),
            destinations: [
              for (final d in dests)
                NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          for (final d in dests)
            NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}

List<Widget> commonActions(BuildContext context) => [
      IconButton(
        tooltip: 'الإعدادات',
        icon: const Icon(Icons.tune),
        onPressed: () => showSettings(context),
      ),
    ];

void showSettings(BuildContext context) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('حجم الخط', style: Theme.of(context).textTheme.titleMedium),
          ValueListenableBuilder<double>(
            valueListenable: fontScale,
            builder: (context, v, _) => Slider(
              value: v,
              min: 0.8,
              max: 1.8,
              divisions: 10,
              label: '${(v * 100).round()}%',
              onChanged: (x) => fontScale.value = x,
            ),
          ),
          const SizedBox(height: 8),
          Text('المظهر', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeMode,
            builder: (context, m, _) => SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('فاتح'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.system, label: Text('تلقائي')),
                ButtonSegment(value: ThemeMode.dark, label: Text('داكن'), icon: Icon(Icons.dark_mode)),
              ],
              selected: {m},
              onSelectionChanged: (s) => themeMode.value = s.first,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: const Text('عن البرنامج والمصادر'),
            onTap: () {
              Navigator.pop(context);
              showAbout(context);
            },
          ),
        ]),
      ),
    ),
  );
}

void showAbout(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('$appName — $appTagline'),
        content: const SingleChildScrollView(
          child: Text(
            'أداة لتحضير المناظرات والرد على من يقدّمون الروايات على كتاب الله.\n\n'
            'المصادر:\n'
            '• نص القرآن الكريم: مشروع Tanzil (tanzil.net) — رواية حفص، النص البسيط المشكول، بدون أي تعديل.\n'
            '• نصوص الأحاديث: مستخرجة آلياً من موقع sunnah.com (قاعدة hadith-json).\n'
            '• أرقام الأحاديث بالترقيم المعتمد في موقع sunnah.com، ولكل حديث رابط للتحقق.\n\n'
            'نصيحة: تحقّق دائماً من الرابط قبل الاستشهاد في مناظرة علنية.',
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
      ),
    ),
  );
}

// ───────────────────────────── Shared widgets ─────────────────────────────

class SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  const SearchBox(
      {super.key, required this.controller, required this.hint, required this.onChanged, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String text;
  final IconData? icon;
  const SectionHeader(this.text, {super.key, this.icon});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 20, color: c.primary), const SizedBox(width: 8)],
        Expanded(
          child: Text(text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.primary, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}

class VerseCard extends StatelessWidget {
  final VerseRef r;
  const VerseCard(this.r, {super.key});

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final c = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => SurahReaderPage(surah: r.surah, ayah: r.ayah))),
        onLongPress: () => copyText(context, '﴿${d.verseText(r)}﴾ [${d.refLabel(r)}]'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('﴿ ${d.verseText(r)} ﴾',
                style: const TextStyle(fontSize: 20, height: 1.9), textAlign: TextAlign.justify),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.bookmark, size: 16, color: c.secondary),
              const SizedBox(width: 4),
              Text(d.refLabel(r), style: TextStyle(color: c.secondary, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'نسخ الآية',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => copyText(context, '﴿${d.verseText(r)}﴾ [${d.refLabel(r)}]'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class ColoredBlock extends StatelessWidget {
  final String label;
  final String text;
  final Color bg, fg;
  final IconData icon;
  const ColoredBlock(
      {super.key, required this.label, required this.text, required this.bg, required this.fg, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: bg,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          SelectableText(text, style: TextStyle(color: fg, fontSize: 17, height: 1.7)),
        ]),
      ),
    );
  }
}

// ───────────────────────────── 1. Debate mode ─────────────────────────────

class DebatePage extends StatefulWidget {
  const DebatePage({super.key});
  @override
  State<DebatePage> createState() => _DebatePageState();
}

class _DebatePageState extends State<DebatePage> {
  final ctrl = TextEditingController();
  String q = '';

  static const quick = [
    'الصلاة', 'طاعة الرسول', 'الحكمة', 'البيان', 'الحفظ', 'الإسناد', 'الرجم', 'الردة',
    'الشفاعة', 'عائشة', 'السحر', 'الغيب', 'الإجماع', 'النسخ', 'الميراث', 'المرأة',
  ];

  void setQuery(String v) {
    ctrl.text = v;
    ctrl.selection = TextSelection.collapsed(offset: v.length);
    setState(() => q = v);
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final w = AppData.words(q);
    final ref = q.trim().isEmpty ? null : d.parseRefQuery(q);
    final objs = w.isEmpty ? d.objections : d.objections.where((o) => AppData.matches(o.key, w)).toList();
    final hads = w.isEmpty ? <Hadith>[] : d.hadiths.where((h) => AppData.matches(h.key, w)).toList();
    final args = w.isEmpty ? <Argument>[] : d.arguments.where((a) => AppData.matches(a.key, w)).toList();
    final verses = (w.isEmpty || ref != null) ? <VerseRef>[] : d.searchQuran(q, limit: 30);
    final nothing = w.isNotEmpty && ref == null && objs.isEmpty && hads.isEmpty && args.isEmpty && verses.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('وضع المناظرة'), actions: commonActions(context)),
      body: Column(children: [
        SearchBox(
          controller: ctrl,
          hint: 'اكتب اعتراض المحاور أو كلمة… أو رقم آية مثل 6:38',
          onChanged: (v) => setState(() => q = v),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final k in quick)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ActionChip(label: Text(k), onPressed: () => setQuery(k)),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            if (ref != null) ...[const SectionHeader('الآية', icon: Icons.bookmark), VerseCard(ref)],
            if (nothing)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('لا توجد نتائج. جرّب كلمة أخرى أو أقصر.')),
              ),
            if (objs.isNotEmpty) ...[
              SectionHeader(w.isEmpty ? 'كل الاعتراضات وردودها' : 'الردود الجاهزة (${objs.length})',
                  icon: Icons.forum),
              for (final o in objs) ObjectionTile(o),
            ],
            if (hads.isNotEmpty) ...[
              SectionHeader('الأحاديث (${hads.length})', icon: Icons.menu_book),
              for (final h in hads) HadithTile(h),
            ],
            if (args.isNotEmpty) ...[
              SectionHeader('الحجج (${args.length})', icon: Icons.verified),
              for (final a in args) ArgumentTile(a),
            ],
            if (verses.isNotEmpty) ...[
              SectionHeader('آيات فيها «${q.trim()}»', icon: Icons.auto_stories),
              for (final v in verses) VerseCard(v),
              if (verses.length >= 30)
                TextButton.icon(
                  icon: const Icon(Icons.expand_more),
                  label: const Text('المزيد في صفحة القرآن'),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => QuranSearchPage(query: q))),
                ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────────── 2. Objections ─────────────────────────────

class ObjectionTile extends StatelessWidget {
  final Objection o;
  const ObjectionTile(this.o, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: c.errorContainer,
            child: Icon(Icons.record_voice_over, color: c.onErrorContainer, size: 20)),
        title: Text(o.objection, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(o.answer, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          tooltip: 'نسخ الرد',
          icon: const Icon(Icons.copy),
          onPressed: () => copyText(context, AppData.I.objectionToText(o)),
        ),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ObjectionDetailPage(o))),
      ),
    );
  }
}

class ObjectionsPage extends StatelessWidget {
  const ObjectionsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    return Scaffold(
      appBar: AppBar(title: const Text('الاعتراضات والردود'), actions: commonActions(context)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        for (final t in d.topics) ...[
          SectionHeader(t.title, icon: Icons.label),
          for (final o in d.objections.where((o) => o.topic == t.id)) ObjectionTile(o),
        ],
      ]),
    );
  }
}

class ObjectionDetailPage extends StatelessWidget {
  final Objection o;
  const ObjectionDetailPage(this.o, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(AppData.I.topicTitle(o.topic)), actions: [
        IconButton(
            tooltip: 'نسخ الرد كاملاً',
            icon: const Icon(Icons.copy_all),
            onPressed: () => copyText(context, AppData.I.objectionToText(o))),
      ]),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        ColoredBlock(
            label: 'يقولون',
            text: o.objection,
            bg: c.errorContainer,
            fg: c.onErrorContainer,
            icon: Icons.record_voice_over),
        ColoredBlock(
            label: 'الرد', text: o.answer, bg: c.primaryContainer, fg: c.onPrimaryContainer, icon: Icons.check_circle),
        const SectionHeader('الأدلة من القرآن', icon: Icons.auto_stories),
        for (final r in o.refs) VerseCard(r),
      ]),
    );
  }
}

// ───────────────────────────── 3. Hadiths ─────────────────────────────

class HadithTile extends StatelessWidget {
  final Hadith h;
  const HadithTile(this.h, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: c.tertiaryContainer, child: Icon(Icons.menu_book, color: c.onTertiaryContainer, size: 20)),
        title: Text(h.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${h.reference} • ${AppData.I.catTitle(h.cat)}'),
        trailing: IconButton(
          tooltip: 'نسخ',
          icon: const Icon(Icons.copy),
          onPressed: () => copyText(context, AppData.I.hadithToText(h)),
        ),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HadithDetailPage(h))),
      ),
    );
  }
}

class HadithsPage extends StatefulWidget {
  const HadithsPage({super.key});
  @override
  State<HadithsPage> createState() => _HadithsPageState();
}

class _HadithsPageState extends State<HadithsPage> {
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
    final w = AppData.words(q);
    final list = d.hadiths
        .where((h) => (cat == null || h.cat == cat) && (w.isEmpty || AppData.matches(h.key, w)))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('مراجع الأحاديث'), actions: commonActions(context)),
      body: Column(children: [
        SearchBox(controller: ctrl, hint: 'ابحث في الأحاديث…', onChanged: (v) => setState(() => q = v)),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                    label: Text('الكل (${d.hadiths.length})'),
                    selected: cat == null,
                    onSelected: (_) => setState(() => cat = null)),
              ),
              for (final c in d.hcats)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                      label: Text(c.title),
                      selected: cat == c.id,
                      onSelected: (_) => setState(() => cat = cat == c.id ? null : c.id)),
                ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('لا توجد نتائج'))
              : ListView(
                  padding: const EdgeInsets.only(top: 6, bottom: 24),
                  children: [for (final h in list) HadithTile(h)],
                ),
        ),
      ]),
    );
  }
}

class HadithDetailPage extends StatelessWidget {
  final Hadith h;
  const HadithDetailPage(this.h, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(AppData.I.catTitle(h.cat)), actions: [
        IconButton(
            tooltip: 'نسخ الحديث مع الرد',
            icon: const Icon(Icons.copy_all),
            onPressed: () => copyText(context, AppData.I.hadithToText(h))),
      ]),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(h.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            Chip(avatar: const Icon(Icons.library_books, size: 18), label: Text(h.book)),
            Chip(avatar: const Icon(Icons.tag, size: 18), label: Text('رقم ${h.number}')),
            if (h.chapter.isNotEmpty) Chip(label: Text(h.chapter)),
          ]),
        ),
        ColoredBlock(
            label: 'نص الرواية',
            text: h.text,
            bg: c.surfaceContainerHighest,
            fg: c.onSurface,
            icon: Icons.format_quote),
        ColoredBlock(
            label: 'وجه الاعتراض',
            text: h.comment,
            bg: c.errorContainer,
            fg: c.onErrorContainer,
            icon: Icons.report),
        const SectionHeader('ما يقوله القرآن', icon: Icons.auto_stories),
        for (final r in h.refs) VerseCard(r),
        const SectionHeader('التحقق من المصدر', icon: Icons.fact_check),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            title: SelectableText(h.url, textDirection: TextDirection.ltr),
            subtitle: const Text('الرقم بترقيم موقع sunnah.com — افتح الرابط وقارن النص'),
            trailing: IconButton(
                icon: const Icon(Icons.copy), tooltip: 'نسخ الرابط', onPressed: () => copyText(context, h.url)),
          ),
        ),
      ]),
    );
  }
}

// ───────────────────────────── 4. Quran ─────────────────────────────

class QuranPage extends StatefulWidget {
  const QuranPage({super.key});
  @override
  State<QuranPage> createState() => _QuranPageState();
}

class _QuranPageState extends State<QuranPage> {
  final ctrl = TextEditingController();
  String q = '';

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = AppData.I;
    final ref = q.trim().isEmpty ? null : d.parseRefQuery(q);
    final nq = norm(q);
    final surahHits = nq.isEmpty ? d.surahs : d.surahs.where((s) => norm(s.name).contains(nq)).toList();
    final verses = (nq.length < 2 || ref != null) ? <VerseRef>[] : d.searchQuran(q);
    return Scaffold(
      appBar: AppBar(title: const Text('القرآن الكريم'), actions: commonActions(context)),
      body: Column(children: [
        SearchBox(
            controller: ctrl,
            hint: 'ابحث بكلمة، أو اسم سورة، أو رقم آية (2:255)',
            onChanged: (v) => setState(() => q = v)),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            if (ref != null) VerseCard(ref),
            if (nq.isNotEmpty && surahHits.isNotEmpty) const SectionHeader('السور', icon: Icons.list),
            for (final s in surahHits) SurahTile(s),
            if (verses.isNotEmpty) ...[
              SectionHeader('الآيات (${verses.length >= 200 ? '+200' : verses.length})', icon: Icons.auto_stories),
              for (final v in verses) VerseCard(v),
            ],
          ]),
        ),
      ]),
    );
  }
}

class SurahTile extends StatelessWidget {
  final Surah s;
  const SurahTile(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: Text(arNum(s.n), style: const TextStyle(fontSize: 13))),
      title: Text('سورة ${s.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${s.meccan ? 'مكية' : 'مدنية'} • ${arNum(s.ayat.length)} آية'),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SurahReaderPage(surah: s.n))),
    );
  }
}

class QuranSearchPage extends StatelessWidget {
  final String query;
  const QuranSearchPage({super.key, required this.query});
  @override
  Widget build(BuildContext context) {
    final verses = AppData.I.searchQuran(query, limit: 1000);
    return Scaffold(
      appBar: AppBar(title: Text('«$query» — ${verses.length} آية')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [for (final v in verses) VerseCard(v)],
      ),
    );
  }
}

class SurahReaderPage extends StatelessWidget {
  final int surah;
  final int ayah;
  const SurahReaderPage({super.key, required this.surah, this.ayah = 1});

  @override
  Widget build(BuildContext context) {
    final s = AppData.I.surah(surah);
    final start = (ayah - 1).clamp(0, s.ayat.length - 1).toInt();
    final c = Theme.of(context).colorScheme;
    const centerKey = ValueKey('center');
    final hasBasmala = surah != 1 && surah != 9;

    Widget verse(int i) {
      final highlight = ayah > 1 && i == start;
      final text = s.ayat[i];
      final ref = VerseRef(surah, i + 1);
      return InkWell(
        onLongPress: () => copyText(context, '﴿$text﴾ [${AppData.I.refLabel(ref)}]'),
        child: Container(
          color: highlight ? c.secondaryContainer : null,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: text),
              TextSpan(
                  text: '  ﴿${arNum(i + 1)}﴾',
                  style: TextStyle(color: c.secondary, fontWeight: FontWeight.bold)),
            ]),
            style: const TextStyle(fontSize: 22, height: 2.0),
            textAlign: TextAlign.justify,
          ),
        ),
      );
    }

    final header = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        Text('سورة ${s.name}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: c.primary, fontWeight: FontWeight.bold)),
        Text('${s.meccan ? 'مكية' : 'مدنية'} • ${arNum(s.ayat.length)} آية'),
        if (hasBasmala) ...[
          const SizedBox(height: 10),
          const Text('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ', style: TextStyle(fontSize: 24)),
        ],
        const Divider(indent: 40, endIndent: 40),
      ]),
    );

    return Scaffold(
      appBar: AppBar(title: Text('سورة ${s.name}'), actions: [
        if (start > 0)
          IconButton(
            tooltip: 'من بداية السورة',
            icon: const Icon(Icons.vertical_align_top),
            onPressed: () => Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => SurahReaderPage(surah: surah))),
          ),
      ]),
      body: CustomScrollView(
        center: centerKey,
        slivers: [
          // Partie au-dessus du verset ciblé (construite vers le haut).
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, k) => k < start ? verse(start - 1 - k) : header,
              childCount: start == 0 ? 0 : start + 1,
            ),
          ),
          SliverList(
            key: centerKey,
            delegate: SliverChildBuilderDelegate(
              (context, k) => start == 0 ? (k == 0 ? header : verse(k - 1)) : verse(start + k),
              childCount: s.ayat.length - start + (start == 0 ? 1 : 0),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

// ───────────────────────────── 5. Arguments ─────────────────────────────

class ArgumentTile extends StatelessWidget {
  final Argument a;
  const ArgumentTile(this.a, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: c.primaryContainer, child: Icon(Icons.verified, color: c.onPrimaryContainer, size: 20)),
        title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(a.text, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
            tooltip: 'نسخ',
            icon: const Icon(Icons.copy),
            onPressed: () => copyText(context, AppData.I.argumentToText(a))),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArgumentDetailPage(a))),
      ),
    );
  }
}

class ArgumentsPage extends StatelessWidget {
  const ArgumentsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حجج القرآن وحده'), actions: commonActions(context)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [for (final a in AppData.I.arguments) ArgumentTile(a)],
      ),
    );
  }
}

class ArgumentDetailPage extends StatelessWidget {
  final Argument a;
  const ArgumentDetailPage(this.a, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(a.title), actions: [
        IconButton(
            tooltip: 'نسخ',
            icon: const Icon(Icons.copy_all),
            onPressed: () => copyText(context, AppData.I.argumentToText(a))),
      ]),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        ColoredBlock(
            label: 'الحجة', text: a.text, bg: c.primaryContainer, fg: c.onPrimaryContainer, icon: Icons.verified),
        const SectionHeader('الآيات', icon: Icons.auto_stories),
        for (final r in a.refs) VerseCard(r),
      ]),
    );
  }
}
