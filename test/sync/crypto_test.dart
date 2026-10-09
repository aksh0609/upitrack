import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/sync/crypto.dart';

void main() {
  // 1000 iterations keep the suite fast; production uses SyncCrypto.iterations.
  Future<SecretKey> key(String pass, List<int> salt) =>
      SyncCrypto.deriveKey(pass, salt, iterations: 1000);

  test('encrypt → decrypt round-trips and never repeats a nonce', () async {
    final k = await key('correct horse', SyncCrypto.newSalt());
    final plain = utf8.encode('{"v":1}');
    final one = await SyncCrypto.encrypt(k, plain);
    final two = await SyncCrypto.encrypt(k, plain);
    expect(one.length, 12 + plain.length + 16);
    expect(one.sublist(0, 12), isNot(two.sublist(0, 12)));
    expect(await SyncCrypto.decrypt(k, one), plain);
    expect(await SyncCrypto.decrypt(k, two), plain);
  });

  test('the wrong key fails authentication; a tampered byte too', () async {
    final salt = SyncCrypto.newSalt();
    final good = await key('correct horse', salt);
    final bad = await key('battery staple', salt);
    final data = await SyncCrypto.encrypt(good, utf8.encode('secret'));
    expect(() => SyncCrypto.decrypt(bad, data), throwsA(isA<SecretBoxAuthenticationError>()));
    data[15] ^= 0xff;
    expect(() => SyncCrypto.decrypt(good, data), throwsA(isA<SecretBoxAuthenticationError>()));
    expect(() => SyncCrypto.decrypt(good, [1, 2, 3]), throwsFormatException);
  });

  test('the same passphrase and salt give the same key; a different salt does not', () async {
    final salt = SyncCrypto.newSalt();
    expect(salt, hasLength(16));
    final a = await (await key('p', salt)).extractBytes();
    final b = await (await key('p', salt)).extractBytes();
    final c = await (await key('p', SyncCrypto.newSalt())).extractBytes();
    expect(a, b);
    expect(a, hasLength(32));
    expect(a, isNot(c));
  });

  test('the key check tells a matching passphrase from a wrong one', () async {
    final salt = SyncCrypto.newSalt();
    final k = await key('p', salt);
    final check = await SyncCrypto.makeCheck(k);
    expect(await SyncCrypto.verifyCheck(k, check), isTrue);
    expect(await SyncCrypto.verifyCheck(await key('q', salt), check), isFalse);
    expect(await SyncCrypto.verifyCheck(k, 'not base64!'), isFalse);
  });
}
