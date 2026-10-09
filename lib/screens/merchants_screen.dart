import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../widgets/merchant_bars.dart';
import 'merchant_screen.dart';

/// Every merchant for one month, largest first.
class MerchantsScreen extends StatelessWidget {
  const MerchantsScreen({
    super.key,
    required this.repository,
    required this.month,
    required this.totals,
  });

  final TxnRepository repository;
  final DateTime month;
  final Map<String, ({int count, int totalPaise})> totals;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Merchants · ${DateFormat('MMMM').format(month)}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          MerchantBars(
            totals: totals,
            onTap: (merchant) =>
                Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => MerchantScreen(
                repository: repository,
                merchant: merchant,
                month: month,
              ),
            )),
          ),
        ],
      ),
    );
  }
}
