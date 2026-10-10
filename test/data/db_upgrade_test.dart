import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/models/txn.dart';

void main() {
  sqfliteFfiInit();

  Txn row(String key, String counterparty, String category, {int editTs = 0}) =>
      Txn(
        key: key,
        amountPaise: 100,
        isDebit: true,
        counterparty: counterparty,
        channel: 'UPI',
        category: category,
        time: DateTime(2026, 10, 5),
        editTs: editTs,
      );

  test('v5 re-guesses untouched Others rows: people and gift cards', () async {
    final dir = await Directory.systemTemp.createTemp('upitrack');
    final path = '${dir.path}/u.db';
    var db = await AppDb.open(factory: databaseFactoryFfi, path: path);
    await db.insertAll([
      row('a', 'ABISHEK KUMAR', 'Others'),
      row('e', 'PRAMOD', 'Others'),
      row('b', 'AMAZON GIFT CARD', 'Others'),
      row('c', 'paytmqr281005@paytm', 'Others'),
      row('d', 'RAHUL SHARMA', 'Others', editTs: 5), // the user chose Others
    ]);
    await db.close();
    // Pretend this file was written by the previous app version.
    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.execute('PRAGMA user_version = 4');
    await raw.close();

    db = await AppDb.open(factory: databaseFactoryFfi, path: path);
    final by = {
      for (final t in await db.between(DateTime(2026, 10), DateTime(2026, 11)))
        t.key: t
    };
    expect(by['a']!.category, 'Transfers');
    expect(by['a']!.editTs, 0, reason: 'automatic, not a user edit');
    expect(by['e']!.category, 'Transfers');
    expect(by['b']!.category, 'Gift cards');
    expect(by['c']!.category, 'Others');
    expect(by['d']!.category, 'Others');
    await db.close();
    await dir.delete(recursive: true);
  });
}
