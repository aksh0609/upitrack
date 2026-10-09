/// Reads transactions out of bank statements and UPI app statements.
///
/// Works on plain text (extracted from a PDF) and on CSV downloads. Pure
/// Dart, tested in `test/statement_parser_test.dart`.
///
/// How PDF text is handled: each transaction starts on a line that begins
/// with a date, and may continue on the next few lines. The last two money
/// amounts in a row are usually "amount" and "running balance", so whether
/// a row is a debit or credit is worked out from how the balance changed.
/// If there's no balance column (e.g. PhonePe), DEBIT/CREDIT words are used.
library;

class StatementRow {
  const StatementRow({
    required this.date,
    required this.amountPaise,
    required this.isDebit,
    required this.narration,
    this.counterparty,
    this.ref,
  });

  /// Transaction date (and time, when the statement has one).
  final DateTime date;
  final int amountPaise;
  final bool isDebit;

  /// The statement's description text for this row.
  final String narration;
  final String? counterparty;

  /// 12-digit UPI reference, used to match the same payment from SMS.
  final String? ref;

  @override
  String toString() => 'StatementRow(${date.toIso8601String()}, '
      '${isDebit ? '-' : '+'}$amountPaise, $counterparty, ref=$ref)';
}

class StatementResult {
  const StatementResult(this.rows, this.skipped);

  final List<StatementRow> rows;

  /// Rows that looked like transactions but couldn't be read reliably.
  final int skipped;
}

class StatementParser {
  StatementParser._();

  // ------------------------------------------------------------------ dates
  static const String _mon = 'jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec';
  static const List<String> _monthNames = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  /// 03/10/26, 03-10-2026, 03.10.2026
  static final RegExp _numericDate =
      RegExp(r'(?<!\d)(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4}|\d{2})(?!\d)');

  /// 03 Oct 2026, 03-Oct-26, 03Oct26, 3 October, 2026
  static final RegExp _dayMonDate = RegExp(
    r'(?<!\d)(\d{1,2})[\s\-\/]?(' +
        _mon +
        r')[a-z]*\.?[\s\-\/,]*(\d{4}|\d{2})(?!\d)',
    caseSensitive: false,
  );

  /// Oct 03, 2026 (PhonePe, Paytm)
  static final RegExp _monDayDate = RegExp(
    r'(?<![a-z])(' + _mon + r')[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})(?!\d)',
    caseSensitive: false,
  );

  static final RegExp _serialPrefix = RegExp(r'\d{1,4}[.)]?\s+');

  static final RegExp _time =
      RegExp(r'\b(\d{1,2}):(\d{2})\s*(am|pm)\b', caseSensitive: false);

  // ---------------------------------------------------------------- amounts
  /// Amounts with exactly two decimals: 250.00, 9,750.00, 1,25,000.00.
  static final RegExp _decimalAmount =
      RegExp(r'(?<![\d.,])(\d{1,3}(?:,\d{2,3})+\.\d{2}|\d+\.\d{2})(?!\d|\.\d)');

  /// ₹250, ₹1,250.50 (UPI app statements).
  static final RegExp _rupeeAmount =
      RegExp(r'₹\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)');

  static final RegExp _openingBalance = RegExp(
    r'opening\s+balance\D{0,30}?(\d{1,3}(?:,\d{2,3})+\.\d{2}|\d+\.\d{2})',
    caseSensitive: false,
  );

  // -------------------------------------------------------------- direction
  static final RegExp _debitMark =
      RegExp(r'\b(?:dr|debit|debited|withdrawal)\b', caseSensitive: false);
  static final RegExp _creditMark =
      RegExp(r'\b(?:cr|credit|credited|deposit)\b', caseSensitive: false);

  /// Lines that end a transaction row: page headers, totals, footers.
  static final RegExp _stopLine = RegExp(
    r'(?:opening\s+balance|closing\s+balance|statement\s+(?:of|for|summary)|'
    r'page\s+\d|\btotal\b|generated\s+on|withdrawal|deposit\s+amt|'
    r'\bnarration\b|\bparticulars\b|transaction\s+details)',
    caseSensitive: false,
  );

