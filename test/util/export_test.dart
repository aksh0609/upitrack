import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/util/export.dart';

Txn t(String who, int paise, {bool debit = true, String? ref}) => Txn(
      key: '$who$paise',
      amountPaise: paise,
      isDebit: debit,
      counterparty: who,
      bank: 'HDFC Bank',
      account: '1234',
      ref: ref,
      channel: 'UPI',
      category: 'Food',
      time: DateTime(2026, 11, 3, 9, 5),
    );

void main() {
  test('CSV: header, signed rupees, quoting, and no formulas from SMS', () {
    final bytes = txnsCsv([
      t('SWIGGY', 25000, ref: '427612345678'),
      t('Acme, "Pvt" Ltd', 5200000, debit: false),
      t('=HYPERLINK("x")', 100),
    ]);
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF], reason: 'UTF-8 BOM');
    final lines = utf8.decode(bytes.sublist(3)).trim().split('\r\n');
    expect(
        lines[0], 'Date,Time,Payee,Category,Amount,Account,Type,UPI ref,Note');
    expect(lines[1],
        '2026-11-03,09:05,SWIGGY,Food,-250.00,HDFC Bank xx1234,UPI,427612345678,');
    expect(lines[2],
        startsWith('2026-11-03,09:05,"Acme, ""Pvt"" Ltd",Food,52000.00'));
    expect(lines[3], startsWith('2026-11-03,09:05,"\'=HYPERLINK(""x"")"'));
  });

  test('PDF: a real PDF file', () async {
    final bytes =
        await txnsPdf([t('SWIGGY', 25000)], 'UPI Track: November 2026');
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });
}
