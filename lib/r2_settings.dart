part of 'main.dart';

// ---------- الجولة الثانية: شاشات الإعدادات الجديدة ----------
// الأجهزة (282/283)، بياناتي (259)، لا تزعج (254)، التخزين (202)، التنسيق (273-275)، التشخيص (220)

/// هيكل شاشة بسيطة بخلفية التطبيق
class _R2Page extends StatelessWidget {
  const _R2Page({required this.title, required this.child, this.actions});
  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(title: Text(title), backgroundColor: Colors.transparent, actions: actions),
        body: Backdrop(child: SafeArea(child: child)),
      );
}

void _r2Push(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute(builder: (_) => w));

/// بطاقة الإعدادات الجديدة بشاشة الملف الشخصي
class _R2Tiles extends StatelessWidget {
  const _R2Tiles();

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData i, String t, String s, Widget page) => ListTile(
          leading: Icon(i),
          title: Text(t),
          subtitle: Text(s),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: () => _r2Push(context, page),
        );
    return Glass(
      radius: 28,
      padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
      child: Column(children: [
        const _SecureTile(),
        tile(Icons.devices_rounded, 'أجهزتي', 'الأجهزة المسجّلة بحسابك وتسجيل الخروج من الباقي', const DevicesScreen()),
        tile(Icons.notifications_paused_rounded, 'لا تزعج', 'كتم الإشعارات لساعة أو لين الصبح', const DndScreen()),
        tile(Icons.storage_rounded, 'التخزين', 'حجم الكاش وحده الأعلى', const CacheScreen()),
        tile(Icons.format_list_numbered_rounded, 'الأرقام والوقت', 'أرقام عربية، 12 أو 24 ساعة، أسماء الأشهر', const FormatScreen()),
        tile(Icons.download_rounded, 'بياناتي', 'شنو نخزّن عنك، ونزّل نسخة منها', const MyDataScreen()),
        tile(Icons.troubleshoot_rounded, 'تشخيص', 'حالة الاتصال والإصدار لإرسالها للدعم', const DiagnosticsScreen()),
      ]),
    );
  }
}

// ===== الأجهزة المسجّلة =====

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesState();
}

class _DevicesState extends State<DevicesScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _err;
  bool _busy = false;
  String _myDevice = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      _myDevice = await _R2.deviceId();
      final r = await _net(_db.rpc('list_devices'));
      if (!mounted) return;
      setState(() {
        _rows = [for (final e in (r as List)) Map<String, dynamic>.from(e as Map)];
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = _friendlyError(e));
    }
  }

  Future<void> _signOutOthers() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج من باقي الأجهزة؟'),
        content: const Text('كل جهاز ثاني مسجّل بحسابك راح يطلع منه، وتحتاج تدخل عليه من جديد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل الخروج')),
        ],
      ),
    );
    if (ok != true || !_tapOk()) return;
    setState(() => _busy = true);
    try {
      final n = await _net(_db.rpc('sign_out_other_devices', params: {'p_keep_device': _myDevice}));
      if (mounted) _toast(context, n is int && n > 0 ? 'طلعنا $n جهاز.' : 'ما في أجهزة ثانية.');
      await _load();
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove(String id) async {
    try {
      await _net(_db.rpc('remove_device', params: {'p_device_id': id}));
      await _load();
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return _R2Page(
      title: 'أجهزتي',
      child: _err != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!, textAlign: TextAlign.center)))
          : rows == null
              ? const _SkeletonList()
              : ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
                  for (final d in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: _Sp.sm),
                      child: Glass(
                        radius: 22,
                        padding: const EdgeInsets.all(_Sp.md),
                        child: Row(children: [
                          Icon(d['is_current'] == true ? Icons.smartphone_rounded : Icons.devices_other_rounded),
                          const SizedBox(width: _Sp.md),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${d['name'] ?? 'جهاز'}${d['is_current'] == true ? '  (هذا الجهاز)' : ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                  'آخر نشاط: ${_Fmt.ago(DateTime.tryParse('${d['last_seen']}')?.toLocal() ?? DateTime.now())}'
                                  ' · ${d['app_version'] ?? ''}',
                                  style: const TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
                            ]),
                          ),
                          if (d['is_current'] != true && d['device_id'] != _myDevice)
                            IconButton(
                                tooltip: 'إزالة الجهاز',
                                onPressed: () => _remove('${d['device_id']}'),
                                icon: const Icon(Icons.logout_rounded, color: Color(0xFFFF6B60))),
                        ]),
                      ),
                    ),
                  if (rows.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('ما في أجهزة مسجّلة بعد.'))),
                  const SizedBox(height: _Sp.md),
                  _Btn(label: 'تسجيل الخروج من باقي الأجهزة', onTap: _signOutOthers, busy: _busy),
                  const SizedBox(height: _Sp.md),
                  const Text('لو شفت جهاز ما تعرفه، اطلعه وغيّر كلمة السر من الإعدادات.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
                ]),
    );
  }
}

