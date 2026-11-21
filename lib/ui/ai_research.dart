import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai.dart';
import '../data.dart';
import '../state.dart';
import 'common.dart';
import 'pages.dart';
import 'smart.dart';

/// Page de recherche par IA : étapes en direct, puis résultats vérifiés.
class AiResearchPage extends StatefulWidget {
  final String question;
  const AiResearchPage(this.question, {super.key});
  @override
  State<AiResearchPage> createState() => _AiResearchPageState();
}

class _AiResearchPageState extends State<AiResearchPage> {
  final steps = <String>[];
  AiUnderstanding? und; // ce que l'IA a compris
  bool editing = false, confirmed = false;
  late final editCtrl = TextEditingController();
  AiResult? res;
  String? error;

  @override
  void initState() {
    super.initState();
    _understand();
  }

  @override
  void dispose() {
    editCtrl.dispose();
    super.dispose();
  }

  Future<void> _understand() async {
    setState(() {
      und = null;
      res = null;
      error = null;
      confirmed = false;
      editing = false;
      steps.clear();
    });
    try {
      final u = await aiUnderstand(widget.question);
      if (mounted) {
        setState(() {
          und = u;
          editCtrl.text = u.understood;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _search(String understood) async {
    setState(() {
      confirmed = true;
      editing = false;
      steps.clear();
      res = null;
      error = null;
    });
    try {
      final r = await aiResearch(widget.question, understood, (st) {
        if (mounted) setState(() => steps.add(st));
      });
      if (mounted) setState(() => res = r);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  String _text(AiResult r) {
    final b = StringBuffer('🔎 ${r.claim}\n\n');
    void sec(String t, List<AiPick> l) {
      if (l.isEmpty) return;
      b.writeln(t);
      for (final p in l) {
        b.writeln('• ${p.c.label}: ${p.why}');
      }
      b.writeln();
    }

    sec('✅ روايات تجيب عن السؤال:', r.answer);
    sec('❌ روايات تناقضها:', r.contra);
    sec('📖 آيات تخالفها:', r.verses);
    if (r.summary.isNotEmpty) b.writeln('الخلاصة: ${r.summary}');
    b.write('— ${Brand.name}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final r = res;
    final u = und;
    return Scaffold(
      appBar: AppBar(title: const Text('بحث بالذكاء الاصطناعي'), actions: [
        if (r != null) ...[
          IconButton(tooltip: 'نسخ', icon: const Icon(Icons.copy_all_rounded), onPressed: () => copyText(context, _text(r))),
          IconButton(tooltip: 'مشاركة', icon: const Icon(Icons.share_rounded), onPressed: () => shareText(context, _text(r))),
        ],
        IconButton(tooltip: 'من جديد', icon: const Icon(Icons.refresh_rounded), onPressed: _understand),
      ]),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Text('سؤالك: ${widget.question}', style: TextStyle(fontSize: 15, color: s.onSurfaceVariant)),
        ),
        // ── Étape 1 : ce que l'IA a compris
        if (u == null && error == null)
          const ListTile(
            leading: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
            title: Text('أحاول فهم قصدك…'),
          ),
        if (u != null)
          AppCard(
            border: s.primary.withAlpha(120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.psychology_rounded, color: s.primary),
                const SizedBox(width: 8),
                Text('فهمتُ سؤالك هكذا:', style: TextStyle(fontWeight: FontWeight.w800, color: s.primary)),
              ]),
              const SizedBox(height: 8),
              if (editing)
                TextField(
                  controller: editCtrl,
                  maxLines: null,
                  autofocus: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'اكتب قصدك بوضوح'),
                )
              else ...[
                Text(u.understood, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.5)),
                if (u.yes.isNotEmpty || u.no.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  if (u.yes.isNotEmpty) Text('✅ ${u.yes}', style: TextStyle(color: s.onSurfaceVariant)),
                  if (u.no.isNotEmpty) Text('❌ ${u.no}', style: TextStyle(color: s.onSurfaceVariant)),
                ],
              ],
              if (!confirmed) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.search_rounded),
                    label: Text(editing ? 'ابحث بهذا' : 'صحيح، ابحث'),
                    onPressed: () => _search(editing ? editCtrl.text.trim() : u.understood),
                  ),
                  if (!editing)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('عدّل'),
                      onPressed: () => setState(() => editing = true),
                    ),
                ]),
              ],
            ]),
          ),
        // ── Étape 2 : recherche en cours
        if (confirmed && r == null && error == null) ...[
          for (final st in steps)
            ListTile(dense: true, leading: const Icon(Icons.check_circle_outline_rounded, size: 20), title: Text(st)),
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        ],
        if (error != null)
          AppCard(
            color: s.errorContainer,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(error!, style: TextStyle(color: s.onErrorContainer)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton(onPressed: u != null && confirmed ? () => _search(editCtrl.text.trim()) : _understand,
                    child: const Text('إعادة المحاولة')),
                OutlinedButton(onPressed: () => openSection(context, 'settings'), child: const Text('الإعدادات')),
              ]),
            ]),
          ),
        // ── Étape 3 : résultats
        if (r != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: Text(
                'بحث في ${arNum(r.searched)} نصاً من الكتب داخل البرنامج${r.rounds > 1 ? ' (جولتان)' : ''}. '
                'النصوص المعروضة من الكتب نفسها، والتصنيف من الذكاء الاصطناعي: راجعه قبل أن تستشهد به.',
                style: TextStyle(color: s.onSurfaceVariant, fontSize: 12.5)),
          ),
          _Section('✅ روايات تجيب عن السؤال', const Color(0xFF2E7D32), r.answer),
          _Section('❌ روايات تناقضها', const Color(0xFFC62828), r.contra),
          _Section('📖 آيات تخالفها', C.goldDeep, r.verses),
          if (r.answer.isEmpty && r.contra.isEmpty)
            AppCard(
              child: Text(
                  'لم أجد روايات مناسبة في هذا البحث. هذا لا يعني أنها غير موجودة في الكتب: '
                  'جرّب «عدّل» واكتب قصدك بكلمات أخرى، أو ابحث بعبارة من الحديث في قسم «الكتب».',
                  style: TextStyle(color: s.onSurfaceVariant, height: 1.6)),
            ),
          if (r.summary.isNotEmpty)
            ColoredBlock(label: 'خلاصة الذكاء الاصطناعي', text: r.summary, color: s.tertiary, icon: Icons.auto_awesome_rounded),
          ExpansionTile(
            title: const Text('العبارات التي بحث بها في المتون'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(r.queries.map((q) => q.join(' ')).join('  •  ')),
              ),
            ],
          ),
        ],
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Color color;
  final List<AiPick> items;
  const _Section(this.title, this.color, this.items);
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Row(children: [
          Container(width: 4, height: 22, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color))),
          Text(arNum(items.length), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ]),
      ),
      for (final p in items) _PickCard(p, color: color),
    ]);
  }
}

