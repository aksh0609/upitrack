import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/data/shortcut_inbox.dart';
import 'package:upitrack/data/sms_source.dart';
import 'package:upitrack/data/repository.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/screens/settings_screen.dart';
import 'package:upitrack/screens/welcome_screen.dart';
import 'package:upitrack/sync/sync_controller.dart';
import 'package:upitrack/theme.dart';
import 'package:upitrack/widgets/category_bars.dart';
import 'package:upitrack/widgets/merchant_bars.dart';
import 'package:upitrack/widgets/txn_tile.dart';

import 'sync/fakes.dart';
import 'sync/memory_sync_store.dart';

void main() {
  testWidgets('CategoryBars shows each category with its total',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CategoryBars(totals: {'Food': 150000, 'Travel': 25050}),
      ),
    ));

    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);
    expect(find.textContaining('1,500'), findsOneWidget);
    expect(find.textContaining('250.50'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
  });

  testWidgets('TxnTile can be swiped away only when onHide is given',
      (tester) async {
    final txn = Txn(
      key: 'k',
      amountPaise: 25000,
      isDebit: true,
      counterparty: 'SWIGGY',
      channel: 'UPI',
      category: 'Food',
      time: DateTime(2026, 10, 3, 9),
    );
    var hidden = 0;
    var shown = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(children: [
            TxnTile(txn: txn, onTap: () {}),
            if (shown)
              TxnTile(
                  txn: txn,
                  onTap: () {},
                  onHide: () => setState(() {
                        hidden++;
                        shown = false;
                      })),
          ]),
        ),
      ),
    ));
    expect(find.byType(Dismissible), findsOneWidget);
    expect(tester.widget<Text>(find.text('₹250').first).semanticsLabel,
        'Paid ₹250');
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(hidden, 1);
    expect(find.byType(Dismissible), findsNothing);
  });

  testWidgets('MerchantBars shows limited rows and reports taps',
      (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MerchantBars(
          totals: {
            'Amazon': (count: 3, totalPaise: 450000),
            'Swiggy': (count: 2, totalPaise: 30000),
          },
          limit: 1,
          onTap: (m) => tapped = m,
        ),
      ),
    ));
    expect(find.text('Amazon'), findsOneWidget);
    expect(find.text('Swiggy'), findsNothing);
    expect(find.text('3 payments'), findsOneWidget);
    expect(find.textContaining('4,500'), findsOneWidget);
    await tester.tap(find.text('Amazon'));
    expect(tapped, 'Amazon');
  });

  testWidgets('Sign-in is required: welcome, Google, passphrase, then the app',
      (tester) async {
    sqfliteFfiInit();
    // Real sqflite I/O never completes in the fake-async zone: run it in real time.
    final db = (await tester.runAsync(() =>
        AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath)))!;
    final store = MemorySyncStore();
    final sync = SyncController(db,
        auth: FakeAuth(),
        keys: MemorySyncKeys(),
        storeFor: (_) => store,
        iterations: 1000);
    await tester.runAsync(sync.start);
    await tester.pumpWidget(MaterialApp(
        home: SignInGate(sync: sync, child: const Text('the app'))));

    expect(find.text('Welcome to UPI Track'), findsOneWidget);
    expect(find.text('the app'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('Continue with Google'));
      await waitFor(() => sync.state == SyncState.needsPassphrase);
    });
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('passphrase')), 'correct horse');
    await tester.enterText(
        find.byKey(const Key('passphrase2')), 'correct horse');
    await tester.runAsync(() async {
      await tester.tap(find.text('Create account'));
      await waitFor(() => !sync.syncing && sync.lastOk != null);
    });
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('the app'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
            repository: TxnRepository(db, SmsSource(), ShortcutInbox()),
            sync: sync)));
    // Let the screen's settings read finish before the database closes.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('Signed in as me@example.com'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    await tester.runAsync(db.close);
  });

  testWidgets('Settings → Appearance switches the theme and remembers it',
      (tester) async {
    sqfliteFfiInit();
    final db = (await tester.runAsync(() =>
        AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath)))!;
    await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
            repository: TxnRepository(db, SmsSource(), ShortcutInbox()))));
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(themeMode.value, ThemeMode.dark);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    final saved =
        await tester.runAsync<String?>(() => db.getMeta(kThemeSetting));
    expect(themeModeNamed(saved), ThemeMode.dark);
    themeMode.value = ThemeMode.system;
    await tester.runAsync(db.close);
  });
}
