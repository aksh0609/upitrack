import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/parser/anonymise.dart';

void main() {
  test('masks account digits, reference and payee; keeps amount and bank words', () {
    expect(
      anonymise('Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 03/10/26\nRef 427612345678'),
      'Sent Rs.250.00\nFrom NAME Bank A/C *XXXX\nTo NAME\nOn 03/10/26\nRef XXXXXXXXXXXX',
    );
  });

  test('masks the UPI ID local part, keeps the handle and structure words', () {
    expect(
      anonymise('Rs.1,250.50 debited from A/c XX5678 on 03-10-2026 to VPA abc@ybl '
          '(UPI Ref No 427612343333). Avl Bal Rs.10,000.00'),
      // Years are 4 digits and get masked too; the parser never reads dates.
      'Rs.1,250.50 debited from A/c XXXXXX on 03-10-XXXX to VPA xxxx@ybl '
      '(UPI Ref No XXXXXXXXXXXX). Avl Bal Rs.10,000.00',
    );
  });

  test('keeps an amount written without a currency symbol', () {
    expect(
      anonymise('A/C X1234 debited by 12000 on date 03Oct26 trf to ZOMATO Refno 427698765432'),
      'A/C XXXXX debited by 12000 on date 03Oct26 trf to NAME Refno XXXXXXXXXXXX',
    );
  });

  test('masks a Title Case person name', () {
    expect(
      anonymise('credited with Rs 1000.00 on 03-Oct-26 from Rahul Kumar. UPI:427612340001'),
      'credited with Rs 1000.00 on 03-Oct-26 from NAME. UPI:XXXXXXXXXXXX',
    );
  });
}
