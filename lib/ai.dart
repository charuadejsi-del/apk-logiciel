import 'dart:convert';

import 'package:http/http.dart' as http;

import 'data.dart';
import 'state.dart';

/// Fournisseur d'IA : format OpenAI (compatible) ou Anthropic.
class AiProvider {
  final String id, name, base, defaultModel;
  final bool anthropic, free, json;
  final List<String> preferred; // modèles préférés, dans l'ordre (gratuits d'abord)
  final int maxHadith, clip, maxVerses; // taille de la requête adaptée aux limites du fournisseur
  const AiProvider(this.id, this.name, this.base, this.defaultModel,
      {this.anthropic = false,
      this.free = false,
      this.json = true,
      this.preferred = const [],
      this.maxHadith = 40,
      this.clip = 600,
      this.maxVerses = 18});
}

const aiProviders = [
  AiProvider('groq', 'Groq', 'https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile',
      free: true,
      preferred: [
        'llama-3.3-70b-versatile',
        'openai/gpt-oss-120b',
        'qwen/qwen3-32b',
        'meta-llama/llama-4-maverick-17b-128e-instruct',
        'meta-llama/llama-4-scout-17b-16e-instruct',
        'openai/gpt-oss-20b',
        'llama-3.1-8b-instant',
      ],
      maxHadith: 18,
      clip: 350,
      maxVerses: 10),
  AiProvider('gemini', 'Google Gemini', 'https://generativelanguage.googleapis.com/v1beta/openai', 'gemini-2.5-flash',
      free: true,
      preferred: ['gemini-2.5-flash', 'gemini-flash-latest', 'gemini-2.0-flash', 'gemini-2.5-flash-lite', 'gemini-flash-lite-latest'],
      maxHadith: 45,
      clip: 700,
      maxVerses: 20),
  AiProvider('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1', 'meta-llama/llama-3.3-70b-instruct:free',
      free: true,
      json: false,
      preferred: [
        'meta-llama/llama-3.3-70b-instruct:free',
        'deepseek/deepseek-chat-v3-0324:free',
        'qwen/qwen-2.5-72b-instruct:free',
        'google/gemini-2.0-flash-exp:free',
      ],
      maxHadith: 25,
      clip: 450,
      maxVerses: 12),
  AiProvider('anthropic', 'Claude (Anthropic)', 'https://api.anthropic.com/v1', 'claude-sonnet-5-5',
      anthropic: true, json: false, preferred: ['claude-sonnet-5-5', 'claude-haiku-5-5']),
  AiProvider('openai', 'OpenAI', 'https://api.openai.com/v1', 'gpt-4.1-mini', preferred: ['gpt-4.1-mini', 'gpt-4o-mini']),
  AiProvider('deepseek', 'DeepSeek', 'https://api.deepseek.com', 'deepseek-chat', preferred: ['deepseek-chat']),
];

