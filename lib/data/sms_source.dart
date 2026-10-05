import 'package:flutter/services.dart';

class RawSms {
  const RawSms({
    required this.id,
    required this.address,
    required this.body,
    required this.date,
  });

  final int id;
  final String address;
  final String body;
  final DateTime date;
}

/// Reads the SMS inbox through a small Kotlin bridge in MainActivity.kt.
/// Requires the READ_SMS permission to be granted first.
class SmsSource {
  static const MethodChannel _channel = MethodChannel('upitrack/sms');

  Future<List<RawSms>> readInbox({required DateTime since}) async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'readInbox',
      {'sinceMillis': since.millisecondsSinceEpoch},
    );
    return [
      for (final m in rows ?? const <Map<Object?, Object?>>[])
        RawSms(
          id: (m['id'] as num).toInt(),
          address: m['address'] as String? ?? '',
          body: m['body'] as String? ?? '',
          date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()),
        ),
    ];
  }
}
