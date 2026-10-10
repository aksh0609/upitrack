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
  final byName = txn('ABISHEK KUMAR', 'Others'); // filed before v4
  final oneName = txn('PRAMOD', 'Others');
  final friendForFood = txn('YOGESH KUMAR S', 'Food'); // user's own pick
  final unknown = txn('Unknown', 'Others');
  final fromFriend = txn('rahul.k@okaxis', 'Income', isDebit: false);
  final salary = txn('ACME PAYROLL', 'Income', isDebit: false);
  final gift = txn('AMAZON GIFT CARD', 'Gift cards');
  final self = txn('ICICI 1234', 'Self transfer');

  List<Txn> pick(Who who) => [
        swiggy,
        unknownShop,
        friend,
        byName,
        oneName,
        friendForFood,
        unknown,
        fromFriend,
        salary,
        gift,
        self,
      ].where((t) => matchesWho(t, who)).toList();

  test('All keeps everything', () {
    expect(pick(Who.all).length, 11);
  });

  test('Merchants: brands, QR shops, anything filed under a spending category',
      () {
    expect(pick(Who.merchants), [swiggy, unknownShop, friendForFood, unknown]);
  });

  test('People: Transfers, plus Others/Income payees that are not businesses',
      () {
    expect(pick(Who.people), [friend, byName, oneName, fromFriend]);
  });

  test('Gift cards is the category alone', () {
    expect(pick(Who.giftCards), [gift]);
  });
}
