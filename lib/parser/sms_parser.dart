/// Turns Indian bank transaction SMS into structured transactions.
///
/// Every UPI payment (from PhonePe, Google Pay, Paytm, BHIM or any other app)
/// makes the *bank* send an SMS. This parser reads those bank SMS, so it works
/// no matter which UPI app was used.
///
/// The parser is pure Dart with no Flutter imports, so it is fully unit
/// tested in `test/sms_parser_test.dart`. To support a new bank format, add a
/// sample SMS to that test file first, then adjust the patterns below.
library;

/// A transaction extracted from one SMS.
class ParsedTxn {
  const ParsedTxn({
    required this.amountPaise,
    required this.isDebit,
    required this.channel,
    this.counterparty,
    this.bank,
    this.account,
    this.ref,
  });

  /// Amount in paise (₹1 = 100) to avoid floating-point rounding errors.
  final int amountPaise;

  /// true = money left your account, false = money came in.
  final bool isDebit;

  /// 'UPI', 'Card' or 'Bank'.
  final String channel;

  /// Payee for debits, payer for credits. A UPI ID or a merchant/person name.
  final String? counterparty;

  /// Bank name, e.g. 'HDFC Bank'.
  final String? bank;

  /// Last 4 digits of the account or card.
  final String? account;

  /// UPI reference number (RRN), used to avoid counting a payment twice.
  final String? ref;

  @override
  String toString() =>
      'ParsedTxn(${isDebit ? 'debit' : 'credit'} $amountPaise paise, '
      '$counterparty, $bank, $account, ref=$ref, $channel)';
}

class SmsParser {
  SmsParser._();

