import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/sync/snapshot.dart';

void main() {
  test('build → encode → decode round-trips, with the version tag', () {
    final snap = buildSnapshot(
      deviceId: 'abc',
      exportedMs: 1760000000000,
      txns: [
        {'key': 'k1', 'amount_paise': 100, 'is_debit': 1, 'counterparty': 'SWIGGY',
         'channel': 'UPI', 'category': 'Food', 'ts': 1, 'hidden': 0, 'edit_ts': 0, 'raw': null},
      ],
      rules: [{'counterparty': 'SWIGGY', 'category': 'Food', 'ts': 7}],
    );
    expect(snap['v'], kSnapshotVersion);
    expect(snap['device'], 'abc');
    final back = decodeSnapshot(encodeSnapshot(snap));
    expect(back, snap);
    expect(((back['txns'] as List).single as Map)['amount_paise'], 100);
  });

  test('an unknown version is refused', () {
    final bytes = encodeSnapshot({'v': 99, 'device': 'x', 'exported_ms': 0, 'txns': [], 'rules': []});
    expect(() => decodeSnapshot(bytes), throwsFormatException);
  });

  test('garbage is refused', () {
    expect(() => decodeSnapshot([1, 2, 3]), throwsFormatException);
  });
}
