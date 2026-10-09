import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/txn.dart';
import '../widgets/txn_tile.dart';

/// Payments the user hid. Unhide puts them back in the month view.
class HiddenScreen extends StatefulWidget {
  const HiddenScreen({super.key, required this.repository});

  final TxnRepository repository;

  @override
  State<HiddenScreen> createState() => _HiddenScreenState();
}

class _HiddenScreenState extends State<HiddenScreen> {
  List<Txn>? _txns;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final txns = await widget.repository.hidden();
    if (mounted) setState(() => _txns = txns);
  }

  Future<void> _unhide(Txn t) async {
    await widget.repository.unhide(t);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final txns = _txns;
    return Scaffold(
      appBar: AppBar(title: const Text('Hidden')),
      body: txns == null
          ? const Center(child: CircularProgressIndicator())
          : txns.isEmpty
              ? const Center(child: Text('Nothing hidden.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    for (final t in txns)
                      Row(
                        children: [
                          Expanded(child: TxnTile(txn: t, onTap: () {})),
                          TextButton(
                            onPressed: () => _unhide(t),
                            child: const Text('Unhide'),
                          ),
                        ],
                      ),
                  ],
                ),
    );
  }
}
