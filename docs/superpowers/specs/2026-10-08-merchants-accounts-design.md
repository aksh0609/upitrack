# UPI Track Phase 1b — merchants and multiple accounts

Date: 2026-10-08
Status: approved design, awaiting implementation plan
Order: after PR #1 (Phase 1) merges, before Phase 2 (Drive sync + web) in
`2026-10-07-upitrack-v2-design.md`.

## 1. Goal

Plain English: answer "how much did I spend at Amazon?" and "which bank did
this come from?" without any setup. Payees are grouped into merchants with a
total per merchant; payments can be searched by name; each bank account the
SMS mention becomes a filter chip; and moving money between your own accounts
stops counting as spending.

### In scope

- Merchant names: group messy payee strings ("SWIGGY", "swiggy.stores@axb",
  "Swiggy Limited") under one merchant.
- Top merchants on the home screen, a merchant screen with a six-month view,
  and a search box.
- Account chips (discovered from SMS) that filter the whole month view.
- Self-transfer detection: a debit from one of your accounts and a credit into
  another on the same day for the same amount, excluded from totals.

### Out of scope

- Separate per-bank dashboards, manual account setup, merchant logos.
- Reading the account number out of a statement PDF/CSV (statement rows have
  no account; they appear under "All").
- Refund detection and budgets (Phase 3).
- Any schema change. Everything here is computed from existing columns.

## 2. Merchants

### 2.1 Merchant names (`lib/parser/merchant.dart`, pure Dart, tested)

```dart
/// Canonical merchant for a payee string, or null when it is not a known
/// merchant.
String? knownMerchant(String counterparty);

/// The name payments are grouped under: the known merchant, else the
/// payee string trimmed with spaces collapsed (UPI IDs stay as they are).
String merchantOf(String counterparty);
```

Matching is whole-word and case-insensitive, like `Categorizer`, on an
ordered list so longer names win ("swiggy instamart" before "swiggy",
"prime video" before "amazon"):

| Keyword(s) | Merchant |
| --- | --- |
| swiggy instamart, instamart | Swiggy Instamart |
| swiggy | Swiggy |
| zomato | Zomato |
| blinkit, grofers | Blinkit |
| zepto | Zepto |
| bigbasket | BigBasket |
| dmart | DMart |
| jiomart | JioMart |
| prime video, primevideo | Prime Video |
| amazon, amzn | Amazon |
| flipkart | Flipkart |
| myntra | Myntra |
| meesho | Meesho |
| ajio | Ajio |
| nykaa | Nykaa |
| croma | Croma |
| uber | Uber |
| ola, olacabs | Ola |
| rapido | Rapido |
| irctc | IRCTC |
| makemytrip | MakeMyTrip |
| redbus | redBus |
| netflix | Netflix |
| hotstar, jiohotstar | JioHotstar |
| spotify | Spotify |
| bookmyshow | BookMyShow |
| jio | Jio |
| airtel | Airtel |
| vodafone, vodafoneidea, vi | Vi |
| bsnl | BSNL |
| apollo | Apollo |
| pharmeasy | PharmEasy |
| 1mg | Tata 1mg |
| google play, googleplay | Google Play |
| apple | Apple |

The table is a `const List<(String, String)>` so adding a merchant is one
line. Tested: each keyword maps; "bholanath sweets" is not Ola; an unknown
payee passes through unchanged; `swiggy.stores@axb` → Swiggy.

### 2.2 Totals (`MonthSummary`)

`MonthSummary` gains

```dart
/// Spending per merchant, largest first: merchant → (count, total paise).
final Map<String, ({int count, int totalPaise})> byMerchant;
```

built from debits only, excluding category `Self transfer` (§3.3). The
existing `spentPaise`, `receivedPaise`, `todaySpentPaise` and `byCategory`
also exclude `Self transfer`. Tested alongside the existing summary test.

### 2.3 Home screen

Under "Where it went": a **Top merchants** block — the five largest
`byMerchant` entries as rows (name, "3 payments", total, bar scaled to the
largest), then a "See all" link when there are more than five. Tapping a row
opens the merchant screen. The block is hidden when `byMerchant` is empty.
Rows reuse the look of `CategoryBars` with a generic storefront icon; the
widget is `MerchantBars` in `lib/widgets/merchant_bars.dart` (a sibling of
`CategoryBars`, not a generalisation of it).

### 2.4 Merchant screen (`lib/screens/merchant_screen.dart`)

Opened with a merchant name and the month on screen.

- Header: merchant name, this month's total and count.
- **Last 6 months**: one bar per calendar month ending with the month on
  screen, labelled "May", "Jun", … with the amount; data from
  `repository.between(firstOfMonth - 5 months, firstOfNextMonth)` filtered by
  `merchantOf(t.counterparty) == merchant`, debits only, excluding
  `Self transfer`.
- **Category**: a chip row like the detail sheet. Choosing one calls
  `repository.setCategory(t, category, forPayee: true)` for one transaction
  per distinct `counterparty` in the merchant's six-month set, so the rule
  covers every payee string that maps to the merchant.
