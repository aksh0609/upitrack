import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repository.dart';
import '../util/export.dart';

/// Shares a month's or a year's payments (hidden ones left out) as a CSV
/// for spreadsheets or a PDF to print or send. [month] is the month on
/// screen; its year is the other choice.
Future<void> showExportSheet(
    BuildContext context, TxnRepository repository, DateTime month) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ExportSheet(repository: repository, month: month),
  );
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.repository, required this.month});

  final TxnRepository repository;
  final DateTime month;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  bool _year = false;
  bool _pdf = false;
  bool _busy = false;
  String? _problem;

  Future<void> _share() async {
    final m = widget.month;
    final from = _year ? DateTime(m.year) : m;
    final to = _year ? DateTime(m.year + 1) : DateTime(m.year, m.month + 1);
    final label = _year ? '${m.year}' : DateFormat('MMMM y').format(m);
    final stamp = _year ? '${m.year}' : DateFormat('yyyy-MM').format(m);
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final txns = await widget.repository.between(from, to);
      if (txns.isEmpty) {
        setState(() => _problem = 'No payments in $label.');
        return;
      }
      final name = 'upitrack-$stamp.${_pdf ? 'pdf' : 'csv'}';
      final bytes =
          _pdf ? await txnsPdf(txns, 'UPI Track: $label') : txnsCsv(txns);
      await SharePlus.instance.share(ShareParams(
        subject: 'UPI Track payments, $label',
        files: [
          XFile.fromData(bytes,
              name: name, mimeType: _pdf ? 'application/pdf' : 'text/csv'),
        ],
        fileNameOverrides: [name],
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _problem = 'Could not export: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.month;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Export payments', style: text.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                    value: false, label: Text(DateFormat('MMMM y').format(m))),
                ButtonSegment(value: true, label: Text('All of ${m.year}')),
              ],
              selected: {_year},
              onSelectionChanged: (s) => setState(() => _year = s.single),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    icon: Icon(Icons.table_chart_outlined),
                    label: Text('CSV')),
                ButtonSegment(
                    value: true,
                    icon: Icon(Icons.picture_as_pdf_outlined),
                    label: Text('PDF')),
              ],
              selected: {_pdf},
              onSelectionChanged: (s) => setState(() => _pdf = s.single),
            ),
            const SizedBox(height: 8),
            Text(
              _pdf
                  ? 'A table to print or send, with the totals.'
                  : 'For Excel or Google Sheets. Money paid is negative.',
              style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (_problem != null) ...[
              const SizedBox(height: 8),
              Text(_problem!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _share,
              icon: const Icon(Icons.ios_share),
              label: const Text('Share'),
            ),
          ],
        ),
      ),
    );
  }
}
