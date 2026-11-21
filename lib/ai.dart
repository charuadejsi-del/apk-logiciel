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

/// Candidat trouvé localement : hadith d'un livre, hadith annoté, ou verset.
class Candidate {
  final String id; // b12, m40, t7, h55, q2:255
  final String book; // bukhari, muslim, tabari, annot, quran
  final BookHadith? h;
  final VerseRef? v;
  final String? labelOverride, note;
  int score = 0;
  Candidate(this.id, this.book, {this.h, this.v, this.labelOverride, this.note});

  String get label => labelOverride ?? (v != null ? AppData.I.refLabel(v!) : '${Books.names[book] ?? book} — ${h!.ref}');
  String get fullText => v != null ? AppData.I.verseText(v!) : h!.text;
}

class AiPick {
  final Candidate c;
  final String why;
  AiPick(this.c, this.why);
}

class AiUnderstanding {
  final String understood, claim, yes, no;
  AiUnderstanding(this.understood, this.claim, this.yes, this.no);
}

class AiResult {
  final String question, claim, summary;
  final List<List<String>> queries;
  final List<AiPick> answer, contra, verses;
  final int searched, rounds;
  AiResult(this.question, this.claim, this.summary, this.queries, this.answer, this.contra, this.verses, this.searched,
      this.rounds);
}

/// Contexte permanent : à quoi sert l'application et qui pose les questions.
const _ctx = 'سياق ثابت: هذا برنامج «حسبنا كتاب الله»، أداة مناظرة لمسلم قرآني يكتفي بالقرآن، يناظر أهل الحديث.\n'
    'المستخدم يكتب أسئلة قصيرة جداً أو بالعامية الجزائرية أو بالفرنسية المخلوطة أو بأخطاء إملائية.\n'
    'هدفه دائماً: إيجاد روايات البخاري ومسلم المتعلقة بالمسألة، وما يناقضها من روايات أخرى، والآيات التي تخالفها.\n'
    'افهم قصده لا ألفاظه: «الإيمان غصبا» تعني الإكراه على الدين بالقتال، «يقتلو اللي يخرج من الدين» تعني حد الردة، '
    '«عايشة شحال كان عمرها» تعني سن عائشة عند الزواج.\n';

const _sysU = '${_ctx}مهمتك الآن: فهم سؤال المستخدم فقط. أجب بـ JSON فقط:\n'
    '{"understood": "إعادة صياغة السؤال بالعربية الفصحى الواضحة كما يقصده المستخدم، في جملة أو جملتين",\n'
    ' "claim": "الدعوى المسؤول عنها في جملة قصيرة",\n'
    ' "yes_side": "ما الذي تقوله الروايات المثبتة",\n'
    ' "no_side": "ما الذي ينفيها من روايات أو آيات"}';

const _sysQ = '${_ctx}أنت عالم بمتون صحيحي البخاري ومسلم. للسؤال المعطى:\n'
    '1) تذكّر الأحاديث الحقيقية التي تعرفها في هذا المعنى من الجانبين (المثبتة والنافية)، حتى 12 حديثاً.\n'
    '2) لكل حديث أعطِ من 1 إلى 3 عبارات قصيرة (كلمتان إلى أربع كلمات) منقولة حرفياً من متنه كما ترد في الكتب، بلا تشكيل، مميزة له.\n'
    '   مثال: حديث «أمرت أن أقاتل الناس حتى يقولوا لا إله إلا الله» ← عباراته: "اقاتل الناس"، "حتى يشهدوا".\n'
    '   لا تستعمل ألفاظ السؤال الحديثة (يجبر، قسر، غصب…) إلا إن وردت فعلاً في المتن.\n'
    '3) أعطِ 3 إلى 6 عبارات قرآنية بألفاظ الآيات المناسبة.\n'
    'أجب بـ JSON فقط:\n'
    '{"hadiths": [{"about": "وصف قصير للحديث", "side": "yes أو no", "phrases": ["...", "..."]}],\n'
    ' "quran": ["...", "..."]}';

