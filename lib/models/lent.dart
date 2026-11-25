import 'txn.dart';

/// Where things stand with one person.
class LentBalance {
  const LentBalance(this.name, this.balancePaise, this.txns);

  /// The payee as the latest payment spells it.
  final String name;

  /// Positive: they owe you. Negative: you owe them. Zero: settled.
  final int balancePaise;

  /// Their payments marked Lent & borrowed, newest first.
  final List<Txn> txns;
}

/// Groups payments marked Lent & borrowed by person: money sent counts as
/// lent, money received as paid back (or borrowed). Open balances first,
/// largest first; settled people last.
/// ponytail: a person is matched by payee text, so "RAHUL K" and
/// "rahul@okaxis" are two people; merge by phone or UPI ID if that bites.
List<LentBalance> lentBalances(List<Txn> txns) {
  final byPerson = <String, List<Txn>>{};
  for (final t in txns) {
    byPerson.putIfAbsent(t.counterparty.trim().toLowerCase(), () => []).add(t);
  }
  final out = [
    for (final list in byPerson.values)
      () {
        list.sort((a, b) => b.time.compareTo(a.time));
        final balance = list.fold<int>(
            0, (sum, t) => sum + (t.isDebit ? t.amountPaise : -t.amountPaise));
        return LentBalance(list.first.counterparty, balance, list);
      }()
  ];
  out.sort((a, b) {
    if ((a.balancePaise == 0) != (b.balancePaise == 0)) {
      return a.balancePaise == 0 ? 1 : -1;
    }
    return b.balancePaise.abs().compareTo(a.balancePaise.abs());
  });
  return out;
}

/// Totals over all people: what others owe you and what you owe.
({int owedToYou, int youOwe}) lentTotals(List<LentBalance> all) {
  var owed = 0;
  var owe = 0;
  for (final b in all) {
    if (b.balancePaise > 0) owed += b.balancePaise;
    if (b.balancePaise < 0) owe -= b.balancePaise;
  }
  return (owedToYou: owed, youOwe: owe);
}
