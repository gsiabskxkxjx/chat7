part of 'main.dart';

// ===== التشفير بين الطرفين (E2EE) =====
// كل جهاز يسوي مفتاح خاص (X25519) ما يطلع منه أبداً، والمفتاح العام ينحفظ بالسيرفر.
// مفتاح المحادثة = ECDH بين مفتاحك الخاص ومفتاح الطرف الثاني ثم HKDF، والرسائل تتشفّر بـ AES-256-GCM.
// السيرفر يشوف نص مشفّر فقط (e2e1:<رقم المحادثة>:<base64>)، حتى لو انفتحت قاعدة البيانات كاملة.

const _e2ePrefix = e2ePrefix;
const _e2eLocked = '🔒 رسالة مشفّرة، تعذّر فتحها على هالجهاز';

final _navKey = GlobalKey<NavigatorState>();

class _E2EUnavailable implements Exception {
  const _E2EUnavailable([this.why = 'no_key']);
  final String why;
  @override
  String toString() => 'e2e_unavailable:$why';
}

// ---- عمليات AES (تنعمل بخيط منفصل للملفات الكبيرة) ----

Future<Uint8List> _e2eAesSeal(Uint8List key, Uint8List data, Uint8List aad) =>
    E2ECrypto.sealBytes(key, data, aad);

Future<Uint8List?> _e2eAesOpen(Uint8List key, Uint8List data, Uint8List aad) =>
    E2ECrypto.openBytes(key, data, aad);

Future<Uint8List> _isoSeal(Uint8List k, Uint8List d, Uint8List a) =>
    Isolate.run(() => E2ECrypto.sealBytes(k, d, a));

Future<Uint8List?> _isoOpen(Uint8List k, Uint8List d, Uint8List a) =>
    Isolate.run(() => E2ECrypto.openBytes(k, d, a));

Future<Uint8List> _isoKdf(String code, Uint8List salt) =>
    Isolate.run(() => E2ECrypto.kdf(code, salt));

class _E2E {
  static final _store = FlutterSecureStorage();
  static Uint8List? _seed;
  static Uint8List? _pub;
  static String? _uid;
  static Future<void>? _initF;
  static Completer<void> _ready = Completer<void>();

  /// المحادثة المفتوحة حالياً (تُستعمل لما الطلب ما فيه رقم محادثة)
  static String? activeChat;
  static List<String> chatIds = const [];

  static final epoch = ValueNotifier<int>(0);
  static final changed = ValueNotifier<Set<String>>(<String>{});
  static final noPeer = ValueNotifier<Set<String>>(<String>{});

  static final _keys = <String, cr.SecretKey>{};
  static final _peer = <String, Uint8List>{};
  static final _peerAt = <String, DateTime>{};
  static final _olds = <String, List<Uint8List>>{};
  static final _lastRefresh = <String, DateTime>{};
  static final _plain = <String, String>{};
  static bool _codeShowing = false;
  static bool _migrating = false;

  static bool get isReady => _seed != null;
  static Uint8List? get myPub => _pub;

