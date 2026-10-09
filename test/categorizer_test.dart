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
      expect(Categorizer.categorizeWith(rules, 'SWIGGY', isDebit: true),
          'Groceries');
      expect(
          Categorizer.categorizeWith(rules, 'ZOMATO', isDebit: true), 'Food');
      expect(Categorizer.categorizeWith(rules, 'SWIGGY', isDebit: false),
          'Income');
    });
  });

  group('MonthSummary', () {
    Txn txn(int paise, bool debit, String category, DateTime time,
            {String counterparty = 'x'}) =>
        Txn(
          key: '$paise$time$counterparty',
          amountPaise: paise,
          isDebit: debit,
          counterparty: counterparty,
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

    test('byMerchant groups payee spellings and sorts by total', () {
      final s = MonthSummary.from([
        txn(10000, true, 'Food', DateTime(2026, 10, 2), counterparty: 'SWIGGY'),
        txn(20000, true, 'Food', DateTime(2026, 10, 3),
            counterparty: 'swiggy.stores@axb'),
        txn(50000, true, 'Shopping', DateTime(2026, 10, 4),
            counterparty: 'AMAZON PAY'),
        txn(99900, false, 'Income', DateTime(2026, 10, 4),
            counterparty: 'AMAZON PAY'),
      ], now: DateTime(2026, 10, 5));
      expect(s.byMerchant.keys.toList(), ['Amazon', 'Swiggy']);
      expect(s.byMerchant['Swiggy'], (count: 2, totalPaise: 30000));
      expect(s.byMerchant['Amazon'], (count: 1, totalPaise: 50000));
    });

    test('self transfers count for nothing', () {
      final s = MonthSummary.from([
        txn(500000, true, Categorizer.selfTransfer, DateTime(2026, 10, 2),
            counterparty: 'me@okaxis'),
        txn(500000, false, Categorizer.selfTransfer, DateTime(2026, 10, 2),
            counterparty: 'HDFC'),
        txn(10000, true, 'Food', DateTime(2026, 10, 2), counterparty: 'SWIGGY'),
      ], now: DateTime(2026, 10, 2));
      expect(s.spentPaise, 10000);
      expect(s.receivedPaise, 0);
      expect(s.todaySpentPaise, 10000);
      expect(s.byCategory.keys, ['Food']);
      expect(s.byMerchant.keys, ['Swiggy']);
    });
  });

  group('monthlyTotals', () {
    Txn spend(int paise, DateTime time, {String category = 'Food'}) => Txn(
          key: '$paise$time',
          amountPaise: paise,
          isDebit: true,
          counterparty: 'SWIGGY',
          channel: 'UPI',
          category: category,
          time: time,
        );

    test(
        'one entry per month ending at lastMonth, zeros kept, self transfers out',
        () {
      final rows = monthlyTotals([
        spend(10000, DateTime(2026, 10, 3)),
        spend(5000, DateTime(2026, 10, 20)),
        spend(7000, DateTime(2026, 8, 1)),
        spend(99999, DateTime(2026, 9, 9), category: Categorizer.selfTransfer),
        spend(1, DateTime(2026, 4, 30)), // before the window
      ], DateTime(2026, 10));
      expect(rows.map((r) => r.month), [
        DateTime(2026, 5),
        DateTime(2026, 6),
        DateTime(2026, 7),
        DateTime(2026, 8),
        DateTime(2026, 9),
        DateTime(2026, 10),
      ]);
      expect(rows.map((r) => r.paise), [0, 0, 0, 7000, 0, 15000]);
    });
  });
}
