import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repository.dart';
import '../models/lent.dart';
import '../models/txn.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/txn_tile.dart';
import 'txn_sheet.dart';

/// Who owes you and whom you owe, from payments marked Lent & borrowed.
class LentScreen extends StatefulWidget {
  const LentScreen({super.key, required this.repository});

  final TxnRepository repository;

  @override
  State<LentScreen> createState() => _LentScreenState();
}

class _LentScreenState extends State<LentScreen> {
  List<LentBalance>? _people;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final txns = await widget.repository.lent();
    if (mounted) setState(() => _people = lentBalances(txns));
  }

  Future<void> _open(Txn t) async {
    final changed = await showTxnSheet(context, t, widget.repository);
    if (changed == true) await _load();
  }

  Future<void> _remind(LentBalance b) => SharePlus.instance.share(ShareParams(
        text: 'Hi ${b.name}, a gentle reminder about the '
            '${formatPaise(b.balancePaise)} I lent you. Thanks!',
      ));

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final how = Text(
      'Open a payment to or from a person and choose the category '
      '"Lent & borrowed". Money you send counts as lent; money you get back '
      'counts as repaid, or borrowed. Neither counts as spending.',
      style: text.bodyMedium?.copyWith(color: muted),
    );
    if (people == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lent & borrowed')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final totals = lentTotals(people);
    return Scaffold(
      appBar: AppBar(title: const Text('Lent & borrowed')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (people.isEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 24), child: how)
          else ...[
            Row(
              children: [
                Expanded(
                  child: _Total(
                      label: 'Owed to you',
                      paise: totals.owedToYou,
                      color: scheme.moneyIn),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Total(
                      label: 'You owe',
                      paise: totals.youOwe,
                      color: scheme.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final b in people)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  title: Text(b.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(balanceLabel(b.balancePaise)),
                  trailing: Text(
                    formatPaise(b.balancePaise.abs()),
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: kTabular,
                      color: b.balancePaise > 0
                          ? scheme.moneyIn
                          : b.balancePaise == 0
                              ? muted
                              : scheme.onSurface,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  children: [
                    for (final t in b.txns)
                      TxnTile(txn: t, onTap: () => _open(t)),
                    if (b.balancePaise > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _remind(b),
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('Send a reminder'),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            how,
          ],
        ],
      ),
    );
  }
}

/// "Owes you ₹500", "You owe ₹300" or "Settled".
String balanceLabel(int paise) => paise > 0
    ? 'Owes you ${formatPaise(paise)}'
    : paise < 0
        ? 'You owe ${formatPaise(-paise)}'
        : 'Settled';

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.paise, required this.color});

  final String label;
  final int paise;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(formatPaise(paise),
                style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: kTabular,
                    color: color)),
          ],
        ),
      ),
    );
  }
}
