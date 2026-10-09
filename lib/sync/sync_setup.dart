/// First-time setup and recovery (spec §4.6, §4.7): `meta.json` holds the
/// salt and a key check so every device derives the same key from the
/// passphrase and can tell a wrong one apart.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto.dart';
import 'sync_store.dart';

class SyncSetup {
  SyncSetup(this._store, {this.iterations = SyncCrypto.iterations});

  final SyncStore _store;

  /// PBKDF2 rounds for a *new* meta.json. Joining uses the rounds the file
  /// records. Tests lower it.
  final int iterations;

  static const String metaName = 'meta.json';

  /// The folder's `meta.json`, or null when no device has set up sync yet.
  Future<Map<String, Object?>?> readMeta() async {
    final files = await _store.list();
    for (final f in files) {
      if (f.name == metaName) {
        return jsonDecode(utf8.decode(await _store.download(f.id)))
            as Map<String, Object?>;
      }
    }
    return null;
  }

  /// First device: choose a passphrase, write meta.json, return the key.
  Future<SecretKey> create(String passphrase) async {
    final salt = SyncCrypto.newSalt();
    final key =
        await SyncCrypto.deriveKey(passphrase, salt, iterations: iterations);
    final meta = {
      'v': 1,
      'kdf': 'pbkdf2-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'check': await SyncCrypto.makeCheck(key),
    };
    await _store.upload(
        metaName, Uint8List.fromList(utf8.encode(jsonEncode(meta))));
    return key;
  }

  /// Another device: derive from the recorded salt; null when the
  /// passphrase doesn't match the one used on the first device.
  Future<SecretKey?> join(String passphrase, Map<String, Object?> meta) async {
    final key = await SyncCrypto.deriveKey(
      passphrase,
      base64Decode(meta['salt'] as String),
      iterations: (meta['iterations'] as num).toInt(),
    );
    return await SyncCrypto.verifyCheck(key, meta['check'] as String)
        ? key
        : null;
  }

  /// Forgotten passphrase: wipe the folder. Local data is untouched; the
  /// caller then runs [create] again and re-uploads.
  Future<void> reset() => _store.deleteAll();
}
