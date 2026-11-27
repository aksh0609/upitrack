import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/models/txn.dart';

/// Two "devices" need two databases; ':memory:' is shared per process, so
/// each gets its own temp file.
Future<AppDb> openDevice(Directory dir, String name) =>
    AppDb.open(factory: databaseFactoryFfi, path: p.join(dir.path, '$name.db'));

Txn txn(String key,
        {String category = 'Food', int editTs = 0, bool hidden = false}) =>
    Txn(
      key: key,
      amountPaise: 25000,
      isDebit: true,
      counterparty: 'SWIGGY',
      bank: 'HDFC Bank',
      account: '1234',
      channel: 'UPI',
      category: category,
      time: DateTime(2026, 10, 3, 9),
      raw: 'Sent Rs.250.00 ...',
      editTs: editTs,
      hidden: hidden,
    );

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late AppDb a;
  late AppDb b;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('upitrack_sync');
    a = await openDevice(dir, 'a');
    b = await openDevice(dir, 'b');
  });
  tearDown(() async {
    await a.close();
    await b.close();
    await dir.delete(recursive: true);
  });

  Future<List<Txn>> all(AppDb db) =>
      db.betweenIncludingHidden(DateTime(2026, 10), DateTime(2026, 11));

  test('snapshot has every row without ids, plus rules and the device id',
      () async {
    await a.insertAll([txn('k1'), txn('k2', hidden: true)]);
    await a.setCategoryForPayee('SWIGGY', 'Groceries');
    final snap = await a.snapshot();
    expect(snap['v'], 1);
    expect(snap['device'], await a.deviceId());
    final txns = snap['txns'] as List;
    expect(txns, hasLength(2));
    expect(txns.every((t) => !(t as Map).containsKey('id')), isTrue);
    expect((txns.firstWhere((t) => t['key'] == 'k2') as Map)['hidden'], 1);
    expect((snap['rules'] as List).single['category'], 'Groceries');
  });

  test('apply inserts unknown rows and rules, and flags dirty', () async {
    await a.insertAll([txn('k1')]);
    await a.setCategoryForPayee('SWIGGY', 'Groceries');
    await b.setMeta('sync_dirty', '0');
    expect(await b.applySnapshot(await a.snapshot()), isTrue);
    final rows = await all(b);
    expect(rows.single.key, 'k1');
    expect(rows.single.category, 'Groceries');
    expect(await b.rules(), {'SWIGGY': 'Groceries'});
    expect(await b.getMeta('sync_dirty'), '1');
  });

  test('a newer edit wins; an automatic row never overwrites an edit',
      () async {
    await a.insertAll([txn('k1')]);
    await b.insertAll([txn('k1')]);
    final local = (await all(b)).single;
    await b.setCategory(local.id!, 'Travel'); // b edits (edit_ts = now)
    expect(await b.applySnapshot(await a.snapshot()), isFalse,
        reason: "a's row is automatic");
    expect((await all(b)).single.category, 'Travel');

    expect(await a.applySnapshot(await b.snapshot()), isTrue);
    final onA = (await all(a)).single;
    expect(onA.category, 'Travel');
    expect(onA.editTs, greaterThan(0));
  });

  test('hiding propagates and is idempotent', () async {
    await a.insertAll([txn('k1')]);
    await b.applySnapshot(await a.snapshot());
    await a.hide((await all(a)).single.id!);
    expect(await b.applySnapshot(await a.snapshot()), isTrue);
    expect((await all(b)).single.hidden, isTrue);
    expect(await b.applySnapshot(await a.snapshot()), isFalse,
        reason: 'second apply changes nothing');
  });

  test('a rule applies to automatic rows but not to a later direct edit',
      () async {
    await b.insertAll([txn('k1'), txn('k2')]);
    final rows = await all(b);
    await b.setCategory(
        rows.firstWhere((t) => t.key == 'k2').id!, 'Travel'); // now
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await a.insertAll([txn('k1')]);
    await a.setCategoryForPayee(
        'SWIGGY', 'Groceries'); // rule ts later than b's edit
    await b.applySnapshot(await a.snapshot());
    final byKey = {for (final t in await all(b)) t.key: t.category};
    expect(byKey['k1'], 'Groceries');
    expect(byKey['k2'], 'Groceries',
        reason: 'rule is newer than the edit, so it wins — same as locally');

    // And the other way round: an edit newer than the rule stays.
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await b.setCategory(
        (await all(b)).firstWhere((t) => t.key == 'k2').id!, 'Travel');
    await b.applySnapshot(await a.snapshot());
    expect((await all(b)).firstWhere((t) => t.key == 'k2').category, 'Travel');
  });

  test('a local rule applies to a row that arrives later', () async {
    await b.setCategoryForPayee('SWIGGY', 'Groceries'); // no rows on b yet
    await a.insertAll([txn('z')]); // automatic Food on a
    await b.applySnapshot(await a.snapshot());
    expect((await all(b)).single.category, 'Groceries');
  });

  test(
      'a remote edit older than the local rule yields to the rule; a newer one wins',
      () async {
    await a.insertAll([txn('x')]);
    await a.setCategory((await all(a)).single.id!, 'Travel'); // T1
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await b.setCategoryForPayee('SWIGGY', 'Groceries'); // T2 > T1
    await b.applySnapshot(await a.snapshot());
    expect((await all(b)).single.category, 'Groceries');

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await a.setCategory((await all(a)).single.id!, 'Shopping'); // T3 > T2
    await b.applySnapshot(await a.snapshot());
    expect((await all(b)).single.category, 'Shopping');
  });

  test('budgets sync both ways; a removal wins when newer', () async {
    await a.setBudget('Food', 500000);
    expect(await b.applySnapshot(await a.snapshot()), isTrue);
    expect(await b.budgets(), {'Food': 500000});

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await b.setBudget('Food', 0);
    await a.applySnapshot(await b.snapshot());
    expect(await a.budgets(), isEmpty);
    expect(await a.applySnapshot(await b.snapshot()), isFalse,
        reason: 'idempotent');
  });

  test('added regular payments sync both ways; a removal wins when newer',
      () async {
    await a.setBill('Rent', 1500000, 5);
    expect(await b.applySnapshot(await a.snapshot()), isTrue);
    expect([for (final x in await b.bills()) (x.name, x.amountPaise, x.day)],
        [('Rent', 1500000, 5)]);

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await b.setBill('Rent', 0, 0);
    await a.applySnapshot(await b.snapshot());
    expect(await a.bills(), isEmpty);
    expect(await a.applySnapshot(await b.snapshot()), isFalse,
        reason: 'idempotent');
  });

  test('a snapshot from an older app, without budgets, still applies',
      () async {
    await a.setBudget('Food', 500000);
    final old = await b.snapshot()
      ..remove('budgets');
    await a.applySnapshot(old);
    expect(await a.budgets(), {'Food': 500000});
  });

  test('notes come back with payments, sync, and clear', () async {
    await a.insertAll([txn('n1')]);
    await a.setNote('n1', 'office lunch');
    expect((await all(a)).single.note, 'office lunch');

    await b.applySnapshot(await a.snapshot());
    expect((await all(b)).single.note, 'office lunch');

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await b.setNote('n1', '');
    await a.applySnapshot(await b.snapshot());
    expect((await all(a)).single.note, isNull);
  });

  test('a payee rule, here or from another device, leaves a loan alone',
      () async {
    await a.insertAll([txn('l1'), txn('l2')]);
    final rows = await all(a);
    await a.setCategory(rows.first.id!, 'Lent & borrowed');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await a.setCategoryForPayee('SWIGGY', 'Groceries');
    final cats = {for (final t in await all(a)) t.key: t.category};
    expect(cats[rows.first.key], 'Lent & borrowed');
    expect(cats[rows.last.key], 'Groceries');

    await b.insertAll([txn('l1')]);
    await b.setCategory((await all(b)).single.id!, 'Lent & borrowed');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await b.setCategoryForPayee('SWIGGY', 'Travel');
    await a.applySnapshot(await b.snapshot());
    // b's newer edit marks l1 as a loan on a too; b's later Travel rule
    // then touches neither loan.
    expect((await a.inCategory('Lent & borrowed')).map((t) => t.key),
        unorderedEquals(['l1', 'l2']));
  });
}
