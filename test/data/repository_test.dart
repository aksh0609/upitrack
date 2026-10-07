import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/data/repository.dart';
import 'package:upitrack/data/shortcut_inbox.dart';
import 'package:upitrack/data/sms_source.dart';

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
}