class _PickCard extends StatelessWidget {
  final AiPick p;
  final Color color;
  const _PickCard(this.p, {required this.color});
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final c = p.c;
    final verse = c.v != null;
    final t = c.fullText;
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      border: color.withAlpha(90),
      onTap: verse
          ? () => openTag(context, 'v:${c.v!.key}')
          : () => showBookHadith(context, Books.names[c.book] ?? c.book, c.h!),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (p.why.isNotEmpty) Text(p.why, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.55)),
        const SizedBox(height: 6),
        Text(
          verse ? '﴿ $t ﴾' : (t.length > 380 ? '…${t.substring(t.length - 380)}' : t),
          style: verse ? quranStyle.copyWith(fontSize: 19) : hadithStyle.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 6),
        Pill(c.label, icon: verse ? Icons.auto_stories_rounded : Icons.library_books_rounded, color: s.tertiary),
      ]),
    );
  }
}

/// Réglages : on colle la clé, tout le reste est automatique.
class AiSettingsCard extends StatefulWidget {
  const AiSettingsCard({super.key});
  @override
  State<AiSettingsCard> createState() => _AiSettingsCardState();
}

class _AiSettingsCardState extends State<AiSettingsCard> {
  late final keyCtrl = TextEditingController(text: AppState.I.aiKey);
  late final modelCtrl = TextEditingController(text: AppState.I.aiModel);
  bool hide = true, busy = false;
  Timer? _deb;
  List<String> models = [];
  String? advStatus;

