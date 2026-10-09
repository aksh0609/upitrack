/// One bank account seen in the SMS: the bank (may be unknown) and the last
/// digits the SMS mentioned.
typedef AccountRef = ({String? bank, String last4});

/// "HDFC •••1234", or "•••1234" when the bank is unknown.
String accountLabel(AccountRef a) {
  final bank = a.bank?.split(' ').first ?? '';
  return bank.isEmpty ? '•••${a.last4}' : '$bank •••${a.last4}';
}
