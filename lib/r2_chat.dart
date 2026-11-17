part of 'main.dart';

// ---------- الجولة الثانية: ميزات المحادثة ----------
// تثبيت رسائل (301)، رسائل مجدولة (302)، رسائل مؤقتة (303)،
// تصدير المحادثة (304)، شريط الساعة والاستعادة، تراجع عن الحذف (224)

final _msgKeys = <int, GlobalKey>{};
GlobalKey _msgKey(int id) => _msgKeys.putIfAbsent(id, GlobalKey.new);

extension _R2Chat on _ChatState {
  // ----- المثبّتات -----

  void _watchPins() {
    _pinSub?.cancel();
    _pinSub = _db
        .from('pinned_messages')
        .stream(primaryKey: ['chat_id', 'message_id'])
        .eq('chat_id', widget.chat.id)
        .listen((rows) {
      if (!mounted) return;
      final ids = [for (final r in rows) (r['message_id'] as num).toInt()]..sort();
      setState(() => _pinIds = ids);
    }, onError: (_) {});
  }

  Future<void> _togglePin(Msg m) async {
    final on = _pinIds.contains(m.id);
    try {
      if (on) {
        await _net(_db
            .from('pinned_messages')
            .delete()
            .eq('chat_id', widget.chat.id)
            .eq('message_id', m.id));
      } else {
        await _net(_db.from('pinned_messages').insert({'chat_id': widget.chat.id, 'message_id': m.id}));
      }
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  /// ينط للرسالة لو ظاهرة بالقائمة، وإلا يخبر المستخدم
  void _jumpToMsg(int id) {
    final ctx = _msgKeys[id]?.currentContext;
    if (ctx != null) {
      unawaited(Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350), alignment: 0.4, curve: Curves.easeOut));
    } else {
      _toast(context, 'الرسالة بعيدة بالمحادثة، انزل للأعلى لتوصلها.');
    }
  }

  String _pinText(int id) {
    final m = _lastMsgs.where((x) => x.id == id).toList();
    if (m.isEmpty) return 'رسالة مثبّتة';
    return _quoteSnippet(m.first);
  }

  /// أشرطة الجولة الثانية: المثبّتات، ساعة الجهاز، كود الاستعادة
  List<Widget> _r2Bars() {
    final out = <Widget>[];
    final bar = _r2Bar;
    if (_pinIds.isNotEmpty) {
      final id = _pinIds.last;
      out.add(bar('📌', _pinText(id),
          onTap: () => _jumpToMsg(id),
          onClose: _pinIds.length > 1
              ? () => setState(() => _pinIds = _pinIds.sublist(0, _pinIds.length - 1))
              : null));
    }
    final skew = _R2.clockOff.value;
    if (skew != null && !_clockDismissed) {
      out.add(bar('🕐', 'ساعة جوالك تختلف ${skew.inMinutes.abs()} دقيقة عن الوقت الحقيقي. صحّحها حتى توصلك الإشعارات والمواعيد بوقتها.',
          onClose: () => setState(() => _clockDismissed = true)));
    }
    if (_R2.needRecovery.value && !_recoveryDismissed) {
      out.add(bar('🔑', 'ما عندك كود استعادة. بدونه ما تقدر ترجع لحسابك لو نسيت كلمة السر. سوّيه الحين.',
          onTap: () => unawaited(_makeRecoveryNow()),
          onClose: () => setState(() => _recoveryDismissed = true)));
    }
    out.addAll(_liveBars());
    return out;
  }

