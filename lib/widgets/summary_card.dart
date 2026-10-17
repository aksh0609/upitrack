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
            color: kGlow.withValues(alpha: dark ? 0.45 : 0.30),
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
            // A band of light sweeps across once per month shown.
            Positioned.fill(child: _Sheen(key: ValueKey(month))),
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
                          _Stat(label: 'Today', paise: summary.todaySpentPaise),
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
  const _Stat({required this.label, required this.paise, this.prefix = ''});

  final String label;
  final int paise;
  final String prefix;

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
                    color: Colors.white,
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

/// A soft diagonal band of light that crosses the card once.
class _Sheen extends StatelessWidget {
  const _Sheen({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1400),
          curve: Curves.easeInOutCubic,
          builder: (context, t, _) => t == 1
              ? const SizedBox.shrink()
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(4 * t - 3, -1),
                      end: Alignment(4 * t - 1, 1),
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
        ),
      );
}