const _sys2 = '${_ctx}أنت باحث دقيق في نقد الحديث بعرضه على القرآن. ستُعطى السؤال كما فهمناه وقائمة نصوص بمعرّفات\n'
    '(b… البخاري، m… مسلم، t… الطبري، h… أحاديث مشروحة في البرنامج، q… آيات).\n'
    'صنّف النصوص ذات الصلة فقط، وأجب بـ JSON فقط:\n'
    '{"answer": [{"id": "...", "why": "..."}],\n'
    ' "contra": [{"id": "...", "why": "..."}],\n'
    ' "verses": [{"id": "...", "why": "..."}],\n'
    ' "summary": "خلاصة من سطرين مبنية على النصوص المختارة فقط"}\n'
    '- answer: روايات تثبت الدعوى أو تجيب عن السؤال.\n'
    '- contra: روايات تناقض روايات answer أو تنفي الدعوى.\n'
    '- verses: آيات تخالف روايات answer أو تبيّن موقف القرآن.\n'
    '- why: جملة عربية واحدة قصيرة تشرح وجه الإثبات أو التناقض من النص المعطى.\n'
    '- لا تستعمل إلا المعرّفات المعطاة، ولا تخترع نصاً ولا رقماً. لا تقل «لا توجد روايات» عن شيء لم يُعطَ لك.';

/// Étape 1 : comprendre l'intention (montrée à l'utilisateur pour validation).
Future<AiUnderstanding> aiUnderstand(String question) async {
  final ai = AiClient.fromSettings();
  if (ai == null) throw AiException('أضف مفتاح الذكاء الاصطناعي من الإعدادات أولاً.');
  final j = extractJson(await ai.chat(_sysU, question, wantJson: true));
  return AiUnderstanding('${j['understood'] ?? question}', '${j['claim'] ?? ''}', '${j['yes_side'] ?? ''}',
      '${j['no_side'] ?? ''}');
}

