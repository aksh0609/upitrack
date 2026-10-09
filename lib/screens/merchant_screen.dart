import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../models/category.dart';
import '../models/summary.dart';
import '../models/txn.dart';
import '../parser/categorizer.dart';
import '../parser/merchant.dart';
import '../util/format.dart';
import '../widgets/txn_day_list.dart';
import 'txn_sheet.dart';

/// One merchant: this month's total, the last six months, its category and
/// every payment in that window.
class MerchantScreen extends StatefulWidget {
  const MerchantScreen({
    super.key,
    required this.repository,
    required this.merchant,
    required this.month,
  });

  final TxnRepository repository;
  final String merchant;

  /// First day of the month that was on screen; the six-month view ends here.
  final DateTime month;

  @override
  State<MerchantScreen> createState() => _MerchantScreenState();
}

class _MerchantScreenState extends State<MerchantScreen> {
  List<Txn>? _txns;

  DateTime get _from => DateTime(widget.month.year, widget.month.month - 5);
  DateTime get _to => DateTime(widget.month.year, widget.month.month + 1);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.repository.between(_from, _to);
    final mine =
        all.where((t) => merchantOf(t.counterparty) == widget.merchant).toList();
    if (mounted) setState(() => _txns = mine);
  }

  Iterable<Txn> get _debits => (_txns ?? const []).where(
      (t) => t.isDebit && t.category != Categorizer.selfTransfer);

  bool get _canSetCategory => _debits.any((t) => t.canApplyToPayee);

  /// The category most of this merchant's payments carry.
  String? get _category {
    final counts = <String, int>{};
    for (final t in _debits) {
      counts[t.category] = (counts[t.category] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  /// Remembers [category] for every payee spelling behind this merchant.
  Future<void> _setCategory(String category) async {
    final seen = <String>{};
    for (final t in _debits.where((t) => t.canApplyToPayee)) {
      if (seen.add(t.counterparty)) {
        await widget.repository.setCategory(t, category, forPayee: true);
      }
    }
    await _load();
  }

  Future<void> _openTxn(Txn t) async {
    final changed = await showTxnSheet(context, t, widget.repository);
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final txns = _txns;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (txns == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.merchant)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final thisMonth = _debits
        .where((t) => !t.time.isBefore(widget.month) && t.time.isBefore(_to))
        .toList();
    final thisMonthTotal = thisMonth.fold<int>(0, (a, t) => a + t.amountPaise);
    final history = monthlyTotals(txns, widget.month);
    final maxMonth = history.fold<int>(0, (a, r) => r.paise > a ? r.paise : a);
    final category = _category;

    return Scaffold(
      appBar: AppBar(title: Text(widget.merchant)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '${DateFormat('MMMM').format(widget.month)}: ${formatPaise(thisMonthTotal)}',
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            thisMonth.length == 1 ? '1 payment' : '${thisMonth.length} payments',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Text('Last 6 months', style: text.titleMedium),
          const SizedBox(height: 8),
          for (final r in history)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(DateFormat('MMM').format(r.month),
                        style: text.bodySmall),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxMonth == 0 ? 0 : r.paise / maxMonth,
                        minHeight: 10,
                        color: scheme.primary,
                        backgroundColor: scheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: Text(formatPaise(r.paise),
                        textAlign: TextAlign.right, style: text.bodySmall),
                  ),
                ],
              ),
            ),
          if (category != null && _canSetCategory) ...[
            const SizedBox(height: 24),
            Text('Category', style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in kCategories)
                  if (c.name != Categorizer.income &&
                      c.name != Categorizer.selfTransfer)
                    ChoiceChip(
                      label: Text(c.name),
                      avatar: Icon(c.icon, size: 18, color: c.color),
                      selected: category == c.name,
                      onSelected: (_) => _setCategory(c.name),
                    ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text('Payments', style: text.titleMedium),
          if (txns.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No payments in the last six months.'),
            )
          else
            ...txnsGroupedByDay(context, txns, onTap: _openTxn),
        ],
      ),
    );
  }
}
