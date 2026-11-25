import '../models/txn.dart';
import '../parser/merchant.dart';

/// True when [query] (trimmed, case-insensitive) is empty or appears in the
/// payee string, its merchant name or the note.
bool matchesSearch(Txn t, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return t.counterparty.toLowerCase().contains(q) ||
      merchantOf(t.counterparty).toLowerCase().contains(q) ||
      (t.note?.toLowerCase().contains(q) ?? false);
}
