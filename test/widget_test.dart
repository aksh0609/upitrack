import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/screens/settings_screen.dart';
import 'package:upitrack/sync/sync_controller.dart';
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

  testWidgets('TxnTile shows a Hide button only when onHide is given', (tester) async {
    final txn = Txn(
      key: 'k', amountPaise: 25000, isDebit: true, counterparty: 'SWIGGY',
      channel: 'UPI', category: 'Food', time: DateTime(2026, 10, 3, 9),
    );
    var hidden = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          TxnTile(txn: txn, onTap: () {}),
          TxnTile(txn: txn, onTap: () {}, onHide: () => hidden++),
        ]),
      ),
    ));
    expect(find.byTooltip('Hide'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide'));
    expect(hidden, 1);
  });

  testWidgets('MerchantBars shows limited rows and reports taps', (tester) async {
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

  testWidgets('Settings walks from sign-in to a passphrase to ready', (tester) async {
    sqfliteFfiInit();
    // Real sqflite I/O never completes in the fake-async zone: run it in real time.
    final db = (await tester.runAsync(
        () => AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath)))!;
    final store = MemorySyncStore();
    final sync = SyncController(db,
        auth: FakeAuth(), keys: MemorySyncKeys(), storeFor: (_) => store, iterations: 1000);
    await tester.runAsync(sync.start);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(sync: sync)));

    expect(find.text('Sign in with Google'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Sign in with Google'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Turn on sync'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('passphrase')), 'correct horse');
    await tester.enterText(find.byKey(const Key('passphrase2')), 'correct horse');
    await tester.runAsync(() async {
      await tester.tap(find.text('Turn on sync'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.textContaining('Last synced'), findsOneWidget);
    await tester.runAsync(db.close);
  });
}
