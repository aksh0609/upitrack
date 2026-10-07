import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repository.dart';
import '../models/unparsed.dart';
import '../parser/anonymise.dart';
import '../parser/sms_parser.dart';
import '../util/format.dart';
import 'add_txn_sheet.dart';

/// Bank SMS the parser couldn't read. Each can be added by hand, ignored, or
/// shared (anonymised) so the parser can be taught the new format.
class UnparsedScreen extends StatefulWidget {
  const UnparsedScreen({super.key, required this.repository});

  final TxnRepository repository;

  @override
  State<UnparsedScreen> createState() => _UnparsedScreenState();
}

class _UnparsedScreenState extends State<UnparsedScreen> {
  List<UnparsedSms>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.repository.unparsed();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _add(UnparsedSms u) async {
    final added = await showAddTxnSheet(
      context,
      widget.repository,
      amountPaise: SmsParser.firstAmountPaise(u.body),
      date: u.time,
      raw: u.body,
    );
    if (added == true) {
      await widget.repository.resolveUnparsed(u, state: 'added');
      await _load();
    }
  }

  Future<void> _ignore(UnparsedSms u) async {
    await widget.repository.resolveUnparsed(u, state: 'ignored');
    await _load();
  }

  Future<void> _report(UnparsedSms u) => SharePlus.instance.share(ShareParams(
        subject: 'UPI Track: bank SMS not recognised',
        text: 'Sender: ${u.sender}\n\n${anonymise(u.body)}\n\n'
            'Shared from UPI Track. Names, account numbers, references and '
            'UPI IDs have been masked.',
      ));

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Not recognised')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('Every bank SMS was understood.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Text(
                      'These look like bank payments but the app could not read '
                      'them. Add them by hand, or report one so the next version '
                      'understands it. Reports are anonymised.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final u in items)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${u.sender} · ${dayLabel(u.time)}',
                                  style: text.labelLarge),
                              const SizedBox(height: 6),
                              Text(u.body,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                      onPressed: () => _report(u),
                                      child: const Text('Report')),
                                  TextButton(
                                      onPressed: () => _ignore(u),
                                      child: const Text('Ignore')),
                                  FilledButton.tonal(
                                      onPressed: () => _add(u),
                                      child: const Text('Add')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
