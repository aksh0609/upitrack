import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/db.dart';
import '../parser/categorizer.dart';
import '../parser/sms_parser.dart';
import 'sms_notification.dart';

/// Body of the `smsBackground` entrypoint in main.dart. Started by
/// android/.../SmsReceiver.kt when an SMS arrives while the app may be
/// closed. Shows a notification and nothing else: the inbox sync on next
/// open records the payment, so nothing is written here (spec §3.5).
Future<void> runSmsBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('upitrack/sms_bg');
  channel.setMethodCallHandler((call) async {
    if (call.method != 'sms') return null;
    final args = (call.arguments as Map).cast<String, Object?>();
    await notifyForSms(
      address: args['address'] as String? ?? '',
      body: args['body'] as String? ?? '',
    );
    return null;
  });
  // Tell Kotlin the handler is in place; it answers with the 'sms' call.
  await channel.invokeMethod<void>('ready');
}

Future<void> notifyForSms({required String address, required String body}) async {
  final parsed = SmsParser.parse(address, body);
  if (parsed == null) return;

  final rules = await _rules();
  final who = parsed.counterparty ?? 'Unknown';
  final category = Categorizer.categorizeWith(rules, who, isDebit: parsed.isDebit);
  final text = notificationText(parsed, category);

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await plugin.show(
    id: (parsed.ref ?? body).hashCode,
    title: text.title,
    body: text.body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'payments',
        'Payments',
        channelDescription: 'A payment was caught from a bank SMS',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    ),
  );
}

/// The payee→category rules, from a private read-only connection. Empty when
/// the database doesn't exist yet (an SMS before the app's first launch).
Future<Map<String, String>> _rules() async {
  final AppDb db;
  try {
    db = await AppDb.openReadOnly();
  } catch (_) {
    return const {};
  }
  try {
    return await db.rules();
  } finally {
    await db.close();
  }
}
