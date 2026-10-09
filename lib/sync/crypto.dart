/// Passphrase → key and file encryption for sync (spec §4.6). Pure Dart via
/// package:cryptography, so it runs on Android, iOS and web alike.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class SyncCrypto {
  SyncCrypto._();

  static const int iterations = 200000;
  static const String checkPlain = 'upitrack-key-ok';
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  static final AesGcm _aes = AesGcm.with256bits();

  static List<int> newSalt() {
    final rng = Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256));
  }

  /// PBKDF2-HMAC-SHA256 → 32-byte key. Tests pass a small [iterations].
  static Future<SecretKey> deriveKey(String passphrase, List<int> salt,
      {int iterations = SyncCrypto.iterations}) {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    return kdf.deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
  }

  /// `nonce(12) ‖ ciphertext ‖ tag(16)`. A fresh random nonce every call.
  static Future<Uint8List> encrypt(SecretKey key, List<int> plain) async {
    final box = await _aes.encrypt(plain, secretKey: key);
    return Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// Throws [SecretBoxAuthenticationError] for a wrong key or tampered data.
  static Future<Uint8List> decrypt(SecretKey key, List<int> data) async {
    if (data.length < _nonceLength + _macLength) {
      throw const FormatException('encrypted data too short');
    }
    final box = SecretBox(
      data.sublist(_nonceLength, data.length - _macLength),
      nonce: data.sublist(0, _nonceLength),
      mac: Mac(data.sublist(data.length - _macLength)),
    );
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: key));
  }

  /// The value stored as `meta.check`: [checkPlain] encrypted, base64.
  static Future<String> makeCheck(SecretKey key) async =>
      base64Encode(await encrypt(key, utf8.encode(checkPlain)));

  /// True when [key] is the one [check] was made with.
  static Future<bool> verifyCheck(SecretKey key, String check) async {
    try {
      return utf8.decode(await decrypt(key, base64Decode(check))) == checkPlain;
    } on SecretBoxAuthenticationError {
      return false;
    } on FormatException {
      return false;
    }
  }
}
