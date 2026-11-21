part of 'main.dart';

// ---------- أدوات مشتركة ----------

SupabaseClient get _sb => Supabase.instance.client;

/// ينادي دالة سيرفر (RPC) ويرجّع الناتج (Map أو List أو null)
Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) async {
  final r = await _sb.rpc(fn, params: params);
  return r;
}

Map<String, dynamic> _map(dynamic v) => Map<String, dynamic>.from(v as Map);

List<Map<String, dynamic>> _list(dynamic v) =>
    (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

String _s(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final t = v.toString();
  return t.isEmpty ? fallback : t;
}

/// رسالة خطأ مفهومة بالعربي
String _err(Object e) {
  final raw = e is PostgrestException
      ? e.message
      : (e is AuthException ? e.message : e.toString());
  const known = {
    'forbidden': 'ما عندك صلاحية لهالإجراء',
    'cannot_target_admin': 'ما تقدر تطبّق هالإجراء على أدمن',
    'locked': 'محاولات غلط كثيرة. جرّب بعد ساعة',
    'slow_down': 'انتظر دقيقة بين كل إشعار جماعي والثاني',
    'bad_text': 'العنوان (حتى 60 حرف) والنص (حتى 240 حرف) مطلوبين',
    'not_found': 'ما لقيت المستخدم',
    'bad_value': 'القيمة غير صالحة',
    'too_long': 'النص طويل',
    'not_authenticated': 'سجّل دخول من جديد',
    'Invalid login credentials': 'الإيميل أو كلمة السر غلط',
    'User already registered': 'هذا الإيميل مسجّل من قبل. سجّل دخول بدل إنشاء حساب',
    'Email not confirmed': 'الإيميل مو مؤكَّد. افتح رسالة التأكيد بإيميلك',
    'Password should be at least': 'كلمة السر قصيرة',
    'rate limit': 'محاولات كثيرة. جرّب بعد شوي',
    'banned': 'هذا الحساب محظور',
  };
  for (final k in known.keys) {
    if (raw.contains(k)) return known[k]!;
  }
  if (raw.contains('SocketException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('ClientException') ||
      raw.contains('Connection')) {
    return 'ما في اتصال بالإنترنت';
  }
  return raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
}

void _toast(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

DateTime? _parse(dynamic iso) {
  if (iso == null) return null;
  return DateTime.tryParse(iso.toString())?.toLocal();
}

String _two(int n) => n < 10 ? '0$n' : '$n';

/// تاريخ كامل: 2026-11-21 17:08
String _dt(dynamic iso) {
  final d = _parse(iso);
  if (d == null) return '—';
  return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
}

/// منذ متى: قبل 5 د / قبل 3 س / قبل 2 يوم
String _ago(dynamic iso) {
  final d = _parse(iso);
  if (d == null) return '—';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'الآن';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
  if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
  return _dt(iso).substring(0, 10);
}

String _actionName(String a) {
  const names = {
    'claim': 'ربط حساب أدمن',
    'ban': 'حظر مستخدم',
    'unban': 'فك حظر',
    'logout': 'تسجيل خروج من كل الأجهزة',
    'delete_user': 'حذف حساب',
    'unlink': 'فك ربط المحادثة',
    'reset_e2e': 'إعادة ضبط مفاتيح التشفير',
    'report_done': 'إنهاء بلاغ',
    'report_reopen': 'إعادة فتح بلاغ',
    'feedback_done': 'إنهاء ملاحظة',
    'feedback_reopen': 'إعادة فتح ملاحظة',
    'errors_clear': 'مسح أخطاء قديمة',
    'config_maintenance': 'وضع الصيانة',
    'config_maintenance_msg': 'رسالة الصيانة',
    'config_min_build': 'الحد الأدنى للإصدار',
    'config_announce': 'الإعلان',
    'broadcast': 'إشعار جماعي',
    'push_user': 'إشعار لمستخدم',
  };
  return names[a] ?? a;
}

// ---------- نوافذ ----------

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  String ok = 'تأكيد',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: const Color(0xFFD32F2F)) : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

class _FieldsDialog extends StatefulWidget {
  const _FieldsDialog({required this.title, required this.fields, required this.ok});
  final String title;
  final List<(String, int, int)> fields; // الاسم، أقصى طول، أقصى أسطر
  final String ok;

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final List<TextEditingController> _c = [
    for (final _ in widget.fields) TextEditingController(),
  ];

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.fields.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _c[i],
                  maxLength: widget.fields[i].$2,
                  minLines: 1,
                  maxLines: widget.fields[i].$3,
                  decoration: InputDecoration(
                    labelText: widget.fields[i].$1,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop([for (final c in _c) c.text.trim()]),
          child: Text(widget.ok),
        ),
      ],
    );
  }
}

Future<List<String>?> _fieldsDialog(
  BuildContext context,
  String title,
  List<(String, int, int)> fields, {
  String ok = 'إرسال',
}) =>
    showDialog<List<String>>(
      context: context,
      builder: (_) => _FieldsDialog(title: title, fields: fields, ok: ok),
    );

// ---------- عناصر واجهة ----------

/// يحمّل بيانات مرة وحدة، وفيه تحديث بالسحب وإعادة محاولة
class _Async<T> extends StatefulWidget {
  const _Async({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<_Async<T>> createState() => _AsyncState<T>();
}

class _AsyncState<T> extends State<_Async<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (mounted) setState(() => _loading = true);
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      if (_data != null) _toast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _ErrorBox(message: _err(_error ?? 'خطأ'), onRetry: _run);
    }
    return widget.builder(context, d, _run);
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 44),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(40),
        child: Center(child: Text(text, textAlign: TextAlign.center)),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.color = const Color(0xFF455A64)});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withAlpha(60),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(140)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11)),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xB3FFFFFF))),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: children),
            ),
          ),
        ],
      );
}

class _KV extends StatelessWidget {
  const _KV(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Color(0x99FFFFFF)))),
            Expanded(child: SelectableText(v)),
          ],
        ),
      );
}
