import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/background/sms_notification.dart';
import 'package:upitrack/parser/sms_parser.dart';

void main() {
  test('debit: amount, payee, category, bank and account', () {
    final t = SmsParser.parse(
      'VM-HDFCBK',
      'Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 03/10/26\nRef 427612345678',
    )!;
    final n = notificationText(t, 'Food');
    expect(n.title, '-₹250 to SWIGGY');
    expect(n.body, 'Food · HDFC Bank · •••1234');
  });

  test('credit: no category line', () {
    final t = SmsParser.parse(
      'VM-HDFCBK',
      'Received Rs.500.00 in your HDFC Bank A/c XX1234 from VPA rahul@okicici '
          'on 03-10-26. UPI Ref: 427612345679',
    )!;
    final n = notificationText(t, 'Income');
    expect(n.title, '+₹500 from rahul@okicici');
    expect(n.body, 'HDFC Bank · •••1234');
  });

  test('unknown payee', () {
    final t = SmsParser.parse(
      'AD-SBIUPI',
      'Dear SBI UPI User, ur A/cX1234 credited by Rs500 on 03Oct26 by (Ref no 427612345670)',
    )!;
    expect(notificationText(t, 'Income').title, '+₹500 from Unknown');
  });
}