// ===== بياناتي =====

class MyDataScreen extends StatefulWidget {
  const MyDataScreen({super.key});

  @override
  State<MyDataScreen> createState() => _MyDataState();
}

class _MyDataState extends State<MyDataScreen> {
  bool _busy = false;

  Future<void> _export() async {
    if (!_tapOk()) return;
    setState(() => _busy = true);
    try {
      final data = await _net(_db.rpc('export_my_data'), t: const Duration(seconds: 60));
      final dir = await getTemporaryDirectory();
      final d = DateTime.now();
      final f = File('${dir.path}/bainatna_data_${d.year}-${_two(d.month)}-${_two(d.day)}.json');
      await f.writeAsString(jsonEncode(data));
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget row(String t, String s) => Padding(
          padding: const EdgeInsets.only(bottom: _Sp.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(s, style: const TextStyle(fontSize: _Fs.meta, color: Color(0xCCFFFFFF), height: 1.5)),
          ]),
        );
    return _R2Page(
      title: 'بياناتي',
      child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
        Glass(
          radius: 24,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            row('الحساب', 'اسم المستخدم، الاسم الظاهر، الصورة، الجنس وتاريخ الميلاد (إذا أدخلتها)، وحالة توثيق الرقم. رقم الهاتف نفسه ما ننحفظ، بس بصمة مشفّرة منه.'),
            row('المحادثة', 'رسائلك ووسائطك وتفاعلاتك وملفاتك، وكل شي تضيفه بالقوائم والتقويم والميزانية واليوميات والألعاب.'),
            row('الأجهزة والإشعارات', 'أسماء أجهزتك المسجّلة ورموز الإشعارات.'),
            row('السجلات', 'أخطاء التطبيق وزمن الفتح بدون محتوى رسائل وبدون اسمك (رمز مجهول)، وتنحذف بعد 30 يوم.'),
            const Text('الرسائل المرسلة منك بس تنزل بالنسخة، وما تنزل رسائل الطرف الثاني.',
                style: TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
          ]),
        ),
        const SizedBox(height: _Sp.lg),
        _Btn(label: 'نزّل نسخة من بياناتي (JSON)', onTap: _export, busy: _busy),
      ]),
    );
  }
}

// ===== لا تزعج =====

class DndScreen extends StatefulWidget {
  const DndScreen({super.key});

  @override
  State<DndScreen> createState() => _DndState();
}

