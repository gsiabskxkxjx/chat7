import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/e2e_crypto.dart';

const chat = '123e4567-e89b-12d3-a456-426614174000';
const other = '123e4567-e89b-12d3-a456-426614174999';

void main() {
  test('both sides derive the same key and read each other', () async {
    final a = await E2ECrypto.newKeys();
    final b = await E2ECrypto.newKeys();
    final ka = await E2ECrypto.derive(a.seed, b.pub, chat);
    final kb = await E2ECrypto.derive(b.seed, a.pub, chat);
    final c = await E2ECrypto.seal(ka, chat, 'هلا وغلا 👋');
    expect(c.startsWith(e2ePrefix), isTrue);
    expect(c.contains('هلا'), isFalse);
    expect(E2ECrypto.chatOf(c), chat);
    expect(await E2ECrypto.open(c, [kb]), 'هلا وغلا 👋');
    expect(await E2ECrypto.open(c, [ka]), 'هلا وغلا 👋');
  });

  test('same text encrypts differently each time (random nonce)', () async {
    final a = await E2ECrypto.newKeys();
    final b = await E2ECrypto.newKeys();
    final k = await E2ECrypto.derive(a.seed, b.pub, chat);
    final c1 = await E2ECrypto.seal(k, chat, 'x');
    final c2 = await E2ECrypto.seal(k, chat, 'x');
    expect(c1 == c2, isFalse);
  });

  test('an outsider, another chat key, or tampering cannot open it', () async {
    final a = await E2ECrypto.newKeys();
    final b = await E2ECrypto.newKeys();
    final eve = await E2ECrypto.newKeys();
    final k = await E2ECrypto.derive(a.seed, b.pub, chat);
    final c = await E2ECrypto.seal(k, chat, 'سر');
    final keve = await E2ECrypto.derive(eve.seed, b.pub, chat);
    expect(await E2ECrypto.open(c, [keve]), isNull);
    final kOtherChat = await E2ECrypto.derive(a.seed, b.pub, other);
    expect(await E2ECrypto.open(c, [kOtherChat]), isNull);
    // flip one character in the payload
    final i = c.length - 6;
    final t = c.substring(0, i) + (c[i] == 'A' ? 'B' : 'A') + c.substring(i + 1);
    expect(await E2ECrypto.open(t, [k]), isNull);
    // moving the ciphertext to another chat id must fail (bound as AAD)
    final moved = c.replaceFirst(chat, other);
    expect(await E2ECrypto.open(moved, [k]), isNull);
  });

  test('old keys in the list are tried (partner key rotation)', () async {
    final a = await E2ECrypto.newKeys();
    final oldB = await E2ECrypto.newKeys();
    final newB = await E2ECrypto.newKeys();
    final kOld = await E2ECrypto.derive(a.seed, oldB.pub, chat);
    final kNew = await E2ECrypto.derive(a.seed, newB.pub, chat);
    final c = await E2ECrypto.seal(kOld, chat, 'قديمة');
    expect(await E2ECrypto.open(c, [kNew, kOld]), 'قديمة');
  });

  test('files: sealed bytes hide the content and open back', () async {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final aad = Uint8List.fromList(utf8.encode(chat));
    final data = Uint8List.fromList(List<int>.generate(5000, (i) => i % 251));
    final s = await E2ECrypto.sealBytes(key, data, aad);
    expect(E2ECrypto.isSealed(s), isTrue);
    expect(E2ECrypto.isSealed(data), isFalse);
    expect(await E2ECrypto.openBytes(key, s, aad), data);
    final bad = Uint8List.fromList(key)..[0] ^= 1;
    expect(await E2ECrypto.openBytes(bad, s, aad), isNull);
  });

  test('backup code wraps the private key and only the right code restores it', () async {
    final a = await E2ECrypto.newKeys();
    final salt = Uint8List.fromList(List<int>.generate(16, (i) => 7 * i));
    final good = await E2ECrypto.kdf('ABCD2345EFGH6789JKLM2345', salt, iterations: 1000);
    final bk = await E2ECrypto.wrap(a.seed, good);
    expect(bk.startsWith('bk1:'), isTrue);
    expect(await E2ECrypto.unwrap(bk, good), a.seed);
    final wrong = await E2ECrypto.kdf('ZZZZ2345EFGH6789JKLM2345', salt, iterations: 1000);
    expect(await E2ECrypto.unwrap(bk, wrong), isNull);
    expect(await E2ECrypto.pubOf(a.seed), a.pub);
  });

  test('safety number is the same for both and changes with a key', () async {
    final a = await E2ECrypto.newKeys();
    final b = await E2ECrypto.newKeys();
    final c = await E2ECrypto.newKeys();
    final n1 = await E2ECrypto.safety(a.pub, b.pub);
    final n2 = await E2ECrypto.safety(b.pub, a.pub);
    expect(n1, n2);
    expect(RegExp(r'^(\d{5} \d{5} \d{5} \d{5}\n){2}\d{5} \d{5} \d{5} \d{5}$').hasMatch(n1), isTrue);
    expect(await E2ECrypto.safety(a.pub, c.pub) == n1, isFalse);
  });
}
