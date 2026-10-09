/// One device's whole table as JSON (spec §4.4): built, encoded to bytes
/// for encryption, and decoded back. Pure Dart so it runs on web too.
library;

import 'dart:convert';
import 'dart:typed_data';

const int kSnapshotVersion = 1;

Map<String, Object?> buildSnapshot({
  required String deviceId,
  required int exportedMs,
  required List<Map<String, Object?>> txns,
  required List<Map<String, Object?>> rules,
}) =>
    {
      'v': kSnapshotVersion,
      'device': deviceId,
      'exported_ms': exportedMs,
      'txns': txns,
      'rules': rules,
    };

/// UTF-8 JSON. ponytail: no compression; ~300 B per row is fine for personal
/// data. Gzip here (and bump kSnapshotVersion) if a snapshot passes a few MB.
Uint8List encodeSnapshot(Map<String, Object?> snapshot) =>
    Uint8List.fromList(utf8.encode(jsonEncode(snapshot)));

/// Throws [FormatException] for anything that isn't a version-1 snapshot.
Map<String, Object?> decodeSnapshot(List<int> bytes) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Exception catch (e) {
    throw FormatException('not a snapshot: $e');
  }
  if (decoded is! Map<String, Object?> ||
      decoded['v'] != kSnapshotVersion ||
      decoded['txns'] is! List ||
      decoded['rules'] is! List) {
    throw const FormatException('unsupported snapshot');
  }
  return decoded;
}
