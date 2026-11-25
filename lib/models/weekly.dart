import '../parser/categorizer.dart';
import '../util/format.dart';
import 'recurring.dart';
import 'txn.dart';

/// Monday 00:00 of [d]'s week.
DateTime weekStart(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

String ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Last week's spending (Monday to Sunday before [now]'s week) against the
/// four weeks before it. [usualPaise] averages the weeks that had any
/// spending, null when none did (a new install).
typedef WeekSummary = ({
  int spentPaise,
  int? usualPaise,
  String? topCategory,
  int topPaise,
});

WeekSummary? weeklySummary(List<Txn> txns, DateTime now) {
  final thisWeek = weekStart(now);
  final lastWeek = DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7);
  final weeks = <int, int>{}; // 0 = last week, 1..4 = before it
  final byCategory = <String, int>{};
  for (final t in txns) {
    if (!t.isDebit || !Categorizer.countsAsSpending(t.category)) continue;
    if (!t.time.isBefore(thisWeek)) continue;
    final back = weekStart(t.time).difference(lastWeek).inDays ~/ -7;
    if (back < 0 || back > 4) continue;
    weeks[back] = (weeks[back] ?? 0) + t.amountPaise;
    if (back == 0) {
      byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amountPaise;
    }
  }
  final spent = weeks[0] ?? 0;
  final before =
      [for (var w = 1; w <= 4; w++) weeks[w] ?? 0].where((p) => p > 0).toList();
  if (spent == 0 && before.isEmpty) return null;
  final top = byCategory.entries.isEmpty
      ? null
      : byCategory.entries.reduce((a, b) => b.value > a.value ? b : a);
  return (
    spentPaise: spent,
    usualPaise:
        before.isEmpty ? null : before.reduce((a, b) => a + b) ~/ before.length,
    topCategory: top?.key,
    topPaise: top?.value ?? 0,
  );
}

({String title, String body}) weeklyText(WeekSummary s) {
  final usual = s.usualPaise;
  final compare = usual == null || usual == 0
      ? null
      : () {
          final pct = ((s.spentPaise - usual) * 100 / usual).round();
          return pct == 0
              ? 'About your usual ${formatPaise(usual)}'
              : '${pct.abs()}% ${pct > 0 ? 'more' : 'less'} than your usual '
                  '${formatPaise(usual)}';
        }();
  final top = s.topCategory == null
      ? null
      : 'most on ${s.topCategory} (${formatPaise(s.topPaise)})';
  final body = [if (compare != null) compare, if (top != null) top].join(' · ');
  return (
    title: '${formatPaise(s.spentPaise)} spent last week',
    body: body.isEmpty
        ? 'Open UPI Track for the details'
        : body[0].toUpperCase() + body.substring(1),
  );
}

/// Repeats due in one or two days that haven't been announced yet (see
/// [dueKey] and [sent]).
List<Recurring> dueToRemind(
    List<Recurring> all, DateTime now, Set<String> sent) {
  final today = DateTime(now.year, now.month, now.day);
  return [
    for (final r in all)
      if (!sent.contains(dueKey(r)) &&
          {1, 2}.contains(DateTime(r.next.year, r.next.month, r.next.day)
              .difference(today)
              .inDays))
        r
  ];
}

String dueKey(Recurring r) => '${r.name}|${ymd(r.next)}';

({String title, String body}) dueText(Recurring r, DateTime now) => (
      title:
          '${r.name} ${formatPaise(r.amountPaise)} due ${dueLabel(r.next, now: now)}',
      body: 'It came every month for the last ${r.count} months.',
    );