class _DndState extends State<DndScreen> {
  Future<void> _set(DateTime? until) async {
    await _R2.setDnd(until);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final on = _R2.dndActive();
    final until = _R2Store.get<int>('dnd_until');
    var morning = DateTime(now.year, now.month, now.day, 8);
    if (!morning.isAfter(now)) morning = morning.add(const Duration(days: 1));
    Widget opt(String t, DateTime? u, {IconData icon = Icons.timer_rounded}) => Padding(
          padding: const EdgeInsets.only(bottom: _Sp.sm),
          child: Glass(
            radius: 20,
            padding: EdgeInsets.zero,
            child: ListTile(leading: Icon(icon), title: Text(t), onTap: () => _set(u)),
          ),
        );
    return _R2Page(
      title: 'لا تزعج',
      child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
        Padding(
          padding: const EdgeInsets.only(bottom: _Sp.lg),
          child: Text(
            on
                ? 'مفعّل لين ${_Fmt.time(DateTime.fromMillisecondsSinceEpoch(until!))}. الإشعارات توصل بصمت.'
                : 'الإشعارات بحالتها العادية.',
            style: const TextStyle(fontSize: _Fs.title, height: 1.5),
          ),
        ),
        opt('ساعة', now.add(const Duration(hours: 1))),
        opt('3 ساعات', now.add(const Duration(hours: 3))),
        opt('لين الصبح (8:00)', morning, icon: Icons.bedtime_rounded),
        if (on) opt('إيقاف لا تزعج', null, icon: Icons.notifications_active_rounded),
        const SizedBox(height: _Sp.md),
        Glass(
          radius: 20,
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            title: const Text('إخفاء اسم المرسل والنص بالإشعار'),
            subtitle: const Text('يظهر «رسالة جديدة» بس على شاشة القفل'),
            value: _R2Store.get<bool>('hide_sender') ?? false,
            onChanged: (v) async {
              await _R2Store.set('hide_sender', v);
              if (mounted) setState(() {});
            },
          ),
        ),
        const SizedBox(height: _Sp.md),
        const Text('المكالمات الواردة تبقى تنبّهك. لو تبي ساعات نوم ثابتة كل يوم استخدم «وضع النوم» من التخصيص.',
            style: TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF), height: 1.5)),
      ]),
    );
  }
}

// ===== التخزين =====

Future<int> _dirBytes(Directory d) async {
  var n = 0;
  try {
    if (!await d.exists()) return 0;
    await for (final e in d.list(recursive: true)) {
      if (e is File) n += await e.length();
    }
  } catch (_) {}
  return n;
}

/// يحذف الأقدم لين ما يصغر الكاش تحت الحد الأعلى (202)
Future<void> _trimMediaCache() async {
  try {
    final dir = await _MediaFiles._dir();
    final max = (_R2Store.get<int>('cache_mb') ?? _C.cacheLimitMb) * 1024 * 1024;
    final files = <(File, DateTime, int)>[];
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) {
        final len = await e.length();
        files.add((e, await e.lastModified(), len));
        total += len;
      }
    }
    if (total <= max) return;
    files.sort((a, b) => a.$2.compareTo(b.$2));
    for (final f in files) {
      if (total <= max) break;
      try {
        await f.$1.delete();
        total -= f.$3;
      } catch (_) {}
    }
  } catch (_) {}
}

class CacheScreen extends StatefulWidget {
  const CacheScreen({super.key});

  @override
  State<CacheScreen> createState() => _CacheState();
}

class _CacheState extends State<CacheScreen> {
  int? _bytes;
  int _limit = _R2Store.get<int>('cache_mb') ?? _C.cacheLimitMb;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final b = await _dirBytes(await _MediaFiles._dir());
    if (mounted) setState(() => _bytes = b);
  }

  String _size(int b) => b > 1024 * 1024 ? '${(b / 1048576).toStringAsFixed(1)} ميغا' : '${(b / 1024).round()} كيلو';

  @override
  Widget build(BuildContext context) => _R2Page(
        title: 'التخزين',
        child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
          Glass(
            radius: 24,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('كاش الصور والفيديو', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: _Sp.xs),
              Text(_bytes == null ? 'نحسب...' : 'الحجم الحالي: ${_size(_bytes!)}',
                  style: const TextStyle(color: Color(0xCCFFFFFF))),
              const SizedBox(height: _Sp.md),
              Text('الحد الأعلى: $_limit ميغا', style: const TextStyle(fontSize: _Fs.meta)),
              Slider(
                min: 100,
                max: 2000,
                divisions: 19,
                value: _limit.toDouble().clamp(100, 2000),
                label: '$_limit',
                onChanged: (v) => setState(() => _limit = v.round()),
                onChangeEnd: (v) async {
                  await _R2Store.set('cache_mb', v.round());
                  await _trimMediaCache();
                  await _load();
                },
              ),
              const Text('لما يوصل الحد نحذف الأقدم لحاله. الوسائط الأصلية تبقى بالسيرفر وتنزل من جديد لو احتجتها.',
                  style: TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF), height: 1.5)),
            ]),
          ),
          const SizedBox(height: _Sp.lg),
          _Btn(
              label: 'امسح الكاش',
              onTap: () async {
                await _MediaFiles.clearAll();
                await _load();
                if (context.mounted) _toast(context, 'انمسح الكاش.');
              }),
        ]),
      );
}