  Future<void> _makeRecoveryNow() async {
    try {
      final code = await _net(_issueRecoveryCode());
      if (!mounted) return;
      _R2.needRecovery.value = false;
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RecoveryCodeScreen(code: code, onDone: (c) => Navigator.of(c).pop())));
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e, fallback: 'تعذر إنشاء الرمز. جرّب مرة ثانية.'));
    }
  }

  // ----- تراجع عن الحذف -----

  /// يخفي الرسائل فوراً ويعطي 5 ثواني للتراجع قبل التنفيذ الفعلي
  void _undoableDelete(List<Msg> msgs, Future<void> Function() commit) {
    if (msgs.isEmpty) return;
    var undone = false;
    final ids = msgs.map((m) => m.id).toSet();
    setState(() => _hidden.addAll(ids));
    final sb = ScaffoldMessenger.of(context);
    sb.hideCurrentSnackBar();
    sb.showSnackBar(SnackBar(
      content: Text(msgs.length == 1 ? 'انحذفت الرسالة' : 'انحذفت ${msgs.length} رسائل'),
      behavior: SnackBarBehavior.floating,
      duration: _C.undoDelete,
      action: SnackBarAction(
        label: 'تراجع',
        onPressed: () {
          undone = true;
          if (mounted) setState(() => _hidden.removeAll(ids));
        },
      ),
    ));
    Future.delayed(_C.undoDelete + const Duration(milliseconds: 300), () async {
      if (undone) return;
      try {
        await commit();
      } catch (e) {
        if (mounted) {
          setState(() => _hidden.removeAll(ids));
          _toast(context, _friendlyError(e, fallback: 'تعذر الحذف.'));
        }
      }
    });
  }

  // ----- الانتقال لتاريخ -----

  Future<void> _jumpToDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: now, firstDate: DateTime(2020), lastDate: now);
    if (d == null || !mounted) return;
    try {
      final start = DateTime(d.year, d.month, d.day).toUtc().toIso8601String();
      final r = await _net(_db
          .from('messages')
          .select('id')
          .eq('chat_id', widget.chat.id)
          .gte('created_at', start)
          .order('id', ascending: true)
          .limit(1)
          .maybeSingle());
      if (r == null) {
        if (mounted) _toast(context, 'ما في رسائل من هذا اليوم أو بعده.');
        return;
      }
      final target = (r['id'] as num).toInt();
      final cnt = (await _net(_db
              .from('messages')
              .select('id')
              .eq('chat_id', widget.chat.id)
              .gte('id', target)
              .count(CountOption.exact)))
          .count;
      if (!mounted) return;
      setState(() {
        _limit = math.min(cnt + 30, 2500);
        _stream = _makeStream();
      });
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) _jumpToMsg(target);
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  // ----- أدوات المحادثة (قائمة) -----

  void _openR2Tools() {
    final id = widget.chat.id;
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.schedule_send_rounded),
              title: const Text('رسالة مجدولة'),
              subtitle: const Text('تنرسل بوقت تحدده'),
              onTap: () {
                Navigator.pop(ctx);
                push(ScheduledScreen(chatId: id));
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('رسائل تختفي'),
              subtitle: const Text('تنحذف تلقائياً بعد مدة'),
              onTap: () {
                Navigator.pop(ctx);
                push(DisappearScreen(chatId: id));
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('معرض المحادثة'),
              subtitle: const Text('صور، فيديو، ملفات، روابط'),
              onTap: () {
                Navigator.pop(ctx);
                push(GalleryScreen(chatId: id));
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_rounded),
              title: const Text('انتقل لتاريخ'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_jumpToDate());
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: const Text('شنو فاتك؟'),
              subtitle: const Text('ملخص بنقاط لآخر الرسائل'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_aiCatchUp());
              },
            ),
            ListTile(
              leading: const Icon(Icons.spellcheck_rounded),
              title: const Text('صحّح كتابتي'),
              subtitle: const Text('يصحح النص اللي بمربع الكتابة'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_aiFixDraft());
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('صدّر المحادثة'),
              subtitle: const Text('ملف نصي بالرسائل'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_exportChat(id));
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _exportChat(String chatId) async {
    if (!_tapOk()) return;
    _toast(context, 'نجهّز الملف...');
    try {
      final rows = await _net(
          _db
              .from('messages')
              .select('id,sender_id,body,kind,created_at')
              .eq('chat_id', chatId)
              .order('id', ascending: true)
              .limit(20000),
          t: const Duration(seconds: 60));
      final me = _db.auth.currentUser?.id;
      final myName = 'أنا';
      final other = widget.chat.partner;
      final b = StringBuffer('محادثة بيناتنا\n\n');
      for (final r in rows) {
        final k = (r['kind'] as String?) ?? 'text';
        if (k == 'call') continue;
        final at = DateTime.tryParse('${r['created_at']}')?.toLocal();
        final who = r['sender_id'] == me ? myName : other;
        final body = switch (k) {
          'image' => '[صورة]',
          'video' => '[فيديو]',
          'audio' => '[رسالة صوتية]',
          'vnote' => '[فيديو دائري]',
          'file' => '[ملف] ${r['body'] ?? ''}',
          _ => '${r['body'] ?? ''}',
        };
        b.writeln('${at == null ? '' : '${_Fmt.date(at)} ${_Fmt.time(at)}'} - $who: $body');
      }
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/bainatna_chat.txt');
      await f.writeAsString(b.toString());
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }
}

// ===== الرسائل المجدولة =====

class ScheduledScreen extends StatefulWidget {
  const ScheduledScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<ScheduledScreen> createState() => _ScheduledState();
}

class _ScheduledState extends State<ScheduledScreen> {
  final _c = TextEditingController();
  DateTime _at = DateTime.now().add(const Duration(hours: 1));
  List<Map<String, dynamic>> _rows = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _net(_db
          .from('scheduled_messages')
          .select('id,body,send_at')
          .eq('chat_id', widget.chatId)
          .isFilter('sent_at', null)
          .order('send_at', ascending: true));
      if (mounted) setState(() => _rows = [for (final e in r) Map<String, dynamic>.from(e)]);
    } catch (_) {}
  }

  Future<void> _pick() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _at,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    final text = _c.text.trim();
    if (text.isEmpty) {
      _toast(context, 'اكتب الرسالة أول.');
      return;
    }
    if (_at.isBefore(DateTime.now())) {
      _toast(context, 'اختر وقت جاي.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _net(_db.from('scheduled_messages').insert({
        'chat_id': widget.chatId,
        'body': text,
        'send_at': _at.toUtc().toIso8601String(),
      }));
      _c.clear();
      await _load();
      if (mounted) _toast(context, 'انجدولت الرسالة.');
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _del(int id) async {
    try {
      await _net(_db.from('scheduled_messages').delete().eq('id', id));
      await _load();
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => _R2Page(
        title: 'رسالة مجدولة',
        child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
          Glass(
            radius: 24,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _c,
                maxLength: 2000,
                maxLines: 4,
                minLines: 2,
                decoration: const InputDecoration(hintText: 'شنو تبي ترسل؟'),
              ),
              const SizedBox(height: _Sp.sm),
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.event_rounded),
                label: Text('${_Fmt.date(_at)} · ${_Fmt.time(_at)}'),
              ),
              const SizedBox(height: _Sp.md),
              _Btn(label: 'جدولها', onTap: _save, busy: _busy),
            ]),
          ),
          const SizedBox(height: _Sp.lg),
          if (_rows.isNotEmpty) _secTitle('المجدولة (${_rows.length})'),
          for (final r in _rows)
            Padding(
              padding: const EdgeInsets.only(bottom: _Sp.sm),
              child: Glass(
                radius: 20,
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r['body']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(
                          () {
                            final d = DateTime.tryParse('${r['send_at']}')?.toLocal();
                            return d == null ? '' : '${_Fmt.date(d)} · ${_Fmt.time(d)}';
                          }(),
                          style: const TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
                    ]),
                  ),
                  IconButton(
                      tooltip: 'حذف',
                      onPressed: () => _del((r['id'] as num).toInt()),
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF6B60))),
                ]),
              ),
            ),
          const SizedBox(height: _Sp.md),
          const Text('الرسائل تنرسل من السيرفر حتى لو التطبيق مسكّر. أقصى عدد 20 رسالة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
        ]),
      );
}

