import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/lent.dart';
import 'package:upitrack/models/summary.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/parser/categorizer.dart';
import 'package:upitrack/util/who.dart';

Txn loan(String who, int rupees, {bool sent = true, int day = 1}) => Txn(
      key: '$who$rupees$sent$day',
      amountPaise: rupees * 100,
      isDebit: sent,
      counterparty: who,
      channel: 'UPI',
      category: Categorizer.lent,
      time: DateTime(2026, 11, day),
    );

void main() {
  test('sent is lent, received is paid back; open balances first', () {
    final all = lentBalances([
      loan('RAHUL K', 1000, day: 1),
      loan('Rahul K', 400, sent: false, day: 9), // same person, other case
      loan('PRIYA', 300, sent: false, day: 4), // borrowed from Priya
      loan('AMIT', 500, day: 2),
      loan('AMIT', 500, sent: false, day: 5), // settled
    ]);
    expect(all.map((b) => (b.name, b.balancePaise)), [
      ('Rahul K', 60000),
      ('PRIYA', -30000),
      ('AMIT', 0),
    ]);
    expect(all.first.txns.first.time.day, 9, reason: 'newest first');
    expect(lentTotals(all), (owedToYou: 60000, youOwe: 30000));
  });

  test('a loan is not spending, and it belongs to People', () {
    final t = loan('RAHUL K', 1000);
    expect(MonthSummary.from([t]).spentPaise, 0);
    expect(matchesWho(t, Who.people), isTrue);
    expect(matchesWho(t, Who.merchants), isFalse);
  });
}
