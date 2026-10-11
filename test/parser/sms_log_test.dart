import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/parser/sms_log.dart';

void main() {
  group('SmsLog.parse', () {
    test('one entry per timestamped line; other lines continue the body', () {
      const log = '2026-10-03T09:15:30+05:30 Sent Rs.250.00\n'
          'From HDFC Bank A/C *1234\n'
          'To SWIGGY\n'
          '\n'
          '2026-10-04 Dear SBI UPI User, ur A/cX5678 debited by Rs120\r\n';
      final r = SmsLog.parse(log);
      expect(r.undated, 0);
      expect(r.messages, hasLength(2));
      final first = r.messages.first;
      expect(first.date.toUtc(), DateTime.utc(2026, 10, 3, 3, 45, 30));
      expect(first.body, 'Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY');
      expect(first.sender, '');
      expect(r.messages.last.date, DateTime(2026, 10, 4));
      expect(r.messages.last.body,
          'Dear SBI UPI User, ur A/cX5678 debited by Rs120');
    });

    test('ids depend only on time and text', () {
      String inboxId(String log) => SmsLog.parse(log).messages.single.id;
      final a = inboxId('2026-10-03T09:15:30+05:30 Sent Rs.250.00');
      final b = inboxId('2026-10-03T09:15:30+05:30 Sent Rs.250.00');
      final c = inboxId('2026-10-03T09:15:31+05:30 Sent Rs.250.00');
      final d = inboxId('2026-10-03T09:15:30+05:30 Sent Rs.250.01');
      expect(a, b);
      expect(a, isNot(c));
      expect(a, isNot(d));
      expect(a, matches(RegExp(r'^[0-9a-f]{1,8}$')));
    });

    test('lines before the first timestamp are counted, not imported', () {
      final r = SmsLog.parse(
          'Sent Rs.250.00\nTo SWIGGY\n\n2026-10-03T09:15:30Z Sent Rs.10.00');
      expect(r.undated, 2);
      expect(r.messages.map((m) => m.body), ['Sent Rs.10.00']);
    });

    test('a timestamp with no text after it is dropped', () {
      expect(SmsLog.parse('2026-10-03T09:15:30Z\n\n').messages, isEmpty);
    });

    test('a statement CSV is not a log', () {
      final r = SmsLog.parse(
          'Date,Narration,Withdrawal\n03/10/26,UPI-SWIGGY,250.00\n');
      expect(r.messages, isEmpty);
      expect(r.undated, 2);
    });

    test('separators after the timestamp are tolerated', () {
      for (final sep in [' ', ', ', ' - ', '\t', '|']) {
        final r = SmsLog.parse('2026-10-03T09:15:30Z${sep}Sent Rs.10.00');
        expect(r.messages.single.body, 'Sent Rs.10.00', reason: 'sep "$sep"');
      }
    });
  });
}
