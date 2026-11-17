import 'package:flutter/material.dart';

import 'data.dart';
import 'state.dart';
import 'ui/common.dart';
import 'ui/pages.dart';

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

  static const railIds = [
    'home', 'debate', 'objections', 'contra', 'chains', 'hadiths', 'arguments', 'quran', 'books', 'training',
    'favorites', 'mine', 'settings',
  ];

  static const bottom = [
    ('home', 'الرئيسية', Icons.home_outlined, Icons.home_rounded),
    ('debate', 'المناظرة', Icons.bolt_outlined, Icons.bolt_rounded),
    ('library', 'المكتبة', Icons.collections_bookmark_outlined, Icons.collections_bookmark_rounded),
    ('quran', 'القرآن', Icons.auto_stories_outlined, Icons.auto_stories_rounded),
    ('more', 'المزيد', Icons.apps_outlined, Icons.apps_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return ListenableBuilder(
      listenable: AppState.I, // reconstruit après mise à jour du contenu
      builder: (context, _) => ValueListenableBuilder<String>(
        valueListenable: shellNav,
        builder: (context, current, _) {
          if (wide) {
            final idx = railIds.indexOf(current);
            final sel = idx < 0 ? 0 : idx;
            final extended = MediaQuery.of(context).size.width >= 1250;
            return Scaffold(
              body: Row(children: [
                SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        extended: extended,
                        minExtendedWidth: 230,
                        selectedIndex: sel,
                        onDestinationSelected: (i) => shellNav.value = railIds[i],
                        labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                        leading: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Column(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset('assets/brand/icon.png', width: 48, height: 48),
                            ),
                            if (extended) ...[
                              const SizedBox(height: 8),
                              const Text(Brand.name,
                                  style: TextStyle(fontFamily: 'Amiri', fontWeight: FontWeight.w700, fontSize: 19)),
                            ],
                          ]),
                        ),
                        destinations: [
                          for (final id in railIds)
                            NavigationRailDestination(
                              icon: Icon(sectionInfo[id]!.$2),
                              label: Text(sectionInfo[id]!.$1),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: KeyedSubtree(key: ValueKey(railIds[sel]), child: pageFor(railIds[sel]))),
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
    );
  }
}
