import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/category.dart';
import '../models/summary.dart';
import '../models/trends.dart';
import '../models/txn.dart';
import '../theme.dart';
import '../util/format.dart';

/// This month's spending against last month's, overall and by category.
class MonthChange extends StatelessWidget {
  const MonthChange({super.key, required this.comparison, required this.month});

  final MonthComparison comparison;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final prev = DateTime(month.year, month.month - 1);
    final against = c.throughDay == null
        ? DateFormat('MMMM').format(prev)
        : '1–${c.throughDay} ${DateFormat('MMM').format(prev)}';
    final pct = c.percent;
    final headline = pct == null
        ? 'Nothing spent in $against'
        : pct == 0
            ? 'The same as $against'
            : '${pct.abs()}% ${pct > 0 ? 'more' : 'less'} than $against';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatPaise(c.nowPaise),
            style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800, fontFeatures: kTabular)),
        Row(
          children: [
            if (pct != null && pct != 0) ...[
              Icon(pct > 0 ? Icons.trending_up : Icons.trending_down,
                  size: 18, color: muted),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                  pct == null
                      ? headline
                      : '$headline (${formatPaise(c.beforePaise)})',
                  style: text.bodyMedium?.copyWith(color: muted)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final row
            in c.categories.where((r) => r.nowPaise != r.beforePaise).take(6))
          _ChangeRow(row: row),
      ],
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.row});

  final CategoryChange row;

  @override
  Widget build(BuildContext context) {
    final cat = categoryOf(row.category);
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final diff = row.nowPaise - row.beforePaise;
    final change = row.beforePaise == 0
        ? 'new'
        : '${diff >= 0 ? '+' : '−'}${formatPaise(diff.abs())} '
            '(${(diff * 100 / row.beforePaise).round().abs()}%)';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: cat.color.withValues(alpha: 0.15),
            child: Icon(cat.icon, size: 16, color: cat.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.category, style: text.bodyMedium),
                Text(change,
                    style: text.bodySmall
                        ?.copyWith(color: muted, fontFeatures: kTabular)),
              ],
            ),
          ),
          if (diff != 0)
            Icon(diff > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14, color: muted),
          const SizedBox(width: 4),
          Text(formatPaise(row.nowPaise),
              style: text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600, fontFeatures: kTabular)),
        ],
      ),
    );
  }
}

/// Spending per month for the twelve months ending at [month], one hue,
/// the shown month in full strength. Tap a bar to go to that month; hold
/// it for the amount.
class YearBars extends StatelessWidget {
  const YearBars({
    super.key,
    required this.txns,
    required this.month,
    required this.onMonth,
  });

  final List<Txn> txns;
  final DateTime month;
  final ValueChanged<DateTime> onMonth;

  static const double _height = 120;

  @override
  Widget build(BuildContext context) {
    final rows = monthlyTotals(txns, month, months: 12);
    final max = rows.fold<int>(0, (a, r) => r.paise > a ? r.paise : a);
    final withSpend = rows.where((r) => r.paise > 0).toList();
    // Whole rupees: an average to the paisa is noise.
    final average = withSpend.isEmpty
        ? 0
        : withSpend.fold<int>(0, (a, r) => a + r.paise) ~/
            withSpend.length ~/
            100 *
            100;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final muted = scheme.onSurfaceVariant;
    if (max == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('No spending in these twelve months.',
            style: text.bodyMedium?.copyWith(color: muted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${DateFormat('MMMM').format(month)} ${formatPaise(rows.last.paise)}'
          ' · average ${formatPaise(average)} a month',
          style:
              text.bodyMedium?.copyWith(color: muted, fontFeatures: kTabular),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _height + 20,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final r in rows)
                Expanded(
                  child: Tooltip(
                    message:
                        '${DateFormat('MMM y').format(r.month)}: ${formatPaise(r.paise)}',
                    triggerMode: TooltipTriggerMode.longPress,
                    child: InkWell(
                      onTap: () => onMonth(r.month),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: r.paise / max),
                              duration: const Duration(milliseconds: 700),
                              curve: Curves.easeOutCubic,
                              builder: (context, v, _) => Container(
                                height: r.paise == 0
                                    ? 2
                                    : (_height * v).clamp(2, _height),
                                decoration: BoxDecoration(
                                  color: r.month == month
                                      ? scheme.primary
                                      : scheme.primary.withValues(alpha: 0.3),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('MMMMM').format(r.month),
                              style: text.labelSmall?.copyWith(
                                color:
                                    r.month == month ? scheme.onSurface : muted,
                                fontWeight: r.month == month
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The month as a calendar, each day shaded by what went out: light to
/// dark in one hue. Tap a day for the amount.
class SpendCalendar extends StatelessWidget {
  const SpendCalendar({super.key, required this.txns, required this.month});

  final List<Txn> txns;
  final DateTime month;

  static const List<double> _alpha = [0, 0.22, 0.42, 0.66, 0.92];

  @override
  Widget build(BuildContext context) {
    final byDay = dailyTotals(txns, month);
    final levels = heatLevels(byDay);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final blanks = DateTime(month.year, month.month).weekday - 1;
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final muted = scheme.onSurfaceVariant;
    final busiest = byDay.entries.isEmpty
        ? null
        : byDay.entries.reduce((a, b) => b.value > a.value ? b : a);

    Color fill(int level) => level == 0
        ? scheme.onSurface.withValues(alpha: 0.05)
        : scheme.primary.withValues(alpha: _alpha[level]);

    Widget cell(int day) {
      final date = DateTime(month.year, month.month, day);
      final future = date.isAfter(now);
      final paise = byDay[day] ?? 0;
      final level = levels[day] ?? 0;
      return Tooltip(
        message: '${DateFormat('EEE d MMM').format(date)}: '
            '${paise == 0 ? 'nothing spent' : formatPaise(paise)}',
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: future ? null : fill(level),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$day',
              style: text.labelMedium?.copyWith(
                color: future
                    ? muted.withValues(alpha: 0.5)
                    : level >= 3
                        ? scheme.onPrimary
                        : scheme.onSurface,
                fontFeatures: kTabular,
              )),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (busiest != null)
          Text(
            'Busiest: ${DateFormat('EEE d MMM').format(DateTime(month.year, month.month, busiest.key))}, '
            '${formatPaise(busiest.value)}',
            style: text.bodyMedium?.copyWith(color: muted),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Text(d,
                    textAlign: TextAlign.center,
                    style: text.labelSmall?.copyWith(color: muted)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          padding: EdgeInsets.zero,
          children: [
            for (var i = 0; i < blanks; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++) cell(d),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Less', style: text.labelSmall?.copyWith(color: muted)),
            const SizedBox(width: 4),
            for (var l = 0; l <= 4; l++)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                    color: fill(l), borderRadius: BorderRadius.circular(3)),
              ),
            const SizedBox(width: 4),
            Text('More', style: text.labelSmall?.copyWith(color: muted)),
          ],
        ),
      ],
    );
  }
}
