import 'package:flutter/material.dart';

import '../models/summary.dart';
import '../util/format.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.summary, required this.showToday});

  final MonthSummary summary;

  /// Only meaningful when the current month is on screen.
  final bool showToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spent this month',
                style: text.labelLarge
                    ?.copyWith(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(
              formatPaise(summary.spentPaise),
              style: text.headlineLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(
                    label: 'Received',
                    value: formatPaise(summary.receivedPaise),
                    color: scheme.onPrimaryContainer),
                if (showToday)
                  _Stat(
                      label: 'Today',
                      value: formatPaise(summary.todaySpentPaise),
                      color: scheme.onPrimaryContainer),
                _Stat(
                  label: 'Net',
                  value:
                      '${summary.netPaise < 0 ? '-' : '+'}${formatPaise(summary.netPaise.abs())}',
                  color: scheme.onPrimaryContainer,
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
                  ?.copyWith(color: color.withValues(alpha: 0.75))),
          const SizedBox(height: 2),
          Text(value,
              style: text.titleMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
