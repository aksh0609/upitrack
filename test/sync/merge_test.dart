import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/sync/merge.dart';

void main() {
  Map<String, Object?> txn(int editTs, {String category = 'Food'}) =>
      {'key': 'k', 'category': category, 'edit_ts': editTs};

  test('a row the device has never seen is inserted', () {
    expect(mergeTxn(null, txn(0)), TxnMerge.insert);
  });

  test('an edit beats an automatic row and an older edit', () {
    expect(mergeTxn(txn(0), txn(5)), TxnMerge.update);
    expect(mergeTxn(txn(3), txn(5)), TxnMerge.update);
  });

  test('an automatic row never beats an edit; equal stamps keep local', () {
    expect(mergeTxn(txn(5), txn(0)), TxnMerge.keep);
    expect(mergeTxn(txn(5), txn(5)), TxnMerge.keep);
    expect(mergeTxn(txn(0), txn(0)), TxnMerge.keep);
  });

  test('a missing edit_ts counts as 0', () {
    expect(mergeTxn({'key': 'k'}, {'key': 'k', 'edit_ts': 1}), TxnMerge.update);
    expect(mergeTxn({'key': 'k', 'edit_ts': 1}, {'key': 'k'}), TxnMerge.keep);
  });

  test('a rule wins when unknown locally or newer', () {
    Map<String, Object?> rule(int ts) =>
        {'counterparty': 'SWIGGY', 'category': 'Food', 'ts': ts};
    expect(ruleWins(null, rule(1)), isTrue);
    expect(ruleWins(rule(1), rule(2)), isTrue);
    expect(ruleWins(rule(2), rule(2)), isFalse);
    expect(ruleWins(rule(3), rule(2)), isFalse);
  });
}
