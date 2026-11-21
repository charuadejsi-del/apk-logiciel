import 'dart:convert';

import 'package:http/http.dart' as http;

import 'data.dart';
import 'state.dart';

/// Fournisseur d'IA : format OpenAI (compatible) ou Anthropic.
class AiProvider {
  final String id, name, base, defaultModel;
  final bool anthropic;
  const AiProvider(this.id, this.name, this.base, this.defaultModel, {this.anthropic = false});
}

const aiProviders = [
  AiProvider('gemini', 'Google Gemini', 'https://generativelanguage.googleapis.com/v1beta/openai', 'gemini-2.5-flash'),
  AiProvider('anthropic', 'Claude (Anthropic)', 'https://api.anthropic.com/v1', 'claude-sonnet-5-5', anthropic: true),
  AiProvider('openai', 'OpenAI', 'https://api.openai.com/v1', 'gpt-4.1-mini'),
  AiProvider('groq', 'Groq', 'https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile'),
  AiProvider('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1', 'openai/gpt-4.1-mini'),
  AiProvider('deepseek', 'DeepSeek', 'https://api.deepseek.com', 'deepseek-chat'),
];

/// Devine le fournisseur à partir du préfixe de la clé.
String detectProvider(String key) {
  final k = key.trim();
  if (k.startsWith('sk-ant-')) return 'anthropic';
  if (k.startsWith('AIza')) return 'gemini';
  if (k.startsWith('gsk_')) return 'groq';
  if (k.startsWith('sk-or-')) return 'openrouter';
  if (k.startsWith('sk-')) return 'openai';
  return '';
}

class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}

class AiClient {
  final AiProvider p;
  final String key, model;
  AiClient(this.p, this.key, this.model);

  static AiClient? fromSettings() {
    final st = AppState.I;
    if (st.aiKey.isEmpty) return null;
    final id = st.aiProvider.isNotEmpty ? st.aiProvider : detectProvider(st.aiKey);
    final p = aiProviders.firstWhere((x) => x.id == id, orElse: () => aiProviders.first);
    return AiClient(p, st.aiKey, st.aiModel.isEmpty ? p.defaultModel : st.aiModel);
  }

  Map<String, String> get _headers => p.anthropic
      ? {'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'}
      : {'Authorization': 'Bearer $key', 'content-type': 'application/json'};

  String _err(http.Response r) {
    var msg = '';
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final e = j is List ? j.first['error'] : j['error'];
      msg = e is Map ? '${e['message'] ?? ''}' : '$e';
    } catch (_) {}
    final hint = switch (r.statusCode) {
      401 || 403 => 'المفتاح غير صالح أو لا يملك الصلاحية.',
      404 => 'اسم النموذج غير موجود عند هذا المزوّد. اضغط «جلب النماذج» واختر واحداً.',
      429 => 'تجاوزت الحد المسموح (أو انتهى الرصيد). انتظر قليلاً ثم أعد المحاولة.',
      _ => 'خطأ من خادم الذكاء الاصطناعي.',
    };
    return '$hint (HTTP ${r.statusCode})${msg.isEmpty ? '' : '\n$msg'}';
  }

  Future<String> chat(String system, String user) async {
    final http.Response r;
    if (p.anthropic) {
      r = await http
          .post(Uri.parse('${p.base}/messages'),
              headers: _headers,
              body: jsonEncode({
                'model': model,
                'max_tokens': 4000,
                'system': system,
                'messages': [
                  {'role': 'user', 'content': user}
                ],
              }))
          .timeout(const Duration(seconds: 120));
    } else {
      r = await http
          .post(Uri.parse('${p.base}/chat/completions'),
              headers: _headers,
              body: jsonEncode({
                'model': model,
                'temperature': 0.2,
                'messages': [
                  {'role': 'system', 'content': system},
                  {'role': 'user', 'content': user},
                ],
              }))
          .timeout(const Duration(seconds: 120));
    }
    if (r.statusCode != 200) throw AiException(_err(r));
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (p.anthropic) {
      return ((j['content'] as List).where((c) => c['type'] == 'text').map((c) => c['text']).join());
    }
    return '${j['choices'][0]['message']['content'] ?? ''}';
  }

  Future<List<String>> listModels() async {
    final r = await http.get(Uri.parse('${p.base}/models'), headers: _headers).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw AiException(_err(r));
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final list = (j['data'] ?? j['models'] ?? const []) as List;
    return list.map((m) => '${m['id'] ?? m['name'] ?? ''}'.replaceFirst('models/', '')).where((s) => s.isNotEmpty).toList()
      ..sort();
  }
}