  @override
  void dispose() {
    _deb?.cancel();
    keyCtrl.dispose();
    modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    final k = keyCtrl.text.trim();
    if (k.isEmpty) return;
    setState(() => busy = true);
    AppState.I.setAi(key: k, status: '');
    final r = await autoSetup(k);
    if (!mounted) return;
    if (!r.ok) AppState.I.setAi(status: '❌ ${r.message}');
    modelCtrl.text = AppState.I.aiModel;
    setState(() => busy = false);
  }

  void _changed(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 900), () {
      if (mounted && v.trim().length >= 20) _setup();
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final s = Theme.of(context).colorScheme;
    final prov = providerById(st.aiProvider.isNotEmpty ? st.aiProvider : (detectProvider(st.aiKey).isEmpty ? 'groq' : detectProvider(st.aiKey)));
    final ok = st.aiStatus.startsWith('✅');
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('ألصق مفتاحك فقط، والبرنامج يختار النموذج المجاني ويختبره تلقائياً.',
            style: TextStyle(fontWeight: FontWeight.w700)),
        Text('المفاتيح المجانية: Groq (console.groq.com) أو Gemini (aistudio.google.com) أو OpenRouter.',
            style: TextStyle(fontSize: 12.5, color: s.onSurfaceVariant)),
        const SizedBox(height: 10),
        TextField(
          controller: keyCtrl,
          obscureText: hide,
          autocorrect: false,
          enableSuggestions: false,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: 'مفتاح API',
            border: const OutlineInputBorder(),
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  tooltip: 'لصق',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final d = await Clipboard.getData('text/plain');
                    final t = d?.text?.trim() ?? '';
                    if (t.isNotEmpty) {
                      keyCtrl.text = t;
                      _setup();
                    }
                  }),
              IconButton(
                  icon: Icon(hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => hide = !hide)),
            ]),
          ),
          onChanged: _changed,
          onSubmitted: (_) => _setup(),
        ),
        const SizedBox(height: 10),
        if (busy)
          const Row(children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Expanded(child: Text('جارٍ الإعداد: التعرّف على المزوّد، اختيار نموذج مجاني، اختبار…')),
          ])
        else if (st.aiStatus.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (ok ? const Color(0xFF2E7D32) : s.error).withAlpha(28),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(st.aiStatus, style: const TextStyle(height: 1.5)),
          ),
        if (!busy && st.aiKey.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة الإعداد'), onPressed: _setup),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('خيارات متقدمة'),
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey(prov.id),
              initialValue: prov.id,
              decoration: const InputDecoration(labelText: 'المزوّد', border: OutlineInputBorder(), isDense: true),
              items: [
                for (final p in aiProviders)
                  DropdownMenuItem(value: p.id, child: Text('${p.name}${p.free ? ' — مجاني' : ' — مدفوع'}')),
              ],
              onChanged: (v) => setState(() => st.setAi(provider: v, model: '', fallback: [])),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: modelCtrl,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                  labelText: 'النموذج (فارغ = ${prov.defaultModel})', border: const OutlineInputBorder(), isDense: true),
              onChanged: (v) => st.setAi(model: v),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.list_rounded),
                label: const Text('عرض النماذج المتاحة'),
                onPressed: () async {
                  final ai = AiClient.fromSettings();
                  if (ai == null) return;
                  try {
                    models = await ai.listModels();
                    advStatus = null;
                  } catch (e) {
                    advStatus = '$e';
                  }
                  if (mounted) setState(() {});
                },
              ),
            ),
            if (advStatus != null) Text(advStatus!),
            if (models.isNotEmpty)
              SizedBox(
                height: 150,
                child: ListView(children: [
                  for (final m in models)
                    ListTile(
                      dense: true,
                      title: Text(m, textDirection: TextDirection.ltr),
                      selected: m == st.aiModel,
                      onTap: () => setState(() {
                        modelCtrl.text = m;
                        st.setAi(model: m);
                      }),
                    ),
                ]),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('شمل تاريخ الطبري في البحث'),
              subtitle: const Text('أخباره غير مصحّحة؛ معطّل افتراضياً.'),
              value: st.aiTabari,
              onChanged: (v) => setState(() => st.setAi(tabari: v)),
            ),
          ],
        ),
        Text('مفتاحك يُحفظ في هذا الجهاز فقط، ولا يُرسل إلا إلى مزوّد الذكاء الاصطناعي.',
            style: TextStyle(fontSize: 12, color: s.onSurfaceVariant)),
      ]),
    );
  }
}
