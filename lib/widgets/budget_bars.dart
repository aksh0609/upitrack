import 'package:flutter/material.dart';

import '../models/budget.dart';
import '../models/category.dart';
import '../theme.dart';
import '../util/format.dart';

/// Amber for a budget past 80%; red (the scheme's error) once over.
const Color kBudgetNear = Color(0xFFF59E0B);

/// Each budget as "spent of limit" with a bar that turns amber near the
/// limit and red past it.
class BudgetBars extends StatelessWidget {
  const BudgetBars({super.key, required this.lines});

  final List<BudgetLine> lines;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Builder(builder: (context) {
              final level = budgetLevel(l.spentPaise, l.limitPaise);
              final color = switch (level) {
                BudgetLevel.over => scheme.error,
                BudgetLevel.near => kBudgetNear,
                BudgetLevel.ok => l.key == kTotalBudget
                    ? scheme.primary
                    : categoryOf(l.key).color,
              };
              final left = l.limitPaise - l.spentPaise;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(budgetName(l.key),
                            style: text.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        left >= 0
                            ? '${formatPaise(left)} left'
                            : '${formatPaise(-left)} over',
                        style: text.bodySmall?.copyWith(
                            color: level == BudgetLevel.ok
                                ? scheme.onSurfaceVariant
                                : color,
                            fontWeight: FontWeight.w600,
                            fontFeatures: kTabular),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(
                          begin: 0,
                          end: (l.spentPaise / l.limitPaise).clamp(0.0, 1.0)),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 8,
                        color: color,
                        backgroundColor: color.withValues(alpha: 0.14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatPaise(l.spentPaise)} of ${formatPaise(l.limitPaise)}',
                    style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant, fontFeatures: kTabular),
                  ),
                ],
              );
            }),
          ),
      ],
    );
  }
}
