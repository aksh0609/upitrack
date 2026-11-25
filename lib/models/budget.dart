import '../parser/categorizer.dart';
import 'category.dart';
import 'summary.dart';

/// Key of the whole-month budget; category budgets use the category name.
const String kTotalBudget = '*';

String budgetName(String key) => key == kTotalBudget ? 'All spending' : key;

/// One budget and what the month has spent against it.
typedef BudgetLine = ({String key, int spentPaise, int limitPaise});

/// [budgets] (key → monthly limit) against [summary]: the overall budget
/// first, then categories, most used first.
List<BudgetLine> budgetLines(Map<String, int> budgets, MonthSummary summary) {
  final lines = [
    for (final e in budgets.entries)
      (
        key: e.key,
        spentPaise: e.key == kTotalBudget
            ? summary.spentPaise
            : summary.byCategory[e.key] ?? 0,
        limitPaise: e.value,
      )
  ];
  double used(BudgetLine l) => l.spentPaise / l.limitPaise;
  lines.sort((a, b) {
    if (a.key == kTotalBudget) return -1;
    if (b.key == kTotalBudget) return 1;
    return used(b).compareTo(used(a));
  });
  return lines;
}

enum BudgetLevel { ok, near, over }

/// Near from 80% of the limit; over once spending passes it.
BudgetLevel budgetLevel(int spentPaise, int limitPaise) =>
    spentPaise > limitPaise
        ? BudgetLevel.over
        : spentPaise * 5 >= limitPaise * 4
            ? BudgetLevel.near
            : BudgetLevel.ok;

/// Categories a budget makes sense for: money that is spent.
Iterable<CategoryInfo> get budgetCategories => kCategories.where((c) =>
    Categorizer.countsAsSpending(c.name) && c.name != Categorizer.income);
