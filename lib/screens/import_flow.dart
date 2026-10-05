import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../data/statement_reader.dart';
import '../parser/statement_parser.dart';

/// Pick a statement file, unlock it if needed, preview and import.
/// Returns true if anything was added.
Future<bool> importStatement(BuildContext context, TxnRepository repository) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: StatementReader.extensions,
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return false;
  final file = picked.files.single;
  final bytes = file.bytes;
  if (bytes == null) {
    if (context.mounted) _snack(context, 'Could not read that file.');
    return false;
  }

  String? password;
  late StatementResult result;
  while (true) {
    try {
      if (!context.mounted) return false;
      result = await _withProgress(
        context,
        'Reading statement…',
        StatementReader.read(fileName: file.name, bytes: bytes, password: password),
      );
      break;
    } on PasswordRequired catch (e) {
      if (!context.mounted) return false;
      password = await _askPassword(context, wrong: e.wrongPassword);
      if (password == null) return false;
    } on UnreadableFile catch (e) {
      if (context.mounted) _snack(context, e.message);
      return false;
    }
  }

  if (!context.mounted) return false;
  if (result.rows.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No transactions found'),
        content: const Text(
          "This file's layout wasn't recognised. Try the CSV download from "
          'your net banking, or a PDF statement from the bank or UPI app.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
    return false;
  }

  final ok = await _confirm(context, result);
  if (ok != true || !context.mounted) return false;

  final summary = await repository.importStatement(result);
  if (context.mounted) {
    final parts = [
      '${summary.added} added',
      if (summary.duplicates > 0) '${summary.duplicates} already there',
      if (summary.unreadable > 0) '${summary.unreadable} unreadable',
    ];
    _snack(context, parts.join(' · '));
  }
  return summary.added > 0;
}

Future<T> _withProgress<T>(BuildContext context, String label, Future<T> work) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator()),
            const SizedBox(width: 20),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
  try {
    return await work;
  } finally {
    navigator.pop();
  }
}

Future<String?> _askPassword(BuildContext context, {required bool wrong}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Statement password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(wrong
              ? 'That password did not work. Try again.'
              : 'This PDF is locked. Banks usually use your customer ID, '
                  'date of birth or a mix of both; the email with the '
                  'statement explains the format.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Unlock'),
        ),
      ],
    ),
  );
}

Future<bool?> _confirm(BuildContext context, StatementResult result) {
  final dates = result.rows.map((r) => r.date).toList()..sort();
  final f = DateFormat('d MMM y');
  final spent = result.rows.where((r) => r.isDebit).length;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Import ${result.rows.length} transactions?'),
      content: Text(
        '${f.format(dates.first)} to ${f.format(dates.last)}\n'
        '$spent payments, ${result.rows.length - spent} received.\n\n'
        'Payments already in the app are skipped.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
      ],
    ),
  );
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
