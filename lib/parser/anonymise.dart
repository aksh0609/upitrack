/// Masks the parts of a bank SMS that identify a person — account digits,
/// references, UPI IDs, names — so it can be shared as a parser test case.
/// Amounts and the bank's own wording are kept, because that is what
/// `SmsParser` keys on. Pure Dart, tested in `test/parser/anonymise_test.dart`.
library;

final RegExp _vpa = RegExp(
  r'\b[a-z0-9][a-z0-9._-]+@([a-z][a-z0-9]+)\b',
  caseSensitive: false,
);

/// A Title Case or ALL CAPS word, e.g. "Rahul", "SWIGGY".
const String _word = r'(?:[A-Z][a-z]{2,}|[A-Z]{3,})';

/// Words that follow a direction word but are structure, not a name.
const String _structure = r'(?!(?:Ref|Refno|Avl|Bal|Via|Using|Thru|Through|UPI|'
    r'VPA|INR|Rs|Bank|Call|SMS|Not|Info|On|Date|Your|The|Acct|Account|Dear)\b)';

/// "To SWIGGY", "from Rahul Kumar", "at NETFLIX": the name run after a
/// direction word, stopping at punctuation, lowercase or a structure word.
final RegExp _name = RegExp(
  r'\b((?:[Tt]o|TO|[Ff]rom|FROM|[Bb]y|BY|[Aa]t|AT)\s+)'
  '($_structure$_word(?:\\s+$_structure$_word)*)',
);

final RegExp _digits = RegExp(r'\d{4,}');

/// Text just before a digit run that marks it as an amount, not an id.
final RegExp _amountPrefix = RegExp(
  r'(?:\b(?:rs|inr)\.?|₹|\b(?:debited|credited)\s+(?:by|for|with|of)?)\s*$',
  caseSensitive: false,
);

String anonymise(String body) {
  var s = body.replaceAllMapped(_vpa, (m) => 'xxxx@${m.group(1)}');
  s = s.replaceAllMapped(_name, (m) => '${m.group(1)}NAME');
  return s.replaceAllMapped(_digits, (m) {
    final start = m.start < 24 ? 0 : m.start - 24;
    final before = m.input.substring(start, m.start);
    return _amountPrefix.hasMatch(before) ? m.group(0)! : 'X' * m.group(0)!.length;
  });
}
