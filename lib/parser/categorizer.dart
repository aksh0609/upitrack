/// Guesses a spending category from the payee name or UPI ID.
///
/// The user can always change it in the app, and that choice is remembered
/// for the same payee, so this only needs to be a good first guess.
class Categorizer {
  Categorizer._();

  static const String income = 'Income';
  static const String transfers = 'Transfers';
  static const String giftCards = 'Gift cards';

  /// Money moved between the user's own accounts. Never guessed here; only
  /// TxnRepository's pairing assigns it (spec §3.3).
  static const String selfTransfer = 'Self transfer';
  static const String others = 'Others';

  /// Checked top to bottom, so put more specific words first
  /// (e.g. "prime video" before "amazon").
  static const Map<String, List<String>> keywords = {
    // First, so "amazon gift card" is a gift card and not Shopping.
    'Gift cards': [
      'gift',
      'giftcard',
      'giftcards',
      'egift',
      'egiftcard',
      'e-gift',
      'woohoo',
      'qwikcilver',
      'gyftr',
      'vouchagram',
      'zingoy',
      'giftease',
    ],
    'Food': [
      'swiggy',
      'zomato',
      'eatsure',
      'dominos',
      'domino',
      'mcdonald',
      'mcdonalds',
      'kfc',
      'pizza',
      'burger',
      'cafe',
      'restaurant',
      'dhaba',
      'bakery',
      'starbucks',
      'chai',
      'haldiram',
      'food',
    ],
    'Groceries': [
      'blinkit',
      'zepto',
      'bigbasket',
      'instamart',
      'dmart',
      'jiomart',
      'grofers',
      'grocery',
      'kirana',
      'supermarket',
      'reliance fresh',
      'milk',
      'dairy',
    ],
    'Entertainment': [
      'netflix',
      'hotstar',
      'jiocinema',
      'jiohotstar',
      'spotify',
      'prime video',
      'primevideo',
      'bookmyshow',
      'pvr',
      'inox',
      'youtube',
      'sonyliv',
      'zee5',
      'gaana',
    ],
    'Shopping': [
      'amazon',
      'flipkart',
      'myntra',
      'meesho',
      'ajio',
      'nykaa',
      'tatacliq',
      'croma',
      'decathlon',
      'lenskart',
      'snapdeal',
      'shop',
      'store',
      'mart',
    ],
    'Travel': [
      'uber',
      'ola',
      'olacabs',
      'rapido',
      'irctc',
      'makemytrip',
      'goibibo',
      'redbus',
      'indigo',
      'airindia',
      'akasa',
      'metro',
      'fastag',
      'yatra',
      'cleartrip',
      'ixigo',
    ],
    'Fuel': [
      'petrol',
      'diesel',
      'fuel',
      'hpcl',
      'bpcl',
      'iocl',
      'indianoil',
      'indian oil',
      'nayara',
      'filling station',
      'petroleum',
    ],
    'Bills & Recharge': [
      'jio',
      'airtel',
      'vodafone',
      'vodafoneidea',
      'bsnl',
      'recharge',
      'electricity',
      'power',
      'bescom',
      'hpseb',
      'tata power',
      'water',
      'gas',
      'broadband',
      'fibernet',
      'dth',
      'tatasky',
      'tata play',
      'bill',
      'billdesk',
      'lic',
      'insurance',
      'postpaid',
      'prepaid',
    ],
    'Health': [
      'pharmacy',
      'pharma',
      'apollo',
      'medplus',
      '1mg',
      'pharmeasy',
      'netmeds',
      'hospital',
      'clinic',
      'diagnostic',
      'diagnostics',
      'lab',
      'doctor',
      'medical',
      'medicos',
      'chemist',
    ],
    'Education': [
      'school',
      'college',
      'university',
      'udemy',
      'coursera',
      'byjus',
      'unacademy',
      'fees',
      'tuition',
    ],
  };

  static final Map<String, List<RegExp>> _patterns = {
    for (final e in keywords.entries)
      e.key: [
        for (final k in e.value)
          // Whole-word match, so 'ola' doesn't match 'bholanath'.
          RegExp('(?<![a-z0-9])${RegExp.escape(k)}(?![a-z0-9])'),
      ],
  };

  /// Personal UPI IDs: phone-number handles and Google Pay personal handles.
  /// (Google Pay merchant handles are @okbiz..., so they don't match.)
  static final RegExp _personVpa =
      RegExp(r'^(?:\d{10}@|.+@ok(?:axis|icici|sbi|hdfcbank)$)');

  /// True for a personal UPI handle rather than a business.
  static bool isPerson(String counterparty) =>
      _personVpa.hasMatch(counterparty.toLowerCase());

  static String categorize(String counterparty, {required bool isDebit}) {
    if (!isDebit) return income;
    final text = counterparty.toLowerCase();
    for (final e in _patterns.entries) {
      if (e.value.any((p) => p.hasMatch(text))) return e.key;
    }
    if (isPerson(text)) return transfers;
    return others;
  }

  /// The user's remembered choice for this payee, else the keyword guess.
  /// Rules only apply to money going out.
  static String categorizeWith(
    Map<String, String> rules,
    String counterparty, {
    required bool isDebit,
  }) =>
      (isDebit ? rules[counterparty] : null) ??
      categorize(counterparty, isDebit: isDebit);
}
