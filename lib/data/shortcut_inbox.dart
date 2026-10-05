import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A bank SMS handed over by the iPhone Shortcuts action.
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.date,
    required this.file,
  });

  /// File name, unique per message. Used as the duplicate key when the SMS
  /// has no UPI reference.
  final String id;
  final String sender;
  final String body;
  final DateTime date;
  final File file;
}

/// Reads messages written by ios/Runner/BankSmsIntent.swift.
class ShortcutInbox {
  /// Must match BankSmsInbox.folderName in the Swift file.
  static const String folderName = '.sms_inbox';

  Future<Directory> _folder() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, folderName));
  }

  Future<List<InboxMessage>> pending() async {
    final folder = await _folder();
    if (!await folder.exists()) return const [];
    final messages = <InboxMessage>[];
    await for (final entity in folder.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        messages.add(InboxMessage(
          id: p.basenameWithoutExtension(entity.path),
          sender: json['sender'] as String? ?? '',
          body: json['body'] as String? ?? '',
          date: DateTime.fromMillisecondsSinceEpoch((json['date'] as num).toInt()),
          file: entity,
        ));
      } catch (_) {
        // A half-written or corrupt file: drop it.
        await entity.delete();
      }
    }
    messages.sort((a, b) => a.date.compareTo(b.date));
    return messages;
  }

  /// Call after the messages have been stored.
  Future<void> remove(List<InboxMessage> messages) async {
    for (final m in messages) {
      if (await m.file.exists()) await m.file.delete();
    }
  }
}
