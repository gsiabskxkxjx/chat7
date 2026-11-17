part of 'main.dart';

// ---------- الجولة الثانية: بنية أساسية مشتركة ----------
// ثوابت موحّدة (297)، معرّف فريد للرسائل (214)، مهلة الشبكة (219)،
// منع الضغط المزدوج (217)، كشف الساعة الغلط (216)، تسجيل الجهاز (282)،
// تسجيل الأداء والأعطال (210/294)، ومخزن صغير للإعدادات الجديدة.

class _C {
  _C._();
  static const netTimeout = Duration(seconds: 15);
  static const tapGuard = Duration(milliseconds: 700);
  static const maxPins = 3;
  static const clockSkewWarn = Duration(minutes: 5);
  static const cacheLimitMb = 500;
  static const undoDelete = Duration(seconds: 5);
  static const maxVoiceSecs = 300;
  static const aiDailyLimit = 40;
}

/// وقت بدء التطبيق (لقياس سرعة الفتح)
final _appBoot = Stopwatch()..start();

String _uuid4() {
  final r = math.Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
      '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}

class _NetTimeout implements Exception {
  const _NetTimeout();
  @override
  String toString() => 'انتهت مهلة الاتصال. تأكد من الإنترنت وجرّب مرة ثانية.';
}

/// أي طلب شبكة بمهلة واضحة بدل التعليق المفتوح
Future<T> _net<T>(Future<T> f, {Duration t = _C.netTimeout}) =>
    f.timeout(t, onTimeout: () => throw const _NetTimeout());

/// رسالة عربية مفهومة لأي خطأ
String _friendlyError(Object e, {String fallback = 'تعذر تنفيذ الطلب. جرّب مرة ثانية.'}) {
  if (e is _NetTimeout) return e.toString();
  if (e is _E2EUnavailable) return 'التشفير ما اكتمل. الطرف الثاني لازم يفتح آخر نسخة من التطبيق.';
  if (e is PostgrestException) {
    final m = e.message;
    if (m.contains('rate_limited')) return 'ترسل بسرعة كبيرة، انتظر ثواني.';
    if (m.contains('pin_limit')) return 'تقدر تثبّت ${_C.maxPins} رسائل بس. فك تثبيت وحدة أول.';
    if (m.contains('sched_limit')) return 'عندك 20 رسالة مجدولة، احذف وحدة منها أول.';
    if (m.contains('media_locked')) return 'الوسائط تنفتح لما الطرفين يضغطون «أثق فيه».';
    if (m.contains('not_authenticated')) return 'سجّل دخولك من جديد.';
    if (m.contains('e2e_required')) return 'الرسالة لازم تنرسل مشفّرة. حدّث التطبيق.';
    return fallback;
  }
  if (e is AuthException) return e.message;
  if (e is FunctionException) {
    final d = e.details;
    if (d is Map && d['error'] == 'quota') return 'خلصت حصتك اليومية من المساعد الذكي. ارجع بكرة.';
    if (d is Map && d['error'] == 'not_configured') return 'المساعد الذكي مو مفعّل بعد.';
    return fallback;
  }
  return 'تعذر الاتصال. تأكد من الإنترنت وجرّب مرة ثانية.';
}

// ---------- منع الضغط المزدوج ----------

DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

/// يرجّع false لو الضغطة السابقة كانت قبل أقل من 0.7 ثانية
bool _tapOk() {
  final n = DateTime.now();
  if (n.difference(_lastTapAt) < _C.tapGuard) return false;
  _lastTapAt = n;
  return true;
}

// ---------- مخزن صغير للإعدادات الجديدة (ملف JSON) ----------

class _R2Store {
  static final Map<String, dynamic> _m = {};
  static bool _loaded = false;

  static Future<File> _f() async =>
      File('${(await getApplicationSupportDirectory()).path}/r2.json');

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _f();
      if (await f.exists()) {
        _m.addAll(Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map));
      }
    } catch (_) {}
  }

  static T? get<T>(String k) {
    final v = _m[k];
    return v is T ? v : null;
  }

  static Future<void> set(String k, Object? v) async {
    if (v == null) {
      _m.remove(k);
    } else {
      _m[k] = v;
    }
    try {
      await (await _f()).writeAsString(jsonEncode(_m));
    } catch (_) {}
  }
}

// ---------- أدوات عامة ----------

class _R2 {
  static final needRecovery = ValueNotifier<bool>(false);
  static final clockOff = ValueNotifier<Duration?>(null);
  static final _perfSent = <String>{};
  static final _partnerIds = <String, String>{};

  static String verLabel() => _buildNo == 0 ? '0.14' : '0.14+$_buildNo';

  static Future<String> deviceId() async {
    var id = _R2Store.get<String>('device_id');
    if (id == null) {
      id = _uuid4();
      await _R2Store.set('device_id', id);
    }
    return id;
  }

  static Future<String> _deviceName() async {
    try {
      final i = await DeviceInfoPlugin().androidInfo;
      final n = '${i.manufacturer} ${i.model}'.trim();
      if (n.isNotEmpty) return n;
    } catch (_) {}
    return 'جهاز أندرويد';
  }

  /// بعد تسجيل الدخول: نسجّل الجهاز، ونتأكد إن عندنا كود استعادة
  static Future<void> onAuth() async {
    if (!_configured || _db.auth.currentUser == null) return;
    unawaited(_E2E.init()); // لو فشلت التهيئة (إنترنت ضعيف) نعيدها
    try {
      await _net(_db.rpc('register_device', params: {
        'p_device_id': await deviceId(),
        'p_name': await _deviceName(),
        'p_platform': defaultTargetPlatform.name,
        'p_version': verLabel(),
      }));
    } catch (_) {}
    unawaited(saveTimezone());
    try {
      final has = await _net(_db.rpc('has_recovery_code'));
      needRecovery.value = has == false;
    } catch (_) {}
  }

