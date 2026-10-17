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
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const on = Colors.white;
    final net = summary.netPaise;
    final spent = summary.spentPaise;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: kBrandGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF6D28D9).withValues(alpha: dark ? 0.40 : 0.28),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            const Positioned(right: -50, top: -60, child: _Ring(size: 190)),
            const Positioned(right: 50, bottom: -80, child: _Ring(size: 150)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showToday
                        ? 'Spent this month'
                        : 'Spent in ${DateFormat('MMMM').format(month)}',
                    style: text.labelLarge
                        ?.copyWith(color: on.withValues(alpha: 0.85)),
                  ),
                  const SizedBox(height: 4),
                  // Counts up to the new total when it changes.
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: spent.toDouble()),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        // Whole rupees while counting, so no paise flicker.
                        formatPaise(
                            v == spent ? spent : (v / 100).round() * 100),
                        style: text.displaySmall?.copyWith(
                          color: on,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: on.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: on.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      children: [
                        _Stat(
                            label: 'Received',
                            value: '+${formatPaise(summary.receivedPaise)}'),
                        if (showToday)
                          _Stat(
                              label: 'Today',
                              value: formatPaise(summary.todaySpentPaise)),
                        _Stat(
                          label: net < 0 ? 'Net out' : 'Net in',
                          value: formatPaise(net.abs()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A faint circle that decorates the card's corners.
class _Ring extends StatelessWidget {
  const _Ring({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.07),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: text.labelMedium
                  ?.copyWith(color: Colors.white.withValues(alpha: 0.75))),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: text.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFeatures: kTabular)),
          ),
        ],
      ),
    );
  }
}
