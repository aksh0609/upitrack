import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/util/who.dart';

void main() {
  Txn txn(String counterparty, String category, {bool isDebit = true}) => Txn(
        key: '$counterparty/$category/$isDebit',
        amountPaise: 100,
        isDebit: isDebit,
        counterparty: counterparty,
        channel: 'UPI',
        category: category,
        time: DateTime(2026, 10, 1),
      );

  final swiggy = txn('SWIGGY', 'Food');
  final unknownShop = txn('paytmqr281005@paytm', 'Others');
  final friend = txn('9876543210@ybl', 'Transfers');
  final fromFriend = txn('rahul.k@okaxis', 'Income', isDebit: false);
  final salary = txn('ACME PAYROLL', 'Income', isDebit: false);
  final gift = txn('AMAZON GIFT CARD', 'Gift cards');
  final self = txn('ICICI 1234', 'Self transfer');

  List<Txn> pick(Who who) => [
        swiggy,
        unknownShop,
        friend,
        fromFriend,
        salary,
        gift,
        self,
      ].where((t) => matchesWho(t, who)).toList();

  test('All keeps everything', () {
    expect(pick(Who.all).length, 7);
  });

  test('Merchants are debits to businesses, whatever the category', () {
    expect(pick(Who.merchants), [swiggy, unknownShop]);
  });

  test('People covers transfers out and money in from personal handles', () {
    expect(pick(Who.people), [friend, fromFriend]);
  });

  test('Gift cards is the category alone', () {
    expect(pick(Who.giftCards), [gift]);
  });
}