  static final RegExp _skipRow = RegExp(
      r'opening\s+balance|closing\s+balance|\bb\/f\b|brought\s+forward',
      caseSensitive: false);

  // ----------------------------------------------------------------- payees
  static final RegExp _ref = RegExp(r'(?<!\d)\d{12}(?!\d)');
  static final RegExp _vpa = RegExp(
      r'\b[a-z0-9][a-z0-9._-]{1,}@[a-z][a-z0-9]{1,}\b',
      caseSensitive: false);
  static final RegExp _paidTo = RegExp(
    r'\b(?:paid\s+to|received\s+from|sent\s+to|money\s+sent\s+to|'
    r'money\s+received\s+from|transfer\s+to|transfer\s+from)\s+(.+?)'
    r'(?=\s+(?:debit|credit)\b|\s+transaction\b|\s+utr\b|$)',
    caseSensitive: false,
  );
  static final RegExp _ifsc =
      RegExp(r'^[a-z]{4}0[a-z0-9]{6}$', caseSensitive: false);

  /// Narration words that are never the payee.
  static const Set<String> _noise = {
    'upi',
    'dr',
    'cr',
    'p2m',
    'p2a',
    'to',
    'by',
    'transfer',
    'trf',
    'payment',
    'pay',
    'paid',
    'imps',
    'neft',
    'rtgs',
    'ach',
    'nach',
    'mmt',
    'inb',
    'ib',
    'ref',
    'txn',
    'sent',
    'from',
    'collect',
    'upiintent',
    'mob',
    'mb',
    'bil',
    'onl',
    'pos',
    'na',
    'none',
    'others',
    'other',
  };

  // ============================================================== PDF text

  /// Parses text extracted from a statement PDF.
  static StatementResult parseText(String text) {
    final blocks = _blocks(text);
    final opening = _toPaise(_openingBalance.firstMatch(text)?.group(1));

    // Pass 1: amount and running balance for each row.
    final amounts = <int?>[];
    final balances = <int?>[];
    final hints = <bool?>[];
    for (final b in blocks) {
      final body = b.text;
      if (_skipRow.hasMatch(body)) {
        // "Opening balance" style rows: no transaction, but their balance
        // anchors the arithmetic for the neighbouring row.
        final all = _decimalAmount.allMatches(_stripDates(body)).toList();
        amounts.add(null);
        balances.add(all.isEmpty ? null : _toPaise(all.last.group(1)));
        hints.add(null);
        continue;
      }
      final clean = _stripDates(body);
      final rupees = _rupeeAmount
          .allMatches(clean)
          .map((m) => _toPaise(m.group(1)))
          .whereType<int>()
          .toList();
      final values = rupees.isNotEmpty
          ? rupees
          : _decimalAmount
              .allMatches(clean)
              .map((m) => _toPaise(m.group(1)))
              .whereType<int>()
              .toList();

      int? amount;
      int? balance;
      bool? hint;
      if (values.isEmpty) {
        // no amount: not a transaction row
      } else if (rupees.isNotEmpty || values.length == 1) {
        amount = values.first;
      } else if (values.length >= 3 &&
          (values[values.length - 3] == 0) !=
              (values[values.length - 2] == 0)) {
        // Withdrawal and deposit columns, one of them 0.00.
        balance = values.last;
        if (values[values.length - 3] != 0) {
          amount = values[values.length - 3];
          hint = true;
        } else {
          amount = values[values.length - 2];
          hint = false;
        }
      } else {
        amount = values[values.length - 2];
        balance = values.last;
      }
      amounts.add(amount == 0 ? null : amount);
      balances.add(balance);
      hints.add(hint);
    }

    // Pass 2: newest-first or oldest-first? Pick whichever makes the
    // balance arithmetic work for more rows.
    final n = blocks.length;
    var forward = 0;
    var backward = 0;
    for (var i = 0; i < n; i++) {
      final amt = amounts[i];
      final bal = balances[i];
      if (amt == null || bal == null) continue;
      if (_fits(i == 0 ? opening : balances[i - 1], amt, bal) != null) {
        forward++;
      }
      if (_fits(i == n - 1 ? opening : balances[i + 1], amt, bal) != null) {
        backward++;
      }
    }
    final newestFirst = backward > forward;

    // Pass 3: decide debit/credit and build rows.
    final rows = <StatementRow>[];
    var skipped = 0;
    for (var i = 0; i < n; i++) {
      final amt = amounts[i];
      if (amt == null) continue;
      final b = blocks[i];

      bool? isDebit = hints[i];
      final bal = balances[i];
      if (isDebit == null && bal != null) {
        final prev = newestFirst
            ? (i == n - 1 ? opening : balances[i + 1])
            : (i == 0 ? opening : balances[i - 1]);
        isDebit = _fits(prev, amt, bal);
      }
      if (isDebit == null) {
        final d = _debitMark.hasMatch(b.text);
        final c = _creditMark.hasMatch(b.text);
        if (d != c) isDebit = d;
      }
      if (isDebit == null) {
        skipped++;
        continue;
      }

      final narration = _narration(b.text);
      rows.add(StatementRow(
        date: _withTime(b.date, b.text),
        amountPaise: amt,
        isDebit: isDebit,
        narration: narration,
        counterparty: counterpartyFrom(narration),
        ref: _ref.firstMatch(b.text)?.group(0),
      ));
    }
    return StatementResult(rows, skipped);
  }

