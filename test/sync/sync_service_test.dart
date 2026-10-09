import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/sync/crypto.dart';
import 'package:upitrack/sync/snapshot.dart';
import 'package:upitrack/sync/sync_service.dart';
import 'package:upitrack/sync/sync_setup.dart';

import 'memory_sync_store.dart';

Txn txn(String key) => Txn(
      key: key,
      amountPaise: 25000,
      isDebit: true,
      counterparty: 'SWIGGY',
      bank: 'HDFC Bank',
      account: '1234',
      channel: 'UPI',
      category: 'Food',
      time: DateTime(2026, 10, 3, 9),
    );

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late AppDb a;
  late AppDb b;
  late MemorySyncStore store;
  late SecretKey key;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('upitrack_svc');
    a = await AppDb.open(
        factory: databaseFactoryFfi, path: p.join(dir.path, 'a.db'));
    b = await AppDb.open(
        factory: databaseFactoryFfi, path: p.join(dir.path, 'b.db'));
    store = MemorySyncStore();
    key = await SyncSetup(store, iterations: 1000).create('p');
  });
  tearDown(() async {
    await a.close();
    await b.close();
    await dir.delete(recursive: true);
  });

  Future<List<Txn>> all(AppDb db) =>
      db.betweenIncludingHidden(DateTime(2026, 10), DateTime(2026, 11));

  test(
      'two devices converge; nothing is re-downloaded or re-uploaded when quiet',
      () async {
    final sa = SyncService(a, store, key);
    final sb = SyncService(b, store, key);
    await a.insertAll([txn('k1')]);

    final r1 = await sa.sync();
    expect(r1.uploaded, isTrue);
    expect(store.files.keys,
        [SyncSetup.metaName, SyncService.fileNameFor(await a.deviceId())]);

    final r2 = await sb.sync();
    expect(r2.applied, 1);
    expect(r2.uploaded, isTrue, reason: 'b carries what it learned');
    expect((await all(b)).single.key, 'k1');

    final r3 = await sa.sync();
    expect(r3.applied, 0, reason: "b's snapshot adds nothing a doesn't have");
    expect(r3.uploaded, isFalse);

    final before = (store.downloads, store.uploads);
    final r4 = await sa.sync();
    expect((r4.applied, r4.uploaded), (0, false));
    expect((store.downloads, store.uploads), before,
        reason: 'seen versions skip the download');
  });

  test('a hide on one device reaches the other', () async {
    final sa = SyncService(a, store, key);
    final sb = SyncService(b, store, key);
    await a.insertAll([txn('k1')]);
    await sa.sync();
    await sb.sync();
    await b.hide((await all(b)).single.id!);
    await sb.sync();
    await sa.sync();
    expect((await all(a)).single.hidden, isTrue);
  });

  test('the wrong key cannot read a snapshot', () async {
    await a.insertAll([txn('k1')]);
    await SyncService(a, store, key).sync();
    final wrong = SyncService(b, store, SecretKey(List<int>.filled(32, 8)));
    expect(() => wrong.sync(), throwsA(isA<SecretBoxAuthenticationError>()));
  });

  test('a peer file encrypted with another key is skipped, not fatal',
      () async {
    await a.insertAll([txn('k1')]);
    await b.insertAll([txn('k2')]);
    final k1 = key;
    await SyncService(a, store, k1).sync();
    // Reset elsewhere: new meta.json and key; b's file from before the reset lingers.
    store.files.clear();
    final k2 = await SyncSetup(store, iterations: 1000).create('new');
    store.files['dev-stale.json.enc'] =
        await SyncCrypto.encrypt(k1, encodeSnapshot(await b.snapshot()));
    final r = await SyncService(a, store, k2).sync();
    expect(r.skipped, 1);
    expect(r.uploaded, isTrue);
  });

  test('a changed meta check asks for the passphrase', () async {
    final k1 = key;
    await a.insertAll([txn('k1')]);
    await SyncService(a, store, k1).sync();
    store.files.clear();
    await SyncSetup(store, iterations: 1000).create('other');
    await expectLater(SyncService(a, store, k1).sync(),
        throwsA(isA<SecretBoxAuthenticationError>()));
  });

  test('no meta.json means no upload', () async {
    await a.insertAll([txn('k1')]);
    store.files.clear();
    final r = await SyncService(a, store, key).sync();
    expect(r.uploaded, isFalse);
  });

  test(
      'setup: create writes meta.json, join checks the passphrase, reset wipes',
      () async {
    final store = MemorySyncStore(); // empty, unlike the fixture's
    final setup = SyncSetup(store, iterations: 1000);
    expect(await setup.readMeta(), isNull);
    final created = await setup.create('correct horse');
    final meta = await setup.readMeta();
    expect(meta, isNotNull);
    expect(meta!['kdf'], 'pbkdf2-sha256');
    expect(meta['iterations'], 1000);
    expect(await setup.join('battery staple', meta), isNull);
    final joined = await setup.join('correct horse', meta);
    expect(await joined!.extractBytes(), await created.extractBytes());
    await setup.reset();
    expect(store.files, isEmpty);
  });

  test('a change landing during the upload is carried by the next round',
      () async {
    final sa = SyncService(a, store, key);
    await a.insertAll([txn('k1')]);
    store.onUpload = () async {
      store.onUpload = null;
      await a.insertAll(
          [txn('k2')]); // lands while the first snapshot is in flight
    };
    await sa.sync();
    expect(await a.getMeta('sync_dirty'), '1',
        reason: 'the mid-upload write re-dirtied the device');
    expect((await sa.sync()).uploaded, isTrue);
    expect(await a.getMeta('sync_dirty'), '0');
  });

  test('a failed upload leaves the device dirty', () async {
    final sa = SyncService(a, store, key);
    await a.insertAll([txn('k1')]);
    store.onUpload = () async => throw StateError('offline');
    await expectLater(sa.sync(), throwsA(isA<StateError>()));
    expect(await a.getMeta('sync_dirty'), '1');
    store.onUpload = null;
    expect((await sa.sync()).uploaded, isTrue);
  });
}
