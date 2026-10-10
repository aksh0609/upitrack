import 'merchant.dart';

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

  /// A word that marks a payee as a business, not a person.
  static const Set<String> businessWords = {
    // Legal and generic
    'ltd', 'limited', 'pvt', 'private', 'llp', 'inc', 'corp', 'co', 'company',
    'enterprise', 'enterprises', 'traders', 'trading', 'industries', 'agency',
    'agencies', 'associates', 'international', 'india', 'global', 'group',
    'ventures', 'solutions', 'services', 'service', 'systems', 'technologies',
    'technology', 'tech', 'digital', 'online', 'app', 'apps', 'and', 'sons',
    'brothers', 'bros', 'unknown', 'merchant', 'merchants', 'business',
    // Shops
    'store', 'stores', 'shop', 'shoppe', 'mart', 'supermarket', 'hypermarket',
    'bazaar', 'bazar', 'market', 'mall', 'plaza', 'retail', 'sales',
    'kirana', 'general', 'provision', 'provisions', 'dairy', 'collection',
    'collections', 'textiles', 'garments', 'fashion', 'fashions', 'boutique',
    'jewellers', 'jewellery', 'furniture', 'hardware', 'stationery', 'books',
    'electronics', 'mobiles', 'mobile', 'computers', 'optical', 'opticals',
    // Food and drink
    'foods', 'food', 'restaurant', 'cafe', 'hotel', 'hotels', 'dhaba',
    'sweets', 'bakery', 'bakers', 'confectionery', 'tea', 'chai', 'stall',
    'juice', 'pizza', 'burger', 'biryani', 'canteen', 'mess', 'tiffin',
    'caterers', 'catering', 'wala', 'wale',
    // Travel, fuel, transport
    'travels', 'tours', 'cabs', 'cab', 'taxi', 'rentals', 'logistics',
    'courier', 'cargo', 'transport', 'transports', 'petrol', 'petroleum',
    'fuel', 'fuels', 'filling', 'station', 'pump', 'pumps', 'motors', 'auto',
    'automobiles', 'garage', 'tyres', 'spares', 'parking', 'toll', 'metro',
    'railway', 'railways', 'airlines', 'airways',
    // Health, education, services
    'medical', 'medicals', 'pharma', 'pharmacy', 'clinic', 'hospital',
    'diagnostics', 'labs', 'lab', 'dental', 'care', 'academy', 'school',
    'college', 'university', 'institute', 'classes', 'coaching', 'tutorials',
    'fitness', 'gym', 'salon', 'parlour', 'spa', 'beauty', 'tailors',
    'cleaners', 'laundry', 'repair', 'repairs', 'workshop', 'studio',
    'cinema', 'cinemas', 'theatre', 'club', 'resort', 'resorts', 'lodge',
    'inn', 'hostel', 'builders', 'constructions', 'developers', 'properties',
    'realty', 'infra', 'consultancy', 'consultants',
    // Money, bills, institutions
    'payments', 'pay', 'payroll', 'bank', 'finance', 'financial',
    'insurance', 'fund', 'nidhi', 'capital', 'investments', 'securities',
    'broking', 'loans', 'credit', 'wallet', 'recharge', 'recharges', 'bills',
    'bill', 'utility', 'utilities', 'electricity', 'board', 'gas',
    'broadband', 'dth', 'cable', 'telecom', 'communications', 'municipal',
    'corporation', 'nigam', 'department', 'govt', 'government', 'trust',
    'society', 'foundation', 'samiti', 'sangh', 'welfare', 'charitable',
    'temple', 'mandir', 'church', 'masjid', 'gurudwara',
  };

  /// Merchant QR handles: PhonePe/Paytm/BharatPe business codes carry a
  /// run of digits that is not a phone number, or an @okbiz… domain.
  static final RegExp _merchantVpa = RegExp(
      r'^(?:(?!\d{10}@)[^@]*\d{3,}[^@]*@|[^@]*(?:qr|merchant|store|stores|shop|pay)[^@]*@|.+@okbiz)');

  /// True for a business: a known brand, a word from a spending category
  /// (swiggy, uber, hospital…), a business word (ltd, traders, kirana…), or
  /// a merchant QR handle. Personal UPI handles are never businesses.
  static bool isBusiness(String counterparty) {
    final text = counterparty.toLowerCase().trim();
    if (_personVpa.hasMatch(text)) return false;
    if (knownMerchant(text) != null) return true;
    if (_patterns.values.any((ps) => ps.any((p) => p.hasMatch(text)))) {
      return true;
    }
    final words = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim().split(' ');
    if (words.any(businessWords.contains)) return true;
    return _merchantVpa.hasMatch(text);
  }

  /// A person is whoever is not a business: banks report payees by name
  /// ("ABISHEK KUMAR", "Pramod") or by personal handle ("9876543210@ybl").
  static bool isPerson(String counterparty) => !isBusiness(counterparty);

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
