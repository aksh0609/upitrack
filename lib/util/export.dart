import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/summary.dart';
import '../models/txn.dart';

final NumberFormat _rupees = NumberFormat('#,##,##0.00', 'en_IN');

String _account(Txn t) => [
      if (t.bank != null) t.bank!,
      if (t.account != null) 'xx${t.account}',
    ].join(' ');

/// Spreadsheet-ready CSV: one row per payment, amounts in rupees, negative
/// for money paid. Starts with a byte-order mark so Excel reads names right.
Uint8List txnsCsv(List<Txn> txns) {
  final rows = [
    [
      'Date',
      'Time',
      'Payee',
      'Category',
      'Amount',
      'Account',
      'Type',
      'UPI ref',
      'Note',
    ],
    for (final t in txns)
      [
        DateFormat('yyyy-MM-dd').format(t.time),
        t.hasTime ? DateFormat('HH:mm').format(t.time) : '',
        _text(t.counterparty),
        _text(t.category),
        ((t.isDebit ? -t.amountPaise : t.amountPaise) / 100).toStringAsFixed(2),
        _text(_account(t)),
        t.channel,
        _text(t.ref ?? ''),
        _text(t.note ?? ''),
      ],
  ];
  final csv = rows.map((r) => r.map(_cell).join(',')).join('\r\n');
  return Uint8List.fromList(utf8.encode('\uFEFF$csv\r\n'));
}

/// Payee names come from SMS: a leading = + - @ would make a spreadsheet
/// run them as a formula, so such text gets a leading apostrophe.
String _text(String v) => RegExp(r'^[=+\-@\t\r]').hasMatch(v) ? "'$v" : v;

String _cell(String v) =>
    RegExp(r'[",\r\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;

/// A printable table of [txns] under [title], with the period's totals.
/// ponytail: PDF's built-in Helvetica, so amounts say "Rs" (no ₹ glyph) and
/// payee names in Indian scripts don't render; embed a TTF if that matters.
Future<Uint8List> txnsPdf(List<Txn> txns, String title) async {
  final doc = PdfDocument();
  try {
    final page = doc.pages.add();
    final summary = MonthSummary.from(txns);
    page.graphics.drawString(title,
        PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold),
        bounds: const Rect.fromLTWH(0, 0, 500, 24));
    page.graphics.drawString(
        'Spent Rs ${_rupees.format(summary.spentPaise / 100)}   '
        'Received Rs ${_rupees.format(summary.receivedPaise / 100)}   '
        '${txns.length} payments',
        PdfStandardFont(PdfFontFamily.helvetica, 10),
        bounds: const Rect.fromLTWH(0, 26, 500, 16));

    final grid = PdfGrid()..columns.add(count: 5);
    grid.style = PdfGridStyle(
      font: PdfStandardFont(PdfFontFamily.helvetica, 9),
      cellPadding: PdfPaddings(left: 4, right: 4, top: 3, bottom: 3),
    );
    final header = grid.headers.add(1)[0];
    for (final (i, h)
        in ['Date', 'Payee', 'Category', 'Account', 'Amount (Rs)'].indexed) {
      header.cells[i].value = h;
    }
    header.style = PdfGridRowStyle(
        font: PdfStandardFont(PdfFontFamily.helvetica, 9,
            style: PdfFontStyle.bold));
    final right = PdfStringFormat(alignment: PdfTextAlignment.right);
    for (final t in txns) {
      final row = grid.rows.add();
      row.cells[0].value = DateFormat('d MMM y').format(t.time);
      row.cells[1].value = t.counterparty;
      row.cells[2].value = t.category;
      row.cells[3].value = _account(t);
      row.cells[4].value =
          '${t.isDebit ? '-' : '+'}${_rupees.format(t.amountPaise / 100)}';
      row.cells[4].stringFormat = right;
    }
    grid.columns[0].width = 70;
    grid.columns[4].width = 80;
    grid.draw(page: page, bounds: const Rect.fromLTWH(0, 50, 0, 0));
    return Uint8List.fromList(await doc.save());
  } finally {
    doc.dispose();
  }
}
