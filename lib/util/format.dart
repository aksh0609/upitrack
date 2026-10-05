import 'package:intl/intl.dart';

final NumberFormat _whole =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final NumberFormat _exact =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// 150000 → "₹1,500", 12345 → "₹123.45". Uses Indian digit grouping.
String formatPaise(int paise) =>
    (paise % 100 == 0 ? _whole : _exact).format(paise / 100);

String dayLabel(DateTime day, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  final diff = t.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('EEE, d MMM').format(day);
}
