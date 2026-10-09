/// One sync round (spec §4.5): pull every other device's snapshot we haven't
/// seen, merge it, then push ours if anything changed locally.
library;

import 'package:cryptography/cryptography.dart';

import '../data/db.dart';
import 'crypto.dart';
import 'snapshot.dart';
import 'sync_store.dart';

class SyncResult {
  const SyncResult({required this.applied, required this.uploaded});

  /// Remote snapshots that changed something here.
  final int applied;
  final bool uploaded;
}

class SyncService {
  SyncService(this._db, this._store, this._key);

  final AppDb _db;
  final SyncStore _store;
  final SecretKey _key;

  static String fileNameFor(String deviceId) => 'dev-$deviceId.json.enc';

  /// Throws on network or auth failure, and [SecretBoxAuthenticationError]
  /// when the stored key no longer matches the folder (sync was reset).
  Future<SyncResult> sync() async {
    final mine = fileNameFor(await _db.deviceId());
    final files = await _store.list();

    var applied = 0;
    for (final f in files) {
      if (!f.name.startsWith('dev-') || f.name == mine) continue;
      final seenKey = 'seen:${f.name}';
      if (f.version != null && f.version == await _db.getMeta(seenKey)) continue;
      final bytes = await SyncCrypto.decrypt(_key, await _store.download(f.id));
      if (await _db.applySnapshot(decodeSnapshot(bytes))) applied++;
      if (f.version != null) await _db.setMeta(seenKey, f.version!);
    }

    var uploaded = false;
    final haveMine = files.any((f) => f.name == mine);
    if (!haveMine || await _db.getMeta('sync_dirty') == '1') {
      // Clear the flag BEFORE reading the snapshot: a change that lands while
      // we upload sets it again and goes out next round. Put it back if the
      // upload fails, so nothing is ever stranded.
      await _db.setMeta('sync_dirty', '0');
      try {
        final snap = encodeSnapshot(await _db.snapshot());
        await _store.upload(mine, await SyncCrypto.encrypt(_key, snap));
      } catch (_) {
        await _db.setMeta('sync_dirty', '1');
        rethrow;
      }
      uploaded = true;
    }
    return SyncResult(applied: applied, uploaded: uploaded);
  }
}
