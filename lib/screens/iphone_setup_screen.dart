import 'package:flutter/material.dart';

/// Explains how to create the Shortcuts automation that sends bank SMS to
/// the app. iOS doesn't allow apps to create automations themselves.
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

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
                  ? 'Working: $messagesReceived messages received'
                  : 'Not set up yet'),
              subtitle: const Text(
                  'iPhones don\'t let apps read SMS. A one-time Shortcuts '
                  'automation passes each bank SMS to this app instead. It '
                  'stays on your phone.'),
            ),
          ),
          const SizedBox(height: 16),
          for (final (i, step) in _steps.indexed)
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
