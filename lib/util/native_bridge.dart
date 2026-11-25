import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/summary.dart';
import '../models/txn.dart';

/// Android's small key-value store and home-screen widget
/// (android/.../NativeBridge.kt), reachable from the app and from the
/// background SMS engine, which can't write the database. Does nothing on
/// iPhone, the web, or when the platform side is missing (tests).
class NativeBridge {
  NativeBridge._();

  static const MethodChannel _channel = MethodChannel('upitrack/native');

  static bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<String?> get(String key) async {
    if (!available) return null;
    try {
      return await _channel.invokeMethod<String>('get', {'key': key});
    } on Exception {
      return null;
    }
  }

  static Future<void> set(String key, String value) =>
      _call('set', {'key': key, 'value': value});

  /// The widget's totals; the stored copy is read back with [get]
  /// ([WidgetTotals.key]).
  static Future<void> widget(WidgetTotals totals) =>
      _call('widget', {'state': jsonEncode(totals.toJson())});

  static Future<void> _call(String method, Map<String, String> args) async {
    if (!available) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on Exception {
      // No widget or store here; nothing to keep up to date.
    }
  }
}

/// What the home-screen widget shows: spending today and this month, as
/// of [day].
class WidgetTotals {
  const WidgetTotals(
      {required this.day, required this.todayPaise, required this.monthPaise});

  /// Where NativeBridge keeps the JSON; SpendWidget.kt reads the same key.
  static const String key = 'widget';

  final DateTime day;
  final int todayPaise;
  final int monthPaise;

  /// From the current month's payments (self transfers and loans left out,
  /// as on the Overview).
  factory WidgetTotals.of(List<Txn> month, DateTime now) {
    final s = MonthSummary.from(month, now: now);
    return WidgetTotals(
        day: now, todayPaise: s.todaySpentPaise, monthPaise: s.spentPaise);
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, Object> toJson() => {
        'day': _ymd(day),
        'month': _ymd(day).substring(0, 7),
        'today': todayPaise,
        'total': monthPaise,
      };

  static WidgetTotals? fromJson(String? json) {
    if (json == null) return null;
    try {
      final m = jsonDecode(json) as Map<String, Object?>;
      return WidgetTotals(
        day: DateTime.parse(m['day']! as String),
        todayPaise: (m['today']! as num).toInt(),
        monthPaise: (m['total']! as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// With a payment of [paise] caught at [at] added; a new day starts today
  /// at zero, a new month the month too.
  WidgetTotals add(int paise, DateTime at) {
    final sameMonth = at.year == day.year && at.month == day.month;
    final sameDay = sameMonth && at.day == day.day;
    return WidgetTotals(
      day: at,
      todayPaise: (sameDay ? todayPaise : 0) + paise,
      monthPaise: (sameMonth ? monthPaise : 0) + paise,
    );
  }
}
