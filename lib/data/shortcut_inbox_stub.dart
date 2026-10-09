import 'shortcut_inbox.dart' show InboxMessage;

/// Web: no Shortcuts action and no file system, so the inbox is always
/// empty. The home screen never asks for it on web anyway (spec §4.8).
class ShortcutInbox {
  static const String folderName = '.sms_inbox';

  Future<List<InboxMessage>> pending() async => const [];

  Future<void> remove(List<InboxMessage> messages) async {}
}