  static Future<void> waitReady() => _ready.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );

  static void onAuthChange() {
    if (_db.auth.currentUser == null) {
      _uid = null;
      _initF = null;
      _seed = null;
      _pub = null;
      _keys.clear();
      _peer.clear();
      _peerAt.clear();
      _olds.clear();
      _plain.clear();
      activeChat = null;
      chatIds = const [];
      if (_ready.isCompleted) _ready = Completer<void>();
    } else {
      unawaited(init());
    }
  }

  static Future<void> init() {
    final u = _db.auth.currentUser;
    if (u == null) return Future<void>.value();
    if (_uid == u.id && _initF != null) return _initF!;
    _uid = u.id;
    _seed = null;
    _pub = null;
    _keys.clear();
    _peer.clear();
    _peerAt.clear();
    _olds.clear();
    _plain.clear();
    if (_ready.isCompleted) _ready = Completer<void>();
    return _initF = _init(u.id).whenComplete(() {
      if (_seed == null) _initF = null; // نعيد المحاولة لاحقاً
    });
  }

  // ---------- تهيئة المفاتيح ----------

  static Future<void> _init(String uid) async {
    try {
      final stored = await _store.read(key: 'e2e_seed_$uid');
      Map<String, dynamic>? row;
      var fetched = false;
      try {
        row = await _db
            .from('e2e_keys')
            .select('pub,backup,backup_salt')
            .maybeSingle();
        fetched = true;
      } catch (_) {}
      try {
        final cs = await _db.from('chats').select('id');
        chatIds = [for (final c in cs) c['id'] as String];
      } catch (_) {}

      if (stored != null) {
        final seed = Uint8List.fromList(base64Decode(stored));
        final pub = await _pubOf(seed);
        if (!fetched) {
          _setSeed(seed, pub); // بدون إنترنت: نكمل بمفتاح الجهاز
          return;
        }
        if (row == null) {
          await _publishNew(uid, seed, pub, replace: false);
        } else if (row['pub'] == base64Encode(pub)) {
          _setSeed(seed, pub);
          if (await _store.read(key: 'e2e_codepending_$uid') != null) {
            unawaited(_showCode(uid));
          }
        } else {
          // المفتاح بالسيرفر غير مفتاح هالجهاز (انسوّى من جهاز ثاني)
          await _store.delete(key: 'e2e_seed_$uid');
          await _askRestore(uid, row);
        }
        return;
      }
      if (!fetched) return;
      if (row == null) {
        await _setupNew(uid);
      } else {
        await _askRestore(uid, row);
      }
    } catch (_) {}
  }

  static Future<Uint8List> _pubOf(Uint8List seed) => E2ECrypto.pubOf(seed);

  static void _setSeed(Uint8List seed, Uint8List pub) {
    _seed = seed;
    _pub = pub;
    if (!_ready.isCompleted) _ready.complete();
    epoch.value++;
    unawaited(migrateLegacy());
  }

  static Uint8List _rand(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  static String _newCode() {
    const al = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List<String>.generate(24, (_) => al[r.nextInt(al.length)]).join();
  }

  static String fmtCode(String c) {
    final b = StringBuffer();
    for (var i = 0; i < c.length; i++) {
      if (i > 0 && i % 4 == 0) b.write('-');
      b.write(c[i]);
    }
    return b.toString();
  }

  static String _normCode(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static Future<String> _wrap(Uint8List seed, String code, Uint8List salt) async =>
      E2ECrypto.wrap(seed, await _isoKdf(code, salt));

  static Future<Uint8List?> _unwrap(String bk, String code, Uint8List salt) async {
    try {
      return await E2ECrypto.unwrap(bk, await _isoKdf(code, salt));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _setupNew(String uid) async {
    final k = await E2ECrypto.newKeys();
    await _publishNew(uid, k.seed, k.pub, replace: false);
  }

  /// ينشر المفتاح العام + نسخة احتياطية مشفّرة برمز يظهر للمستخدم مرة وحدة
  static Future<void> _publishNew(String uid, Uint8List seed, Uint8List pub,
      {required bool replace}) async {
    final code = _newCode();
    final salt = _rand(16);
    final bk = await _wrap(seed, code, salt);
    await _store.write(key: 'e2e_seed_$uid', value: base64Encode(seed));
    await _store.write(key: 'e2e_codepending_$uid', value: code);
    await _db.rpc('e2e_publish', params: {
      'p_pub': base64Encode(pub),
      'p_backup': bk,
      'p_salt': base64Encode(salt),
      'p_replace': replace,
    });
    _setSeed(seed, pub);
    unawaited(_showCode(uid));
  }

  /// رمز جديد لنفس المفتاح (الرمز القديم يبطل)
  static Future<void> renewBackup() async {
    final uid = _uid;
    final seed = _seed;
    final pub = _pub;
    if (uid == null || seed == null || pub == null) return;
    final code = _newCode();
    final salt = _rand(16);
    final bk = await _wrap(seed, code, salt);
    await _db.rpc('e2e_publish', params: {
      'p_pub': base64Encode(pub),
      'p_backup': bk,
      'p_salt': base64Encode(salt),
      'p_replace': false,
    });
    await _store.write(key: 'e2e_codepending_$uid', value: code);
    unawaited(_showCode(uid));
  }

  static Future<BuildContext?> _ctx() async {
    for (var i = 0; i < 80; i++) {
      final c = _navKey.currentContext;
      if (c != null && c.mounted) return c;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  static Future<void> _showCode(String uid) async {
    if (_codeShowing) return;
    final code = await _store.read(key: 'e2e_codepending_$uid');
    if (code == null) return;
    _codeShowing = true;
    try {
      final ctx = await _ctx();
      if (ctx == null) return;
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => _CodeDialog(code: fmtCode(code)),
      );
      await _store.delete(key: 'e2e_codepending_$uid');
    } finally {
      _codeShowing = false;
    }
  }

  static Future<void> _askRestore(String uid, Map<String, dynamic> row) async {
    final ctx = await _ctx();
    if (ctx == null) return;
    final bk = (row['backup'] as String?) ?? '';
    Uint8List salt;
    try {
      salt = base64Decode((row['backup_salt'] as String?) ?? '');
    } catch (_) {
      salt = Uint8List(0);
    }
    final ok = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _RestoreDialog(
        verify: (code) async {
          final seed = await _unwrap(bk, _normCode(code), salt);
          if (seed == null) return false;
          final pub = await _pubOf(seed);
          if (row['pub'] != base64Encode(pub)) return false;
          await _store.write(key: 'e2e_seed_$uid', value: base64Encode(seed));
          _setSeed(seed, pub);
          return true;
        },
        onNew: () async {
          final k = await E2ECrypto.newKeys();
          await _publishNew(uid, k.seed, k.pub, replace: true);
          return true;
        },
      ),
    );
    if (ok != true) {
      // ما كمّل: نخلي التطبيق يسأل مرة ثانية بالمرة الجاية
      _initF = null;
    }
  }

  // ---------- مفاتيح المحادثات ----------

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<cr.SecretKey> _derive(String chatId, Uint8List peer) =>
      E2ECrypto.derive(_seed!, peer, chatId);

  static final _keyInflight = <String, Future<cr.SecretKey?>>{};

  /// طلب واحد فقط لكل محادثة (حتى لو انفكت 100 رسالة بنفس الوقت)
  static Future<cr.SecretKey?> keyFor(String chatId) =>
      _keyInflight[chatId] ??= _keyForImpl(chatId).whenComplete(() => _keyInflight.remove(chatId));

  static Future<cr.SecretKey?> _keyForImpl(String chatId) async {
    if (_seed == null) return null;
    var peer = _peer[chatId];
    final at = _peerAt[chatId];
    final stale = at == null || DateTime.now().difference(at) > const Duration(minutes: 5);
    if (peer == null || stale) {
      try {
        final r = await _db.rpc('e2e_partner_pub', params: {'p_chat': chatId});
        if (r is Map && r['pub'] is String) {
          final b64 = r['pub'] as String;
          final np = Uint8List.fromList(base64Decode(b64));
          if (peer == null || !_eq(peer, np)) {
            if (peer != null) {
              _keys.remove(chatId);
              _plain.clear();
            }
            peer = np;
            _peer[chatId] = np;
            await _pin(chatId, b64);
          }
          _peerAt[chatId] = DateTime.now();
        } else if (peer == null) {
          return null; // الطرف الثاني لسه ما سوّى مفتاح
        }
      } catch (_) {
        if (peer == null) return null;
      }
    }
    var k = _keys[chatId];
    if (k != null) return k;
    k = await _derive(chatId, peer!);
    _keys[chatId] = k;
    return k;
  }

  static Future<void> _pin(String chatId, String pub) async {
    try {
      final pk = 'e2e_pin_$chatId';
      final old = await _store.read(key: pk);
      if (old == null) {
        await _store.write(key: pk, value: pub);
        return;
      }
      if (old == pub) return;
      final hk = 'e2e_hist_$chatId';
      final h = <String>[];
      final raw = await _store.read(key: hk);
      if (raw != null) {
        try {
          h.addAll((jsonDecode(raw) as List).cast<String>());
        } catch (_) {}
      }
      if (!h.contains(old)) h.add(old);
      await _store.write(key: hk, value: jsonEncode(h));
      await _store.write(key: pk, value: pub);
      await _store.write(key: 'e2e_changed_$chatId', value: '1');
      _olds[chatId] = [for (final x in h) Uint8List.fromList(base64Decode(x))];
      changed.value = {...changed.value, chatId};
    } catch (_) {}
  }

  static Future<List<Uint8List>> _history(String chatId) async {
    final c = _olds[chatId];
    if (c != null) return c;
    final out = <Uint8List>[];
    try {
      final raw = await _store.read(key: 'e2e_hist_$chatId');
      if (raw != null) {
        for (final x in (jsonDecode(raw) as List).cast<String>()) {
          out.add(Uint8List.fromList(base64Decode(x)));
        }
      }
    } catch (_) {}
    _olds[chatId] = out;
    return out;
  }

  static Future<void> prepare(String chatId) async {
    await waitReady();
    final k = await keyFor(chatId);
    final s = Set<String>.of(noPeer.value);
    if (k == null) {
      s.add(chatId);
    } else {
      s.remove(chatId);
    }
    noPeer.value = s;
    try {
      if (await _store.read(key: 'e2e_changed_$chatId') != null) {
        changed.value = {...changed.value, chatId};
      }
    } catch (_) {}
  }

  static Future<void> ackChange(String chatId) async {
    try {
      await _store.delete(key: 'e2e_changed_$chatId');
    } catch (_) {}
    changed.value = Set<String>.of(changed.value)..remove(chatId);
  }

  // ---------- نصوص ----------

  static String? defaultChat() {
    final a = activeChat;
    if (a != null) return a;
    if (chatIds.length == 1) return chatIds.first;
    return null;
  }

  static Future<String> seal(String chatId, String plain) async {
    await waitReady();
    final k = await keyFor(chatId);
    if (k == null) throw const _E2EUnavailable();
    return E2ECrypto.seal(k, chatId, plain);
  }

  static Future<String?> open(String s) async {
    final cached = _plain[s];
    if (cached != null) return cached;
    final chatId = E2ECrypto.chatOf(s);
    if (chatId == null) return null;
    var res = await _tryOpen(chatId, s);
    if (res == null) {
      // يمكن مفتاح الطرف الثاني تغيّر: نحدّثه مرة كل نص دقيقة
      final last = _lastRefresh[chatId];
      if (last == null || DateTime.now().difference(last) > const Duration(seconds: 30)) {
        _lastRefresh[chatId] = DateTime.now();
        _peerAt.remove(chatId);
        res = await _tryOpen(chatId, s);
      }
    }
    if (res != null) {
      if (_plain.length > 3000) _plain.clear();
      _plain[s] = res;
    }
    return res;
  }

  static Future<List<cr.SecretKey>> _allKeys(String chatId) async {
    final keys = <cr.SecretKey>[];
    final cur = await keyFor(chatId);
    if (cur != null) keys.add(cur);
    for (final p in await _history(chatId)) {
      keys.add(await _derive(chatId, p));
    }
    return keys;
  }

  static Future<String?> _tryOpen(String chatId, String s) async {
    if (_seed == null) return null;
    return E2ECrypto.open(s, await _allKeys(chatId));
  }

  /// يمشي على JSON ويفك كل نص مشفّر
  static Future<dynamic> walk(dynamic v) async {
    if (v is String) {
      if (!v.startsWith(_e2ePrefix)) return v;
      await waitReady();
      return (await open(v)) ?? _e2eLocked;
    }
    if (v is List) {
      for (var i = 0; i < v.length; i++) {
        v[i] = await walk(v[i]);
      }
      return v;
    }
    if (v is Map) {
      if (v['_e2e'] is String) {
        await waitReady();
        final s = await open(v['_e2e'] as String);
        if (s != null) {
          try {
            return jsonDecode(s);
          } catch (_) {}
        }
        return <String, dynamic>{};
      }
      for (final k in v.keys.toList()) {
        v[k] = await walk(v[k]);
      }
      return v;
    }
    return v;
  }

  static bool _hasCipher(Object? v) {
    if (v is String) return v.startsWith(_e2ePrefix);
    if (v is Map) return v.containsKey('_e2e') || v.values.any(_hasCipher);
    if (v is List) return v.any(_hasCipher);
    return false;
  }

  /// صفوف الستريم (Realtime توصل مشفّرة بدون مرورها بطبقة HTTP)
  static Future<List<Map<String, dynamic>>> openRows(List<Map<String, dynamic>> rows) async {
    if (!rows.any(_hasCipher)) return rows;
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final c = Map<String, dynamic>.from(r);
      out.add(Map<String, dynamic>.from(await walk(c) as Map));
    }
    return out;
  }

  // ---------- ملفات ----------

  static bool isSealed(List<int> b) => E2ECrypto.isSealed(b);

  static Future<Uint8List> sealBytes(String chatId, Uint8List data) async {
    await waitReady();
    final k = await keyFor(chatId);
    if (k == null) throw const _E2EUnavailable();
    final kb = Uint8List.fromList(await k.extractBytes());
    final aad = Uint8List.fromList(utf8.encode(chatId));
    if (data.length > 200 * 1024) return _isoSeal(kb, data, aad);
    return _e2eAesSeal(kb, data, aad);
  }

  static Future<Uint8List?> openBytes(String chatId, Uint8List data) async {
    await waitReady();
    if (_seed == null) return null;
    final aad = Uint8List.fromList(utf8.encode(chatId));
    for (final k in await _allKeys(chatId)) {
      final kb = Uint8List.fromList(await k.extractBytes());
      final r = data.length > 200 * 1024
          ? await _isoOpen(kb, data, aad)
          : await _e2eAesOpen(kb, data, aad);
      if (r != null) return r;
    }
    return null;
  }

  /// يرفع ملف مشفّر لمخزن الوسائط (السيرفر يشوف بايتات عشوائية بس)
  static Future<void> uploadFile(String chatId, String path, File f) async {
    final enc = await sealBytes(chatId, await f.readAsBytes());
    await _db.storage.from('chat-media').uploadBinary(path, enc,
        fileOptions: FileOptions(contentType: 'application/octet-stream'));
  }

  // ---------- تشفير الرسائل القديمة ----------

  static Future<int> migrateLegacy() async {
    final uid = _uid;
    if (uid == null || _seed == null || _migrating) return 0;
    _migrating = true;
    var total = 0;
    try {
      for (var round = 0; round < 8; round++) {
        final rows = await _db
            .from('messages')
            .select('id,chat_id,body,reply_quote,alt')
            .eq('sender_id', uid)
            .inFilter('kind', const ['text', 'card', 'location', 'ref', 'file', 'alert'])
            .neq('body', '')
            .not('body', 'like', '$_e2ePrefix%')
            .order('id', ascending: false)
            .limit(100);
        if (rows.isEmpty) break;
        final out = <Map<String, dynamic>>[];
        for (final r in rows) {
          try {
            final chat = r['chat_id'] as String;
            final m = <String, dynamic>{'id': r['id']};
            m['body'] = await seal(chat, r['body'] as String);
            final rq = r['reply_quote'];
            if (rq is String && rq.isNotEmpty) m['reply_quote'] = await seal(chat, rq);
            final al = r['alt'];
            if (al is String && al.isNotEmpty) m['alt'] = await seal(chat, al);
            out.add(m);
          } catch (_) {}
        }
        if (out.isEmpty) break;
        final n = await _db.rpc('e2e_migrate', params: {'p_table': 'messages', 'p_rows': out});
        total += (n is int) ? n : 0;
        if (rows.length < 100) break;
      }
      for (final t in const ['love_notes', 'diary_entries']) {
        final rows = await _db
            .from(t)
            .select('id,chat_id,body')
            .eq('author', uid)
            .not('body', 'like', '$_e2ePrefix%')
            .limit(100);
        final out = <Map<String, dynamic>>[];
        for (final r in rows) {
          try {
            out.add({'id': r['id'], 'body': await seal(r['chat_id'] as String, r['body'] as String)});
          } catch (_) {}
        }
        if (out.isNotEmpty) {
          final n = await _db.rpc('e2e_migrate', params: {'p_table': t, 'p_rows': out});
          total += (n is int) ? n : 0;
        }
      }
    } catch (_) {
    } finally {
      _migrating = false;
    }
    return total;
  }

  // ---------- رقم الأمان ----------

  static Future<String?> safetyNumber(String chatId) async {
    await waitReady();
    final k = await keyFor(chatId);
    final mine = _pub;
    final peer = _peer[chatId];
    if (k == null || mine == null || peer == null) return null;
    return E2ECrypto.safety(mine, peer);
  }
}

// ===== طبقة HTTP: تشفّر عند الإرسال وتفك عند الاستلام (كل التطبيق يمر منها) =====

class _E2EClient extends http.BaseClient {
  _E2EClient(this._inner);
  final http.Client _inner;

  @override
  void close() => _inner.close();

  static const _cols = <String, List<String>>{
    'messages': ['body', 'reply_quote', 'alt'],
    'scheduled_messages': ['body'],
    'love_notes': ['body'],
    'diary_entries': ['body'],
    'time_capsules': ['body'],
    'shared_items': ['body'],
    'daily_needs': ['need'],
    'daily_answers': ['answer'],
  };
  static const _jsonCols = <String, List<String>>{
    'call_signals': ['data'],
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final seg = request.url.pathSegments;
    final rest = seg.length >= 3 && seg[0] == 'rest' && seg[1] == 'v1';
    var req = request;
    if (rest &&
        request is http.Request &&
        (request.method == 'POST' || request.method == 'PATCH' || request.method == 'PUT') &&
        request.bodyBytes.isNotEmpty) {
      req = await _sealReq(request, seg);
    }
    final res = await _inner.send(req);
    if (!rest) return res;
    final ct = res.headers['content-type'] ?? '';
    if (!ct.contains('json')) return res;
    final bytes = await res.stream.toBytes();
    var out = bytes;
    if (bytes.length > 16) {
      final s = utf8.decode(bytes, allowMalformed: true);
      if (s.contains(_e2ePrefix) || s.contains('"_e2e"')) {
        try {
          final j = await _E2E.walk(jsonDecode(s));
          out = Uint8List.fromList(utf8.encode(jsonEncode(j)));
        } catch (_) {}
      }
    }
    final h = Map<String, String>.from(res.headers)
      ..remove('content-length')
      ..remove('content-encoding')
      ..remove('transfer-encoding');
    return http.StreamedResponse(Stream<List<int>>.value(out), res.statusCode,
        contentLength: out.length,
        request: res.request,
        headers: h,
        isRedirect: res.isRedirect,
        persistentConnection: res.persistentConnection,
        reasonPhrase: res.reasonPhrase);
  }

  Future<http.BaseRequest> _sealReq(http.Request r, List<String> seg) async {
    final table = seg[2];
    final cols = _cols[table];
    final jcols = _jsonCols[table];
    final isRpc = table == 'rpc';
    if (cols == null && jcols == null && !isRpc) return r;
    dynamic j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      return r;
    }
    var changed = false;

    Future<String> sealStr(String? chat, String v) async {
      final c = chat ?? _E2E.defaultChat();
      if (c == null) throw const _E2EUnavailable('no_chat');
      changed = true;
      return _E2E.seal(c, v);
    }

    if (isRpc) {
      final fn = seg.length > 3 ? seg[3] : '';
      if (j is Map<String, dynamic>) {
        if (fn == 'edit_message' && j['p_body'] is String && !(j['p_body'] as String).startsWith(_e2ePrefix)) {
          j['p_body'] = await sealStr(null, j['p_body'] as String);
        } else if (fn == 'daily_answer' &&
            j['p_answer'] is String &&
            !(j['p_answer'] as String).startsWith(_e2ePrefix)) {
          j['p_answer'] = await sealStr(j['p_chat'] as String?, j['p_answer'] as String);
        }
      }
    } else {
      Future<void> row(dynamic m) async {
        if (m is! Map<String, dynamic>) return;
        final chat = m['chat_id'] is String ? m['chat_id'] as String : null;
        for (final c in cols ?? const <String>[]) {
          final v = m[c];
          if (v is String && v.isNotEmpty && !v.startsWith(_e2ePrefix)) {
            m[c] = await sealStr(chat, v);
          }
        }
        for (final c in jcols ?? const <String>[]) {
          final v = m[c];
          if (v is Map && !v.containsKey('_e2e')) {
            // علامة الفيديو تبقى ظاهرة حتى يطلع إشعار المكالمة بنوعها الصحيح
            m[c] = {
              '_e2e': await sealStr(chat, jsonEncode(v)),
              if (v['video'] is bool) 'video': v['video'],
            };
          }
        }
      }

      if (j is List) {
        for (final x in j) {
          await row(x);
        }
      } else {
        await row(j);
      }
    }
    if (!changed) return r;
    final n = http.Request(r.method, r.url)
      ..headers.addAll(r.headers)
      ..bodyBytes = utf8.encode(jsonEncode(j))
      ..followRedirects = r.followRedirects
      ..maxRedirects = r.maxRedirects
      ..persistentConnection = r.persistentConnection;
    return n;
  }
}

extension _E2EStream on Stream<List<Map<String, dynamic>>> {
  Stream<List<Map<String, dynamic>>> get e2e => asyncMap(_E2E.openRows);
}

// ===== واجهات =====

/// شريط أعلى المحادثة: مفتاح تغيّر / الطرف الثاني ما سوّى تشفير بعد
class _E2EBar extends StatelessWidget {
  const _E2EBar({required this.chatId});
  final String chatId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_E2E.changed, _E2E.noPeer]),
        builder: (c, _) {
          if (_E2E.noPeer.value.contains(chatId)) {
            return _r2Bar('⏳', 'التشفير ما اكتمل: الطرف الثاني لازم يفتح آخر نسخة من التطبيق حتى تنرسل رسائلكم.',
                onTap: () => unawaited(_E2E.prepare(chatId)));
          }
          if (_E2E.changed.value.contains(chatId)) {
            return _r2Bar('⚠️', 'مفتاح الأمان للطرف الثاني تغيّر (ممكن غيّر جهازه). قارن رقم الأمان قبل لا تثق.',
                onTap: () => _r2Push(c, _E2EScreen(chatId: chatId)));
          }
          return const SizedBox.shrink();
        },
      );
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.code});
  final String code;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('🔐 رمز استرجاع محادثاتك'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                  'محادثاتكم مشفّرة، والسيرفر ما يقدر يقراها. هذا الرمز الوحيد اللي يرجّعها لو غيّرت جهازك أو مسحت التطبيق. اكتبه بمكان آمن، وما ننعرضه مرة ثانية.'),
              const SizedBox(height: 14),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: SelectableText(widget.code,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1.5, fontFamily: 'monospace')),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: widget.code));
                    if (context.mounted) _toast(context, 'انسخ. الصقه بمكان آمن وامسحه من الحافظة.');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('نسخ'),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _saved,
                onChanged: (v) => setState(() => _saved = v ?? false),
                title: const Text('كتبت الرمز بمكان آمن'),
              ),
            ]),
          ),
          actions: [
            FilledButton(
              onPressed: _saved ? () => Navigator.of(context).pop() : null,
              child: const Text('تم'),
            ),
          ],
        ),
      );
}

