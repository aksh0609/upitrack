import '../parser/categorizer.dart';
import '../parser/merchant.dart';
import 'txn.dart';

/// Totals for the transactions currently on screen. Self transfers (money
/// moved between the user's own accounts) count for nothing.
class MonthSummary {
  const MonthSummary({
    required this.spentPaise,
    required this.receivedPaise,
    required this.todaySpentPaise,
    required this.byCategory,
    required this.byMerchant,
  });

  final int spentPaise;
  final int receivedPaise;
  final int todaySpentPaise;

  /// Spending per category, largest first.
  final Map<String, int> byCategory;

  /// Spending per merchant (see [merchantOf]), largest first.
  final Map<String, ({int count, int totalPaise})> byMerchant;

  int get netPaise => receivedPaise - spentPaise;

  factory MonthSummary.from(List<Txn> txns, {DateTime? now}) {
    final today = now ?? DateTime.now();
    var spent = 0;
    var received = 0;
    var todaySpent = 0;
    final byCategory = <String, int>{};
    final byMerchant = <String, ({int count, int totalPaise})>{};

    for (final t in txns) {
      if (t.category == Categorizer.selfTransfer) continue;
      if (t.isDebit) {
        spent += t.amountPaise;
        byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amountPaise;
        final m = merchantOf(t.counterparty);
        final prev = byMerchant[m] ?? (count: 0, totalPaise: 0);
        byMerchant[m] = (
          count: prev.count + 1,
          totalPaise: prev.totalPaise + t.amountPaise
        );
        if (t.time.year == today.year &&
            t.time.month == today.month &&
            t.time.day == today.day) {
          todaySpent += t.amountPaise;
        }
      } else {
        received += t.amountPaise;
      }
    }

    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final merchants = byMerchant.entries.toList()
      ..sort((a, b) => b.value.totalPaise.compareTo(a.value.totalPaise));

    return MonthSummary(
      spentPaise: spent,
      receivedPaise: received,
      todaySpentPaise: todaySpent,
      byCategory: Map.fromEntries(categories),
      byMerchant: Map.fromEntries(merchants),
    );
  }
}

/// Spending per calendar month for the [months] months ending at
/// [lastMonth] (first-of-month), oldest first, with zeros for empty months.
/// Debits only; self transfers excluded.
List<({DateTime month, int paise})> monthlyTotals(
  List<Txn> txns,
  DateTime lastMonth, {
  int months = 6,
}) {
  final rows = <({DateTime month, int paise})>[];
  for (var i = months - 1; i >= 0; i--) {
    final month = DateTime(lastMonth.year, lastMonth.month - i);
    final next = DateTime(month.year, month.month + 1);
    var sum = 0;
    for (final t in txns) {
      if (!t.isDebit || t.category == Categorizer.selfTransfer) continue;
      if (!t.time.isBefore(month) && t.time.isBefore(next)) {
        sum += t.amountPaise;
      }
    }
    rows.add((month: month, paise: sum));
  }
  return rows;
}