AiProvider providerById(String id) => aiProviders.firstWhere((p) => p.id == id, orElse: () => aiProviders.first);

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
  final String key;
  final List<String> models; // modèle principal puis modèles de repli
  String get model => models.first;
  AiClient(this.p, this.key, this.models);

  static AiClient? fromSettings() {
    final st = AppState.I;
    if (st.aiKey.isEmpty) return null;
    final p = providerById(st.aiProvider.isNotEmpty ? st.aiProvider : detectProvider(st.aiKey));
    final main = st.aiModel.isEmpty ? p.defaultModel : st.aiModel;
    return AiClient(p, st.aiKey, [main, ...st.aiFallback.where((m) => m != main)]);
  }

  Map<String, String> get _headers => p.anthropic
      ? {'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'}
      : {
          'Authorization': 'Bearer $key',
          'content-type': 'application/json',
          if (p.id == 'openrouter') 'X-Title': 'Hasbuna',
        };

  static String _apiMsg(http.Response r) {
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final e = j is List ? j.first['error'] : j['error'];
      return e is Map ? '${e['message'] ?? ''}' : '${e ?? ''}';
    } catch (_) {
      return '';
    }
  }

  String _err(http.Response r) {
    final msg = _apiMsg(r);
    final hint = switch (r.statusCode) {
      401 || 403 => 'المفتاح غير صالح أو موقوف. انسخه من جديد من موقع ${p.name} والصقه.',
      402 => 'لا يوجد رصيد في حسابك عند ${p.name}.',
      404 => 'النموذج غير متاح في حسابك.',
      413 => 'الطلب أكبر من حدّ الخطة المجانية.',
      429 => 'تجاوزت الحد المجاني عند ${p.name}. انتظر دقيقة (أو حتى الغد إن كان الحد اليومي) ثم أعد المحاولة.',
      _ => 'خطأ من خادم ${p.name}.',
    };
    return '$hint (HTTP ${r.statusCode})${msg.isEmpty ? '' : '\n$msg'}';
  }

  Future<http.Response> _post(String model, String system, String user, bool json) {
    if (p.anthropic) {
      return http
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
    }
    return http
        .post(Uri.parse('${p.base}/chat/completions'),
            headers: _headers,
            body: jsonEncode({
              'model': model,
              'temperature': 0.2,
              if (json) 'response_format': {'type': 'json_object'},
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
            }))
        .timeout(const Duration(seconds: 120));
  }

  /// Envoie la requête ; en cas d'échec : sans JSON, attente courte, puis modèle de repli suivant.
  Future<String> chat(String system, String user, {bool wantJson = false}) async {
    http.Response? last;
    for (final m in models.take(4)) {
      var json = wantJson && p.json;
      for (var attempt = 0; attempt < 3; attempt++) {
        final r = await _post(m, system, user, json);
        if (r.statusCode == 200) {
          final j = jsonDecode(utf8.decode(r.bodyBytes));
          final text = p.anthropic
              ? (j['content'] as List).where((c) => c['type'] == 'text').map((c) => c['text']).join()
              : '${j['choices']?[0]?['message']?['content'] ?? ''}';
          if (text.trim().isNotEmpty) return text;
          break; // réponse vide : modèle suivant
        }
        last = r;
        if (r.statusCode == 401 || r.statusCode == 403 || r.statusCode == 402) throw AiException(_err(r));
        if (r.statusCode == 400 && json) {
          json = false; // le modèle n'accepte pas le mode JSON : on réessaie sans
          continue;
        }
        if (r.statusCode == 429 && attempt == 0) {
          final wait = int.tryParse(r.headers['retry-after'] ?? '') ?? 8;
          if (wait <= 20) {
            await Future.delayed(Duration(seconds: wait));
            continue;
          }
        }
        break; // 404, 413, 429 long, 5xx : modèle suivant
      }
    }
    throw AiException(last == null ? 'لا يوجد نموذج يعمل.' : _err(last));
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

/// Résultat de la configuration automatique.
class AiSetup {
  final bool ok;
  final String message;
  AiSetup(this.ok, this.message);
}

/// Configuration en un geste : fournisseur détecté, modèle gratuit choisi, test réel.
Future<AiSetup> autoSetup(String key) async {
  final st = AppState.I;
  key = key.trim();
  if (key.length < 20) return AiSetup(false, 'المفتاح قصير جداً. انسخه كاملاً.');
  final id = detectProvider(key);
  if (id.isEmpty && st.aiProvider.isEmpty) {
    return AiSetup(false, 'لم أتعرّف على نوع المفتاح. اختر المزوّد من «خيارات متقدمة».');
  }
  final p = providerById(id.isNotEmpty ? id : st.aiProvider);
  final probe = AiClient(p, key, [p.defaultModel]);

  // 1) Modèles disponibles sur ce compte
  List<String> available = [];
  try {
    available = await probe.listModels();
  } on AiException catch (e) {
    if (e.message.contains('HTTP 401') || e.message.contains('HTTP 403')) {
      return AiSetup(false, e.message);
    }
  } catch (_) {
    return AiSetup(false, 'تعذّر الاتصال بـ ${p.name}. تأكد من الإنترنت.');
  }

  // 2) Choix : modèles préférés présents sur le compte, puis (OpenRouter) tout modèle « :free »
  final avail = available.toSet();
  final chosen = <String>[
    ...p.preferred.where((m) => avail.isEmpty || avail.contains(m)),
    if (p.id == 'openrouter') ...available.where((m) => m.endsWith(':free') && !p.preferred.contains(m)),
  ];
  if (chosen.isEmpty && available.isNotEmpty) {
    // Aucun modèle préféré sur ce compte : modèles de texte disponibles (sans audio, image, embeddings, garde).
    final bad = RegExp(r'whisper|tts|embed|guard|vision|image|audio|moderation|distil|playai|orpheus|compound', caseSensitive: false);
    final text = available.where((m) => !bad.hasMatch(m)).toList()
      ..sort((a, b) => (b.contains('70b') || b.contains('flash') ? 1 : 0).compareTo(a.contains('70b') || a.contains('flash') ? 1 : 0));
    chosen.addAll(p.id == 'openrouter' ? text.where((m) => m.endsWith(':free')) : text);
  }
  if (chosen.isEmpty) chosen.addAll(p.preferred.isEmpty ? [p.defaultModel] : p.preferred);

  // 3) Test réel, avec repli automatique
  final c = AiClient(p, key, chosen);
  for (var i = 0; i < chosen.length && i < 5; i++) {
    final cl = AiClient(p, key, [chosen[i]]);
    try {
      await cl.chat('أجب بكلمة واحدة.', 'قل: يعمل');
      final fb = chosen.where((m) => m != chosen[i]).take(3).toList();
      final msg = '✅ جاهز — ${p.name} · ${chosen[i]}${p.free ? ' (مجاني)' : ' — ⚠️ مزوّد مدفوع: كل بحث يُخصم من رصيدك'}';
      st.setAi(key: key, provider: p.id, model: chosen[i], fallback: fb, status: msg);
      return AiSetup(true, msg);
    } on AiException catch (e) {
      if (e.message.contains('HTTP 401') || e.message.contains('HTTP 403') || e.message.contains('HTTP 402')) {
        return AiSetup(false, e.message);
      }
      if (i == chosen.length - 1 || i == 4) return AiSetup(false, e.message);
    } catch (_) {
      return AiSetup(false, 'تعذّر الاتصال بـ ${p.name}. تأكد من الإنترنت.');
    }
  }
  return AiSetup(false, 'لا يوجد نموذج يعمل بهذا المفتاح (${c.models.length} نموذجاً جُرّب).');
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
  final j1 = extractJson(await ai.chat(_sys1, question, wantJson: true));
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
      for (var i = 0; i < list.length && n < (ai.p.maxHadith < 25 ? 6 : 12); i++) {
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
  final top = [
    ...hadiths.take(ai.p.maxHadith),
    ...(verses.values.toList()..sort((a, b) => b.score.compareTo(a.score))).take(ai.p.maxVerses)
  ];
  if (top.isEmpty) {
    throw AiException('لم يجد البحث نصوصاً مطابقة في الكتب. أعد صياغة السؤال بكلمات أخرى.');
  }

  progress('٣/٤ قراءة ${top.length} نصاً وتصنيفها…');
  String clip(String t) => t.length <= ai.p.clip ? t : '…${t.substring(t.length - ai.p.clip)}';
  final buf = StringBuffer('السؤال: $question\nالدعوى: $claim\n\nالنصوص:\n');
  for (final c in top) {
    buf.writeln('[${c.id}] (${c.label}) ${clip(c.fullText)}');
  }
  final j2 = extractJson(await ai.chat(_sys2, buf.toString(), wantJson: true));
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
