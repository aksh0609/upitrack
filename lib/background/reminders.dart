import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/recurring.dart';
import '../models/txn.dart';
import '../models/weekly.dart';
import '../util/native_bridge.dart';

/// Setting (TxnRepository.flag / meta) that turns the weekly summary and
/// bill reminders off. Unset means on.
const String kRemindersOff = 'reminders_off';

/// Android: once a week, last week's spending; and a day or two before a
/// monthly payment is due, a heads-up. Runs after the app reads SMS and from
/// the background SMS engine on every incoming SMS, which is often enough
/// without a scheduler. Markers in [NativeBridge] keep each to once.
/// ponytail: from the background, payments since the app last opened are
/// not in the database yet, so a summary sent then can come out low.
Future<void> runReminders(
    Future<List<Txn>> Function(DateTime from, DateTime to) between,
    {DateTime? now}) async {
  if (!NativeBridge.available) return;
  final today = now ?? DateTime.now();
  final txns = await between(DateTime(today.year, today.month - 6, today.day),
      DateTime(today.year, today.month, today.day + 1));

  final week = ymd(weekStart(today));
  if (await NativeBridge.get('weekly_sent') != week) {
    await NativeBridge.set('weekly_sent', week);
    // Monday to Wednesday only: on a Saturday, "last week" is stale news.
    final summary = today.weekday <= 3 ? weeklySummary(txns, today) : null;
    if (summary != null) await _show(7000, weeklyText(summary));
  }

  final sent = (await NativeBridge.get('due_sent') ?? '')
      .split('\n')
      .where((s) => s.isNotEmpty)
      .toList();
  final due = dueToRemind(findRecurring(txns, now: today), today, sent.toSet());
  if (due.isEmpty) return;
  for (final r in due) {
    await _show(7001 + r.name.hashCode % 1000, dueText(r, today));
    sent.add(dueKey(r));
  }
  // The last 50 are plenty to remember what was announced.
  await NativeBridge.set('due_sent',
      sent.skip(sent.length > 50 ? sent.length - 50 : 0).join('\n'));
}

Future<void> _show(int id, ({String title, String body}) text) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await plugin.show(
    id: id,
    title: text.title,
    body: text.body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'summaries',
        'Summaries & reminders',
        channelDescription: 'Weekly spending and bills due soon',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    ),
  );
}