class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog({required this.verify, required this.onNew});
  final Future<bool> Function(String code) verify;
  final Future<bool> Function() onNew;

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  final _c = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    bool ok = false;
    try {
      ok = await widget.verify(_c.text);
    } catch (_) {}
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _err = 'الرمز غلط. تأكد منه وجرّب مرة ثانية.';
      });
    }
  }

  Future<void> _fresh() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تبدأ بمفاتيح جديدة؟'),
        content: const Text(
            'الرسائل والصور القديمة اللي انرسلت قبل ما تضيع المفاتيح ما راح ترجع تنفتح عندك أبداً. الرسائل الجديدة تشتغل عادي.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إي، ابدأ من جديد')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    bool ok = false;
    try {
      ok = await widget.onNew();
    } catch (_) {}
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _err = 'تعذر، تأكد من الإنترنت.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('🔐 استرجاع محادثاتك'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('هذا جهاز جديد أو نظيف. اكتب رمز الاسترجاع اللي انعرض لك أول مرة حتى ترجع محادثاتك القديمة.'),
              const SizedBox(height: 12),
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _c,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.2),
                  decoration: InputDecoration(hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX', errorText: _err),
                  onSubmitted: (_) => unawaited(_go()),
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: _busy ? null : _fresh, child: const Text('ما عندي الرمز')),
            FilledButton(onPressed: _busy ? null : _go, child: const Text('استرجاع')),
          ],
        ),
      );
}

