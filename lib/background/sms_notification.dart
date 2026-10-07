import '../parser/sms_parser.dart';
import '../util/format.dart';

/// Title and body of the "payment caught" notification, e.g.
/// "-₹250 to SWIGGY" / "Food · HDFC Bank · •••1234". Pure, tested in
/// `test/background/sms_notification_test.dart`.
({String title, String body}) notificationText(ParsedTxn t, String category) {
  final who = t.counterparty ?? 'Unknown';
  final amount = formatPaise(t.amountPaise);
  final title = t.isDebit ? '-$amount to $who' : '+$amount from $who';
  final body = [
    if (t.isDebit) category,
    if (t.bank != null) t.bank!,
    if (t.account != null) '•••${t.account}',
  ].join(' · ');
  return (title: title, body: body);
}
