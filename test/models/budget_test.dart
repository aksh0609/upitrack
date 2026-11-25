import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/budget.dart';
import 'package:upitrack/models/summary.dart';
import 'package:upitrack/models/txn.dart';

Txn pay(int rupees, String category) => Txn(
      key: '$rupees$category',
      amountPaise: rupees * 100,
      isDebit: true,
      counterparty: 'X',
      channel: 'UPI',
      category: category,
      time: DateTime(2026, 11, 3),
    );

void main() {
  test('overall budget first, then the most used category', () {
    final s = MonthSummary.from(
        [pay(900, 'Food'), pay(100, 'Travel'), pay(500, 'Self transfer')]);
    final lines = budgetLines(
        {'Travel': 100000, 'Food': 100000, kTotalBudget: 500000}, s);
    expect(lines.map((l) => l.key), [kTotalBudget, 'Food', 'Travel']);
    expect(lines.first.spentPaise, 100000); // self transfer left out
    expect(lines[1].spentPaise, 90000);
  });

  test('levels: ok below 80%, near from 80%, over past the limit', () {
    expect(budgetLevel(79, 100), BudgetLevel.ok);
    expect(budgetLevel(80, 100), BudgetLevel.near);
    expect(budgetLevel(100, 100), BudgetLevel.near);
    expect(budgetLevel(101, 100), BudgetLevel.over);
  });

  test('no budgets for income or self transfers', () {
    final names = budgetCategories.map((c) => c.name);
    expect(names, contains('Food'));
    expect(names, isNot(contains('Income')));
    expect(names, isNot(contains('Self transfer')));
  });
}
