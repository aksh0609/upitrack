import '../models/budget.dart';
import '../models/summary.dart';
import '../parser/categorizer.dart';
import '../parser/sms_parser.dart';
import '../util/format.dart';

/// Title and body of the "payment caught" notification, e.g.
/// "-₹250 to SWIGGY" / "Food · HDFC Bank · •••1234". Pure, tested in
/// `test/background/sms_notification_test.dart`.
({String title, String body}) notificationText(ParsedTxn t, String category,
    {String? budget}) {
  final who = t.counterparty ?? 'Unknown';
  final amount = formatPaise(t.amountPaise);
  final title = t.isDebit ? '-$amount to $who' : '+$amount from $who';
  final body = [
    if (t.isDebit) category,
    if (budget != null) budget,
    if (t.bank != null) t.bank!,
    if (t.account != null) '•••${t.account}',
  ].join(' · ');
  return (title: title, body: body);
}

/// "85% of budget used" once a payment of [paise] in [category] takes
/// its budget (or, without one, the overall budget) to 80% or more; null
/// below that or without a budget. [month] is the month before this payment.
String? budgetNote(
    Map<String, int> budgets, MonthSummary? month, String category, int paise) {
  if (month == null || !Categorizer.countsAsSpending(category)) return null;
  final key = budgets.containsKey(category) ? category : kTotalBudget;
  final limit = budgets[key];
  if (limit == null) return null;
  final spent = paise +
      (key == kTotalBudget ? month.spentPaise : month.byCategory[key] ?? 0);
  final which = key == kTotalBudget ? 'monthly budget' : 'budget';
  return switch (budgetLevel(spent, limit)) {
    BudgetLevel.ok => null,
    BudgetLevel.near => '${(spent * 100 / limit).floor()}% of $which used',
    BudgetLevel.over => '${formatPaise(spent - limit)} over $which',
  };
}
