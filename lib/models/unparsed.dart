/// A bank-looking SMS the parser could not read. Shown to the user so it
/// can be added by hand, ignored, or reported.
class UnparsedSms {
  const UnparsedSms({
    this.id,
    required this.key,
    required this.sender,
    required this.body,
    required this.time,
    this.state = 'open',
  });

  final int? id;

  /// `sms:<inbox id>` on Android, `shortcut:<file id>` on iPhone.
  final String key;
  final String sender;
  final String body;
  final DateTime time;

  /// 'open', 'added' (user entered it manually) or 'ignored'.
  final String state;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'key': key,
        'sender': sender,
        'body': body,
        'ts': time.millisecondsSinceEpoch,
        'state': state,
      };

  factory UnparsedSms.fromMap(Map<String, Object?> m) => UnparsedSms(
        id: m['id'] as int?,
        key: m['key'] as String,
        sender: m['sender'] as String,
        body: m['body'] as String,
        time: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        state: m['state'] as String,
      );
}
