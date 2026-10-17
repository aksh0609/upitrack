import 'package:flutter/material.dart';

import '../models/txn.dart';
import '../parser/categorizer.dart';
import '../theme.dart';
import '../util/format.dart';
import 'appear.dart';
import 'txn_tile.dart';

/// [txns] (newest first) as day headers and tiles, for use inside a ListView.
/// Each header shows what went out that day.
List<Widget> txnsGroupedByDay(
  BuildContext context,
  List<Txn> txns, {
  required void Function(Txn) onTap,
  void Function(Txn)? onHide,
}) {
  final text = Theme.of(context).textTheme;
  final muted = Theme.of(context).colorScheme.onSurfaceVariant;
  final spentByDay = <DateTime, int>{};
  for (final t in txns) {
    if (!t.isDebit || t.category == Categorizer.selfTransfer) continue;
    final day = DateTime(t.time.year, t.time.month, t.time.day);
    spentByDay[day] = (spentByDay[day] ?? 0) + t.amountPaise;
  }

  final widgets = <Widget>[];
  DateTime? currentDay;
  var n = 0;
  for (final t in txns) {
    final day = DateTime(t.time.year, t.time.month, t.time.day);
    if (day != currentDay) {
      currentDay = day;
      final spent = spentByDay[day] ?? 0;
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(dayLabel(day),
                  style: text.labelLarge?.copyWith(color: muted)),
            ),
            if (spent > 0)
              Text(formatPaise(spent),
                  style: text.labelLarge
                      ?.copyWith(color: muted, fontFeatures: kTabular)),
          ],
        ),
      ));
    }
    final tile = TxnTile(
      key: ValueKey(t.key),
      txn: t,
      onTap: () => onTap(t),
      onHide: onHide == null ? null : () => onHide(t),
    );
    // The first rows slide in one by one; the rest of a long list just shows.
    // ponytail: fixed cap of 12, keeps a long list from animating hundreds.
    widgets.add(n < 12
        ? Appear(key: ValueKey('in:${t.key}'), index: n, child: tile)
        : tile);
    n++;
  }
  return widgets;
}
