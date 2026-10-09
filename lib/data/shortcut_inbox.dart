export 'shortcut_inbox_stub.dart' if (dart.library.io) 'shortcut_inbox_io.dart';

/// A bank SMS handed over by the iPhone Shortcuts action.
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.date,
  });

  /// File name without the extension, unique per message. Used as the
  /// duplicate key when the SMS has no UPI reference.
  final String id;
  final String sender;
  final String body;
  final DateTime date;
}
