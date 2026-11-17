// عمليات التشفير الصافية (بدون فلاتر) حتى نقدر نختبرها بـ flutter test.
// X25519 للمفاتيح، HKDF-SHA256 لمفتاح المحادثة، AES-256-GCM للرسائل والملفات، PBKDF2 للنسخة الاحتياطية.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cr;

const e2ePrefix = 'e2e1:';
const e2eMagic = <int>[0x42, 0x45, 0x32, 0x45, 0x31]; // BE2E1

class E2ECrypto {
  static final _x = cr.X25519();
  static final _aes = cr.AesGcm.with256bits();
  static final _hkdf = cr.Hkdf(hmac: cr.Hmac.sha256(), outputLength: 32);

  static Future<({Uint8List seed, Uint8List pub})> newKeys() async {
    final kp = await _x.newKeyPair();
    return (
      seed: Uint8List.fromList(await kp.extractPrivateKeyBytes()),
      pub: Uint8List.fromList((await kp.extractPublicKey()).bytes),
    );
  }

  static Future<Uint8List> pubOf(Uint8List seed) async {
    final kp = await _x.newKeyPairFromSeed(seed);
    return Uint8List.fromList((await kp.extractPublicKey()).bytes);
  }

  /// مفتاح المحادثة: ECDH ثم HKDF (نفس المفتاح عند الطرفين)
  static Future<cr.SecretKey> derive(Uint8List seed, Uint8List peerPub, String chatId) async {
    final kp = await _x.newKeyPairFromSeed(seed);
    final shared = await _x.sharedSecretKey(
        keyPair: kp,
        remotePublicKey: cr.SimplePublicKey(peerPub, type: cr.KeyPairType.x25519));
    return _hkdf.deriveKey(
        secretKey: shared,
        nonce: utf8.encode('bainatna-e2e-v1'),
        info: utf8.encode(chatId));
  }

  /// e2e1:<رقم المحادثة>:<base64(nonce|ciphertext|tag)>
  static Future<String> seal(cr.SecretKey k, String chatId, String plain) async {
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: k, aad: utf8.encode(chatId));
    return '$e2ePrefix$chatId:${base64Encode(box.concatenation())}';
  }

  /// رقم المحادثة المكتوب داخل النص المشفّر، أو null لو الشكل غلط
  static String? chatOf(String s) {
    if (!s.startsWith(e2ePrefix) || s.length < e2ePrefix.length + 38) return null;
    if (s[e2ePrefix.length + 36] != ':') return null;
    return s.substring(e2ePrefix.length, e2ePrefix.length + 36);
  }

  static Future<String?> open(String s, List<cr.SecretKey> keys) async {
    final chatId = chatOf(s);
    if (chatId == null) return null;
    Uint8List data;
    try {
      data = base64Decode(s.substring(e2ePrefix.length + 37));
    } catch (_) {
      return null;
    }
    for (final k in keys) {
      try {
        final box = cr.SecretBox.fromConcatenation(data, nonceLength: 12, macLength: 16);
        final clear = await _aes.decrypt(box, secretKey: k, aad: utf8.encode(chatId));
        return utf8.decode(clear);
      } catch (_) {}
    }
    return null;
  }

  // ---- ملفات ----

  static bool isSealed(List<int> b) {
    if (b.length < e2eMagic.length + 28) return false;
    for (var i = 0; i < e2eMagic.length; i++) {
      if (b[i] != e2eMagic[i]) return false;
    }
    return true;
  }

  static Future<Uint8List> sealBytes(Uint8List key, Uint8List data, Uint8List aad) async {
    final box = await _aes.encrypt(data, secretKey: cr.SecretKey(key), aad: aad);
    final b = BytesBuilder(copy: false)
      ..add(e2eMagic)
      ..add(box.concatenation());
    return b.toBytes();
  }

  static Future<Uint8List?> openBytes(Uint8List key, Uint8List data, Uint8List aad) async {
    try {
      final body = Uint8List.sublistView(data, e2eMagic.length);
      final box = cr.SecretBox.fromConcatenation(body, nonceLength: 12, macLength: 16);
      final clear = await _aes.decrypt(box, secretKey: cr.SecretKey(key), aad: aad);
      return Uint8List.fromList(clear);
    } catch (_) {
      return null;
    }
  }

  // ---- نسخة احتياطية للمفتاح الخاص برمز استرجاع ----

  static Future<Uint8List> kdf(String code, Uint8List salt, {int iterations = 100000}) async {
    final k = await cr.Pbkdf2(
            macAlgorithm: cr.Hmac.sha256(), iterations: iterations, bits: 256)
        .deriveKeyFromPassword(password: code, nonce: salt);
    return Uint8List.fromList(await k.extractBytes());
  }

  static Future<String> wrap(Uint8List seed, Uint8List kdfKey) async {
    final box = await _aes.encrypt(seed,
        secretKey: cr.SecretKey(kdfKey), aad: utf8.encode('bainatna-e2e-backup'));
    return 'bk1:${base64Encode(box.concatenation())}';
  }

  static Future<Uint8List?> unwrap(String bk, Uint8List kdfKey) async {
    try {
      if (!bk.startsWith('bk1:')) return null;
      final box = cr.SecretBox.fromConcatenation(base64Decode(bk.substring(4)),
          nonceLength: 12, macLength: 16);
      final clear = await _aes.decrypt(box,
          secretKey: cr.SecretKey(kdfKey), aad: utf8.encode('bainatna-e2e-backup'));
      return Uint8List.fromList(clear);
    } catch (_) {
      return null;
    }
  }

  /// رقم الأمان: SHA-256 للمفتاحين العامين مرتبين، 12 مجموعة من 5 أرقام
  static Future<String> safety(Uint8List a, Uint8List b) async {
    final sa = base64Encode(a);
    final sb = base64Encode(b);
    final first = sa.compareTo(sb) <= 0 ? a : b;
    final second = sa.compareTo(sb) <= 0 ? b : a;
    final h = await cr.Sha256().hash([...first, ...second]);
    final by = h.bytes;
    final groups = <String>[];
    for (var i = 0; i < 12; i++) {
      final v = (by[2 * i] << 8) | by[2 * i + 1];
      groups.add(v.toString().padLeft(5, '0'));
    }
    return [
      groups.sublist(0, 4).join(' '),
      groups.sublist(4, 8).join(' '),
      groups.sublist(8, 12).join(' '),
    ].join('\n');
  }
}