/// شاشة التشفير والأمان (رقم الأمان للمحادثة + الرمز + تشفير القديم)
class _E2EScreen extends StatefulWidget {
  const _E2EScreen({this.chatId});
  final String? chatId;

  @override
  State<_E2EScreen> createState() => _E2EScreenState();
}

class _E2EScreenState extends State<_E2EScreen> {
  String? _safety;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    String? s;
    final id = widget.chatId;
    if (id != null) {
      await _E2E.prepare(id);
      s = await _E2E.safetyNumber(id);
    } else {
      await _E2E.waitReady();
    }
    if (!mounted) return;
    setState(() {
      _safety = s;
      _loading = false;
    });
  }

  Future<void> _renew() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رمز جديد؟'),
        content: const Text('الرمز القديم يبطل. اكتب الجديد بمكان آمن.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _E2E.renewBackup();
    } catch (e) {
      if (mounted) _toast(context, _friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _migrate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final n = await _E2E.migrateLegacy();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(context, n > 0 ? 'تشفّرت $n من رسائلك القديمة.' : 'ماكو رسائل قديمة تحتاج تشفير من عندك.');
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.chatId;
    return _R2Page(
      title: 'التشفير والأمان',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
              Glass(
                radius: 24,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_E2E.isReady ? Icons.lock_rounded : Icons.lock_open_rounded),
                    const SizedBox(width: 10),
                    Text(_E2E.isReady ? 'محادثاتكم مشفّرة بين الطرفين' : 'التشفير غير جاهز بعد',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: _Fs.title)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                      'الرسائل والصور والفيديوهات والصوتيات والملفات والمكالمات تتشفّر بجوالك قبل ما تطلع. السيرفر وصاحب التطبيق يشوفون بايتات غير مفهومة، وبس إنت والطرف الثاني تفكونها.'),
                ]),
              ),
              if (id != null) ...[
                const SizedBox(height: _Sp.md),
                ValueListenableBuilder<Set<String>>(
                  valueListenable: _E2E.changed,
                  builder: (_, ch, __) => ch.contains(id)
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: _Sp.md),
                          child: Glass(
                            radius: 24,
                            tint: const Color(0x33FFB300),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('⚠️ مفتاح الأمان للطرف الثاني تغيّر',
                                  style: TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              const Text(
                                  'يصير إذا غيّر جهازه أو مسح التطبيق. قارن رقم الأمان معاه بمكالمة أو شخصياً، وإذا تطابق اضغط تأكيد.'),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton(
                                    onPressed: () => unawaited(_E2E.ackChange(id)),
                                    child: const Text('تأكيد، الرقم يتطابق')),
                              ),
                            ]),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Glass(
                  radius: 24,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('رقم الأمان', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_safety == null)
                      const Text('الطرف الثاني لسه ما فعّل التشفير. لازم يفتح آخر نسخة من التطبيق.')
                    else ...[
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Center(
                          child: SelectableText(_safety!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 18, height: 1.7, letterSpacing: 1)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                          'اطلب من الطرف الثاني يفتح هالشاشة عنده. لو الرقم نفسه عندكم الاثنين، محد قدر يتدخل بالمحادثة.',
                          style: TextStyle(fontSize: _Fs.meta)),
                    ],
                  ]),
                ),
              ],
              const SizedBox(height: _Sp.md),
              Glass(
                radius: 24,
                padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.key_rounded),
                    title: const Text('رمز الاسترجاع'),
                    subtitle: const Text('أنشئ رمز جديد (القديم يبطل)'),
                    onTap: _busy ? null : _renew,
                  ),
                  ListTile(
                    leading: const Icon(Icons.enhanced_encryption_rounded),
                    title: const Text('تشفير رسائلي القديمة'),
                    subtitle: const Text('الرسائل اللي انرسلت قبل التشفير تتحول لمشفّرة'),
                    onTap: _busy ? null : _migrate,
                  ),
                ]),
              ),
              const SizedBox(height: _Sp.md),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: _Sp.sm),
                child: Text(
                    'شنو ما يتشفّر: اسمك وصورة حسابك، ومتى انرسلت الرسالة ونوعها (نص/صورة/صوت) وحجمها، ومين يحجي ويا مين. المكالمات تتشفّر وتمر مباشرة بين الجهازين. ميزات الذكاء الاصطناعي وتحويل الصوت لنص ترسل النص أو الصوت المحدد لخدمة خارجية فقط لما تضغطها إنت.',
                    style: TextStyle(fontSize: _Fs.meta, height: 1.6)),
              ),
            ]),
    );
  }
}
