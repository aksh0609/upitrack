import '../models/txn.dart';
import '../parser/categorizer.dart';
import '../parser/sms_parser.dart';
import '../parser/statement_parser.dart';
import 'db.dart';
import 'shortcut_inbox.dart';
import 'sms_source.dart';

/// Result of importing a statement.
class ImportSummary {
  const ImportSummary({
    required this.added,
    required this.duplicates,
    required this.unreadable,
  });

  final int added;

  /// Already in the app (from SMS, the iPhone shortcut or an earlier import).
  final int duplicates;

  /// Rows the parser couldn't read reliably.
  final int unreadable;
}

class TxnRepository {
  TxnRepository(this._db, this._sms, this._inbox);

  final AppDb _db;
  final SmsSource _sms;
  final ShortcutInbox _inbox;

  /// How far back to look the very first time the app reads SMS (Android).
  static const Duration firstSyncWindow = Duration(days: 180);

  // ------------------------------------------------------------- Android

  /// Reads new SMS from the inbox, parses bank transactions and stores them.
  /// Returns the number of new transactions.
  Future<int> syncSms() async {
    final now = DateTime.now();
    final last = await _db.getMeta('last_sync_ms');
    // Re-read one day of overlap; duplicates are skipped by their key.
    final since = last == null
        ? now.subtract(firstSyncWindow)
        : DateTime.fromMillisecondsSinceEpoch(int.parse(last))
            .subtract(const Duration(days: 1));

    final messages = await _sms.readInbox(since: since);
    final rules = await _db.rules();
    final txns = [
      for (final m in messages)
        _fromSms(
          sender: m.address,
          body: m.body,
          time: m.date,
          fallbackKey: 'sms:${m.id}',
          smsId: m.id,
          source: 'sms',
          rules: rules,
        ),
    ].whereType<Txn>().toList();

    final added = await _db.insertAll(txns);
    await _db.setMeta('last_sync_ms', now.millisecondsSinceEpoch.toString());
    return added;
  }

  // -------------------------------------------------------------- iPhone

  /// Stores bank SMS handed over by the "Log Bank SMS" Shortcuts action.
  Future<int> syncShortcutInbox() async {
    final messages = await _inbox.pending();
    if (messages.isEmpty) return 0;
    final rules = await _db.rules();
    final txns = [
      for (final m in messages)
        _fromSms(
          sender: m.sender,
          body: m.body,
          time: m.date,
          fallbackKey: 'shortcut:${m.id}',
          source: 'shortcut',
          rules: rules,
        ),
    ].whereType<Txn>().toList();
    final added = await _db.insertAll(txns);
    await _inbox.remove(messages);

    final seen = int.tryParse(await _db.getMeta('shortcut_count') ?? '') ?? 0;
    await _db.setMeta('shortcut_count', '${seen + messages.length}');
    return added;
  }

  /// How many messages the iPhone shortcut has delivered so far. 0 means
  /// the automation probably isn't set up yet.
  Future<int> shortcutMessageCount() async =>
      int.tryParse(await _db.getMeta('shortcut_count') ?? '') ?? 0;

  Txn? _fromSms({
    required String sender,
    required String body,
    required DateTime time,
    required String fallbackKey,
    required String source,
    required Map<String, String> rules,
    int? smsId,
  }) {
    final parsed = SmsParser.parse(sender, body);
    if (parsed == null) return null;
    final counterparty = parsed.counterparty ?? 'Unknown';
    return Txn(
      key: parsed.ref != null
          ? 'ref:${parsed.ref}:${parsed.isDebit ? 'd' : 'c'}'
          : fallbackKey,
      smsId: smsId,
      amountPaise: parsed.amountPaise,
      isDebit: parsed.isDebit,
      counterparty: counterparty,
      bank: parsed.bank,
      account: parsed.account,
      ref: parsed.ref,
      channel: parsed.channel,
      category: _category(counterparty, parsed.isDebit, rules),
      time: time,
      raw: body,
      source: source,
    );
  }

  String _category(String counterparty, bool isDebit, Map<String, String> rules) =>
      (isDebit ? rules[counterparty] : null) ??
      Categorizer.categorize(counterparty, isDebit: isDebit);

  // ----------------------------------------------------------- statements

  /// Adds statement rows that aren't already in the app.
  ///
  /// A row is treated as already present when it has the same UPI reference
  /// as a stored transaction, or when a stored transaction has the same day,
  /// amount and direction. Re-importing the same statement adds nothing.
  Future<ImportSummary> importStatement(StatementResult result) async {
    final rows = result.rows;
    if (rows.isEmpty) {
      return ImportSummary(added: 0, duplicates: 0, unreadable: result.skipped);
    }

    final first = rows.map((r) => r.date).reduce((a, b) => a.isBefore(b) ? a : b);
    final last = rows.map((r) => r.date).reduce((a, b) => a.isAfter(b) ? a : b);
    final existing = await _db.between(
      DateTime(first.year, first.month, first.day),
      DateTime(last.year, last.month, last.day + 1),
    );
    // How many non-statement payments exist per day/amount/direction. Each
    // statement row consumes one match, so two ₹50 payments on one day with
    // only one SMS caught still import the second one.
    final present = <String, int>{};
    for (final t in existing) {
      if (t.source == 'statement') continue;
      final k = _sameDayKey(t.time, t.amountPaise, t.isDebit);
      present[k] = (present[k] ?? 0) + 1;
    }

    final rules = await _db.rules();
    final occurrences = <String, int>{};
    final txns = <Txn>[];
    var duplicates = 0;

    for (final r in rows) {
      final dayKey = _sameDayKey(r.date, r.amountPaise, r.isDebit);
      final left = present[dayKey] ?? 0;
      if (left > 0) {
        present[dayKey] = left - 1;
        duplicates++;
        continue;
      }
      final base = 'stmt:${_ymd(r.date)}:${r.amountPaise}:${r.isDebit ? 'd' : 'c'}:'
          '${_hash(r.narration)}';
      final n = occurrences[base] = (occurrences[base] ?? 0) + 1;
      final counterparty = r.counterparty ?? 'Unknown';
      final isUpi = RegExp(r'\bupi\b', caseSensitive: false).hasMatch(r.narration) ||
          r.ref != null;
      txns.add(Txn(
        key: r.ref != null ? 'ref:${r.ref}:${r.isDebit ? 'd' : 'c'}' : '$base:$n',
        amountPaise: r.amountPaise,
        isDebit: r.isDebit,
        counterparty: counterparty,
        ref: r.ref,
        channel: isUpi ? 'UPI' : 'Bank',
        category: _category(counterparty, r.isDebit, rules),
        time: r.date,
        raw: r.narration,
        source: 'statement',
      ));
    }

    final added = await _db.insertAll(txns);
    return ImportSummary(
      added: added,
      duplicates: duplicates + (txns.length - added),
      unreadable: result.skipped,
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  static String _sameDayKey(DateTime d, int amount, bool isDebit) =>
      '${_ymd(d)}|$amount|${isDebit ? 'd' : 'c'}';

  /// Small stable hash (FNV-1a) so the same row gets the same key every time.
  static String _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  // ---------------------------------------------------------------- shared

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
          source: 'manual',
        ),
      ]);
}
