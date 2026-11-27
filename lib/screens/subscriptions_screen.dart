import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../models/category.dart';
import '../models/recurring.dart';
import '../theme.dart';
import '../util/format.dart';
import 'merchant_screen.dart';

/// Subscriptions, bills, rent and SIPs: the ones the user added, and
/// payments that came back every month in the last six months, soonest due
/// first. Added ones are reminded about like found ones.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key, required this.repository});

  final TxnRepository repository;

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  List<Recurring>? _found;
  List<Bill> _bills = const [];

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
    final bills = await widget.repository.bills();
    if (mounted) {
      setState(() {
        _bills = bills;
        _found = regularPayments(txns, bills);
      });
    }
  }

  /// Add one, or change or remove [old].
  Future<void> _edit([Bill? old]) async {
    final bill = await showDialog<Bill>(
        context: context, builder: (_) => _BillDialog(old: old));
    if (bill == null) return;
    if (old != null && old.name != bill.name) {
      await widget.repository.setBill(old.name, 0, 0);
    }
    await widget.repository.setBill(bill.name, bill.amountPaise, bill.day);
    await _load();
  }

  Future<void> _open(Recurring r) async {
    if (r.added) {
      return _edit(_bills.firstWhere((b) => b.name == r.name));
    }
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
      floatingActionButton: BrandFab(onPressed: _edit, label: 'Add a payment'),
      body: found == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              // Room at the bottom for the button.
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                if (found.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'Nothing found yet. The app looks through your payments '
                      'for ones that come back every month (rent, power and '
                      'phone bills, a card bill, recharges, subscriptions, '
                      'EMIs) and reminds you before the next one. It needs '
                      'two months of the same amount, or three of a bill '
                      'that changes. Missing one? Add it yourself.',
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
                    'Found by themselves from payments that come back every '
                    'month; "Next" is a guess from the usual gap, and "~" '
                    'marks a bill whose amount changes. Each shows on the '
                    'home screen as Due soon, with a notification on '
                    'Android, a day or two before. Tap one you added to '
                    'change it.',
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
      subtitle: Text('${r.added ? 'Monthly ·' : 'Next'} '
          '${DateFormat('d MMM').format(r.next)} · $due'),
      trailing: Text('${r.varies ? '~' : ''}${formatPaise(r.amountPaise)}',
          style: text.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700, fontFeatures: kTabular)),
    );
  }
}

/// Name, amount and day of the month; Remove (day 0) when changing one.
class _BillDialog extends StatefulWidget {
  const _BillDialog({this.old});

  final Bill? old;

  @override
  State<_BillDialog> createState() => _BillDialogState();
}

class _BillDialogState extends State<_BillDialog> {
  late final _name = TextEditingController(text: widget.old?.name);
  late final _amount = TextEditingController(
      text: widget.old == null ? '' : '${widget.old!.amountPaise ~/ 100}');
  late int _day = widget.old?.day ?? DateTime.now().day;
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final rupees = int.tryParse(_amount.text.trim());
    if (name.isEmpty) return setState(() => _problem = 'Give it a name.');
    if (rupees == null || rupees <= 0) {
      return setState(() => _problem = 'Enter the amount.');
    }
    Navigator.pop(context, Bill(name, rupees * 100, _day));
  }

  @override
  Widget build(BuildContext context) {
    final old = widget.old;
    return AlertDialog(
      title: Text(old == null ? 'Add a regular payment' : old.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: old == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Name', hintText: 'Rent, school fees, EMI…'),
          ),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
                labelText: 'Amount each month', prefixText: '₹ '),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _day,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Due on, each month'),
            menuMaxHeight: 320,
            items: [
              for (var d = 1; d <= 31; d++)
                DropdownMenuItem(value: d, child: Text(dayOfMonth(d))),
            ],
            onChanged: (d) => setState(() => _day = d!),
          ),
          if (_problem != null) ...[
            const SizedBox(height: 8),
            Text(_problem!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        if (old != null)
          TextButton(
              onPressed: () => Navigator.pop(context, Bill(old.name, 0, 0)),
              child: const Text('Remove')),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// "1st", "22nd", "31st (or the last day)".
String dayOfMonth(int d) {
  final suffix = d >= 11 && d <= 13
      ? 'th'
      : switch (d % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  return '$d$suffix${d > 28 ? ' (or the last day)' : ''}';
}
