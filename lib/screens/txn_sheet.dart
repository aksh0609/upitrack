import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../models/category.dart';
import '../models/txn.dart';
import '../util/format.dart';

/// Shows transaction details. Returns true if something changed.
Future<bool?> showTxnSheet(
    BuildContext context, Txn txn, TxnRepository repository) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TxnSheet(txn: txn, repository: repository),
  );
}

class _TxnSheet extends StatefulWidget {
  const _TxnSheet({required this.txn, required this.repository});

  final Txn txn;
  final TxnRepository repository;

  @override
  State<_TxnSheet> createState() => _TxnSheetState();
}

class _TxnSheetState extends State<_TxnSheet> {
  late String _category = widget.txn.category;
  bool _forPayee = true;
  bool _saving = false;

  bool get _canApplyToPayee =>
      widget.txn.isDebit && !widget.txn.manual && widget.txn.counterparty != 'Unknown';

  Future<void> _save() async {
    if (_category == widget.txn.category) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    await widget.repository.setCategory(widget.txn, _category,
        forPayee: _forPayee && _canApplyToPayee);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _hide() async {
    await widget.repository.hide(widget.txn);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.txn;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t.isDebit ? '-' : '+'}${formatPaise(t.amountPaise)}',
              style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(t.counterparty, style: text.titleMedium),
            const SizedBox(height: 16),
            _Detail(
                'Date',
                DateFormat(t.hasTime ? 'd MMM y, h:mm a' : 'd MMM y')
                    .format(t.time)),
            if (t.bank != null) _Detail('Bank', t.bank!),
            if (t.account != null) _Detail('Account', '•••${t.account}'),
            if (t.ref != null) _Detail('UPI ref', t.ref!),
            _Detail('Type', t.channel),
            const SizedBox(height: 16),
            Text('Category', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in kCategories)
                  ChoiceChip(
                    label: Text(c.name),
                    avatar: Icon(c.icon, size: 18, color: c.color),
                    selected: _category == c.name,
                    onSelected: (_) => setState(() => _category = c.name),
                  ),
              ],
            ),
            if (_canApplyToPayee)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _forPayee,
                onChanged: (v) => setState(() => _forPayee = v),
                title: Text('Use for all payments to ${t.counterparty}'),
              ),
            if (t.raw != null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Original SMS'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(t.raw!, style: text.bodySmall),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : _hide,
                  icon: const Icon(Icons.visibility_off_outlined),
                  label: const Text('Hide'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value, style: text.bodyMedium)),
        ],
      ),
    );
  }
}
