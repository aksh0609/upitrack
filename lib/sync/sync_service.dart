/// One sync round (spec §4.5): pull every other device's snapshot we haven't
/// seen, merge it, then push ours if anything changed locally.
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../data/db.dart';
import 'crypto.dart';
import 'snapshot.dart';
import 'sync_setup.dart';
import 'sync_store.dart';

class SyncResult {
  const SyncResult({required this.applied, required this.uploaded, required this.skipped});

  /// Remote snapshots that changed something here.
  final int applied;
  final bool uploaded;

  /// Peer files that couldn't be read (e.g. still encrypted with the key
  /// from before a reset); retried next round.
  final int skipped;
}

class SyncService {
  SyncService(this._db, this._store, this._key);

  final AppDb _db;
  final SyncStore _store;
  final SecretKey _key;

  static String fileNameFor(String deviceId) => 'dev-$deviceId.json.enc';

  /// Throws on network or auth failure, and [SecretBoxAuthenticationError]
  /// when the stored key fails the check in meta.json (sync was reset,
  /// spec §4.6).
  Future<SyncResult> sync() async {
    final mine = fileNameFor(await _db.deviceId());
    final files = await _store.list();

    // No meta.json: a reset is in progress on another device. Uploading now
    // with the old key would strand this device's file.
    final meta = files.where((f) => f.name == SyncSetup.metaName).firstOrNull;
    if (meta == null) return const SyncResult(applied: 0, uploaded: false, skipped: 0);
    const seenMeta = 'seen:${SyncSetup.metaName}';
    if (meta.version == null || meta.version != await _db.getMeta(seenMeta)) {
      final m = jsonDecode(utf8.decode(await _store.download(meta.id))) as Map<String, Object?>;
      if (!await SyncCrypto.verifyCheck(_key, m['check'] as String)) {
        throw SecretBoxAuthenticationError(message: 'The sync key no longer matches meta.json');
      }
      if (meta.version != null) await _db.setMeta(seenMeta, meta.version!);
    }

    var applied = 0;
    var skipped = 0;
    for (final f in files) {
      if (!f.name.startsWith('dev-') || f.name == mine) continue;
      final seenKey = 'seen:${f.name}';
      if (f.version != null && f.version == await _db.getMeta(seenKey)) continue;
      try {
        final bytes = await SyncCrypto.decrypt(_key, await _store.download(f.id));
        if (await _db.applySnapshot(decodeSnapshot(bytes))) applied++;
      } catch (_) {
        // Unreadable (stale key, partial upload): not seen, retried next
        // round, and never blocks our own upload.
        skipped++;
        continue;
      }
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
    return SyncResult(applied: applied, uploaded: uploaded, skipped: skipped);
  }
}
