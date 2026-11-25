import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/background/sms_notification.dart';
import 'package:upitrack/models/budget.dart';
import 'package:upitrack/models/summary.dart';
import 'package:upitrack/models/txn.dart';
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

  group('budget line', () {
    MonthSummary spent(int foodRupees) => MonthSummary.from([
          Txn(
            key: 'k',
            amountPaise: foodRupees * 100,
            isDebit: true,
            counterparty: 'SWIGGY',
            channel: 'UPI',
            category: 'Food',
            time: DateTime(2026, 11, 2),
          )
        ]);

    test('silent below 80%, a share from 80%, the excess once over', () {
      final b = {'Food': 100000};
      expect(budgetNote(b, spent(500), 'Food', 20000), isNull);
      expect(budgetNote(b, spent(700), 'Food', 15000), '85% of budget used');
      expect(budgetNote(b, spent(900), 'Food', 30000), '₹200 over budget');
    });

    test('falls back to the monthly budget; none, nothing', () {
      expect(budgetNote({kTotalBudget: 100000}, spent(900), 'Travel', 5000),
          '95% of monthly budget used');
      expect(budgetNote(const {}, spent(900), 'Food', 5000), isNull);
      expect(budgetNote({'Food': 1}, null, 'Food', 5000), isNull);
    });

    test('appears after the category', () {
      final t = SmsParser.parse(
        'VM-HDFCBK',
        'Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 03/10/26\nRef 427612345678',
      )!;
      expect(notificationText(t, 'Food', budget: '85% of budget used').body,
          'Food · 85% of budget used · HDFC Bank · •••1234');
    });
  });
}