/// Étapes suivantes : rappel des hadiths, recherche locale, classement, second tour si rien.
Future<AiResult> aiResearch(String question, String understood, void Function(String) progress) async {
  final ai = AiClient.fromSettings();
  if (ai == null) throw AiException('أضف مفتاح الذكاء الاصطناعي من الإعدادات أولاً.');
  final d = AppData.I;
  final books = <String>['bukhari', 'muslim', if (AppState.I.aiTabari) 'tabari'];
  final lists = {for (final b in books) b: await Books.load(b)};
  final perPhrase = ai.p.maxHadith < 25 ? 2 : 4;
  final cands = <String, Candidate>{};
  final verses = <String, Candidate>{};
  final allQueries = <List<String>>[];

  // Contenu déjà vérifié de l'application (hadiths annotés, contradictions) correspondant au sens.
  void addCurated(String text) {
    for (final hit in d.searchAll(text).take(12)) {
      final ids = <String>[];
      if (hit.kind == 'h') ids.add(hit.id);
      if (hit.kind == 'c') {
        final c = d.contraById[hit.id];
        if (c != null) {
          ids.addAll([...c.a, ...c.b].where((x) => !isVerseRef(x)));
          for (final r in [...c.a, ...c.b].where(isVerseRef)) {
            final v = VerseRef.parse(r);
            (verses['q${v.key}'] ??= Candidate('q${v.key}', 'quran', v: v)).score += 2;
          }
        }
      }
      for (final id in ids) {
        final h = d.hadithById[id];
        if (h == null) continue;
        (cands[id] ??= Candidate(id, 'annot',
                h: BookHadith(int.tryParse(h.number) ?? 0, h.text, norm(h.text)), labelOverride: h.reference, note: h.title))
            .score += 2;
      }
    }
  }

  Future<void> searchRound(String prompt) async {
    final j = extractJson(await ai.chat(_sysQ, prompt, wantJson: true));
    for (final x in (j['hadiths'] ?? const []) as List) {
      final phrases = ((x is Map ? x['phrases'] : null) ?? const []) as List;
      for (final ph in phrases.take(3)) {
        final q = norm('$ph').trim();
        if (q.length < 3) continue;
        final words = q.split(' ').where((w) => w.length > 1).toList();
        allQueries.add(words);
        for (final b in books) {
          final list = lists[b]!;
          var n = 0;
          // Expression exacte d'abord, sinon tous les mots.
          for (final exact in [true, false]) {
            if (n > 0) break;
            for (var i = 0; i < list.length && n < perPhrase; i++) {
              final k = list[i].key;
              if (exact ? k.contains(q) : words.every(k.contains)) {
                final id = '${b[0]}$i';
                (cands[id] ??= Candidate(id, b, h: list[i])).score += exact ? 3 : 1;
                n++;
              }
            }
          }
        }
      }
    }
    for (final ph in ((j['quran'] ?? const []) as List).take(6)) {
      for (final v in d.searchQuran('$ph', limit: 6)) {
        (verses['q${v.key}'] ??= Candidate('q${v.key}', 'quran', v: v)).score += 1;
      }
    }
  }

  List<Candidate> pickTop() {
    final hs = cands.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    final vs = verses.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    return [...hs.take(ai.p.maxHadith), ...vs.take(ai.p.maxVerses)];
  }

  Future<Map<String, dynamic>> classify(List<Candidate> top) async {
    String clip(String t) => t.length <= ai.p.clip ? t : '…${t.substring(t.length - ai.p.clip)}';
    final buf = StringBuffer('السؤال كما فهمناه: $understood\n(نص المستخدم: $question)\n\nالنصوص:\n');
    for (final c in top) {
      buf.writeln('[${c.id}] (${c.label}${c.note == null ? '' : ' — ${c.note}'}) ${clip(c.fullText)}');
    }
    return extractJson(await ai.chat(_sys2, buf.toString(), wantJson: true));
  }

  List<AiPick> picks(Map<String, dynamic> j, Map<String, Candidate> byId, String k, {required bool quran}) {
    final out = <AiPick>[];
    final seen = <String>{};
    for (final x in (j[k] ?? const []) as List) {
      final id = '${x is Map ? x['id'] : x}'.trim();
      final c = byId[id];
      if (c == null || seen.contains(id) || (c.v != null) != quran) continue; // inventé ou mal classé : rejeté
      seen.add(id);
      out.add(AiPick(c, '${x is Map ? (x['why'] ?? '') : ''}'));
    }
    return out;
  }

  progress('١/٤ تذكّر الأحاديث المتعلقة بالمعنى وألفاظ متونها…');
  addCurated('$question $understood');
  await searchRound('السؤال كما فهمناه: $understood\n(نص المستخدم: $question)');

  var rounds = 1;
  var top = pickTop();
  if (top.isEmpty) throw AiException('لم يجد البحث أي نص. أعد صياغة السؤال.');
  progress('٢/٤ وُجد ${arabicDigits(top.length)} نصاً في الكتب؛ قراءتها وتصنيفها…');
  var j2 = await classify(top);
  var byId = {for (final c in top) c.id: c};
  var ans = picks(j2, byId, 'answer', quran: false), con = picks(j2, byId, 'contra', quran: false);

  if (ans.isEmpty && con.isEmpty) {
    rounds = 2;
    progress('٣/٤ لم تكفِ الجولة الأولى؛ بحث ثانٍ بعبارات أخرى…');
    await searchRound('السؤال كما فهمناه: $understood\n'
        'العبارات التالية لم تجد نصوصاً مناسبة، فاقترح أحاديث وعبارات أخرى مختلفة: '
        '${allQueries.map((q) => q.join(' ')).join('، ')}');
    top = pickTop();
    j2 = await classify(top);
    byId = {for (final x in top) x.id: x};
    ans = picks(j2, byId, 'answer', quran: false);
    con = picks(j2, byId, 'contra', quran: false);
  }

  progress('٤/٤ التحقق من المعرّفات…');
  final vs = picks(j2, byId, 'verses', quran: true);
  final summary = (ans.isEmpty && con.isEmpty) ? '' : '${j2['summary'] ?? ''}';
  return AiResult(question, understood, summary, allQueries, ans, con, vs, top.length, rounds);
}

String arabicDigits(int n) {
  const d = '٠١٢٣٤٥٦٧٨٩';
  return '$n'.split('').map((ch) => d[int.parse(ch)]).join();
}
