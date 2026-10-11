import '../data/shortcut_inbox.dart' show InboxMessage;
import '../util/hash.dart';

/// What [SmsLog.parse] found in a text log.
class SmsLogResult {
  const SmsLogResult({required this.messages, required this.undated});

  final List<InboxMessage> messages;

  /// Non-empty lines before the first dated entry: the automation is
  /// missing the Current Date variable, or the file is not a log at all.
  final int undated;
}

/// The text log the iPhone Shortcuts automation appends each bank SMS to
/// (README → iPhone auto-tracking). An entry starts with an ISO 8601
/// timestamp (Shortcuts' "Current Date" formatted as ISO 8601), a space,
/// then the message. A line without a timestamp continues the previous
/// entry, because bank SMS often contain line breaks.
class SmsLog {
  SmsLog._();

  static final RegExp _entry =
      RegExp(r'^\s*(\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?'
          r'(?:Z|[+-]\d{2}:?\d{2})?)?)\s*[,|;:-]?\s*(.*)$');

  static SmsLogResult parse(String text) {
    final messages = <InboxMessage>[];
    var undated = 0;
    DateTime? date;
    final body = StringBuffer();

    void flush() {
      final s = body.toString().trim();
      if (date != null && s.isNotEmpty) messages.add(_message(date!, s));
    }

    for (final raw in text.split('\n')) {
      final line = raw.replaceAll('\r', '').replaceAll('﻿', '');
      if (line.trim().isEmpty) continue;
      final m = _entry.firstMatch(line);
      final stamp = m == null ? null : DateTime.tryParse(m.group(1)!);
      if (stamp != null) {
        flush();
        date = stamp.toLocal();
        body
          ..clear()
          ..write(m!.group(2));
      } else if (date != null) {
        body
          ..write('\n')
          ..write(line.trim());
      } else {
        undated++;
      }
    }
    flush();
    return SmsLogResult(messages: messages, undated: undated);
  }

  /// The id doubles as the duplicate key when the SMS has no UPI reference,
  /// so it depends only on the message, not on the file or the device.
  static InboxMessage _message(DateTime date, String body) => InboxMessage(
        id: fnv1a('${date.millisecondsSinceEpoch}|$body'),
        sender: '',
        body: body,
        date: date,
      );
}