- **Payments**: every payment to the merchant in the six-month window,
  grouped by day with the existing `TxnTile`; tap opens the existing detail
  sheet. Returns to the home screen with a reload.

"See all" opens `MerchantsScreen` (`lib/screens/merchants_screen.dart`): the
full `byMerchant` list for the month, same rows, same tap behaviour.

### 2.5 Search

A search icon in the app bar toggles a text field above the Transactions
header. The list (and the summary card, category and merchant blocks) is
filtered to transactions where `merchantOf(counterparty)` or `counterparty`
contains the query, case-insensitive. Pure helper, tested:

```dart
bool matchesSearch(Txn t, String query);
```

Search is within the month on screen; clearing the field restores the full
month. Cross-month search is a later feature.

## 3. Multiple accounts

### 3.1 Discovery

```dart
/// One bank account seen in the SMS: ('HDFC Bank', '1234'). Bank may be
/// null when the SMS named only the account.
typedef AccountRef = ({String? bank, String last4});

Future<List<AccountRef>> AppDb.accounts();
```

`SELECT bank, account, COUNT(*) FROM txns WHERE account IS NOT NULL AND
hidden = 0 GROUP BY bank, account ORDER BY COUNT(*) DESC`. Displayed as
`HDFC •••1234` (bank's first word) or `•••1234` when bank is null. Tested.

### 3.2 Account chips

On the home screen, next to "UPI only", when **two or more** accounts exist:
`All · HDFC •••1234 · SBI •••5678`. Selecting one filters the month's
transactions to `t.bank == bank && t.account == last4` before the summary,
categories, merchants, search and list are computed. Transactions without an
account (manual, statements) appear only under All. The selection lives in
the home screen's state and resets on restart.

### 3.3 Self transfers

Plain English: moving ₹5,000 from your HDFC account to your SBI account
produces an HDFC "debited" SMS and an SBI "credited" SMS. Today that shows as
₹5,000 spent and ₹5,000 received. It will show as one labelled "Self
transfer" pair that counts for neither.

- New category `Self transfer` in `kCategories` (icon `swap_vert`, grey). It
  is never guessed by `Categorizer`; only pairing assigns it.
- Pairing rule: a debit D and a credit C are a pair when
  `D.amountPaise == C.amountPaise`, both fall on the same calendar day, both
  have a non-null `account`, and `(D.bank, D.account) != (C.bank, C.account)`.
  Each transaction joins at most one pair; candidates are tried newest first.
- When to run: `TxnRepository._pairSelfTransfers(DateTime from, DateTime to)`
  runs after `syncSms`, `syncShortcutInbox` and `importStatement` whenever at
  least one row was added, over `[earliest added − 1 day, latest added + 1
  day]`. It loads the visible transactions in that window, finds pairs, and
  sets `category = 'Self transfer'` on both with `AppDb.setCategory`
  (per transaction, never a payee rule).
- Respecting the user's choices: a transaction is only relabelled when its
  current category equals what `Categorizer.categorizeWith(rules, …)` would
  produce for it — i.e. it is still the automatic guess. A category the user
  set by hand on either side is left alone, and that side is skipped for
  pairing. (Phase 2's `edit_ts` makes this exact; until then "still equals
  the guess" is the marker.)
- Undo: changing the category of either transaction by hand simply
  re-categorises it; the other side keeps `Self transfer` until the user
  changes it too.
- `ponytail:` statement rows have no account and are never paired; a friend
  paying you back the exact amount you paid someone else, into a different
  account, on the same day, is mis-paired — the user fixes it in one tap.

Tested against a real in-memory DB: HDFC debit + SBI credit same amount/day
→ both `Self transfer` and excluded from `MonthSummary`; same account on
both sides → not paired; a hand-set category on the debit → neither side
relabelled; a second sync doesn't re-pair or double-count.

## 4. Files

| Path | Purpose |
| --- | --- |
| `lib/parser/merchant.dart` | §2.1 |
| `lib/models/summary.dart` (modify) | §2.2 |
| `lib/models/category.dart` (modify) | `Self transfer` category |
| `lib/widgets/merchant_bars.dart` | §2.3 |
| `lib/screens/merchant_screen.dart`, `merchants_screen.dart` | §2.4 |
| `lib/screens/home_screen.dart` (modify) | top merchants, search, account chips |
| `lib/util/search.dart` | `matchesSearch` |
| `lib/data/db.dart` (modify) | `accounts()` |
| `lib/data/repository.dart` (modify) | `_pairSelfTransfers`, `accounts()` |
| `test/parser/merchant_test.dart`, `test/categorizer_test.dart` (summary), `test/data/repository_test.dart`, `test/util/search_test.dart` | tests |

No new dependencies. No schema change.

## 5. Order of work

1. Merchant names + tests → `byMerchant` in `MonthSummary` → `MerchantBars`
   on the home screen → merchant screen + "See all" → search.
2. `Self transfer` category + `accounts()` → pairing in the repository with
   tests → account chips on the home screen → summary exclusions.
3. README: merchants, search, accounts, self transfers.
