import 'txn.dart';

/// Totals for the transactions currently on screen.
class MonthSummary {
  const MonthSummary({
    required this.spentPaise,
    required this.receivedPaise,
    required this.todaySpentPaise,
    required this.byCategory,
  });

  final int spentPaise;
  final int receivedPaise;
  final int todaySpentPaise;

  /// Spending per category, largest first.
  final Map<String, int> byCategory;

  int get netPaise => receivedPaise - spentPaise;

  factory MonthSummary.from(List<Txn> txns, {DateTime? now}) {
    final today = now ?? DateTime.now();
    var spent = 0;
    var received = 0;
    var todaySpent = 0;
    final byCategory = <String, int>{};

    for (final t in txns) {
      if (t.isDebit) {
        spent += t.amountPaise;
        byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amountPaise;
        if (t.time.year == today.year &&
            t.time.month == today.month &&
            t.time.day == today.day) {
          todaySpent += t.amountPaise;
        }
      } else {
        received += t.amountPaise;
      }
    }

    final sorted = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return MonthSummary(
      spentPaise: spent,
      receivedPaise: received,
      todaySpentPaise: todaySpent,
      byCategory: Map.fromEntries(sorted),
    );
  }
}