  // ---------------------------------------------------------------- amounts
  static final RegExp _currencyAmount = RegExp(
    r'(?:\b(?:rs|inr)\.?|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  /// SBI style: "debited by 120.0" with no currency symbol.
  static final RegExp _verbAmount = RegExp(
    r'\b(?:debited|credited)\s+(?:by|for|with|of)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b',
    caseSensitive: false,
  );

  // -------------------------------------------------------------- direction
  static final RegExp _debitWord = RegExp(
    r'\b(?:debited|sent|paid|spent|withdrawn|deducted|purchase)\b',
    caseSensitive: false,
  );
  static final RegExp _creditWord = RegExp(
    r'\b(?:credited|received|deposited|refunded|refund)\b',
    caseSensitive: false,
  );

  /// OTPs, collect requests, reminders, failed payments and promotions.
  static final RegExp _exclude = RegExp(
    r'\b(?:otp|one[\s-]?time[\s-]?password|requested|collect request|is due|'
    r'due on|due date|will be (?:debited|credited)|minimum amount|reminder|'
    r'offer|congratulations|apply now|claim now|eligible|failed|declined|'
    r'unsuccessful|is pending)\b',
    caseSensitive: false,
  );

  // ------------------------------------------------------- transaction bits
  static final RegExp _upiWord = RegExp(r'\bupi\b', caseSensitive: false);
  static final RegExp _cardWord = RegExp(r'\bcard\b', caseSensitive: false);

  static final RegExp _vpa = RegExp(
    r'\b[a-z0-9][a-z0-9._-]{1,}@[a-z][a-z0-9]{1,}\b',
    caseSensitive: false,
  );

  static final RegExp _account = RegExp(
    r'(?:a\/c|acct|account|\bac\b|\bcard\b)\s*(?:no\.?\s*)?'
    r'(?:ending\s*(?:with\s*)?)?[x*\s]*(\d{3,})',
    caseSensitive: false,
  );

  /// Axis style: "UPI/P2M/427612341111/BLINKIT".
  static final RegExp _upiPath = RegExp(
    r'upi\/[a-z0-9]{2,4}\/(\d{10,16})\/([^\/\n]+)',
    caseSensitive: false,
  );

  static final RegExp _ref = RegExp(
    r'\b(?:upi\s*ref(?:erence)?(?:\s*no)?|ref(?:erence)?\s*no|refno|ref|rrn|'
    r'utr|upi)\s*[:.#-]?\s*(\d{10,16})',
    caseSensitive: false,
  );

  /// Everything after these markers is bank boilerplate ("Not you? Call...").
  static final RegExp _footer = RegExp(
    r'(?:not you|not u\b|if not (?:you|u|done)|\bcall\s*\+?\d|sms block|'
    r'to block|for dispute|to report)',
    caseSensitive: false,
  );

  // Name terminators shared by the payee patterns below.
  static const String _stop =
      r'(?=\s+(?:on\b|ref|upi\b|via\b|avl|using\b|thru\b|through\b)|[\n;,(]|\.\s|\.$|$)';

  static final List<RegExp> _debitParty = [
    // ICICI: "...; AMAZON PAY credited."
    RegExp(r';\s*([a-z0-9][a-z0-9 &.\x27_-]{1,40}?)\s+credited',
        caseSensitive: false),
    // SBI: "trf to ZOMATO Refno ..."
    RegExp(r'\btrf\s+to\s+(.{2,40}?)' + _stop, caseSensitive: false),
    // Generic: "to SWIGGY on ..." / "at AMAZON on ..."
    RegExp(r'\b(?:to|at)\s+(?:vpa\s+)?(.{2,40}?)' + _stop,
        caseSensitive: false),
  ];

  static final List<RegExp> _creditParty = [
    RegExp(r'\b(?:from|by)\s+(?:vpa\s+)?(.{2,40}?)' + _stop,
        caseSensitive: false),
  ];

  static final RegExp _rejectName = RegExp(
    r'^(?:(?:rs|inr)\.?\s*\d|₹|ref|a\/c|ac\b|acct\b|account\b|your\b|ur\b|'
    r'the\b|you\b|date\b|card\b|bank\b)',
    caseSensitive: false,
  );

  /// Substring of the sender ID or body → display name. Checked in order.
  static const Map<String, String> _banks = {
    'HDFC': 'HDFC Bank',
    'ICICI': 'ICICI Bank',
    'SBI': 'SBI',
    'AXIS': 'Axis Bank',
    'KOTAK': 'Kotak Bank',
    'PNB': 'PNB',
    'BARODA': 'Bank of Baroda',
    'BOB': 'Bank of Baroda',
    'CANBNK': 'Canara Bank',
    'CANARA': 'Canara Bank',
    'UNIONB': 'Union Bank',
    'IDFC': 'IDFC First Bank',
    'YESB': 'Yes Bank',
    'INDUS': 'IndusInd Bank',
    'FEDBNK': 'Federal Bank',
    'FEDERAL': 'Federal Bank',
    'AUBANK': 'AU Bank',
    'IDBI': 'IDBI Bank',
    'IOB': 'Indian Overseas Bank',
    'CENTBK': 'Central Bank',
    'PAYTMB': 'Paytm Payments Bank',
    'AIRBNK': 'Airtel Payments Bank',
    'HSBC': 'HSBC',
  };

  /// Personal phone numbers can't be bank senders; ignoring them blocks
  /// people from faking transactions by texting you.
  static bool isLikelyBankSender(String address) =>
      !RegExp(r'^\+?\d{7,}$').hasMatch(address.replaceAll(' ', ''));

  /// Returns a transaction, or null if the SMS isn't a completed money movement.
  static ParsedTxn? parse(String address, String body) {
    if (body.trim().isEmpty || !isLikelyBankSender(address)) return null;
    if (_exclude.hasMatch(body)) return null;

    final isDebit = _direction(body);
    if (isDebit == null) return null;

    final amount = _amount(body);
    if (amount == null || amount <= 0) return null;

    final upiPath = _upiPath.firstMatch(body);
    final vpa = _vpa.firstMatch(body);
    final account = _accountDigits(body);
    final ref = upiPath?.group(1) ?? _ref.firstMatch(body)?.group(1);

    final isUpi = upiPath != null || vpa != null || _upiWord.hasMatch(body);
    final isCard = !isUpi && _cardWord.hasMatch(body);

    // Real bank transaction SMS always mention an account, card, UPI or a
    // reference. Promotions ("Get Rs 100 credited!") usually don't.
    if (account == null && ref == null && !isUpi && !isCard) return null;

    return ParsedTxn(
      amountPaise: amount,
      isDebit: isDebit,
      channel: isUpi ? 'UPI' : (isCard ? 'Card' : 'Bank'),
      counterparty: _counterparty(body, isDebit),
      bank: _bank(address, body),
      account: account,
      ref: ref,
    );
  }

  /// The earliest debit or credit word wins: "debited ...; X credited" is a
  /// debit, "credited ... debited from X" would be a credit.
  static bool? _direction(String body) {
    final d = _debitWord.firstMatch(body)?.start;
    final c = _creditWord.firstMatch(body)?.start;
    if (d == null && c == null) return null;
    if (c == null) return true;
    if (d == null) return false;
    return d < c;
  }

  static int? _amount(String body) {
    for (final m in _currencyAmount.allMatches(body)) {
      // Skip "Avl Bal Rs 5,000" and "Avl Lmt Rs ...".
      final before = body
          .substring(m.start < 20 ? 0 : m.start - 20, m.start)
          .toLowerCase();
      if (before.contains('bal') ||
          before.contains('lmt') ||
          before.contains('limit')) {
        continue;
      }
      return _toPaise(m.group(1)!);
    }
    final verb = _verbAmount.firstMatch(body);
    return verb == null ? null : _toPaise(verb.group(1)!);
  }

  static int? _toPaise(String raw) {
    final value = double.tryParse(raw.replaceAll(',', ''));
    return value == null ? null : (value * 100).round();
  }

  static String? _accountDigits(String body) {
    final m = _account.firstMatch(body);
    if (m == null) return null;
    final digits = m.group(1)!;
    return digits.length <= 4 ? digits : digits.substring(digits.length - 4);
  }

  static String? _bank(String address, String body) {
    final sender = address.toUpperCase();
    for (final e in _banks.entries) {
      if (sender.contains(e.key)) return e.value;
    }
    final upper = body.toUpperCase();
    for (final e in _banks.entries) {
      if (RegExp(r'\b' + e.key + r'\b').hasMatch(upper)) return e.value;
    }
    return null;
  }

  static String? _counterparty(String body, bool isDebit) {
    final footer = _footer.firstMatch(body);
    final core = footer == null ? body : body.substring(0, footer.start);

    final path = _upiPath.firstMatch(core);
    if (path != null) {
      final name = _clean(path.group(2)!);
      if (name != null) return name;
    }

    final vpa = _vpa.firstMatch(core);
    if (vpa != null) return vpa.group(0)!.toLowerCase();

    for (final pattern in isDebit ? _debitParty : _creditParty) {
      for (final m in pattern.allMatches(core)) {
        final name = _clean(m.group(1)!);
        if (name != null) return name;
      }
    }
    return null;
  }

  static String? _clean(String raw) {
    var v = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    v = v.replaceAll(RegExp(r'[\s.,;:-]+$'), '');
    if (v.length < 2) return null;
    if (!RegExp(r'^[a-z0-9]', caseSensitive: false).hasMatch(v)) return null;
    if (RegExp(r'\d{5,}').hasMatch(v)) return null;
    if (_rejectName.hasMatch(v)) return null;
    return v;
  }
}
