import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../models/category.dart';

/// Manual entry for cash, UPI Lite, or anything without a bank SMS.
/// [amountPaise], [date] and [raw] prefill it from an unrecognised SMS.
/// Returns true if a transaction was added.
Future<bool?> showAddTxnSheet(
  BuildContext context,
  TxnRepository repository, {
  int? amountPaise,
  DateTime? date,
  String? raw,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AddTxnSheet(
      repository: repository,
      amountPaise: amountPaise,
      date: date,
      raw: raw,
    ),
  );
}

class _AddTxnSheet extends StatefulWidget {
  const _AddTxnSheet({
    required this.repository,
    this.amountPaise,
    this.date,
    this.raw,
  });

  final TxnRepository repository;
  final int? amountPaise;
  final DateTime? date;
  final String? raw;

  @override
  State<_AddTxnSheet> createState() => _AddTxnSheetState();
}

class _AddTxnSheetState extends State<_AddTxnSheet> {
  late final _amount = TextEditingController(
      text: widget.amountPaise == null ? '' : _amountText(widget.amountPaise!));
  final _payee = TextEditingController();
  bool _isDebit = true;
  String _category = 'Food';
  late DateTime _date = widget.date ?? DateTime.now();
  String? _error;

  /// 25000 → "250", 12050 → "120.50".
  static String _amountText(int paise) =>
      paise % 100 == 0 ? '${paise ~/ 100}' : (paise / 100).toStringAsFixed(2);

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final now = DateTime.now();
      setState(() => _date = DateTime(
          picked.year, picked.month, picked.day, now.hour, now.minute));
    }
  }

  Future<void> _save() async {
    final value = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter an amount');
      return;
    }
    final payee = _payee.text.trim();
    await widget.repository.addManual(
      amountPaise: (value * 100).round(),
      isDebit: _isDebit,
      counterparty:
          payee.isEmpty ? (_isDebit ? 'Cash' : 'Cash received') : payee,
      category: _isDebit ? _category : 'Income',
      time: _date,
      raw: widget.raw,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add transaction',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Spent')),
                  ButtonSegment(value: false, label: Text('Received')),
                ],
                selected: {_isDebit},
                onSelectionChanged: (s) => setState(() => _isDebit = s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                ],
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _payee,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText:
                      _isDebit ? 'Paid to (optional)' : 'From (optional)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(DateFormat('d MMM y').format(_date)),
              ),
              if (_isDebit) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in kCategories)
                      if (c.name != 'Income')
                        ChoiceChip(
                          label: Text(c.name),
                          avatar: Icon(c.icon, size: 18, color: c.color),
                          selected: _category == c.name,
                          onSelected: (_) => setState(() => _category = c.name),
                        ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: const Text('Add')),
            ],
          ),
        ),
      ),
    );
  }
}
