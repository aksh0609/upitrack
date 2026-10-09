import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/parser/sms_parser.dart';

// Sample messages follow each bank's public SMS format. Names, numbers and
// references are made up. When a real SMS from your bank isn't parsed
// correctly, add an anonymised copy here as a new test, then fix the parser.

void main() {
  group('debits', () {
    test('HDFC multi-line UPI debit', () {
      final t = SmsParser.parse(
        'VM-HDFCBK',
        'Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 03/10/26\n'
            'Ref 427612345678\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808',
      )!;
      expect(t.isDebit, isTrue);
      expect(t.amountPaise, 25000);
      expect(t.counterparty, 'SWIGGY');
      expect(t.bank, 'HDFC Bank');
      expect(t.account, '1234');
      expect(t.ref, '427612345678');
      expect(t.channel, 'UPI');
    });

    test('SBI debit without currency symbol', () {
      final t = SmsParser.parse(
        'AD-SBIUPI-S',
        'Dear UPI user A/C X1234 debited by 120.0 on date 03Oct26 trf to ZOMATO '
            'Refno 427698765432. If not u? call 1800111109. -SBI',
      )!;
      expect(t.isDebit, isTrue);
      expect(t.amountPaise, 12000);
      expect(t.counterparty, 'ZOMATO');
      expect(t.bank, 'SBI');
      expect(t.account, '1234');
      expect(t.ref, '427698765432');
    });

    test('ICICI debit with merchant credited', () {
      final t = SmsParser.parse(
        'JD-ICICIT',
        'ICICI Bank Acct XX123 debited for Rs 349.00 on 03-Oct-26; AMAZON PAY '
            'credited. UPI:427612340000. Call 18002662 for dispute. '
            'SMS BLOCK 123 to 9215676766.',
      )!;
      expect(t.isDebit, isTrue);
      expect(t.amountPaise, 34900);
      expect(t.counterparty, 'AMAZON PAY');
      expect(t.account, '123');
      expect(t.ref, '427612340000');
    });

    test('Axis UPI path format', () {
      final t = SmsParser.parse(
        'AX-AXISBK',
        'INR 200.00 debited\nA/c no. XX1234\n03-10-26, 14:22:10\n'
            'UPI/P2M/427612341111/BLINKIT\nNot you? SMS BLOCKUPI Cust ID to '
            '919951860002\nAxis Bank',
      )!;
      expect(t.amountPaise, 20000);
      expect(t.counterparty, 'BLINKIT');
      expect(t.ref, '427612341111');
      expect(t.account, '1234');
      expect(t.bank, 'Axis Bank');
    });

    test('Kotak debit to a UPI ID', () {
      final t = SmsParser.parse(
        'VK-KOTAKB',
        'Sent Rs.150.00 from Kotak Bank AC X1234 to paytmqr123@paytm on '
            '03-10-26.UPI Ref 427612342222. Not you, https://kotak.com/fraud',
      )!;
      expect(t.isDebit, isTrue);
      expect(t.counterparty, 'paytmqr123@paytm');
      expect(t.ref, '427612342222');
      expect(t.bank, 'Kotak Bank');
    });

    test('Generic debit with balance after it', () {
      final t = SmsParser.parse(
        'BP-PNBSMS',
        'Rs.1,250.50 debited from A/c XX5678 on 03-10-2026 to VPA abc@ybl '
            '(UPI Ref No 427612343333). Avl Bal Rs.10,000.00',
      )!;
      expect(t.amountPaise, 125050);
      expect(t.counterparty, 'abc@ybl');
      expect(t.account, '5678');
      expect(t.bank, 'PNB');
    });

    test('Card spend is tracked as Card', () {
      final t = SmsParser.parse(
        'VM-HDFCBK',
        'Rs 499.00 spent on your HDFC Bank Card XX9876 at NETFLIX on 2026-10-03.',
      )!;
      expect(t.channel, 'Card');
      expect(t.counterparty, 'NETFLIX');
      expect(t.account, '9876');
    });
  });

  group('credits', () {
    test('HDFC credit from UPI ID', () {
      final t = SmsParser.parse(
        'VM-HDFCBK',
        'Received Rs.500.00 in your HDFC Bank A/c XX1234 from VPA rahul@okicici '
            'on 03-10-26. UPI Ref: 427612345679',
      )!;
      expect(t.isDebit, isFalse);
      expect(t.amountPaise, 50000);
      expect(t.counterparty, 'rahul@okicici');
    });

    test('ICICI credit from a person', () {
      final t = SmsParser.parse(
        'JD-ICICIT',
        'Dear Customer, Acct XX123 is credited with Rs 1000.00 on 03-Oct-26 '
            'from RAHUL KUMAR. UPI:427612340001-ICICI Bank.',
      )!;
      expect(t.isDebit, isFalse);
      expect(t.counterparty, 'RAHUL KUMAR');
      expect(t.ref, '427612340001');
    });

    test('SBI credit with no payer name', () {
      final t = SmsParser.parse(
        'AD-SBIUPI',
        'Dear SBI UPI User, ur A/cX1234 credited by Rs500 on 03Oct26 by '
            '(Ref no 427612345670)',
      )!;
      expect(t.isDebit, isFalse);
      expect(t.amountPaise, 50000);
      expect(t.counterparty, isNull);
      expect(t.account, '1234');
    });
  });

  group('ignored messages', () {
    test('OTP', () {
      expect(
        SmsParser.parse('VM-HDFCBK',
            '123456 is your OTP for UPI payment of Rs 500 to abc@ybl. Do not share.'),
        isNull,
      );
    });

    test('collect request', () {
      expect(
        SmsParser.parse('VM-ICICIT',
            'abc@ybl has requested money Rs 300 from you on UPI. Pay in the app.'),
        isNull,
      );
    });

    test('promotion', () {
      expect(
        SmsParser.parse('AD-PAYTMB',
            'Get Rs 100 cashback credited on your first payment! Limited offer.'),
        isNull,
      );
    });

    test('bill reminder', () {
      expect(
        SmsParser.parse('VM-AIRTEL',
            'Your bill of Rs 599 is due on 10-Oct. Pay now to avoid late fee.'),
        isNull,
      );
    });

    test('failed payment', () {
      expect(
        SmsParser.parse('VM-HDFCBK',
            'UPI payment of Rs 200 to abc@ybl failed. Amount not debited.'),
        isNull,
      );
    });

    test('message from a personal phone number', () {
      expect(
        SmsParser.parse('+919876543210',
            'Rs 5000 credited to your A/c XX1234. UPI Ref 427612345111'),
        isNull,
      );
    });
  });

  group('looksLikeTransaction', () {
    test('gift card and wallet balance notices are not transactions', () {
      const myntra =
          'Dear Customer, your payment of Rs. 2716 using Myntra Gift Card '
          '************4827 balance is successful. Updated Myntra Gift Card balance: Rs. 1284.0000.';
      const flipkart =
          'Flipkart Update: Your Gift Card ending with 02391 has a remaining '
          'balance of Rs.242.00 and will expire on 12/07/2026. View details: https://flipkart.com/helpcentre';
      expect(SmsParser.looksLikeTransaction('BG-MYNTRA-S', myntra), isFalse);
      expect(SmsParser.looksLikeTransaction('BG-FLPKRT-S', flipkart), isFalse);
      expect(SmsParser.parse('BG-MYNTRA-S', myntra), isNull);
    });
    test('unfamiliar bank wording with an amount', () {
      const body =
          'Your a/c 1234 has a withdrawal of INR 320.00 at 10:12 towards UPI/9876';
      expect(SmsParser.parse('AD-UCOBNK', body), isNull,
          reason: 'not parsed today');
      expect(SmsParser.looksLikeTransaction('AD-UCOBNK', body), isTrue);
    });

    test('debit word without a currency symbol', () {
      expect(
          SmsParser.looksLikeTransaction(
              'AD-SBIUPI', 'A/c X1234 debited 300 for a new format'),
          isTrue);
    });

    test('OTP, promotion and personal numbers are not transactions', () {
      expect(
          SmsParser.looksLikeTransaction(
              'VM-HDFCBK', '123456 is your OTP for Rs 500'),
          isFalse);
      expect(
          SmsParser.looksLikeTransaction(
              'AD-PAYTMB', 'Get Rs 100 cashback! Limited offer.'),
          isFalse);
      expect(
          SmsParser.looksLikeTransaction(
              '+919876543210', 'Rs 5000 credited to your A/c'),
          isFalse);
    });

    test('no amount and no money word', () {
      expect(
          SmsParser.looksLikeTransaction(
              'VM-HDFCBK', 'Thank you for banking with us.'),
          isFalse);
    });

    test('merchant and telecom SMS with an amount are not transactions', () {
      for (final body in [
        'Your Swiggy order worth Rs 250 is on its way!',
        'Airtel: recharge of Rs 299 successful. Enjoy unlimited calls.',
        'Your Amazon order of Rs 1,299 has shipped. Track it in the app.',
        'Zomato: refund of Rs 180 initiated to your original payment mode.',
        'Jio: Rs 239 pack activated. Valid 28 days.',
      ]) {
        expect(SmsParser.looksLikeTransaction('VM-SWIGGY', body), isFalse,
            reason: body);
      }
    });
  });

  group('firstAmountPaise', () {
    test('first transaction amount, skipping balances', () {
      expect(SmsParser.firstAmountPaise('withdrawal of INR 320.00 towards UPI'),
          32000);
      expect(
          SmsParser.firstAmountPaise('A/c debited by 120.0 trf to X'), 12000);
      expect(SmsParser.firstAmountPaise('Avl Bal Rs.10,000.00 only'), isNull);
    });
  });
}
