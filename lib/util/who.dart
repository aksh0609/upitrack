import '../models/txn.dart';
import '../parser/categorizer.dart';

/// The chip row on the home screen: who the money went to.
enum Who {
  all('All'),
  merchants('Merchants'),
  people('People'),
  giftCards('Gift cards');

  const Who(this.label);
  final String label;
}

/// [Who.people] is anyone [Categorizer.isPerson] recognises (a personal UPI
/// handle or a plain name like "ABISHEK KUMAR"), whatever category the
/// payment ended up in, plus anything filed under Transfers.
/// [Who.merchants] is every other payment out: shops, apps, bills, unknown
/// QR codes. A payment the user filed under Gift cards shows only there;
/// self transfers show only under [Who.all].
bool matchesWho(Txn t, Who who) {
  final c = t.category;
  if (who == Who.all) return true;
  if (who == Who.giftCards) return c == Categorizer.giftCards;
  if (c == Categorizer.selfTransfer || c == Categorizer.giftCards) {
    return false;
  }
  final person =
      c == Categorizer.transfers || Categorizer.isPerson(t.counterparty);
  return who == Who.people ? person : t.isDebit && !person;
}
