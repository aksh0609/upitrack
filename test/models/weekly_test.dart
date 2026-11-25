import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/recurring.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/models/weekly.dart';

Txn pay(int rupees, DateTime at, {String category = 'Food'}) => Txn(
      key: '$rupees$at$category',
      amountPaise: rupees * 100,
      isDebit: true,
      counterparty: 'X',
      channel: 'UPI',
      category: category,
      time: at,
    );

void main() {
  // Wednesday 25 Nov 2026; this week began Monday 23 Nov.
  final now = DateTime(2026, 11, 25, 9);

  test('weeks start on Monday', () {
    expect(weekStart(now), DateTime(2026, 11, 23));
    expect(weekStart(DateTime(2026, 11, 22, 23)), DateTime(2026, 11, 16));
  });

  test('last week against the weeks before it', () {
    final s = weeklySummary([
      pay(600, DateTime(2026, 11, 16, 9)), // last week, Monday
      pay(300, DateTime(2026, 11, 22, 21), category: 'Travel'), // Sunday
      pay(500, DateTime(2026, 11, 10)), // the week before
      pay(1000, DateTime(2026, 10, 27)), // 3 weeks before
      pay(9999, DateTime(2026, 10, 12)), // 5 weeks before: ignored
      pay(4000, DateTime(2026, 11, 24)), // this week: ignored
      pay(5000, DateTime(2026, 11, 18), category: 'Self transfer'),
    ], now)!;
    expect(s.spentPaise, 90000);
    expect(s.usualPaise, 75000, reason: 'two weeks with spending');
    expect((s.topCategory, s.topPaise), ('Food', 60000));
    expect(weeklyText(s), (
      title: '₹900 spent last week',
      body: '20% more than your usual ₹750 · most on Food (₹600)',
    ));
  });

  test('nothing at all: no summary; no history: no comparison', () {
    expect(weeklySummary(const [], now), isNull);
    final s = weeklySummary([pay(250, DateTime(2026, 11, 20))], now)!;
    expect(s.usualPaise, isNull);
    expect(weeklyText(s).body, 'Most on Food (₹250)');
  });

  test('a bill is announced once, one or two days ahead', () {
    Recurring r(DateTime next) => Recurring(
        name: 'Netflix',
        amountPaise: 64900,
        category: 'Entertainment',
        last: DateTime(2026, 10, 27),
        next: next,
        count: 4);
    final tomorrow = r(DateTime(2026, 11, 26, 9));
    expect(dueToRemind([tomorrow], now, {}), [tomorrow]);
    expect(dueToRemind([tomorrow], now, {dueKey(tomorrow)}), isEmpty);
    expect(dueToRemind([r(DateTime(2026, 11, 25))], now, {}), isEmpty);
    expect(dueToRemind([r(DateTime(2026, 11, 28))], now, {}), isEmpty);
    expect(dueText(tomorrow, now).title, 'Netflix ₹649 due tomorrow');
  });
}
