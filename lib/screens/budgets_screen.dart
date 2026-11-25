import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../models/budget.dart';
import '../models/summary.dart';
import '../util/format.dart';

/// Monthly limits for all spending and for each category, with what this
/// month has spent so far.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key, required this.repository});

  final TxnRepository repository;

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  Map<String, int> _budgets = const {};
  MonthSummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final txns = await widget.repository
        .between(month, DateTime(month.year, month.month + 1));
    final budgets = await widget.repository.budgets();
    if (mounted) {
      setState(() {
        _budgets = budgets;
        _summary = MonthSummary.from(txns);
      });
    }
  }

  Future<void> _edit(String key) async {
    final paise = await showDialog<int>(
      context: context,
      builder: (_) =>
          _BudgetDialog(name: budgetName(key), current: _budgets[key]),
    );
    if (paise == null) return;
    await widget.repository.setBudget(key, paise);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget row(String key, IconData icon, Color color, int spent) {
      final limit = _budgets[key];
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(budgetName(key)),
        subtitle: Text('${DateFormat('MMMM').format(DateTime.now())}: '
            '${formatPaise(spent)}'),
        trailing: limit == null
            ? Text('Set', style: text.labelLarge?.copyWith(color: muted))
            : Text(formatPaise(limit),
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        onTap: () => _edit(key),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: summary == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'A limit for each month. The Overview shows how much is '
                    'left, in amber from 80% and red once it is passed.',
                    style: text.bodyMedium?.copyWith(color: muted),
                  ),
                ),
                row(kTotalBudget, Icons.account_balance_wallet_outlined,
                    Theme.of(context).colorScheme.primary, summary.spentPaise),
                const Divider(),
                for (final c in budgetCategories)
                  row(c.name, c.icon, c.color, summary.byCategory[c.name] ?? 0),
              ],
            ),
    );
  }
}

/// Asks for a monthly amount in rupees. Pops the paise, 0 for Remove, or
/// null when cancelled.
class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.name, this.current});

  final String name;
  final int? current;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final _amount = TextEditingController(
      text: widget.current == null ? '' : '${widget.current! ~/ 100}');

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final rupees = int.tryParse(_amount.text.trim());
    if (rupees == null || rupees <= 0) return;
    Navigator.pop(context, rupees * 100);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.name} budget'),
      content: TextField(
        controller: _amount,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Each month',
          prefixText: '₹ ',
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        if (widget.current != null)
          TextButton(
              onPressed: () => Navigator.pop(context, 0),
              child: const Text('Remove')),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
