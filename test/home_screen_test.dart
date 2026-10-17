import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/data/repository.dart';
import 'package:upitrack/data/shortcut_inbox.dart';
import 'package:upitrack/data/sms_source.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/screens/home_screen.dart';
import 'package:upitrack/theme.dart';

/// SMS permission granted and an empty inbox, so the home screen settles.
void fakePlatform() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async => call.method == 'checkPermissionStatus' ? 1 : null);
  messenger.setMockMethodCallHandler(
      const MethodChannel('upitrack/sms'), (call) async => <Object?>[]);
}

/// A few payments this month, newest first in the list.
List<Txn> samplePayments() {
  final now = DateTime.now();
  DateTime at(int daysAgo, int hour) {
    final d = DateTime(now.year, now.month, now.day - daysAgo, hour, 15);
    // Keep everything inside the current month.
    return d.month == now.month ? d : DateTime(now.year, now.month, 1, hour);
  }

  Txn t(String key, int rupees, String who, String cat, DateTime time,
          {bool debit = true}) =>
      Txn(
        key: key,
        amountPaise: rupees * 100,
        isDebit: debit,
        counterparty: who,
        channel: 'UPI',
        category: cat,
        bank: 'HDFC',
        account: '4821',
        time: time,
      );
  return [
    t('a', 249, 'Swiggy', 'Food', at(0, 13)),
    t('b', 1180, 'Blinkit', 'Groceries', at(0, 9)),
    t('c', 499, 'Uber India', 'Travel', at(1, 19)),
    t('d', 2400, 'Ravi Kumar', 'Transfers', at(1, 11)),
    t('e', 52000, 'Acme Pvt Ltd', 'Income', at(2, 10), debit: false),
    t('f', 3299, 'Amazon', 'Shopping', at(3, 21)),
    t('g', 649, 'Airtel', 'Bills & Recharge', at(4, 8)),
  ];
}

Future<AppDb> openSampleDb(WidgetTester tester, {bool withData = true}) async {
  sqfliteFfiInit();
  final db = (await tester.runAsync(() =>
      AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath)))!;
  addTearDown(() => tester.runAsync(db.close));
  if (withData) await tester.runAsync(() => db.insertAll(samplePayments()));
  return db;
}

Future<void> pumpHome(WidgetTester tester, AppDb db,
    {Brightness brightness = Brightness.light}) async {
  fakePlatform();
  // A typical phone: 393 x 851 logical pixels.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(brightness),
    home:
        HomeScreen(repository: TxnRepository(db, SmsSource(), ShortcutInbox())),
  ));
  // Let the real sqflite calls finish, then draw what they loaded.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  // Let the total count up and the cards slide in.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Overview sums the month; Payments lists and searches',
      (tester) async {
    final db = await openSampleDb(tester);
    await pumpHome(tester, db);

    expect(find.text('Spent this month'), findsOneWidget);
    expect(find.text('₹8,276'), findsOneWidget);
    expect(find.text('Where it went'), findsOneWidget);
    await tester.drag(find.text('Where it went'), const Offset(0, -600));
    await tester.pump();
    expect(find.text('Recent payments'), findsOneWidget);

    await tester.tap(find.text('Payments'));
    // Past the tab cross-fade, so the Overview list is gone.
    await tester.pumpAndSettle();
    expect(find.text('7 payments'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'uber');
    await tester.pump();
    expect(find.text('1 payment'), findsOneWidget);
    expect(find.text('Uber India'), findsOneWidget);
    expect(find.text('Swiggy'), findsNothing);
  });

  testWidgets('An empty month offers Import and Add', (tester) async {
    final db = await openSampleDb(tester, withData: false);
    await pumpHome(tester, db);

    expect(find.text('No payments yet this month.'), findsOneWidget);
    expect(find.text('Import file'), findsOneWidget);
    expect(find.text('Add payment'), findsOneWidget);
  });
}