/// Extrait le premier objet JSON d'une réponse (tolère ```json … ```).
Map<String, dynamic> extractJson(String s) {
  final a = s.indexOf('{'), b = s.lastIndexOf('}');
  if (a < 0 || b <= a) throw AiException('ردّ الذكاء الاصطناعي ليس بالصيغة المطلوبة. أعد المحاولة.');
  return jsonDecode(s.substring(a, b + 1)) as Map<String, dynamic>;
}

// ───────────────────────── Recherche assistée ─────────────────────────

/// Candidat trouvé localement : hadith d'un livre ou verset.
class Candidate {
  final String id; // b12, m40, t7, q2:255
  final String book; // bukhari, muslim, tabari, quran
  final BookHadith? h;
  final VerseRef? v;
  int score = 0;
  Candidate(this.id, this.book, {this.h, this.v});

  String get label => v != null ? AppData.I.refLabel(v!) : '${Books.names[book]} — ${h!.ref}';
  String get fullText => v != null ? AppData.I.verseText(v!) : h!.text;
}

class AiPick {
  final Candidate c;
  final String why;
  AiPick(this.c, this.why);
}

class AiResult {
  final String question, claim, summary;
  final List<List<String>> queries;
  final List<AiPick> answer, contra, verses;
  final int searched;
  AiResult(this.question, this.claim, this.summary, this.queries, this.answer, this.contra, this.verses, this.searched);
}

const _sys1 = '''أنت باحث في الحديث والقرآن. مهمتك تحويل سؤال المستخدم إلى كلمات بحث نصية تُستعمل للبحث الحرفي في متون صحيح البخاري وصحيح مسلم وفي القرآن.
أجب بـ JSON فقط بهذا الشكل:
{"claim": "الدعوى المسؤول عنها في جملة واحدة",
 "hadith_queries": [["كلمة","كلمة"], ...],
 "quran_queries": ["كلمة أو عبارة", ...]}
قواعد:
- من 4 إلى 8 استعلامات للحديث. كل استعلام قائمة من كلمة إلى ثلاث كلمات يجب أن تجتمع في المتن، بلا تشكيل، بألفاظ الحديث القديمة كما ترد في المتون (مثل: الغيب، يعلم، ادري، الساعه).
- غطِّ الجانبين: ألفاظ الروايات التي تثبت الدعوى وألفاظ الروايات التي تنفيها.
- من 3 إلى 6 استعلامات للقرآن بألفاظ قرآنية بلا تشكيل.
- لا تكتب أي نص خارج JSON.''';

const _sys2 = '''أنت باحث دقيق في نقد الحديث بمنهج عرضه على القرآن. ستُعطى سؤالاً وقائمة نصوص مرقّمة بمعرّفات (b… للبخاري، m… لمسلم، t… للطبري، q… للآيات).
صنّف النصوص ذات الصلة فقط، وأجب بـ JSON فقط:
{"answer": [{"id": "...", "why": "..."}],
 "contra": [{"id": "...", "why": "..."}],
 "verses": [{"id": "...", "why": "..."}],
 "summary": "خلاصة من سطرين أو ثلاثة"}
- answer: روايات تجيب عن السؤال وتثبت الدعوى.
- contra: روايات تناقض روايات answer أو تنفي الدعوى.
- verses: آيات تخالف ما تقوله روايات answer، أو تبيّن موقف القرآن من المسألة.
- why: جملة عربية واحدة قصيرة تشرح وجه الإثبات أو التناقض، معتمدة على النص المعطى فقط.
- استعمل المعرّفات الموجودة في القائمة فقط، ولا تخترع نصاً ولا رقماً. اترك القائمة فارغة إن لم تجد شيئاً.
- لا تكتب أي نص خارج JSON.''';