  /// فرق التوقيت عن UTC (للعرض عند الطرف الثاني بوضع المسافة)
  static Future<void> saveTimezone() async {
    final u = _db.auth.currentUser;
    if (!_configured || u == null) return;
    try {
      await _db.from('profiles').update({'tz': _offsetStr(DateTime.now().timeZoneOffset)}).eq('id', u.id);
    } catch (_) {}
  }

  /// هل ساعة الجهاز غلط؟ نقارنها بتاريخ ردّ السيرفر
  static Future<void> checkClock() async {
    if (!_configured) return;
    HttpClient? c;
    try {
      c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await c.headUrl(Uri.parse('$supabaseUrl/auth/v1/health'));
      req.headers.set('apikey', supabaseAnonKey);
      final res = await req.close().timeout(const Duration(seconds: 8));
      final d = res.headers.value('date');
      if (d == null) return;
      final diff = DateTime.now().toUtc().difference(HttpDate.parse(d));
      clockOff.value = diff.abs() > _C.clockSkewWarn ? diff : null;
    } catch (_) {
    } finally {
      c?.close(force: true);
    }
  }

  /// تسجيل زمن حدث (مرة وحدة لكل جلسة) بدون بيانات شخصية
  static void perf(String name) {
    if (!_configured || _db.auth.currentUser == null || !_perfSent.add(name)) return;
    final ms = _appBoot.elapsedMilliseconds;
    unawaited(() async {
      try {
        await _db.rpc('log_perf', params: {
          'p_name': name,
          'p_ms': ms,
          'p_version': verLabel(),
          'p_platform': defaultTargetPlatform.name,
        });
      } catch (_) {}
    }());
  }

  /// تسجيل خطأ غير قاتل (يظهر بجدول error_logs)
  static void report(String context, Object e, [StackTrace? st]) {
    if (!_configured || _db.auth.currentUser == null || !_Prefs.crashReports.value) return;
    unawaited(() async {
      try {
        await _db.rpc('log_error', params: {
          'p_context': context,
          'p_message': e.toString(),
          'p_stack': (st?.toString() ?? '').split('\n').take(8).join('\n'),
          'p_version': verLabel(),
          'p_platform': defaultTargetPlatform.name,
        });
      } catch (_) {}
    }());
  }

  /// رقم الطرف الثاني بالمحادثة
  static Future<String?> partnerId(String chatId) async {
    final cached = _partnerIds[chatId];
    if (cached != null) return cached;
    try {
      final r = await _db.from('chats').select('user_a,user_b').eq('id', chatId).maybeSingle();
      if (r == null) return null;
      final me = _db.auth.currentUser?.id;
      final other = (r['user_a'] == me ? r['user_b'] : r['user_a']) as String?;
      if (other != null) _partnerIds[chatId] = other;
      return other;
    } catch (_) {
      return null;
    }
  }

  // ----- لا تزعج مؤقت (254) -----

  static bool dndActive([DateTime? at]) {
    final until = _R2Store.get<int>('dnd_until');
    if (until == null) return false;
    return (at ?? DateTime.now()).millisecondsSinceEpoch < until;
  }

  static Future<void> setDnd(DateTime? until) =>
      _R2Store.set('dnd_until', until?.millisecondsSinceEpoch);
}

// ---------- تنسيق: الأرقام والوقت وأسماء الأشهر (273/274/275) ----------

class _Fmt {
  static bool get arabicDigits => _R2Store.get<bool>('arabic_digits') ?? false;
  static bool get h24 => _R2Store.get<bool>('h24') ?? PlatformDispatcher.instance.alwaysUse24HourFormat;
  static bool get iraqiMonths => _R2Store.get<bool>('iraqi_months') ?? false;

  static const _ar = '٠١٢٣٤٥٦٧٨٩';
  static String digits(String s) {
    if (!arabicDigits) return s;
    final b = StringBuffer();
    for (final c in s.runes) {
      b.write(c >= 48 && c <= 57 ? _ar[c - 48] : String.fromCharCode(c));
    }
    return b.toString();
  }

  static const _msStd = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const _msIraq = [
    'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
    'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
  ];
  static String month(int m) => (iraqiMonths ? _msIraq : _msStd)[(m - 1).clamp(0, 11)];

  static String time(DateTime t) {
    if (h24) return digits('${_two(t.hour)}:${_two(t.minute)}');
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return digits('$h:${_two(t.minute)} ${t.hour < 12 ? 'ص' : 'م'}');
  }

  static String date(DateTime t) => digits('${t.day} ${month(t.month)} ${t.year}');

  /// «آخر ظهور» بصيغة نسبية (229)
  static String ago(DateTime t, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final d = n.difference(t);
    if (d.inMinutes < 1) return 'قبل لحظات';
    if (d.inMinutes < 60) return digits('قبل ${d.inMinutes} دقيقة');
    final today = DateTime(n.year, n.month, n.day);
    final that = DateTime(t.year, t.month, t.day);
    final days = today.difference(that).inDays;
    if (days == 0) return digits('قبل ${d.inHours} ساعة');
    if (days == 1) return 'أمس ${time(t)}';
    if (days < 7) return digits('قبل $days أيام');
    return date(t);
  }
}
