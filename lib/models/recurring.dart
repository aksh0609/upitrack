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
    this.varies = false,
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

  /// The amount changes from month to month (power, a card); [amountPaise]
  /// is the latest.
  final bool varies;
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

/// Monthly repeats among [txns], soonest due first. Walking back from a
/// recent payment to one merchant, each step one payment 20 to 40 days
/// earlier: three such payments are a repeat, or two of the same amount
/// (rent, a subscription). Bills & Recharge may change from month to month
/// (power, a card, a recharge); anything else stays within 10%, so a
/// shop visited monthly isn't a bill. Merchants paid more than twice a
/// month on average (food, cabs) and repeats whose latest payment is over
/// 45 days before [now] are left out.
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
    if (pays.length < 2) continue;
    pays.sort((a, b) => a.time.compareTo(b.time));
    final months = {for (final t in pays) t.time.year * 12 + t.time.month};
    if (pays.length > months.length * 2) continue;
    // Start from the latest payment, or an earlier one when the latest is
    // a one-off (a top-up beside the monthly plan).
    for (var s = pays.length - 1; s >= 0; s--) {
      final start = pays[s];
      if (today.difference(start.time).inDays > 45) break;
      final chain = _monthlyChain(pays, s);
      final two = chain.length == 2 &&
          (chain[1].amountPaise - start.amountPaise).abs() * 50 <=
              start.amountPaise;
      if (chain.length < 3 && !two) continue;
      final gap =
          start.time.difference(chain.last.time).inDays / (chain.length - 1);
      found.add(Recurring(
        name: name,
        amountPaise: start.amountPaise,
        category: start.category,
        last: start.time,
        // Monthly: the same date next month (rent on the 5th stays on the
        // 5th); a 28-day plan: the usual gap.
        next: gap >= 29.5
            ? _sameDayNextMonth(start.time)
            : start.time.add(Duration(days: gap.round())),
        count: chain.length,
        varies: chain.any((t) =>
            (t.amountPaise - start.amountPaise).abs() * 10 > start.amountPaise),
      ));
      break;
    }
  }
  found.sort((a, b) => a.next.compareTo(b.next));
  return found;
}

DateTime _sameDayNextMonth(DateTime t) => DateTime(t.year, t.month + 1,
    min(t.day, DateTime(t.year, t.month + 2, 0).day), t.hour, t.minute);

/// [pays] (oldest first) from index [s] back, one payment 20 to 40 days
/// before the one after it; newest first.
List<Txn> _monthlyChain(List<Txn> pays, int s) {
  final start = pays[s];
  final bill = start.category == 'Bills & Recharge';
  bool same(Txn t) => bill
      ? t.amountPaise * 3 >= start.amountPaise &&
          t.amountPaise <= start.amountPaise * 3
      : (t.amountPaise - start.amountPaise).abs() * 10 <= start.amountPaise;
  final chain = [start];
  for (var i = s - 1; i >= 0; i--) {
    final gap = chain.last.time.difference(pays[i].time).inDays;
    if (gap > 40) break;
    if (gap >= 20 && same(pays[i])) chain.add(pays[i]);
  }
  return chain;
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
