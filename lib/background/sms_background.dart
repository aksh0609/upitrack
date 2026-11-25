import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/db.dart';
import '../models/summary.dart';
import '../util/native_bridge.dart';
import 'reminders.dart';
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
    try {
      await notifyForSms(
        address: args['address'] as String? ?? '',
        body: args['body'] as String? ?? '',
      );
    } finally {
      // Any SMS, bank or not, is a chance to send what is due.
      await _remind();
    }
    return null;
  });
  // Tell Kotlin the handler is in place; it answers with the 'sms' call.
  await channel.invokeMethod<void>('ready');
}

Future<void> notifyForSms(
    {required String address, required String body}) async {
  final parsed = SmsParser.parse(address, body);
  if (parsed == null) return;

  final ctx = await _context();
  final who = parsed.counterparty ?? 'Unknown';
  final category =
      Categorizer.categorizeWith(ctx.rules, who, isDebit: parsed.isDebit);
  final text = notificationText(parsed, category,
      budget: parsed.isDebit
          ? budgetNote(ctx.budgets, ctx.month, category, parsed.amountPaise)
          : null);

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

  // The home-screen widget counts it now; the app's next load recounts
  // from the database, so nothing is counted twice.
  if (parsed.isDebit && Categorizer.countsAsSpending(category)) {
    final now = DateTime.now();
    final month = ctx.month;
    final base =
        WidgetTotals.fromJson(await NativeBridge.get(WidgetTotals.key)) ??
            WidgetTotals(
                day: now,
                todayPaise: month?.todaySpentPaise ?? 0,
                monthPaise: month?.spentPaise ?? 0);
    await NativeBridge.widget(base.add(parsed.amountPaise, now));
  }
}

/// The weekly summary and bill reminders, from a read-only connection.
Future<void> _remind() async {
  final AppDb db;
  try {
    db = await AppDb.openReadOnly();
  } catch (_) {
    return;
  }
  try {
    if (await db.getMeta(kRemindersOff) == '1') return;
    await runReminders(db.between);
  } catch (_) {
    // Best effort; the app's next sync tries again.
  } finally {
    await db.close();
  }
}

/// The payee→category rules, budgets and this month's totals, from a
/// private read-only connection. Empty when the database doesn't exist yet
/// (an SMS before the app's first launch).
/// ponytail: the month is as of the app's last SMS sync, so payments caught
/// since then are missing from the budget line until the app is opened.
Future<
    ({
      Map<String, String> rules,
      Map<String, int> budgets,
      MonthSummary? month
    })> _context() async {
  final AppDb db;
  try {
    db = await AppDb.openReadOnly();
  } catch (_) {
    return (
      rules: const <String, String>{},
      budgets: const <String, int>{},
      month: null
    );
  }
  try {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final budgets = await db.budgets();
    return (
      rules: await db.rules(),
      budgets: budgets,
      month: MonthSummary.from(await db.between(start, now)),
    );
  } finally {
    await db.close();
  }
}
