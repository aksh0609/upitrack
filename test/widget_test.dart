import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/widgets/category_bars.dart';
import 'package:upitrack/widgets/merchant_bars.dart';
import 'package:upitrack/widgets/txn_tile.dart';

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
}
