import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/parser/statement_parser.dart';

// Statement layouts follow each bank's/app's typical export. All names,
// numbers and references are made up.

void main() {
  group('PDF text', () {
    test('HDFC: oldest first, opening balance, debit/credit from balance', () {
      const text = '''
HDFC BANK Ltd.  Statement of account
Account No : 50100123456789
Date Narration Chq./Ref.No. Value Dt Withdrawal Amt. Deposit Amt. Closing Balance
Opening Balance 10,000.00
01/10/26 UPI-SWIGGY-SWIGGY.STORES@AXB-UTIB0000100-427612345678-PAYMENT 0000427612345678 01/10/26 250.00 9,750.00
02/10/26 UPI-RAHUL KUMAR-RAHUL.K@OKAXIS-SBIN0001234-427612345679-RENT 0000427612345679 02/10/26 5,000.00 14,750.00
03/10/26 NEFT CR-SBIN0001234-ACME PVT LTD-SALARY 03/10/26 50,000.00 64,750.00
04/10/26 POS 4321XXXXXXXX1234 AMAZON PAY INDIA 04/10/26 1,299.00 63,451.00
Page 1 of 1
''';
      final r = StatementParser.parseText(text);
      expect(r.rows, hasLength(4));
      expect(r.skipped, 0);

      final swiggy = r.rows[0];
      expect(swiggy.date, DateTime(2026, 10, 1, 12));
      expect(swiggy.isDebit, isTrue);
      expect(swiggy.amountPaise, 25000);
      expect(swiggy.counterparty, 'SWIGGY');
      expect(swiggy.ref, '427612345678');

      expect(r.rows[1].isDebit, isFalse);
      expect(r.rows[1].amountPaise, 500000);
      expect(r.rows[1].counterparty, 'RAHUL KUMAR');

      expect(r.rows[2].isDebit, isFalse);
      expect(r.rows[2].amountPaise, 5000000);

      expect(r.rows[3].isDebit, isTrue);
      expect(r.rows[3].amountPaise, 129900);
      expect(r.rows[3].counterparty, 'AMAZON PAY INDIA');
    });

    test('SBI: newest first, wrapped narration, no opening balance', () {
      const text = '''
Txn Date Value Date Description Ref No./Cheque No. Debit Credit Balance
04 Oct 2026 04 Oct 2026 TO TRANSFER-UPI/DR/427698765432/ZOMATO/YESB/zomato@yes/Payment 120.00 9,380.00
03 Oct 2026 03 Oct 2026 BY TRANSFER-UPI/CR/427698765431/PRIYA S/HDFC/priya@okhdfcbank/ 500.00 9,500.00
02 Oct 2026 02 Oct 2026 TO TRANSFER-UPI/DR/427698765430/BLINKIT/
YESB/blinkit@yes/Order 1,000.00 9,000.00
''';
      final r = StatementParser.parseText(text);
      expect(r.rows, hasLength(3));

      expect(r.rows[0].isDebit, isTrue);
      expect(r.rows[0].counterparty, 'ZOMATO');
      expect(r.rows[0].amountPaise, 12000);
      expect(r.rows[0].date, DateTime(2026, 10, 4, 12));

      expect(r.rows[1].isDebit, isFalse);
      expect(r.rows[1].counterparty, 'PRIYA S');

      // Oldest row has nothing before it, so the DR marker decides.
      expect(r.rows[2].isDebit, isTrue);
      expect(r.rows[2].amountPaise, 100000);
      expect(r.rows[2].counterparty, 'BLINKIT');
      expect(r.rows[2].ref, '427698765430');
    });

    test('PhonePe: DEBIT/CREDIT words, ₹ amounts, times', () {
      const text = '''
Transaction Statement for 98XXXXXX10
Oct 01, 2026 - Oct 05, 2026
Date Transaction Details Type Amount
Oct 04, 2026 Paid to SWIGGY DEBIT ₹250
10:22 pm
Transaction ID T2610042222123456
UTR No. 427612340099
Paid by XXXXXX1234
Oct 03, 2026 Received from Rahul Kumar CREDIT ₹1,500
09:05 am
Transaction ID T2610030905123456
UTR No. 427612340098
Credited to XXXXXX1234
Page 1 of 1
''';
      final r = StatementParser.parseText(text);
      expect(r.rows, hasLength(2));

      expect(r.rows[0].isDebit, isTrue);
      expect(r.rows[0].amountPaise, 25000);
      expect(r.rows[0].counterparty, 'SWIGGY');
      expect(r.rows[0].ref, '427612340099');
      expect(r.rows[0].date, DateTime(2026, 10, 4, 22, 22));

      expect(r.rows[1].isDebit, isFalse);
      expect(r.rows[1].amountPaise, 150000);
      expect(r.rows[1].counterparty, 'Rahul Kumar');
      expect(r.rows[1].date, DateTime(2026, 10, 3, 9, 5));
    });
  });

  group('CSV', () {
    test('HDFC net banking export', () {
      const csv = 'HDFC Bank\n'
          'Account,50100123456789\n'
          'Date,Narration,Chq./Ref.No.,Value Dt,Withdrawal Amt.,Deposit Amt.,Closing Balance\n'
          '01/10/26,"UPI-SWIGGY-SWIGGY.STORES@AXB-UTIB0000100-427612345678-PAYMENT",0000427612345678,01/10/26,250.00,,"9,750.00"\n'
          '02/10/26,UPI-RAHUL KUMAR-RAHUL.K@OKAXIS-SBIN0001234-427612345679-RENT,0000427612345679,02/10/26,,"5,000.00","14,750.00"\n';
      final r = StatementParser.parseCsv(csv);
      expect(r.rows, hasLength(2));
      expect(r.rows[0].isDebit, isTrue);
      expect(r.rows[0].amountPaise, 25000);
      expect(r.rows[0].counterparty, 'SWIGGY');
      expect(r.rows[0].ref, '427612345678');
      expect(r.rows[1].isDebit, isFalse);
      expect(r.rows[1].amountPaise, 500000);
    });

    test('Paytm export with signed amounts', () {
      const csv = 'Date,Time,Transaction Details,Other Transaction Details (UPI ID or A/c No),Your Account,Amount,UPI Ref No.,Order ID,Remarks,Tags,Comment\n'
          '03/10/2026,13:05:22,Paid to Swiggy,swiggy@paytm,HDFC Bank - 34,-250,427612341234,,,,\n'
          '02/10/2026,09:00:00,Received from Rahul,rahul@ybl,HDFC Bank - 34,"+1,000",427612341233,,,,\n';
      final r = StatementParser.parseCsv(csv);
      expect(r.rows, hasLength(2));
      expect(r.rows[0].isDebit, isTrue);
      expect(r.rows[0].amountPaise, 25000);
      expect(r.rows[0].counterparty, 'Swiggy');
      expect(r.rows[0].ref, '427612341234');
      expect(r.rows[1].isDebit, isFalse);
      expect(r.rows[1].amountPaise, 100000);
    });

    test('file without a recognisable header returns nothing', () {
      expect(StatementParser.parseCsv('a,b,c\n1,2,3\n').rows, isEmpty);
    });
  });

  test('date formats', () {
    final expected = DateTime(2026, 10, 3);
    for (final s in [
      '03/10/26',
      '03-10-2026',
      '03.10.2026',
      '03 Oct 2026',
      '03-Oct-26',
      '03Oct26',
      'Oct 03, 2026',
      '3 October, 2026',
    ]) {
      expect(StatementParser.parseDate(s), expected, reason: s);
    }
    expect(StatementParser.parseDate('31/02/2026'), isNull);
  });
}
