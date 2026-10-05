import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/widgets/category_bars.dart';

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
}
