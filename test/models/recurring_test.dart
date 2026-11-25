import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/recurring.dart';
import 'package:upitrack/models/txn.dart';

Txn pay(String who, int rupees, DateTime at,
        {String category = 'Bills & Recharge'}) =>
    Txn(
      key: '$who$at$rupees',
      amountPaise: rupees * 100,
      isDebit: true,
      counterparty: who,
      channel: 'UPI',
      category: category,
      time: at,
    );

void main() {
  final now = DateTime(2026, 11, 25);

  test('three monthly payments of about the same amount are a repeat', () {
    final found = findRecurring([
      pay('NETFLIX', 649, DateTime(2026, 8, 28)),
      pay('NETFLIX', 649, DateTime(2026, 9, 28)),
      pay('NETFLIX', 649, DateTime(2026, 10, 28)),
      pay('NETFLIX', 199, DateTime(2026, 10, 2)), // a one-off, other amount
    ], now: now);
    expect(found, hasLength(1));
    final r = found.single;
    expect(r.amountPaise, 64900);
    expect(r.count, 3);
    expect(r.next, DateTime(2026, 11, 28));
    expect(dueLabel(r.next, now: now), 'in 3 days');
    expect(comingUp(found, now: now), hasLength(1));
  });

  test('a small change in price still counts; a big one breaks it', () {
    final found = findRecurring([
      pay('JIO', 299, DateTime(2026, 8, 20)),
      pay('JIO', 299, DateTime(2026, 9, 19)),
      pay('JIO', 319, DateTime(2026, 10, 19)),
      pay('BESCOM', 900, DateTime(2026, 8, 5)),
      pay('BESCOM', 1500, DateTime(2026, 9, 5)),
      pay('BESCOM', 2100, DateTime(2026, 10, 5)),
    ], now: now);
    expect(found.map((r) => r.name), ['Jio']);
  });

  test('not a bill: frequent same-sized payments, too few, or stopped', () {
    final coffee = [
      for (var d = 1; d < 90; d += 3)
        pay('STARBUCKS', 250, DateTime(2026, 8, d), category: 'Food')
    ];
    final found = findRecurring([
      ...coffee,
      pay('SPOTIFY', 119, DateTime(2026, 9, 1)),
      pay('SPOTIFY', 119, DateTime(2026, 10, 1)),
      pay('HOTSTAR', 299, DateTime(2026, 5, 1)),
      pay('HOTSTAR', 299, DateTime(2026, 6, 1)),
      pay('HOTSTAR', 299, DateTime(2026, 7, 1)), // stopped in July
    ], now: now);
    expect(found, isEmpty);
  });

  test('self transfers and income are not repeats', () {
    final found = findRecurring([
      for (final m in [8, 9, 10])
        pay('OWN ACCOUNT', 5000, DateTime(2026, m, 1),
            category: 'Self transfer'),
    ], now: now);
    expect(found, isEmpty);
  });

  test('labels', () {
    expect(dueLabel(DateTime(2026, 11, 25, 20), now: now), 'today');
    expect(dueLabel(DateTime(2026, 11, 26), now: now), 'tomorrow');
    expect(dueLabel(DateTime(2026, 11, 23), now: now), 'due now');
  });
}
