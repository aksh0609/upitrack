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

/// [Who.merchants] is every payment to a business (shops, apps, bills).
/// [Who.people] is money sent to, or received from, a personal UPI handle.
/// Self transfers only show under [Who.all].
bool matchesWho(Txn t, Who who) => switch (who) {
      Who.all => true,
      Who.giftCards => t.category == Categorizer.giftCards,
      Who.people => t.category == Categorizer.transfers ||
          (!t.isDebit && Categorizer.isPerson(t.counterparty)),
      Who.merchants => t.isDebit &&
          t.category != Categorizer.transfers &&
          t.category != Categorizer.selfTransfer &&
          t.category != Categorizer.giftCards,
    };
