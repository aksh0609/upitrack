import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/summary.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/parser/categorizer.dart';

void main() {
  group('Categorizer', () {
    String cat(String payee) => Categorizer.categorize(payee, isDebit: true);

    test('known merchants', () {
      expect(cat('SWIGGY'), 'Food');
      expect(cat('swiggy.stores@axb'), 'Food');
      expect(cat('BLINKIT'), 'Groceries');
      expect(cat('AMAZON PAY'), 'Shopping');
      expect(cat('Prime Video'), 'Entertainment');
      expect(cat('uber.india@ybl'), 'Travel');
      expect(cat('Jio Prepaid'), 'Bills & Recharge');
    });

    test('whole words only', () {
      expect(cat('bholanath sweets'), isNot('Travel'));
    });

    test('personal UPI IDs are transfers', () {
      expect(cat('9876543210@ybl'), 'Transfers');
      expect(cat('rahul.k@okaxis'), 'Transfers');
    });

    test('unknown merchants and all credits', () {
      expect(cat('paytmqr281005@paytm'), 'Others');
      expect(Categorizer.categorize('SWIGGY', isDebit: false), 'Income');
    });

    test('categorizeWith prefers the remembered rule for debits only', () {
      const rules = {'SWIGGY': 'Groceries'};
      expect(Categorizer.categorizeWith(rules, 'SWIGGY', isDebit: true), 'Groceries');
      expect(Categorizer.categorizeWith(rules, 'ZOMATO', isDebit: true), 'Food');
      expect(Categorizer.categorizeWith(rules, 'SWIGGY', isDebit: false), 'Income');
    });
  });

  group('MonthSummary', () {
    Txn txn(int paise, bool debit, String category, DateTime time) => Txn(
          key: '$paise$time',
          amountPaise: paise,
          isDebit: debit,
          counterparty: 'x',
          channel: 'UPI',
          category: category,
          time: time,
        );

    test('totals, today and sorted categories', () {
      final now = DateTime(2026, 10, 5, 12);
      final s = MonthSummary.from([
        txn(10000, true, 'Food', now),
        txn(50000, true, 'Shopping', DateTime(2026, 10, 2)),
        txn(5000, true, 'Food', DateTime(2026, 10, 1)),
        txn(200000, false, 'Income', DateTime(2026, 10, 1)),
      ], now: now);

      expect(s.spentPaise, 65000);
      expect(s.receivedPaise, 200000);
      expect(s.todaySpentPaise, 10000);
      expect(s.netPaise, 135000);
      expect(s.byCategory.keys.toList(), ['Shopping', 'Food']);
      expect(s.byCategory['Food'], 15000);
    });
  });
}
