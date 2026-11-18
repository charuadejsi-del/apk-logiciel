import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'data.dart';
import 'state.dart';
import 'ui/common.dart';

/// Une version publiée sur GitHub Releases.
class ReleaseInfo {
  final int build;
  final String tag, notes, page;
  final String? apk, windows, content;
  ReleaseInfo(this.build, this.tag, this.notes, this.page, this.apk, this.windows, this.content);

  String? get download => Platform.isAndroid ? apk : (Platform.isWindows ? windows : page);
}

/// Mise à jour automatique : contenu silencieux + avis de nouvelle version du programme.
class Updater {
  /// Numéro de build injecté par la CI (--dart-define=BUILD=...). 0 en développement.
  static const build = appBuild;
  static const repo = 'charuadejsi-del/apk-logiciel';
  static const _api = 'https://api.github.com/repos/$repo/releases?per_page=5';
  static bool _checkedThisRun = false;

  static String get versionLabel => build == 0 ? 'نسخة تطوير' : 'v2.0.$build';

  static Future<ReleaseInfo?> latest() async {
    final r = await http
        .get(Uri.parse(_api), headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    for (final x in (jsonDecode(r.body) as List)) {
      if (x['draft'] == true) continue;
      final tag = (x['tag_name'] ?? '') as String;
      final b = int.tryParse(tag.split('.').last) ?? 0;
      String? asset(String name) {
        for (final a in (x['assets'] as List? ?? const [])) {
          if (a['name'] == name) return a['browser_download_url'] as String?;
        }
        return null;
      }

      return ReleaseInfo(b, tag, (x['body'] ?? '') as String, (x['html_url'] ?? '') as String,
          asset('hasbuna-android.apk'), asset('hasbuna-windows.zip'), asset('content.json'));
    }
    return null;
  }

  /// Télécharge et installe le contenu d'une version plus récente que celui en cours.
  static Future<bool> updateContent(ReleaseInfo rel) async {
    if (rel.content == null || rel.build <= AppData.contentBuild) return false;
    final r = await http.get(Uri.parse(rel.content!)).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) return false;
    final c = AppData.parseContent(r.body);
    final schema = (c['schema'] as num?)?.toInt() ?? 2;
    if (schema > AppData.contentSchema) return false; // contenu prévu pour un programme plus récent
    await AppData.installUpdate(r.body, build: rel.build);
    AppState.I.contentChanged();
    return true;
  }

  /// Vérification au démarrage (au plus toutes les 6 heures).
  static Future<void> checkOnStart(BuildContext context) async {
    final st = AppState.I;
    if (_checkedThisRun || !st.autoUpdate) return;
    _checkedThisRun = true;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - st.lastUpdateCheck < const Duration(hours: 6).inMilliseconds) return;
    try {
      final rel = await latest();
      st.setLastUpdateCheck(now);
      if (rel == null) return;
      final got = await updateContent(rel);
      if (got && context.mounted) toast(context, 'تم تحديث المحتوى تلقائياً (${rel.tag})');
      if (build > 0 && rel.build > build && rel.build != st.skipBuild && context.mounted) {
        await showUpdateDialog(context, rel);
      }
    } catch (_) {
      // Pas de réseau : on réessaiera au prochain démarrage.
    }
  }

  /// Vérification manuelle depuis les réglages.
  static Future<void> checkNow(BuildContext context) async {
    try {
      final rel = await latest();
      AppState.I.setLastUpdateCheck(DateTime.now().millisecondsSinceEpoch);
      if (!context.mounted) return;
      if (rel == null) {
        toast(context, 'لا توجد إصدارات منشورة بعد');
        return;
      }
      final got = await updateContent(rel);
      if (!context.mounted) return;
      if (build > 0 && rel.build > build) {
        await showUpdateDialog(context, rel);
      } else {
        toast(context, got ? 'تم تحديث المحتوى (${rel.tag})' : 'البرنامج والمحتوى محدّثان (${rel.tag})');
      }
    } catch (e) {
      if (context.mounted) {
        toast(context, 'تعذّر الاتصال بخادم التحديث. تأكد من الإنترنت ومن أن المستودع عام.');
      }
    }
  }

  static Future<void> showUpdateDialog(BuildContext context, ReleaseInfo rel) => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.system_update_rounded, size: 36),
          title: Text('إصدار جديد: ${rel.tag}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('نسختك الحالية: $versionLabel'),
              if (rel.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('الجديد:', style: TextStyle(fontWeight: FontWeight.w800)),
                Text(rel.notes.trim(), style: const TextStyle(height: 1.6)),
              ],
              const SizedBox(height: 10),
              Text(
                Platform.isAndroid
                    ? 'سيُحمَّل ملف APK، ثم افتحه واضغط «تثبيت».'
                    : 'سيُحمَّل ملف ZIP؛ فكّه مكان النسخة القديمة.',
                style: TextStyle(fontSize: 12.5, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () {
                AppState.I.setSkipBuild(rel.build);
                Navigator.pop(ctx);
              },
              child: const Text('تخطّي هذا الإصدار'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لاحقاً')),
            FilledButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: const Text('تحميل'),
              onPressed: () {
                Navigator.pop(ctx);
                openUrl(context, rel.download ?? rel.page);
              },
            ),
          ],
        ),
      );
}

/// Lance la vérification automatique une fois l'interface affichée.
class StartupUpdateCheck extends StatefulWidget {
  final Widget child;
  const StartupUpdateCheck({super.key, required this.child});
  @override
  State<StartupUpdateCheck> createState() => _StartupUpdateCheckState();
}

class _StartupUpdateCheckState extends State<StartupUpdateCheck> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Updater.checkOnStart(context);
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
