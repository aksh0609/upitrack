import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the derived sync key lives between runs (spec §4.6: the key, never
/// the passphrase). Interface so tests can keep it in memory.
abstract class SyncKeys {
  Future<SecretKey?> read();
  Future<void> write(SecretKey key);
  Future<void> clear();
}

/// Android Keystore / iOS Keychain / WebCrypto-wrapped storage on web.
class SecureSyncKeys implements SyncKeys {
  static const _key = 'sync_key';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<SecretKey?> read() async {
    final b64 = await _storage.read(key: _key);
    return b64 == null ? null : SecretKey(base64Decode(b64));
  }

  @override
  Future<void> write(SecretKey key) async =>
      _storage.write(key: _key, value: base64Encode(await key.extractBytes()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
