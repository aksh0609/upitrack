import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/category.dart';
import '../models/txn.dart';
import '../util/format.dart';

class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn, required this.onTap});

  final Txn txn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cat = categoryOf(txn.category);
    final scheme = Theme.of(context).colorScheme;
    final details = [
      DateFormat('h:mm a').format(txn.time),
      if (txn.bank != null) txn.bank!,
      if (txn.account != null) '•••${txn.account}',
      txn.channel,
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: cat.color.withValues(alpha: 0.15),
        child: Icon(cat.icon, color: cat.color, size: 20),
      ),
      title: Text(txn.counterparty, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '${txn.isDebit ? '-' : '+'}${formatPaise(txn.amountPaise)}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: txn.isDebit ? scheme.onSurface : const Color(0xFF2E7D32),
            ),
      ),
    );
  }
}
