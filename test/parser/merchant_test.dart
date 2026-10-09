import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/parser/merchant.dart';

void main() {
  test('known merchants, whatever the payee spelling', () {
    expect(merchantOf('SWIGGY'), 'Swiggy');
    expect(merchantOf('swiggy.stores@axb'), 'Swiggy');
    expect(merchantOf('Swiggy Instamart'), 'Swiggy Instamart');
    expect(merchantOf('AMAZON PAY INDIA'), 'Amazon');
    expect(merchantOf('amazonpay@apl'), 'Amazon');
    expect(merchantOf('Prime Video'), 'Prime Video');
    expect(merchantOf('JIOHOTSTAR'), 'JioHotstar');
    expect(merchantOf('Jio Prepaid'), 'Jio');
    expect(merchantOf('Vi Prepaid'), 'Vi');
    expect(merchantOf('MYNTRA DESIGNS PVT LTD'), 'Myntra');
    expect(merchantOf('flipkart@axisbank'), 'Flipkart');
  });

  test('whole words only', () {
    expect(knownMerchant('bholanath sweets'), isNull);
    expect(knownMerchant('violet cafe'), isNull);
  });

  test('unknown payees pass through, trimmed', () {
    expect(knownMerchant('RAHUL KUMAR'), isNull);
    expect(merchantOf('  RAHUL   KUMAR '), 'RAHUL KUMAR');
    expect(merchantOf('rahul@okaxis'), 'rahul@okaxis');
  });

  test('longer names win over their prefixes', () {
    expect(merchantOf('swiggyinstamart'), isNot('Swiggy'));
    expect(merchantOf('JioMart'), 'JioMart');
  });
}
