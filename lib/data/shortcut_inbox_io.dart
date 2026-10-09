import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'shortcut_inbox.dart' show InboxMessage;

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
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        messages.add(InboxMessage(
          id: p.basenameWithoutExtension(entity.path),
          sender: json['sender'] as String? ?? '',
          body: json['body'] as String? ?? '',
          date: DateTime.fromMillisecondsSinceEpoch(
              (json['date'] as num).toInt()),
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
    final folder = await _folder();
    for (final m in messages) {
      final file = File(p.join(folder.path, '${m.id}.json'));
      if (await file.exists()) await file.delete();
    }
  }
}
