import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'state.dart';
import 'ui/common.dart';
import 'ui/pages.dart';
import 'ui/extra.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HasbunaApp());
}

class HasbunaApp extends StatefulWidget {
  const HasbunaApp({super.key});
  @override
  State<HasbunaApp> createState() => _HasbunaAppState();
}

class _HasbunaAppState extends State<HasbunaApp> {
  late final Future<void> _loading = _init();

  Future<void> _init() async {
    await AppState.I.load();
    await AppData.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) => MaterialApp(
        scrollBehavior: const _AppScroll(),
        title: Brand.name,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: AppState.I.themeMode,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(AppState.I.fontScale)),
            child: child!,
          ),
        ),
        home: FutureBuilder<void>(
          future: _loading,
          builder: (context, snap) {
            if (snap.hasError) {
              return Scaffold(body: Center(child: Text('خطأ في تحميل البيانات:\n${snap.error}')));
            }
            if (snap.connectionState != ConnectionState.done) return const Splash();
            return const Shell();
          },
        ),
      ),
    );
  }
}

class Splash extends StatelessWidget {
  const Splash({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [C.greenDark, C.green], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset('assets/brand/icon.png', width: 120, height: 120),
              ),
              const SizedBox(height: 20),
              const Text(Brand.name,
                  style: TextStyle(fontFamily: 'Amiri', color: C.goldLight, fontSize: 34, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(Brand.tagline, style: TextStyle(color: Colors.white70, fontSize: 15)),
              const SizedBox(height: 26),
              const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: C.goldLight, strokeWidth: 2.5)),
            ]),
          ),
        ),
      );
}

class Shell extends StatelessWidget {
  const Shell({super.key});

  static const groups = <(String, List<String>)>[
    ('', ['home', 'debate', 'cases']),
    ('المكتبة', ['contra', 'chains', 'hadiths', 'fatwas', 'objections', 'arguments']),
    ('الاستكشاف', ['narrators', 'timeline', 'quran', 'books']),
    ('أدواتي', ['training', 'favorites', 'mine', 'settings']),
  ];

  static const bottom = [
    ('home', 'الرئيسية', Icons.home_outlined, Icons.home_rounded),
    ('debate', 'المناظرة', Icons.bolt_outlined, Icons.bolt_rounded),
    ('cases', 'القضايا', Icons.folder_special_outlined, Icons.folder_special_rounded),
    ('quran', 'المصحف', Icons.auto_stories_outlined, Icons.auto_stories_rounded),
    ('more', 'المزيد', Icons.apps_outlined, Icons.apps_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => showCommandPalette(context),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => showCommandPalette(context),
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: AppState.I,
          builder: (context, _) => ValueListenableBuilder<String>(
            valueListenable: shellNav,
            builder: (context, current, _) {
              if (wide) {
                final all = [for (final g in groups) ...g.$2];
                final cur = all.contains(current) ? current : 'home';
                return Scaffold(
                  body: Row(children: [
                    _NavPane(current: cur),
                    Expanded(child: KeyedSubtree(key: ValueKey(cur), child: pageFor(cur))),
                  ]),
                );
              }
              final bIdx = bottom.indexWhere((b) => b.$1 == current);
              final sel = bIdx < 0 ? 0 : bIdx;
              return Scaffold(
                body: KeyedSubtree(key: ValueKey(bottom[sel].$1), child: pageFor(bottom[sel].$1)),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: sel,
                  onDestinationSelected: (i) => shellNav.value = bottom[i].$1,
                  destinations: [
                    for (final b in bottom) NavigationDestination(icon: Icon(b.$3), selectedIcon: Icon(b.$4), label: b.$2),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Volet de navigation façon Windows 11 (Fluent).
class _NavPane extends StatelessWidget {
  final String current;
  const _NavPane({required this.current});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = Theme.of(context).colorScheme;
    final d = AppData.I;
    final counts = <String, int>{
      'cases': d.cases.length,
      'contra': d.contradictions.length,
      'chains': d.chains.length,
      'hadiths': d.hadiths.length,
      'objections': d.objections.length,
      'arguments': d.arguments.length,
      'fatwas': d.fatwas.length,
      'narrators': d.byNarrator.length,
    };
    return Container(
      width: 270,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0D1D17) : C.ivoryPane,
        border: BorderDirectional(end: BorderSide(color: dark ? const Color(0xFF1C3329) : const Color(0xFFDDD5C1))),
      ),
      child: ListView(padding: const EdgeInsets.fromLTRB(10, 14, 10, 14), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset('assets/brand/icon.png', width: 36, height: 36)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(Brand.name, style: TextStyle(fontFamily: 'Amiri', fontWeight: FontWeight.w700, fontSize: 19)),
            ),
          ]),
        ),
        Material(
          color: dark ? const Color(0xFF12261E) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => showCommandPalette(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: dark ? const Color(0xFF1F3A2F) : const Color(0xFFDDD5C1)),
              ),
              child: Row(children: [
                Icon(Icons.search_rounded, size: 18, color: s.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text('ابحث في كل شيء', style: TextStyle(color: s.onSurfaceVariant, fontSize: 13))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      border: Border.all(color: dark ? const Color(0xFF2A4A3D) : const Color(0xFFDDD5C1)),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('Ctrl K', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 10.5, color: s.onSurfaceVariant)),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final g in Shell.groups) ...[
          if (g.$1.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
              child: Text(g.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: s.onSurfaceVariant)),
            ),
          for (final id in g.$2) _NavItem(id: id, selected: id == current, count: counts[id]),
        ],
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String id;
  final bool selected;
  final int? count;
  const _NavItem({required this.id, required this.selected, this.count});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = Theme.of(context).colorScheme;
    final info = sectionInfo[id]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? (dark ? const Color(0xFF17302A) : Colors.white) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => shellNav.value = id,
          child: SizedBox(
            height: 40,
            child: Row(children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                    color: selected ? s.primary : Colors.transparent, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Icon(info.$2, size: 19, color: s.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(info.$1,
                    style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
              ),
              if (count != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: Text(arNum(count!), style: TextStyle(fontSize: 12, color: s.onSurfaceVariant)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Sur Windows : glisser à la souris fait défiler les rangées horizontales.
class _AppScroll extends MaterialScrollBehavior {
  const _AppScroll();
  @override
  Set<PointerDeviceKind> get dragDevices =>
      {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus};
}
