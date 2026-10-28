part of 'main.dart';

// ---------- إرسال ملاحظة للمطوّر ----------

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackState();
}

class _FeedbackState extends State<FeedbackScreen> {
  static const _kinds = {'problem': 'مشكلة', 'idea': 'اقتراح', 'other': 'أخرى'};
  final _c = TextEditingController();
  String _kind = 'problem';
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    final text = _c.text.trim();
    if (text.isEmpty) {
      _toast(context, 'اكتب الملاحظة أول.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _db.rpc('send_feedback', params: {'p_kind': _kind, 'p_body': text});
      if (!mounted) return;
      _toast(context, 'شكراً، وصلت ملاحظتك.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final m = e.toString();
      _toast(
          context,
          m.contains('daily_limit')
              ? 'وصلت الحد اليومي (3 ملاحظات). جرّب بكرة.'
              : 'تعذر الإرسال. جرّب مرة ثانية.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Backdrop(
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(children: [
                  IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back)),
                  const Text('إرسال ملاحظة',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Glass(
                    radius: 28,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                            'شنو اللي تبي توصله للمطوّر؟ كل ملاحظة تساعدنا نحسّن التطبيق.',
                            style: TextStyle(color: Color(0xCCFFFFFF))),
                        const SizedBox(height: 16),
                        Wrap(spacing: 8, children: [
                          for (final e in _kinds.entries)
                            ChoiceChip(
                              label: Text(e.value),
                              selected: _kind == e.key,
                              onSelected: (_) => setState(() => _kind = e.key),
                            ),
                        ]),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _c,
                          maxLines: 6,
                          inputFormatters: [LengthLimitingTextInputFormatter(1000)],
                          decoration: InputDecoration(
                            hintText: 'اكتب ملاحظتك هنا (حد 1000 حرف)',
                            filled: true,
                            fillColor: const Color(0x1FFFFFFF),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: _edge),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _Btn(label: 'إرسال', onTap: _send, busy: _busy),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}
