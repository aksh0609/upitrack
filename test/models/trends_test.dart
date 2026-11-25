import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/trends.dart';
import 'package:upitrack/models/txn.dart';

Txn pay(int rupees, String category, DateTime at) => Txn(
      key: '$rupees$category$at',
      amountPaise: rupees * 100,
      isDebit: true,
      counterparty: 'X',
      channel: 'UPI',
      category: category,
      time: at,
    );

void main() {
  final txns = [
    pay(1000, 'Food', DateTime(2026, 10, 3)),
    pay(500, 'Travel', DateTime(2026, 10, 20)),
    pay(2000, 'Food', DateTime(2026, 10, 28)), // after the 25th
    pay(1300, 'Food', DateTime(2026, 11, 2)),
    pay(400, 'Shopping', DateTime(2026, 11, 24)),
    pay(9000, 'Self transfer', DateTime(2026, 11, 5)),
  ];

  test('the current month is compared day for day', () {
    final c =
        compareMonths(txns, DateTime(2026, 11), now: DateTime(2026, 11, 25));
    expect(c.throughDay, 25);
    expect(c.nowPaise, 170000);
    expect(c.beforePaise, 150000, reason: '28 Oct is past day 25');
    expect(c.percent, 13);
    expect(c.categories.first,
        (category: 'Travel', nowPaise: 0, beforePaise: 50000));
  });

  test('a past month is compared whole', () {
    final c =
        compareMonths(txns, DateTime(2026, 10), now: DateTime(2026, 11, 25));
    expect(c.throughDay, isNull);
    expect(c.nowPaise, 350000);
    expect(c.beforePaise, 0);
    expect(c.percent, isNull);
  });

  test('day 31 against a 30-day month', () {
    final c = compareMonths([
      pay(100, 'Food', DateTime(2026, 6, 30)),
      pay(100, 'Food', DateTime(2026, 7, 31)),
    ], DateTime(2026, 7), now: DateTime(2026, 7, 31));
    expect(c.beforePaise, 10000);
  });

  test('daily totals and heat levels', () {
    final d = dailyTotals(txns, DateTime(2026, 11));
    expect(d, {2: 130000, 24: 40000});
    expect(heatLevels({1: 100, 2: 5000, 3: 300, 4: 200, 5: 0}),
        {1: 1, 4: 2, 3: 3, 2: 4});
    expect(heatLevels({7: 100}), {7: 1});
  });
}