// ===== الأرقام والوقت =====

class FormatScreen extends StatefulWidget {
  const FormatScreen({super.key});

  @override
  State<FormatScreen> createState() => _FormatState();
}

class _FormatState extends State<FormatScreen> {
  Future<void> _flip(String k, bool v) async {
    await _R2Store.set(k, v);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return _R2Page(
      title: 'الأرقام والوقت',
      child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
        Glass(
          radius: 24,
          padding: EdgeInsets.zero,
          child: Column(children: [
            SwitchListTile(
              title: const Text('أرقام عربية (٠١٢٣)'),
              value: _Fmt.arabicDigits,
              onChanged: (v) => _flip('arabic_digits', v),
            ),
            SwitchListTile(
              title: const Text('نظام 24 ساعة'),
              subtitle: const Text('أطفيه لعرض ص وم'),
              value: _Fmt.h24,
              onChanged: (v) => _flip('h24', v),
            ),
            SwitchListTile(
              title: const Text('أسماء الأشهر العراقية'),
              subtitle: const Text('كانون، شباط، تموز، تشرين...'),
              value: _Fmt.iraqiMonths,
              onChanged: (v) => _flip('iraqi_months', v),
            ),
          ]),
        ),
        const SizedBox(height: _Sp.lg),
        Center(child: Text('${_Fmt.date(now)} · ${_Fmt.time(now)}', style: const TextStyle(fontSize: _Fs.heading))),
      ]),
    );
  }
}

// ===== التشخيص =====

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagState();
}

class _DiagState extends State<DiagnosticsScreen> {
  String _net1 = 'نفحص...';
  String _text = '';

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final sw = Stopwatch()..start();
    var conn = '';
    try {
      await _net(_db.from('profiles').select('id').limit(1));
      conn = 'شغّال (${sw.elapsedMilliseconds} ms)';
    } catch (e) {
      conn = 'فشل: ${_friendlyError(e)}';
    }
    await _R2.checkClock();
    final skew = _R2.clockOff.value;
    final lastErr = _R2Store.get<String>('last_error') ?? 'ما في';
    final t = StringBuffer()
      ..writeln('الإصدار: ${_R2.verLabel()}')
      ..writeln('المنصة: ${defaultTargetPlatform.name}')
      ..writeln('الاتصال بالسيرفر: $conn')
      ..writeln('الإشعارات: ${Push.status}')
      ..writeln('ساعة الجهاز: ${skew == null ? 'سليمة' : 'تختلف ${skew.inMinutes} دقيقة عن السيرفر'}')
      ..writeln('الجهاز: ${(await _R2.deviceId()).substring(0, 8)}')
      ..writeln('آخر خطأ: $lastErr');
    if (mounted) {
      setState(() {
        _net1 = conn;
        _text = t.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) => _R2Page(
        title: 'تشخيص',
        child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
          Glass(
            radius: 24,
            child: SelectableText(_text.isEmpty ? 'نفحص... $_net1' : _text,
                style: const TextStyle(height: 1.8, fontSize: _Fs.body)),
          ),
          const SizedBox(height: _Sp.lg),
          _Btn(
              label: 'انسخ التقرير للدعم',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: _text));
                if (context.mounted) _toast(context, 'تم النسخ');
              }),
          const SizedBox(height: _Sp.md),
          TextButton(onPressed: _run, child: const Text('أعد الفحص')),
        ]),
      );
}
