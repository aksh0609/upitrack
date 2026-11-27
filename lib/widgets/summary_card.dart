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
    final brand = context.brand;
    const on = Colors.white;
    final net = summary.netPaise;
    final spent = summary.spentPaise;

    return DecoratedBox(
      decoration: BoxDecoration(
        // One hue, a touch lighter at the top: depth without decoration.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(brand.hero, Colors.white, dark ? 0.10 : 0.06)!,
            brand.hero,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: dark
            ? Border.all(color: Colors.white.withValues(alpha: 0.08))
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
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
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _CountUp(
                      spent,
                      style: text.displaySmall
                          ?.copyWith(color: on, fontFeatures: kTabular),
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
                            paise: summary.receivedPaise,
                            prefix: '+'),
                        if (showToday)
                          _Stat(
                              label: 'Today',
                              paise: summary.todaySpentPaise,
                              color: brand.highlight),
                        _Stat(
                          label: net < 0 ? 'Net out' : 'Net in',
                          paise: net.abs(),
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

class _Stat extends StatelessWidget {
  const _Stat(
      {required this.label,
      required this.paise,
      this.prefix = '',
      this.color = Colors.white});

  final String label;
  final int paise;
  final String prefix;
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
                  ?.copyWith(color: Colors.white.withValues(alpha: 0.75))),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: _CountUp(paise,
                prefix: prefix,
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

/// An amount that counts from its old value to a new one.
class _CountUp extends StatelessWidget {
  const _CountUp(this.paise, {this.prefix = '', this.style});

  final int paise;
  final String prefix;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: paise.toDouble()),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => Text(
          // Whole rupees while counting, so no paise flicker.
          prefix + formatPaise(v == paise ? paise : (v / 100).round() * 100),
          style: style,
        ),
      );
}
