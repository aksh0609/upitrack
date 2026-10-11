import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Explains how to create the Shortcuts automation that sends bank SMS to
/// the app. iOS doesn't allow apps to create automations themselves. The
/// native app receives them through its "Log Bank SMS" action; the web app
/// has no actions, so there the automation appends each SMS to a text file
/// that the user imports.
class IphoneSetupScreen extends StatelessWidget {
  const IphoneSetupScreen({super.key, required this.messagesReceived});

  final int messagesReceived;

  static const List<(String, String)> _steps = [
    (
      'Open Shortcuts',
      'Open the Shortcuts app, go to the Automation tab and tap + '
          '(or New Automation).',
    ),
    (
      'Pick "Message"',
      'Choose Message. Under "Message Contains" type Rs. Most bank SMS '
          'include it. If your bank writes amounts as INR, make a second '
          'automation the same way with INR.',
    ),
    (
      'Run it silently',
      'Choose "Run Immediately" and turn off "Notify When Run", then tap Next.',
    ),
    (
      'Add the UPI Track action',
      'Tap "New Blank Automation", then Add Action. Search for UPI Track and '
          'choose "Log Bank SMS".',
    ),
    (
      'Pass the message in',
      'Tap the Message field and choose "Shortcut Input". Optionally tap Sender '
          'and choose Shortcut Input → Sender. Tap Done.',
    ),
    (
      "You're set",
      'From now on every bank SMS is handed to UPI Track and appears the next '
          'time you open the app. Other messages containing "Rs" are ignored. '
          'For older payments, use Import statement.',
    ),
  ];

  static const List<(String, String)> _webSteps = [
    (
      'Open Shortcuts',
      'Open the Shortcuts app, go to the Automation tab and tap + '
          '(or New Automation).',
    ),
    (
      'Pick "Message"',
      'Choose Message. Under "Message Contains" type Rs. Most bank SMS '
          'include it. If your bank writes amounts as INR, make a second '
          'automation the same way with INR.',
    ),
    (
      'Run it silently',
      'Choose "Run Immediately" and turn off "Notify When Run", then tap Next.',
    ),
    (
      'Add "Append to Text File"',
      'Tap "New Blank Automation", then Add Action. Search for "Append to '
          'Text File" and choose it. Leave Service on iCloud Drive and tap '
          'File Path to type: UPI Track/sms-log.txt',
    ),
    (
      'Put the date and the message in',
      'Tap the text field above the file path. Insert the "Current Date" '
          'variable, tap it and set Date Format to ISO 8601 with "Include ISO '
          '8601 Time" on. Type a space, then insert "Shortcut Input". Make '
          'sure "Make New Line" stays on, then tap Done.',
    ),
    (
      'Import the log now and then',
      'Every bank SMS is appended to the file. When you open UPI Track, use '
          'menu → Import file and pick sms-log.txt (Browse → iCloud Drive → '
          'Shortcuts → UPI Track). Messages already imported are skipped, so '
          'import the same file as often as you like. For older payments, '
          'import a statement.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final steps = kIsWeb ? _webSteps : _steps;

    return Scaffold(
      appBar: AppBar(title: const Text('iPhone auto-tracking')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            elevation: 0,
            color: messagesReceived > 0
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            child: ListTile(
              leading: Icon(messagesReceived > 0
                  ? Icons.check_circle
                  : Icons.info_outline),
              title: Text(messagesReceived > 0
                  ? (kIsWeb
                      ? 'Working: $messagesReceived bank messages imported'
                      : 'Working: $messagesReceived messages received')
                  : 'Not set up yet'),
              subtitle: Text(kIsWeb
                  ? 'iPhones don\'t let apps read SMS. A one-time Shortcuts '
                      'automation saves each bank SMS to a text file in your '
                      'iCloud Drive; you import that file here. Nothing else '
                      'sees it.'
                  : 'iPhones don\'t let apps read SMS. A one-time Shortcuts '
                      'automation passes each bank SMS to this app instead. It '
                      'stays on your phone.'),
            ),
          ),
          const SizedBox(height: 16),
          for (final (i, step) in steps.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: scheme.primary,
                    child: Text('${i + 1}',
                        style:
                            text.labelLarge?.copyWith(color: scheme.onPrimary)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(step.$1, style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text(step.$2, style: text.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Menu names can differ slightly between iOS versions. Needs iOS 17 '
            'or later for automations that run without asking.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
