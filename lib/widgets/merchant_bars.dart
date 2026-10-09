import 'package:flutter/material.dart';

import '../util/format.dart';

/// Rows with bars showing spending per merchant, largest first.
class MerchantBars extends StatelessWidget {
  const MerchantBars({
    super.key,
    required this.totals,
    required this.onTap,
    this.limit,
  });

  /// merchant → (count, total), already sorted largest first.
  final Map<String, ({int count, int totalPaise})> totals;
  final ValueChanged<String> onTap;

  /// Show only the first [limit] rows (null = all).
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.take(limit ?? totals.length).toList();
    final max = entries.fold<int>(
        0, (a, e) => e.value.totalPaise > a ? e.value.totalPaise : a);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (final e in entries)
          InkWell(
            onTap: () => onTap(e.key),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: scheme.secondaryContainer,
                    child: Icon(Icons.storefront_outlined,
                        size: 18, color: scheme.onSecondaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(e.key,
                                  style: text.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Text(formatPaise(e.value.totalPaise),
                                style: text.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Text(
                          e.value.count == 1
                              ? '1 payment'
                              : '${e.value.count} payments',
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: max == 0 ? 0 : e.value.totalPaise / max,
                            minHeight: 6,
                            color: scheme.primary,
                            backgroundColor:
                                scheme.primary.withValues(alpha: 0.12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