// ===== رسائل تختفي =====

class DisappearScreen extends StatefulWidget {
  const DisappearScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<DisappearScreen> createState() => _DisappearState();
}

class _DisappearState extends State<DisappearScreen> {
  int? _cur;
  bool _loaded = false;

  static const _opts = <(String, int?)>[
    ('مطفّية', null),
    ('5 دقايق', 300),
    ('ساعة', 3600),
    ('يوم', 86400),
    ('أسبوع', 604800),
    ('30 يوم', 2592000),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final r = await _db.from('chats').select('expire_after_s').eq('id', widget.chatId).maybeSingle();
        if (mounted) {
          setState(() {
            _cur = (r?['expire_after_s'] as num?)?.toInt();
            _loaded = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loaded = true);
      }
    }());
  }

  Future<void> _set(int? s) async {
    final old = _cur;
    setState(() => _cur = s);
    try {
      await _net(_db.from('chats').update({'expire_after_s': s}).eq('id', widget.chatId));
      if (mounted) _toast(context, s == null ? 'الرسائل ما تختفي.' : 'الرسائل الجديدة والقديمة تختفي بعد المدة.');
    } catch (e) {
      if (mounted) {
        setState(() => _cur = old);
        _toast(context, _friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) => _R2Page(
        title: 'رسائل تختفي',
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
                const Text('الرسائل تنحذف من عند الطرفين بعد المدة اللي تختارها. تطبّق على الرسائل الجديدة والقديمة. الصور والملفات ما تنحذف من التخزين، بس الرسالة نفسها.',
                    style: TextStyle(height: 1.6, color: Color(0xCCFFFFFF))),
                const SizedBox(height: _Sp.lg),
                Glass(
                  radius: 24,
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (final o in _opts)
                      ListTile(
                        title: Text(o.$1),
                        trailing: _cur == o.$2 ? const Icon(Icons.check_circle_rounded) : null,
                        onTap: () => _set(o.$2),
                      ),
                  ]),
                ),
              ]),
      );
}
