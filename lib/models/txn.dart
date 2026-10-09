/// One money movement shown in the app.
class Txn {
  const Txn({
    this.id,
    required this.key,
    this.smsId,
    required this.amountPaise,
    required this.isDebit,
    required this.counterparty,
    this.bank,
    this.account,
    this.ref,
    required this.channel,
    required this.category,
    required this.time,
    this.raw,
    this.manual = false,
    this.source = 'sms',
    this.hidden = false,
    this.editTs = 0,
  });

  final int? id;

  /// Unique key used to skip duplicates: the UPI reference when available,
  /// otherwise the SMS id.
  final String key;
  final int? smsId;
  final int amountPaise;
  final bool isDebit;
  final String counterparty;
  final String? bank;
  final String? account;
  final String? ref;

  /// 'UPI', 'Card', 'Bank' or 'Cash' (manual entries).
  final String channel;
  final String category;
  final DateTime time;

  /// The original SMS text, shown in the detail sheet.
  final String? raw;
  final bool manual;

  /// A remembered category makes sense only for real, parsed payees.
  bool get canApplyToPayee => isDebit && !manual && counterparty != 'Unknown';

  /// Where it came from: 'sms', 'shortcut' (iPhone), 'statement' or 'manual'.
  final String source;

  /// Hidden rows stay in the table (and in sync snapshots) so a later sync
  /// doesn't re-add them.
  final bool hidden;

  /// Milliseconds since epoch of the last change the *user* made to this
  /// row (category, hide/unhide); 0 for rows that only ever had automatic
  /// values. Sync lets the higher edit_ts win (spec §4.3).
  final int editTs;

  /// Statement rows usually have only a date, not a time.
  bool get hasTime =>
      source != 'statement' || time.hour != 12 || time.minute != 0;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'key': key,
        'sms_id': smsId,
        'amount_paise': amountPaise,
        'is_debit': isDebit ? 1 : 0,
        'counterparty': counterparty,
        'bank': bank,
        'account': account,
        'ref': ref,
        'channel': channel,
        'category': category,
        'ts': time.millisecondsSinceEpoch,
        'raw': raw,
        'manual': manual ? 1 : 0,
        'source': source,
        'hidden': hidden ? 1 : 0,
        'edit_ts': editTs,
      };

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
        id: m['id'] as int?,
        key: m['key'] as String,
        smsId: m['sms_id'] as int?,
        amountPaise: m['amount_paise'] as int,
        isDebit: (m['is_debit'] as int) == 1,
        counterparty: m['counterparty'] as String,
        bank: m['bank'] as String?,
        account: m['account'] as String?,
        ref: m['ref'] as String?,
        channel: m['channel'] as String,
        category: m['category'] as String,
        time: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        raw: m['raw'] as String?,
        manual: (m['manual'] as int? ?? 0) == 1,
        source: m['source'] as String? ?? 'sms',
        hidden: (m['hidden'] as int? ?? 0) == 1,
        editTs: m['edit_ts'] as int? ?? 0,
      );
}