  /// true = debit, false = credit, null = the numbers don't add up.
  static bool? _fits(int? previous, int amount, int balance) {
    if (previous == null) return null;
    if ((previous - amount - balance).abs() <= 1) return true;
    if ((previous + amount - balance).abs() <= 1) return false;
    return null;
  }

  static List<_Block> _blocks(String text) {
    final blocks = <_Block>[];
    _Block? current;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final d = _lineDate(line);
      if (d != null) {
        current = _Block(d.date, line.substring(d.end));
        blocks.add(current);
      } else if (_stopLine.hasMatch(line)) {
        current = null;
      } else if (current != null && current.lineCount < 6) {
        current.add(line);
      }
    }
    return blocks;
  }

  static ({DateTime date, int end})? _lineDate(String line) {
    final direct = _dateAt(line, 0);
    if (direct != null) return direct;
    final serial = _serialPrefix.matchAsPrefix(line);
    return serial == null ? null : _dateAt(line, serial.end);
  }

  static ({DateTime date, int end})? _dateAt(String s, int start) {
    for (final r in [_numericDate, _dayMonDate, _monDayDate]) {
      final m = r.matchAsPrefix(s, start);
      if (m == null) continue;
      final d = _toDate(r, m);
      if (d != null) return (date: d, end: m.end);
    }
    return null;
  }

  /// Parses a date anywhere at the start of [s]. Used for CSV cells.
  static DateTime? parseDate(String s) => _dateAt(s.trim(), 0)?.date;

  static DateTime? _toDate(RegExp r, Match m) {
    int day;
    int month;
    int year;
    if (identical(r, _numericDate)) {
      day = int.parse(m.group(1)!);
      month = int.parse(m.group(2)!);
      year = int.parse(m.group(3)!);
    } else if (identical(r, _dayMonDate)) {
      day = int.parse(m.group(1)!);
      month = _monthNames.indexOf(m.group(2)!.toLowerCase()) + 1;
      year = int.parse(m.group(3)!);
    } else {
      month = _monthNames.indexOf(m.group(1)!.toLowerCase()) + 1;
      day = int.parse(m.group(2)!);
      year = int.parse(m.group(3)!);
    }
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (year < 2000 || year > 2100) return null;
    final d = DateTime(year, month, day);
    return d.month == month && d.day == day ? d : null;
  }

  static DateTime _withTime(DateTime date, String text) {
    final m = _time.firstMatch(text);
    if (m == null) return DateTime(date.year, date.month, date.day, 12);
    var hour = int.parse(m.group(1)!) % 12;
    if (m.group(3)!.toLowerCase() == 'pm') hour += 12;
    return DateTime(
        date.year, date.month, date.day, hour, int.parse(m.group(2)!));
  }

  static String _stripDates(String s) => s
      .replaceAll(_numericDate, ' ')
      .replaceAll(_dayMonDate, ' ')
      .replaceAll(_monDayDate, ' ');

  static String _narration(String text) => _stripDates(text)
      .replaceAll(_rupeeAmount, ' ')
      .replaceAll(_decimalAmount, ' ')
      .replaceAll(_time, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // ================================================================ payees

  /// Best guess at the payee or payer from a narration like
  /// "UPI-SWIGGY-SWIGGY.STORES@AXB-UTIB0000100-427612345678-PAYMENT".
  static String? counterpartyFrom(String narration) {
    final paid = _paidTo.firstMatch(narration);
    if (paid != null) {
      final name = _cleanToken(paid.group(1)!);
      if (name != null) return name;
    }

    final vpa = _vpa.firstMatch(narration)?.group(0)?.toLowerCase();
    if (narration.contains('/') || narration.contains('-')) {
      for (final token in narration.split(RegExp(r'[\/\-]'))) {
        if (token.contains('@')) continue;
        final name = _cleanToken(token);
        if (name != null) return name;
      }
    }
    if (vpa != null) return vpa;
    // e.g. "POS 4321XXXX1234 AMAZON PAY INDIA": drop leading noise words only.
    final words = narration
        .split(' ')
        .skipWhile((w) => _noise.contains(w.toLowerCase()))
        .join(' ');
    return _cleanToken(words);
  }

  static String? _cleanToken(String raw) {
    var v = raw
        .replaceAll(RegExp(r'\b[x*]*\d[\dx*]{3,}\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    v = v.replaceAll(RegExp(r'^[\s.,:;]+|[\s.,:;]+$'), '');
    if (v.length < 3 ||
        !RegExp(r'[a-z]{3}', caseSensitive: false).hasMatch(v)) {
      return null;
    }
    if (_ifsc.hasMatch(v)) return null;
    final words = v.toLowerCase().split(' ');
    if (_noise.contains(words.first)) return null;
    if (words.contains('bank') || words.contains('ltd')) return null;
    return v.length > 40 ? v.substring(0, 40).trim() : v;
  }

  // =================================================================== CSV

  /// Parses a statement exported as CSV from net banking.
  static StatementResult parseCsv(String csv) {
    final table = _csvRows(csv);
    var header = -1;
    late _Columns cols;
    for (var i = 0; i < table.length && i < 40; i++) {
      final c = _Columns.detect(table[i]);
      if (c != null) {
        header = i;
        cols = c;
        break;
      }
    }
    if (header < 0) return const StatementResult([], 0);

    final rows = <StatementRow>[];
    var skipped = 0;
    for (final r in table.skip(header + 1)) {
      String cell(int? i) => (i != null && i < r.length) ? r[i].trim() : '';
      final date = parseDate(cell(cols.date));
      if (date == null) continue;

      final narration = cell(cols.narration);
      if (_skipRow.hasMatch(narration)) continue;
      int? amount;
      bool? isDebit;

      final debit = _money(cell(cols.debit));
      final credit = _money(cell(cols.credit));
      if (debit != null && debit > 0) {
        amount = debit;
        isDebit = true;
      } else if (credit != null && credit > 0) {
        amount = credit;
        isDebit = false;
      } else if (cols.amount != null) {
        // Single amount column: direction from a sign (Paytm: -250 / +500),
        // a Dr/Cr suffix, or a separate type column.
        final raw = cell(cols.amount).replaceAll(' ', '');
        final value = _money(raw.replaceAll(RegExp(r'^[+-]'), ''));
        amount = value;
        final type = '${cell(cols.type)} $raw'.toLowerCase();
        if (raw.startsWith('-')) {
          isDebit = true;
        } else if (raw.startsWith('+')) {
          isDebit = false;
        } else if (RegExp(r'(?:\b|\d)(?:dr|debit)\b').hasMatch(type)) {
          isDebit = true;
        } else if (RegExp(r'(?:\b|\d)(?:cr|credit)\b').hasMatch(type)) {
          isDebit = false;
        }
      }
      if (amount == null || amount <= 0 || isDebit == null) {
        skipped++;
        continue;
      }

      final refSource = '$narration ${cell(cols.ref)}';
      rows.add(StatementRow(
        date: DateTime(date.year, date.month, date.day, 12),
        amountPaise: amount,
        isDebit: isDebit,
        narration: narration,
        counterparty: counterpartyFrom(narration),
        ref: _ref.firstMatch(refSource)?.group(0),
      ));
    }
    return StatementResult(rows, skipped);
  }

  static int? _money(String raw) {
    final v = raw
        .replaceAll(RegExp(r'[₹,\s]'), '')
        .replaceAll(RegExp(r'(?:dr|cr)\.?$', caseSensitive: false), '');
    if (v.isEmpty) return null;
    return _toPaise(v);
  }

  static int? _toPaise(String? raw) {
    if (raw == null) return null;
    final value = double.tryParse(raw.replaceAll(',', ''));
    return value == null ? null : (value * 100).round();
  }

  /// Minimal CSV reader: handles quoted fields, escaped quotes and commas
  /// inside quotes.
  static List<List<String>> _csvRows(String csv) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < csv.length; i++) {
      final ch = csv[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < csv.length && csv[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        row.add(field.toString());
        field.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < csv.length && csv[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}

class _Block {
  _Block(this.date, String firstLine) : _text = StringBuffer(firstLine);

  final DateTime date;
  final StringBuffer _text;
  int lineCount = 1;

  void add(String line) {
    _text
      ..write(' ')
      ..write(line);
    lineCount++;
  }

  String get text => _text.toString();
}

/// Which CSV column holds what.
class _Columns {
  _Columns({
    required this.date,
    required this.narration,
    this.debit,
    this.credit,
    this.amount,
    this.type,
    this.ref,
  });

  final int date;
  final int narration;
  final int? debit;
  final int? credit;
  final int? amount;
  final int? type;
  final int? ref;

  static _Columns? detect(List<String> cells) {
    final h = cells.map((c) => c.trim().toLowerCase()).toList();
    int? find(bool Function(String c) test) {
      for (var i = 0; i < h.length; i++) {
        if (test(h[i])) return i;
      }
      return null;
    }

    final date = find((c) => c.contains('date') && !c.contains('value')) ??
        find((c) => c.contains('date'));
    final narration = find((c) =>
        c.contains('narration') ||
        c.contains('description') ||
        c.contains('particular') ||
        c.contains('remark') ||
        c.contains('details'));
    final debit = find((c) =>
        c.contains('withdrawal') ||
        (c.contains('debit') && !c.contains('credit')) ||
        c == 'dr');
    final credit = find((c) =>
        c.contains('deposit') ||
        (c.contains('credit') && !c.contains('debit')) ||
        c == 'cr');
    final amount = find((c) =>
        c.contains('amount') &&
        !c.contains('withdrawal') &&
        !c.contains('deposit'));
    final type =
        find((c) => c == 'type' || c.contains('dr/cr') || c.contains('cr/dr'));
    final ref = find(
        (c) => c.contains('ref') || c.contains('chq') || c.contains('utr'));

    if (date == null || narration == null) return null;
    if ((debit == null || credit == null) && amount == null) return null;
    return _Columns(
      date: date,
      narration: narration,
      debit: debit,
      credit: credit,
      amount: (debit != null && credit != null) ? null : amount,
      type: type,
      ref: ref,
    );
  }
}
