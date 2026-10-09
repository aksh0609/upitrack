import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/sync/sync_controller.dart';
import 'package:upitrack/sync/sync_setup.dart';

import 'fakes.dart';
import 'memory_sync_store.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late AppDb a;
  late AppDb b;
  late MemorySyncStore store;

  SyncController controller(AppDb db, FakeAuth auth, MemorySyncKeys keys) =>
      SyncController(
        db,
        auth: auth,
        keys: keys,
        storeFor: (_) => store,
        debounce: const Duration(milliseconds: 10),
        iterations: 1000,
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('upitrack_ctl');
    a = await AppDb.open(
        factory: databaseFactoryFfi, path: p.join(dir.path, 'a.db'));
    b = await AppDb.open(
        factory: databaseFactoryFfi, path: p.join(dir.path, 'b.db'));
    store = MemorySyncStore();
  });
  tearDown(() async {
    await a.close();
    await b.close();
    await dir.delete(recursive: true);
  });

  test('first device: sign in → create passphrase → ready and uploaded',
      () async {
    final c = controller(a, FakeAuth(), MemorySyncKeys());
    await c.start();
    expect(c.state, SyncState.signedOut);
    await c.signIn();
    expect(c.state, SyncState.needsPassphrase);
    expect(c.metaExists, isFalse);
    expect(await c.setPassphrase('correct horse'), isTrue);
    expect(c.state, SyncState.ready);
    expect(c.lastOk, isNotNull);
    expect(store.files.keys, contains('meta.json'));
    expect(store.files.length, 2);
  });

  test('second device: wrong passphrase refused, right one syncs the data',
      () async {
    final ca = controller(a, FakeAuth(), MemorySyncKeys());
    await ca.start();
    await ca.signIn();
    await ca.setPassphrase('correct horse');
    await a.insertAll([
      Txn(
          key: 'k1',
          amountPaise: 1,
          isDebit: true,
          counterparty: 'SWIGGY',
          channel: 'UPI',
          category: 'Food',
          time: DateTime(2026, 10, 3)),
    ]);
    await ca.syncNow();

    final cb = controller(b, FakeAuth(), MemorySyncKeys());
    await cb.start();
    await cb.signIn();
    expect(cb.metaExists, isTrue);
    expect(await cb.setPassphrase('battery staple'), isFalse);
    expect(cb.state, SyncState.needsPassphrase);
    expect(await cb.setPassphrase('correct horse'), isTrue);
    expect((await b.between(DateTime(2026, 10), DateTime(2026, 11))).single.key,
        'k1');
  });

  test('a stored key restores straight to ready; sign out forgets it',
      () async {
    final auth = FakeAuth();
    final keys = MemorySyncKeys();
    final c1 = controller(a, auth, keys);
    await c1.start();
    await c1.signIn();
    await c1.setPassphrase('p');

    final c2 = controller(a, auth, keys);
    await c2.start();
    expect(c2.state, SyncState.ready);
    await c2.signOut();
    expect(c2.state, SyncState.signedOut);
    expect(keys.key, isNull);
  });

  test(
      'a known account without Drive access stays signed out until the next tap',
      () async {
    final auth = FakeAuth()
      ..signedIn = true
      ..authorized = false;
    final c = controller(a, auth, MemorySyncKeys());
    await c.start();
    expect(c.state, SyncState.signedOut);
    expect(c.hasAccount, isTrue);

    await c.signIn();
    expect(c.state, SyncState.needsPassphrase);
  });

  test('a cancelled sign-in stays signed out; poke debounces into one sync',
      () async {
    final auth = FakeAuth()..cancelNext = true;
    final c = controller(a, auth, MemorySyncKeys());
    await c.start();
    await c.signIn();
    expect(c.state, SyncState.signedOut);

    await c.signIn();
    await c.setPassphrase('p');
    final uploads = store.uploads;
    await a.setMeta('sync_dirty', '1');
    c.poke();
    c.poke();
    c.poke();
    await waitFor(() => store.uploads == uploads + 1);
    expect(store.uploads, uploads + 1);
  });

  test('reset wipes the folder and asks for a new passphrase', () async {
    final c = controller(a, FakeAuth(), MemorySyncKeys());
    await c.start();
    await c.signIn();
    await c.setPassphrase('p');
    await c.reset();
    expect(store.files, isEmpty);
    expect(c.state, SyncState.needsPassphrase);
    expect(c.metaExists, isFalse);
  });

  test('pulled counts only syncs that applied something', () async {
    final ca = controller(a, FakeAuth(), MemorySyncKeys());
    await ca.start();
    await ca.signIn();
    await ca.setPassphrase('correct horse');
    final cb = controller(b, FakeAuth(), MemorySyncKeys());
    await cb.start();
    await cb.signIn();
    await cb.setPassphrase('correct horse');
    await a.insertAll([
      Txn(
          key: 'k1',
          amountPaise: 1,
          isDebit: true,
          counterparty: 'SWIGGY',
          channel: 'UPI',
          category: 'Food',
          time: DateTime(2026, 10, 3)),
    ]);
    await ca.syncNow();
    expect(cb.pulled, 0);
    await cb.syncNow();
    expect(cb.pulled, 1);
    await cb.syncNow();
    expect(cb.pulled, 1);
  });

  test('a key that no longer matches the folder asks for the passphrase again',
      () async {
    final keys = MemorySyncKeys();
    final ca = controller(a, FakeAuth(), keys);
    await ca.start();
    await ca.signIn();
    await ca.setPassphrase('p');
    expect(ca.state, SyncState.ready);
    store.files.clear();
    await SyncSetup(store, iterations: 1000).create('other');
    await ca.syncNow();
    expect(ca.state, SyncState.needsPassphrase);
    expect(ca.lastError, isNotNull);
    expect(keys.key, isNull);
  });
}
