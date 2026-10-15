import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/category.dart';
import '../models/txn.dart';
import '../theme.dart';
import '../util/format.dart';

/// One payment. With [onHide] the row can be swiped away to hide it.
class TxnTile extends StatelessWidget {
  const TxnTile(
      {super.key, required this.txn, required this.onTap, this.onHide});

  final Txn txn;
  final VoidCallback onTap;
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    final cat = categoryOf(txn.category);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final details = [
      if (txn.hasTime) DateFormat('h:mm a').format(txn.time),
      if (txn.source == 'statement') 'Statement',
      if (txn.bank != null)
        txn.account == null ? txn.bank! : '${txn.bank} •••${txn.account}'
      else if (txn.account != null)
        '•••${txn.account}',
      if (txn.channel != 'UPI') txn.channel,
    ].join(' · ');
    final amount = formatPaise(txn.amountPaise);

    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: cat.color.withValues(alpha: 0.15),
        child: Icon(cat.icon, color: cat.color, size: 20),
      ),
      title: Text(txn.counterparty,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
      subtitle: Text(details.isEmpty ? txn.category : details,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        txn.isDebit ? amount : '+$amount',
        semanticsLabel: txn.isDebit ? 'Paid $amount' : 'Received $amount',
        style: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: kTabular,
          color: txn.isDebit ? scheme.onSurface : scheme.moneyIn,
        ),
      ),
    );

    final hide = onHide;
    if (hide == null) return tile;
    return Dismissible(
      key: ValueKey('hide:${txn.key}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => hide(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Hide', style: text.labelLarge),
            const SizedBox(width: 8),
            const Icon(Icons.visibility_off_outlined),
          ],
        ),
      ),
      child: tile,
    );
  }
}
