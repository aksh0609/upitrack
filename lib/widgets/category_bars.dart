import 'package:flutter/material.dart';

import '../models/category.dart';
import '../theme.dart';
import '../util/format.dart';

/// Horizontal bars showing spending per category, largest first.
class CategoryBars extends StatelessWidget {
  const CategoryBars({super.key, required this.totals});

  final Map<String, int> totals;

  @override
  Widget build(BuildContext context) {
    final max = totals.values.fold<int>(0, (a, b) => b > a ? b : a);
    final sum = totals.values.fold<int>(0, (a, b) => a + b);
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      children: [
        for (final e in totals.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Builder(builder: (context) {
              final cat = categoryOf(e.key);
              return Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: cat.color.withValues(alpha: 0.15),
                    child: Icon(cat.icon, size: 18, color: cat.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: Text(e.key, style: text.bodyMedium)),
                            if (sum > 0)
                              Text('${(e.value * 100 / sum).round()}%  ',
                                  style: text.bodySmall?.copyWith(
                                      color: muted, fontFeatures: kTabular)),
                            Text(formatPaise(e.value),
                                style: text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: kTabular)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          // Bars grow in, and glide when the month changes.
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                                begin: 0, end: max == 0 ? 0 : e.value / max),
                            duration: const Duration(milliseconds: 800),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => LinearProgressIndicator(
                              value: v,
                              minHeight: 6,
                              color: cat.color,
                              backgroundColor:
                                  cat.color.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
      ],
    );
  }
}
