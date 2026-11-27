import 'dart:math' show min;

import '../parser/categorizer.dart';
import '../parser/merchant.dart';
import 'txn.dart';

/// A payment that comes back about every month: a subscription, a bill,
/// rent or a SIP.
class Recurring {
  const Recurring({
    required this.name,
    required this.amountPaise,
    required this.category,
    required this.last,
    required this.next,
    required this.count,
  });

  /// The merchant (see [merchantOf]), or the person for rent.
  final String name;

  /// The latest payment's amount.
  final int amountPaise;
  final String category;

  /// The latest payment; null for one the user added.
  final DateTime? last;

  /// When the next one is expected: the last plus the usual gap.
  final DateTime next;

  /// How many monthly payments were seen; 0 for one the user added.
  final int count;

  bool get added => count == 0;
}

/// A regular payment the user added: [amountPaise] on [day] (1–31) of every
/// month. Kept in the database by [name].
class Bill {
  const Bill(this.name, this.amountPaise, this.day);

  final String name;
  final int amountPaise;
  final int day;
}

/// The user's [bills], each due next on its day (the month's last day when
/// the month is shorter), today or later; then the repeats [findRecurring]
/// sees in [txns], except those named like a bill. Soonest first.
/// ponytail: an added bill doesn't know it was paid early, so "Coming up"
/// shows it until its day passes; match it to a payment if that grates.
List<Recurring> regularPayments(List<Txn> txns, List<Bill> bills,
    {DateTime? now}) {
  final today = now ?? DateTime.now();
  final day0 = DateTime(today.year, today.month, today.day);
  DateTime on(int month, int day) => DateTime(
      day0.year, month, min(day, DateTime(day0.year, month + 1, 0).day));
  final mine = [
    for (final b in bills)
      Recurring(
        name: b.name,
        amountPaise: b.amountPaise,
        category: 'Bills & Recharge',
        last: null,
        next: on(day0.month, b.day).isBefore(day0)
            ? on(day0.month + 1, b.day)
            : on(day0.month, b.day),
        count: 0,
      ),
  ];
  final names = {for (final b in bills) b.name.toLowerCase()};
  return [
    ...mine,
    for (final r in findRecurring(txns, now: today))
      if (!names.contains(r.name.toLowerCase())) r,
  ]..sort((a, b) => a.next.compareTo(b.next));
}

/// Monthly repeats among [txns]: three or more payments to one merchant
/// within 10% of their usual amount, 20 to 40 days apart, about one a
/// month, the latest no more than 45 days before [now]. Soonest first.
/// ponytail: monthly only, and a bill that swings by more than 10% (power,
/// a card's minimum due) isn't found; widen the tolerance if that matters.
List<Recurring> findRecurring(List<Txn> txns, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final byMerchant = <String, List<Txn>>{};
  for (final t in txns) {
    if (!t.isDebit || t.hidden || !Categorizer.countsAsSpending(t.category)) {
      continue;
    }
    byMerchant.putIfAbsent(merchantOf(t.counterparty), () => []).add(t);
  }

  final found = <Recurring>[];
  for (final MapEntry(key: name, value: pays) in byMerchant.entries) {
    if (pays.length < 3) continue;
    pays.sort((a, b) => a.time.compareTo(b.time));
    final amounts = [for (final t in pays) t.amountPaise]..sort();
    final usual = amounts[amounts.length ~/ 2];
    final similar =
        pays.where((t) => (t.amountPaise - usual).abs() * 10 <= usual).toList();
    final monthly = <Txn>[];
    for (final t in similar) {
      if (monthly.isEmpty ||
          t.time.difference(monthly.last.time).inDays >= 20) {
        monthly.add(t);
      }
    }
    // Many same-sized payments a month (a daily coffee) aren't a bill.
    if (monthly.length < 3 || similar.length * 4 > monthly.length * 5) continue;
    final gap = monthly.last.time.difference(monthly.first.time).inDays /
        (monthly.length - 1);
    if (gap > 40) continue;
    final last = monthly.last;
    if (today.difference(last.time).inDays > 45) continue;
    found.add(Recurring(
      name: name,
      amountPaise: last.amountPaise,
      category: last.category,
      last: last.time,
      next: last.time.add(Duration(days: gap.round())),
      count: monthly.length,
    ));
  }
  found.sort((a, b) => a.next.compareTo(b.next));
  return found;
}

/// Those expected within the next [days] days, or up to 3 days late.
List<Recurring> comingUp(List<Recurring> all, {DateTime? now, int days = 7}) {
  final today = now ?? DateTime.now();
  final start = DateTime(today.year, today.month, today.day - 3);
  final end = DateTime(today.year, today.month, today.day + days + 1);
  return [
    for (final r in all)
      if (!r.next.isBefore(start) && r.next.isBefore(end)) r
  ];
}

/// "today", "tomorrow", "in 3 days", or "due now" once the day has passed.
String dueLabel(DateTime next, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = DateTime(next.year, next.month, next.day)
      .difference(DateTime(today.year, today.month, today.day))
      .inDays;
  return switch (days) {
    < 0 => 'due now',
    0 => 'today',
    1 => 'tomorrow',
    _ => 'in $days days',
  };
}

/// What the repeats cost in a typical month.
int monthlyCost(List<Recurring> all) =>
    all.fold(0, (sum, r) => sum + r.amountPaise);
