import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/account.dart';

void main() {
  test('accountLabel uses the bank\'s first word', () {
    expect(accountLabel((bank: 'HDFC Bank', last4: '1234')), 'HDFC •••1234');
    expect(accountLabel((bank: 'Bank of Baroda', last4: '99')), 'Bank •••99');
    expect(accountLabel((bank: null, last4: '5678')), '•••5678');
    expect(accountLabel((bank: '', last4: '5678')), '•••5678');
  });
}
