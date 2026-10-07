import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/data/repository.dart';
import 'package:upitrack/data/shortcut_inbox.dart';
import 'package:upitrack/data/sms_source.dart';
import 'package:upitrack/models/unparsed.dart';
import 'package:upitrack/parser/statement_parser.dart';

/// Returns canned SMS instead of reading the Android inbox.
class FakeSms extends SmsSource {
  FakeSms(this.messages);
  final List<RawSms> messages;

  @override
  Future<List<RawSms>> readInbox({required DateTime since}) async => messages;
}

/// No iPhone shortcut messages.
class FakeInbox extends ShortcutInbox {
  @override
  Future<List<InboxMessage>> pending() async => const [];

  @override
  Future<void> remove(List<InboxMessage> messages) async {}
}

Future<AppDb> openTestDb() =>
    AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);

const hdfcSwiggy = 'Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\n'
    'On 03/10/26\nRef 427612345678\nNot You?\nCall 18002586161';

void main() {
  sqfliteFfiInit();
  late AppDb db;

  setUp(() async => db = await openTestDb());
  tearDown(() => db.close());

  group('syncSms', () {
    test('stores a parsed bank SMS once, ignores an OTP', () async {
      final repo = TxnRepository(
        db,
        FakeSms([
          RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcSwiggy, date: DateTime(2026, 10, 3, 9)),
          RawSms(id: 2, address: 'VM-HDFCBK', body: '123456 is your OTP for Rs 500.', date: DateTime(2026, 10, 3, 9)),
        ]),
        FakeInbox(),
      );

      expect(await repo.syncSms(), 1);
      // Second sync of the same inbox adds nothing.
      expect(await repo.syncSms(), 0);

      final txns = await repo.between(DateTime(2026, 10), DateTime(2026, 11));
      expect(txns, hasLength(1));
      expect(txns.single.counterparty, 'SWIGGY');
      expect(txns.single.key, 'ref:427612345678:d');
    });
  });

  group('importStatement', () {
    const chai50 = 'Sent Rs.50.00\nFrom HDFC Bank A/C *1234\nTo CHAI POINT\n'
        'On 03/10/26\nRef 427600000001';

    test('two same-day same-amount rows with one SMS caught: one is added', () async {
      final repo = TxnRepository(
        db,
        FakeSms([RawSms(id: 1, address: 'VM-HDFCBK', body: chai50, date: DateTime(2026, 10, 3, 9))]),
        FakeInbox(),
      );
      await repo.syncSms();

      // Statement narrations without a 12-digit ref, so only the
      // same-day/amount/direction rule can match them.
      final rows = [
        StatementRow(date: DateTime(2026, 10, 3, 12), amountPaise: 5000, isDebit: true,
            narration: 'UPI-CHAI POINT-MORNING', counterparty: 'CHAI POINT'),
        StatementRow(date: DateTime(2026, 10, 3, 12), amountPaise: 5000, isDebit: true,
            narration: 'UPI-CHAI POINT-EVENING', counterparty: 'CHAI POINT'),
      ];
      final s = await repo.importStatement(StatementResult(rows, 0));

      expect(s.added, 1, reason: 'the second ₹50 was never caught by SMS');
      expect(s.duplicates, 1);
      final txns = await repo.between(DateTime(2026, 10), DateTime(2026, 11));
      expect(txns, hasLength(2));
    });

    test('re-importing the same statement adds nothing', () async {
      final repo = TxnRepository(db, FakeSms(const []), FakeInbox());
      final rows = [
        StatementRow(date: DateTime(2026, 10, 1, 12), amountPaise: 25000, isDebit: true,
            narration: 'UPI-SWIGGY-427612345678', counterparty: 'SWIGGY', ref: '427612345678'),
      ];
      expect((await repo.importStatement(StatementResult(rows, 0))).added, 1);
      final again = await repo.importStatement(StatementResult(rows, 0));
      expect(again.added, 0);
      expect(again.duplicates, 1);
    });
  });

  group('hide / unhide', () {
    test('hidden payments leave the month view and can come back', () async {
      final repo = TxnRepository(
        db,
        FakeSms([RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcSwiggy, date: DateTime(2026, 10, 3, 9))]),
        FakeInbox(),
      );
      await repo.syncSms();
      final t = (await repo.between(DateTime(2026, 10), DateTime(2026, 11))).single;

      await repo.hide(t);
      expect(await repo.between(DateTime(2026, 10), DateTime(2026, 11)), isEmpty);
      final hidden = await repo.hidden();
      expect(hidden.single.key, t.key);

      await repo.unhide(hidden.single);
      expect(await repo.hidden(), isEmpty);
      expect(await repo.between(DateTime(2026, 10), DateTime(2026, 11)), hasLength(1));
    });
  });

  group('unparsed SMS', () {
    const ucoBody = 'Your a/c 1234 has a withdrawal of INR 320.00 at 10:12 towards UPI/9876';

    test('bank-looking SMS the parser rejects are kept; OTPs are not', () async {
      final repo = TxnRepository(
        db,
        FakeSms([
          RawSms(id: 7, address: 'AD-UCOBNK', body: ucoBody, date: DateTime(2026, 10, 3, 10)),
          RawSms(id: 8, address: 'VM-HDFCBK', body: '123456 is your OTP for Rs 500.', date: DateTime(2026, 10, 3, 9)),
          RawSms(id: 9, address: 'VM-HDFCBK', body: hdfcSwiggy, date: DateTime(2026, 10, 3, 9)),
        ]),
        FakeInbox(),
      );
      expect(await repo.syncSms(), 1);

      final open = await repo.unparsed();
      expect(open, hasLength(1));
      expect(open.single.key, 'sms:7');
      expect(open.single.sender, 'AD-UCOBNK');
      expect(open.single.body, ucoBody);

      // Syncing again doesn't duplicate it.
      await repo.syncSms();
      expect(await repo.unparsed(), hasLength(1));

      await repo.resolveUnparsed(open.single, state: 'ignored');
      expect(await repo.unparsed(), isEmpty);
    });

    test('resolved rows older than 90 days are purged on sync', () async {
      await db.insertUnparsed([
        UnparsedSms(key: 'sms:1', sender: 'AD-UCOBNK', body: ucoBody,
            time: DateTime.now().subtract(const Duration(days: 120)), state: 'ignored'),
        UnparsedSms(key: 'sms:2', sender: 'AD-UCOBNK', body: ucoBody,
            time: DateTime.now().subtract(const Duration(days: 120))),
      ]);
      final repo = TxnRepository(db, FakeSms(const []), FakeInbox());
      await repo.syncSms();
      final left = await repo.unparsed();
      expect(left.map((u) => u.key), ['sms:2'], reason: 'open rows are never purged');

      // The iPhone path purges too, even when the inbox is empty.
      await db.insertUnparsed([
        UnparsedSms(key: 'shortcut:old', sender: 'AD-UCOBNK', body: ucoBody,
            time: DateTime.now().subtract(const Duration(days: 120)), state: 'ignored'),
      ]);
      await repo.syncShortcutInbox();
      // Handled rows are invisible, so prove the purge: re-inserting the key
      // only lands if the old row is gone (keys are unique, inserts ignore).
      await db.insertUnparsed([
        UnparsedSms(key: 'shortcut:old', sender: 'AD-UCOBNK', body: ucoBody, time: DateTime.now()),
      ]);
      expect((await repo.unparsed()).map((u) => u.key), containsAll(['sms:2', 'shortcut:old']));
    });
  });

  group('openReadOnly', () {
    test('reads rules, refuses writes, and leaves the main connection open', () async {
      final dir = await Directory.systemTemp.createTemp('upitrack_test');
      final path = p.join(dir.path, 'upitrack.db');
      final main = await AppDb.open(factory: databaseFactoryFfi, path: path);
      await main.setCategoryForPayee('SWIGGY', 'Groceries');

      final ro = await AppDb.openReadOnly(factory: databaseFactoryFfi, path: path);
      expect(await ro.rules(), {'SWIGGY': 'Groceries'});
      await expectLater(ro.setMeta('k', 'v'), throwsA(isA<DatabaseException>()));
      await ro.close();

      // The app's own connection is unaffected by the read-only close.
      expect(await main.rules(), {'SWIGGY': 'Groceries'});
      await main.close();
      await dir.delete(recursive: true);
    });

    test('fails when the database file does not exist yet', () async {
      await expectLater(
        AppDb.openReadOnly(factory: databaseFactoryFfi, path: '/nonexistent/upitrack.db'),
        throwsA(anything),
      );
    });
  });
}
