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

  test('a bill may change from month to month; anything else stays within 10%',
      () {
    final found = findRecurring([
      pay('JIO', 299, DateTime(2026, 8, 20)),
      pay('JIO', 299, DateTime(2026, 9, 19)),
      pay('JIO', 319, DateTime(2026, 10, 19)),
      pay('BESCOM', 900, DateTime(2026, 9, 5)),
      pay('BESCOM', 1500, DateTime(2026, 10, 5)),
      pay('BESCOM', 2100, DateTime(2026, 11, 5)),
      for (final (m, rupees) in [(8, 900), (9, 1500), (10, 2100)])
        pay('MYNTRA', rupees, DateTime(2026, m, 12), category: 'Shopping'),
    ], now: now);
    expect([
      for (final r in found) (r.name, r.amountPaise, r.varies)
    ], [
      ('Jio', 31900, false),
      ('BESCOM', 210000, true),
    ]);
    expect(found.last.next, DateTime(2026, 12, 5));
  });

  test('two months of the same amount are enough; of different ones, not', () {
    final found = findRecurring([
      pay('RAHUL SHARMA', 15000, DateTime(2026, 10, 5), category: 'Transfers'),
      pay('RAHUL SHARMA', 15000, DateTime(2026, 11, 5), category: 'Transfers'),
      pay('PRIYA', 500, DateTime(2026, 10, 10), category: 'Transfers'),
      pay('PRIYA', 800, DateTime(2026, 11, 10), category: 'Transfers'),
    ], now: now);
    final rent = found.single;
    expect((rent.name, rent.count, rent.next),
        ('RAHUL SHARMA', 2, DateTime(2026, 12, 5)));
  });

  test('a one-off top-up after the monthly plan does not hide it', () {
    final r = findRecurring([
      pay('AIRTEL', 299, DateTime(2026, 9, 3)),
      pay('AIRTEL', 299, DateTime(2026, 10, 3)),
      pay('AIRTEL', 299, DateTime(2026, 11, 3)),
      pay('AIRTEL', 49, DateTime(2026, 11, 10)),
    ], now: now)
        .single;
    expect((r.amountPaise, r.count, r.next), (29900, 3, DateTime(2026, 12, 3)));
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

  test('added payments fall due on their day; the found twin is dropped', () {
    final all = regularPayments([
      pay('NETFLIX', 649, DateTime(2026, 8, 28)),
      pay('NETFLIX', 649, DateTime(2026, 9, 28)),
      pay('NETFLIX', 649, DateTime(2026, 10, 28)),
    ], const [
      Bill('Rent', 1500000, 5), // the 5th has passed: next month
      Bill('School fees', 400000, 27), // later this month
      Bill('Netflix', 64900, 31), // 31 Nov doesn't exist: the 30th
    ], now: now);
    expect([
      for (final r in all) (r.name, r.next)
    ], [
      ('School fees', DateTime(2026, 11, 27)),
      ('Netflix', DateTime(2026, 11, 30)),
      ('Rent', DateTime(2026, 12, 5)),
    ]);
    expect(all.every((r) => r.added), isTrue);
    expect(
        comingUp(all, now: now).map((r) => r.name), ['School fees', 'Netflix']);
  });

  test('an added payment due today is still this month', () {
    final r = regularPayments(const [], const [Bill('EMI', 1000000, 25)],
            now: DateTime(2026, 11, 25, 18))
        .single;
    expect(r.next, DateTime(2026, 11, 25));
    expect(dueLabel(r.next, now: DateTime(2026, 11, 25, 18)), 'today');
  });
}
