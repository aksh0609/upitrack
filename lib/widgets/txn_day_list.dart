import 'package:flutter/material.dart';

import '../models/txn.dart';
import '../util/format.dart';
import 'txn_tile.dart';

/// [txns] (newest first) as day headers and tiles, for use inside a ListView.
List<Widget> txnsGroupedByDay(
  BuildContext context,
  List<Txn> txns, {
  required void Function(Txn) onTap,
  void Function(Txn)? onHide,
}) {
  final text = Theme.of(context).textTheme;
  final widgets = <Widget>[];
  DateTime? currentDay;
  for (final t in txns) {
    final day = DateTime(t.time.year, t.time.month, t.time.day);
    if (day != currentDay) {
      currentDay = day;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(dayLabel(day),
            style: text.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ));
    }
    widgets.add(TxnTile(
      txn: t,
      onTap: () => onTap(t),
      onHide: onHide == null ? null : () => onHide(t),
    ));
  }
  return widgets;
}