/// Lance la recherche complète. [progress] reçoit les étapes à afficher.
Future<AiResult> aiResearch(String question, void Function(String) progress) async {
  final ai = AiClient.fromSettings();
  if (ai == null) throw AiException('أضف مفتاح الذكاء الاصطناعي من الإعدادات أولاً.');
  final d = AppData.I;

  progress('١/٤ فهم السؤال وتحويله إلى كلمات بحث…');
  final j1 = extractJson(await ai.chat(_sys1, question));
  final claim = '${j1['claim'] ?? question}';
  final hq = ((j1['hadith_queries'] ?? const []) as List)
      .map((q) => (q is List ? q : [q]).map((w) => norm('$w')).where((w) => w.length > 1).toList())
      .where((q) => q.isNotEmpty)
      .take(8)
      .toList();
  final qq = ((j1['quran_queries'] ?? const []) as List).map((w) => '$w').where((w) => w.trim().isNotEmpty).take(6).toList();

  progress('٢/٤ البحث في نصوص الكتب داخل البرنامج…');
  final books = <String>['bukhari', 'muslim', if (AppState.I.aiTabari) 'tabari'];
  final cands = <String, Candidate>{};
  for (final b in books) {
    final list = await Books.load(b);
    final prefix = b[0];
    for (final q in hq) {
      var n = 0;
      for (var i = 0; i < list.length && n < 12; i++) {
        final h = list[i];
        if (q.every(h.key.contains)) {
          final id = '$prefix$i';
          (cands[id] ??= Candidate(id, b, h: h)).score += 1;
          n++;
        }
      }
    }
  }
  final verses = <String, Candidate>{};
  for (final q in qq) {
    for (final v in d.searchQuran(q, limit: 8)) {
      final id = 'q${v.key}';
      (verses[id] ??= Candidate(id, 'quran', v: v)).score += 1;
    }
  }
  final hadiths = cands.values.toList()..sort((a, b) => b.score.compareTo(a.score));
  final top = [...hadiths.take(45), ...(verses.values.toList()..sort((a, b) => b.score.compareTo(a.score))).take(20)];
  if (top.isEmpty) {
    throw AiException('لم يجد البحث نصوصاً مطابقة في الكتب. أعد صياغة السؤال بكلمات أخرى.');
  }

  progress('٣/٤ قراءة ${top.length} نصاً وتصنيفها…');
  String clip(String t) => t.length <= 700 ? t : '…${t.substring(t.length - 700)}';
  final buf = StringBuffer('السؤال: $question\nالدعوى: $claim\n\nالنصوص:\n');
  for (final c in top) {
    buf.writeln('[${c.id}] (${c.label}) ${clip(c.fullText)}');
  }
  final j2 = extractJson(await ai.chat(_sys2, buf.toString()));
  final byId = {for (final c in top) c.id: c};

  progress('٤/٤ التحقق من المعرّفات…');
  List<AiPick> picks(String k, {required bool quran}) {
    final out = <AiPick>[];
    final seen = <String>{};
    for (final x in (j2[k] ?? const []) as List) {
      final id = '${x is Map ? x['id'] : x}'.trim();
      final c = byId[id];
      if (c == null || seen.contains(id) || (c.v != null) != quran) continue; // rejeté : inventé ou mal classé
      seen.add(id);
      out.add(AiPick(c, '${x is Map ? (x['why'] ?? '') : ''}'));
    }
    return out;
  }

  return AiResult(question, claim, '${j2['summary'] ?? ''}', hq, picks('answer', quran: false), picks('contra', quran: false),
      picks('verses', quran: true), top.length);
}
