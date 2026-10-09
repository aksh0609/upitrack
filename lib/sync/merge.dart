/// The merge rules of spec §4.5, as pure functions over row maps so they
/// can be tested without a database. `edit_ts` / `ts` missing means 0.
library;

enum TxnMerge { insert, update, keep }

int _stamp(Map<String, Object?> row, String field) => (row[field] as num?)?.toInt() ?? 0;

/// What to do with [remote] given the [local] row with the same key (null
/// when the device has never seen it). Payments are only ever added, so an
/// unknown row is inserted; a known row changes only when the remote edit
/// is strictly newer — an automatic row (0) never beats a human edit.
TxnMerge mergeTxn(Map<String, Object?>? local, Map<String, Object?> remote) {
  if (local == null) return TxnMerge.insert;
  return _stamp(remote, 'edit_ts') > _stamp(local, 'edit_ts')
      ? TxnMerge.update
      : TxnMerge.keep;
}

/// A payee rule from another device replaces ours when we have none or
/// theirs is strictly newer.
bool ruleWins(Map<String, Object?>? local, Map<String, Object?> remote) =>
    local == null || _stamp(remote, 'ts') > _stamp(local, 'ts');
