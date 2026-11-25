import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/util/native_bridge.dart';

void main() {
  test('totals from the month, as the Overview counts them', () {
    Txn t(int rupees, int day, String cat) => Txn(
          key: '$rupees$day$cat',
          amountPaise: rupees * 100,
          isDebit: true,
          counterparty: 'X',
          channel: 'UPI',
          category: cat,
          time: DateTime(2026, 11, day, 10),
        );
    final w = WidgetTotals.of([
      t(250, 25, 'Food'),
      t(1000, 3, 'Travel'),
      t(5000, 25, 'Self transfer')
    ], DateTime(2026, 11, 25, 18));
    expect(w.toJson(), {
      'day': '2026-11-25',
      'month': '2026-11',
      'today': 25000,
      'total': 125000
    });
  });

  test('a background payment adds up, and starts over on a new day or month',
      () {
    final w = WidgetTotals(
        day: DateTime(2026, 11, 25), todayPaise: 25000, monthPaise: 125000);
    final same = w.add(10000, DateTime(2026, 11, 25, 21));
    expect((same.todayPaise, same.monthPaise), (35000, 135000));
    final tomorrow = w.add(10000, DateTime(2026, 11, 26, 8));
    expect((tomorrow.todayPaise, tomorrow.monthPaise), (10000, 135000));
    final december = w.add(10000, DateTime(2026, 12, 1, 8));
    expect((december.todayPaise, december.monthPaise), (10000, 10000));
  });

  test('JSON round trip; junk reads as nothing', () {
    final w =
        WidgetTotals(day: DateTime(2026, 11, 25), todayPaise: 1, monthPaise: 2);
    final back = WidgetTotals.fromJson('{"day":"2026-11-25","month":"2026-11",'
        '"today":1,"total":2}')!;
    expect(back.toJson(), w.toJson());
    expect(WidgetTotals.fromJson('nope'), isNull);
    expect(WidgetTotals.fromJson(null), isNull);
  });
}
