import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/summary.dart';
import '../theme.dart';
import '../util/format.dart';

/// The month's headline: what went out, big, with what came in beside it.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.summary,
    required this.month,
    required this.showToday,
  });

  final MonthSummary summary;

  /// First day of the month on screen.
  final DateTime month;

  /// Only meaningful when the current month is on screen.
  final bool showToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final on = scheme.onPrimaryContainer;
    final net = summary.netPaise;

    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              showToday
                  ? 'Spent this month'
                  : 'Spent in ${DateFormat('MMMM').format(month)}',
              style: text.labelLarge?.copyWith(color: on),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatPaise(summary.spentPaise),
                style: text.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: on,
                  fontFeatures: kTabular,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(
                    label: 'Received',
                    value: '+${formatPaise(summary.receivedPaise)}',
                    color: on),
                if (showToday)
                  _Stat(
                      label: 'Today',
                      value: formatPaise(summary.todaySpentPaise),
                      color: on),
                _Stat(
                  label: net < 0 ? 'Net out' : 'Net in',
                  value: formatPaise(net.abs()),
                  color: on,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: text.labelMedium
                  ?.copyWith(color: color.withValues(alpha: 0.8))),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: text.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontFeatures: kTabular)),
          ),
        ],
      ),
    );
  }
}
