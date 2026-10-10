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

/// Transfers is a person. Food, Shopping, Travel and the other spending
/// categories are merchants, whether the parser or the user picked them.
/// Others and Income decide by the payee: a person unless
/// [Categorizer.isBusiness] recognises a business.
bool _isPerson(Txn t) => switch (t.category) {
      Categorizer.transfers => true,
      Categorizer.others ||
      Categorizer.income =>
        Categorizer.isPerson(t.counterparty),
      _ => false,
    };

/// A payment filed under Gift cards shows only there; self transfers show
/// only under [Who.all]. [Who.merchants] is money out, [Who.people] both
/// directions.
bool matchesWho(Txn t, Who who) {
  final c = t.category;
  return switch (who) {
    Who.all => true,
    Who.giftCards => c == Categorizer.giftCards,
    Who.people => c != Categorizer.selfTransfer &&
        c != Categorizer.giftCards &&
        _isPerson(t),
    Who.merchants => t.isDebit &&
        c != Categorizer.selfTransfer &&
        c != Categorizer.giftCards &&
        !_isPerson(t),
  };
}
