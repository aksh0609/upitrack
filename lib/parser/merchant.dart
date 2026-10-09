/// Groups messy payee strings ("SWIGGY", "swiggy.stores@axb", "Swiggy Ltd")
/// under one merchant name so spending can be totalled per merchant.
/// Pure Dart, tested in `test/parser/merchant_test.dart`.
library;

/// Keyword → merchant, checked in order so longer names win
/// ("swiggy instamart" before "swiggy", "prime video" before "amazon").
/// Adding a merchant is one line.
const List<(String, String)> merchantKeywords = [
  ('swiggy instamart', 'Swiggy Instamart'),
  ('swiggyinstamart', 'Swiggy Instamart'),
  ('instamart', 'Swiggy Instamart'),
  ('swiggy', 'Swiggy'),
  ('zomato', 'Zomato'),
  ('blinkit', 'Blinkit'),
  ('grofers', 'Blinkit'),
  ('zepto', 'Zepto'),
  ('bigbasket', 'BigBasket'),
  ('dmart', 'DMart'),
  ('jiomart', 'JioMart'),
  ('prime video', 'Prime Video'),
  ('primevideo', 'Prime Video'),
  ('amazon pay', 'Amazon'),
  ('amazonpay', 'Amazon'),
  ('amazon', 'Amazon'),
  ('amzn', 'Amazon'),
  ('flipkart', 'Flipkart'),
  ('myntra', 'Myntra'),
  ('meesho', 'Meesho'),
  ('ajio', 'Ajio'),
  ('nykaa', 'Nykaa'),
  ('croma', 'Croma'),
  ('uber', 'Uber'),
  ('olacabs', 'Ola'),
  ('ola', 'Ola'),
  ('rapido', 'Rapido'),
  ('irctc', 'IRCTC'),
  ('makemytrip', 'MakeMyTrip'),
  ('redbus', 'redBus'),
  ('netflix', 'Netflix'),
  ('jiohotstar', 'JioHotstar'),
  ('hotstar', 'JioHotstar'),
  ('spotify', 'Spotify'),
  ('bookmyshow', 'BookMyShow'),
  ('jio', 'Jio'),
  ('airtel', 'Airtel'),
  ('vodafoneidea', 'Vi'),
  ('vodafone', 'Vi'),
  ('vi', 'Vi'),
  ('bsnl', 'BSNL'),
  ('apollo', 'Apollo'),
  ('pharmeasy', 'PharmEasy'),
  ('1mg', 'Tata 1mg'),
  ('google play', 'Google Play'),
  ('googleplay', 'Google Play'),
  ('apple', 'Apple'),
];

final List<(RegExp, String)> _patterns = [
  for (final (keyword, name) in merchantKeywords)
    // Whole-word match, so 'ola' doesn't match 'bholanath'.
    (RegExp('(?<![a-z0-9])${RegExp.escape(keyword)}(?![a-z0-9])'), name),
];

/// Canonical merchant for a payee string, or null when it is not a known
/// merchant.
String? knownMerchant(String counterparty) {
  final text = counterparty.toLowerCase();
  for (final (pattern, name) in _patterns) {
    if (pattern.hasMatch(text)) return name;
  }
  return null;
}

/// The name payments are grouped under: the known merchant, else the payee
/// string trimmed with spaces collapsed (UPI IDs stay as they are).
String merchantOf(String counterparty) =>
    knownMerchant(counterparty) ??
    counterparty.trim().replaceAll(RegExp(r'\s+'), ' ');
