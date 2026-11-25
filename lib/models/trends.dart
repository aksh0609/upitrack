import '../parser/categorizer.dart';
import 'txn.dart';

/// One category's spending in two periods.
typedef CategoryChange = ({String category, int nowPaise, int beforePaise});

/// [month] against the month before it. For the current month only days
/// 1 to today count on both sides ([throughDay]), so a half month isn't
/// set against a whole one.
class MonthComparison {
  const MonthComparison({
    required this.nowPaise,
    required this.beforePaise,
    required this.categories,
    required this.throughDay,
  });

  final int nowPaise;
  final int beforePaise;

  /// Largest change first.
  final List<CategoryChange> categories;

  /// Null when whole months are compared.
  final int? throughDay;

  /// Percent change, or null when there was nothing before.
  int? get percent => beforePaise == 0
      ? null
      : ((nowPaise - beforePaise) * 100 / beforePaise).round();
}

MonthComparison compareMonths(List<Txn> txns, DateTime month, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final current = month.year == today.year && month.month == today.month;
  final prev = DateTime(month.year, month.month - 1);
  // Day 31 of a 30-day month rolls over, so cap at the month's own length.
  int lastDay(DateTime m) => DateTime(m.year, m.month + 1, 0).day;
  final through = current ? today.day : null;
  DateTime end(DateTime m) => through == null
      ? DateTime(m.year, m.month + 1)
      : DateTime(
          m.year, m.month, (through < lastDay(m) ? through : lastDay(m)) + 1);

  final nowBy = <String, int>{};
  final beforeBy = <String, int>{};
  for (final t in txns) {
    if (!t.isDebit || !Categorizer.countsAsSpending(t.category)) continue;
    if (!t.time.isBefore(month) && t.time.isBefore(end(month))) {
      nowBy[t.category] = (nowBy[t.category] ?? 0) + t.amountPaise;
    } else if (!t.time.isBefore(prev) && t.time.isBefore(end(prev))) {
      beforeBy[t.category] = (beforeBy[t.category] ?? 0) + t.amountPaise;
    }
  }
  final categories = [
    for (final c in {...nowBy.keys, ...beforeBy.keys})
      (category: c, nowPaise: nowBy[c] ?? 0, beforePaise: beforeBy[c] ?? 0)
  ]..sort((a, b) => (b.nowPaise - b.beforePaise)
      .abs()
      .compareTo((a.nowPaise - a.beforePaise).abs()));
  int sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);
  return MonthComparison(
    nowPaise: sum(nowBy),
    beforePaise: sum(beforeBy),
    categories: categories,
    throughDay: through,
  );
}

/// Spending per day of [month] (day of month → paise), days without
/// spending left out.
Map<int, int> dailyTotals(List<Txn> txns, DateTime month) {
  final next = DateTime(month.year, month.month + 1);
  final out = <int, int>{};
  for (final t in txns) {
    if (!t.isDebit || !Categorizer.countsAsSpending(t.category)) continue;
    if (t.time.isBefore(month) || !t.time.isBefore(next)) continue;
    out[t.time.day] = (out[t.time.day] ?? 0) + t.amountPaise;
  }
  return out;
}

/// Day → 1..4 for the calendar's light-to-dark steps, by rank among the
/// days with spending (quartiles), so one big rent day doesn't wash out
/// the rest. Days without spending are left out (level 0).
Map<int, int> heatLevels(Map<int, int> byDay) {
  final ranked = byDay.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return {
    for (final (i, e) in ranked.indexed) e.key: 1 + i * 4 ~/ ranked.length
  };
}
