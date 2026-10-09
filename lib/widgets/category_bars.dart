import 'package:flutter/material.dart';

import '../models/category.dart';
import '../util/format.dart';

/// Horizontal bars showing spending per category, largest first.
class CategoryBars extends StatelessWidget {
  const CategoryBars({super.key, required this.totals});

  final Map<String, int> totals;

  @override
  Widget build(BuildContext context) {
    final max = totals.values.fold<int>(0, (a, b) => b > a ? b : a);
    final text = Theme.of(context).textTheme;

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
                    radius: 16,
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
                            Text(formatPaise(e.value),
                                style: text.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: max == 0 ? 0 : e.value / max,
                            minHeight: 6,
                            color: cat.color,
                            backgroundColor: cat.color.withValues(alpha: 0.12),
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
