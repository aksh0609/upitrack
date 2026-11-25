import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../models/category.dart';
import '../models/recurring.dart';
import '../theme.dart';
import '../util/format.dart';
import 'merchant_screen.dart';

/// Subscriptions, bills, rent and SIPs: payments that came back every
/// month in the last six months, soonest due first.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key, required this.repository});

  final TxnRepository repository;

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  List<Recurring>? _found;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final txns = await widget.repository.between(
        DateTime(now.year, now.month - 6, now.day),
        DateTime(now.year, now.month, now.day + 1));
    if (mounted) setState(() => _found = findRecurring(txns));
  }

  Future<void> _open(Recurring r) async {
    final now = DateTime.now();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MerchantScreen(
        repository: widget.repository,
        merchant: r.name,
        month: DateTime(now.year, now.month),
      ),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions & bills')),
      body: found == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                if (found.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'Nothing repeats yet. A payment that comes back every '
                      'month at about the same amount, like Netflix, a phone '
                      'plan, rent or a SIP, shows here after the third time.',
                      textAlign: TextAlign.center,
                      style: text.bodyLarge,
                    ),
                  )
                else ...[
                  Text('About ${formatPaise(monthlyCost(found))} a month',
                      style: text.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                      found.length == 1
                          ? '1 payment repeats every month'
                          : '${found.length} payments repeat every month',
                      style: text.bodyMedium?.copyWith(color: muted)),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          for (final r in found)
                            RecurringTile(r: r, onTap: () => _open(r)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Found from payments that came back about every month at '
                    'about the same amount. "Next" is a guess from the usual '
                    'gap.',
                    style: text.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ],
            ),
    );
  }
}

/// One repeat: name, amount and when the next one is expected.
class RecurringTile extends StatelessWidget {
  const RecurringTile({super.key, required this.r, this.onTap});

  final Recurring r;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cat = categoryOf(r.category);
    final text = Theme.of(context).textTheme;
    final due = dueLabel(r.next);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: cat.color.withValues(alpha: 0.15),
        child: Icon(cat.icon, color: cat.color, size: 20),
      ),
      title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('Next ${DateFormat('d MMM').format(r.next)} · $due'),
      trailing: Text(formatPaise(r.amountPaise),
          style: text.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700, fontFeatures: kTabular)),
    );
  }
}
