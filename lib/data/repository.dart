import '../models/txn.dart';
import '../parser/categorizer.dart';
import '../parser/sms_parser.dart';
import 'db.dart';
import 'sms_source.dart';

class TxnRepository {
  TxnRepository(this._db, this._sms);

  final AppDb _db;
  final SmsSource _sms;

  /// How far back to look the very first time the app reads SMS.
  static const Duration firstSyncWindow = Duration(days: 180);

  /// Reads new SMS, parses bank transactions and stores them.
  /// Returns the number of new transactions.
  Future<int> sync() async {
    final now = DateTime.now();
    final last = await _db.getMeta('last_sync_ms');
    // Re-read one day of overlap; duplicates are skipped by their key.
    final since = last == null
        ? now.subtract(firstSyncWindow)
        : DateTime.fromMillisecondsSinceEpoch(int.parse(last))
            .subtract(const Duration(days: 1));

    final messages = await _sms.readInbox(since: since);
    final rules = await _db.rules();
    final txns = <Txn>[];

    for (final m in messages) {
      final parsed = SmsParser.parse(m.address, m.body);
      if (parsed == null) continue;
      final counterparty = parsed.counterparty ?? 'Unknown';
      final category = (parsed.isDebit ? rules[counterparty] : null) ??
          Categorizer.categorize(counterparty, isDebit: parsed.isDebit);
      txns.add(Txn(
        key: parsed.ref != null
            ? 'ref:${parsed.ref}:${parsed.isDebit ? 'd' : 'c'}'
            : 'sms:${m.id}',
        smsId: m.id,
        amountPaise: parsed.amountPaise,
        isDebit: parsed.isDebit,
        counterparty: counterparty,
        bank: parsed.bank,
        account: parsed.account,
        ref: parsed.ref,
        channel: parsed.channel,
        category: category,
        time: m.date,
        raw: m.body,
      ));
    }

    final added = await _db.insertAll(txns);
    await _db.setMeta('last_sync_ms', now.millisecondsSinceEpoch.toString());
    return added;
  }

  Future<List<Txn>> between(DateTime from, DateTime to) =>
      _db.between(from, to);

  Future<void> setCategory(Txn t, String category, {required bool forPayee}) =>
      forPayee
          ? _db.setCategoryForPayee(t.counterparty, category)
          : _db.setCategory(t.id!, category);

  Future<void> hide(Txn t) => _db.hide(t.id!);

  /// For cash, UPI Lite or anything that didn't come with a bank SMS.
  Future<void> addManual({
    required int amountPaise,
    required bool isDebit,
    required String counterparty,
    required String category,
    required DateTime time,
  }) =>
      _db.insertAll([
        Txn(
          key: 'manual:${DateTime.now().microsecondsSinceEpoch}',
          amountPaise: amountPaise,
          isDebit: isDebit,
          counterparty: counterparty,
          channel: 'Cash',
          category: category,
          time: time,
          manual: true,
        ),
      ]);
}
