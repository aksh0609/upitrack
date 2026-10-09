import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/util/search.dart';

void main() {
  Txn txn(String counterparty) => Txn(
        key: counterparty,
        amountPaise: 100,
        isDebit: true,
        counterparty: counterparty,
        channel: 'UPI',
        category: 'Others',
        time: DateTime(2026, 10, 1),
      );

  test('matches payee text and merchant name, case-insensitive', () {
    expect(matchesSearch(txn('MYNTRA DESIGNS'), 'myntra'), isTrue);
    expect(matchesSearch(txn('amazonpay@apl'), 'Amazon'), isTrue); // via merchant
    expect(matchesSearch(txn('rahul@okaxis'), 'RAHUL'), isTrue);
    expect(matchesSearch(txn('SWIGGY'), 'zomato'), isFalse);
  });

  test('empty or blank query matches everything', () {
    expect(matchesSearch(txn('x'), ''), isTrue);
    expect(matchesSearch(txn('x'), '   '), isTrue);
  });
}
