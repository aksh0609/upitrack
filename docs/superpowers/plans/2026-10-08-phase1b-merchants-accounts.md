# Phase 1b — Merchants and Multiple Accounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group messy payee strings into merchants with per-merchant totals, a merchant screen and search; turn each bank account seen in the SMS into a filter chip; and stop money moved between the user's own accounts from counting as spending.

**Architecture:** Everything is computed from existing columns — no schema change, no new dependency. A pure-Dart `merchantOf()` (sibling of `Categorizer`) maps payees to merchants at display time; `MonthSummary` gains per-merchant totals and excludes a new `Self transfer` category; the repository pairs same-day equal-amount debit/credit rows across different accounts after every sync or import; the home screen gets a Top-merchants block, a search field and account chips; two new screens show a merchant's history and the full merchant list.

**Tech Stack:** Flutter 3.47 stable / Dart 3.13, sqflite + sqflite_common_ffi (tests). No additions.

**Spec:** `docs/superpowers/specs/2026-10-08-merchants-accounts-design.md` — this plan implements all of it.

## Global Constraints

- Flutter is at `~/flutter/bin`; every `flutter`/`dart` command assumes `export PATH=$HOME/flutter/bin:$PATH`.
- Work on branch `merchants-accounts` (exists; it sits on top of `v2-sync-web`). Commit after every task.
- Every commit message ends with the two lines
  `Co-Authored-By: <model that wrote it> <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY` (the second line verbatim).
- `lib/parser/*` and `lib/models/summary.dart` stay free of Flutter imports.
- `flutter analyze` must report `No issues found!` and the full `flutter test` suite must pass before each commit (60 tests at the start of this plan).
- No schema change: `AppDb.open` stays at `version: 2`. `txns.key` values are never changed.
- The category name is exactly `Self transfer` (constant `Categorizer.selfTransfer`). It is never guessed by `Categorizer.categorize`; only pairing assigns it.
- Amounts are integers in paise. Months are represented by their first day (`DateTime(y, m)`), as the home screen already does.
- No Android SDK on this machine: `flutter analyze` + `flutter test` are the local verification; the APK is built by CI.

---

## File structure

| File | Responsibility | Task |
| --- | --- | --- |
| `lib/parser/merchant.dart` (create) | `merchantKeywords`, `knownMerchant`, `merchantOf` | 1 |
| `lib/parser/categorizer.dart` (modify) | `selfTransfer` constant | 2 |
| `lib/models/category.dart` (modify) | `Self transfer` entry in `kCategories` | 2 |
| `lib/models/summary.dart` (modify) | `byMerchant`, self-transfer exclusion, `monthlyTotals` | 2 |
| `lib/widgets/txn_day_list.dart` (create) | shared day-grouped list used by home and merchant screens | 3 |
| `lib/widgets/merchant_bars.dart` (create) | rows with bars per merchant | 3 |
| `lib/screens/merchant_screen.dart` (create) | one merchant: this month, 6 months, category, payments | 3 |
| `lib/screens/merchants_screen.dart` (create) | all merchants for the month | 4 |
| `lib/screens/home_screen.dart` (modify) | Top merchants block, search, account chips | 4, 5, 6 |
| `lib/util/search.dart` (create) | `matchesSearch` | 5 |
| `lib/models/account.dart` (create) | `AccountRef`, `accountLabel` | 6 |
| `lib/data/db.dart` (modify) | `accounts()` | 6 |
| `lib/data/repository.dart` (modify) | `accounts()`, `_pairSelfTransfers` + hooks | 6, 7 |
| `test/parser/merchant_test.dart`, `test/categorizer_test.dart`, `test/widget_test.dart`, `test/util/search_test.dart`, `test/models/account_test.dart`, `test/data/repository_test.dart` | tests | 1–7 |
| `README.md` (modify) | features, limits | 8 |

---

### Task 1: Merchant names (spec §2.1)

**Files:**
- Create: `lib/parser/merchant.dart`
- Create: `test/parser/merchant_test.dart`

**Interfaces:**
- Produces: `const List<(String, String)> merchantKeywords`; `String? knownMerchant(String counterparty)`; `String merchantOf(String counterparty)` (all top-level).

- [ ] **Step 1: Write the failing tests**

Create `test/parser/merchant_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/parser/merchant.dart';

void main() {
  test('known merchants, whatever the payee spelling', () {
    expect(merchantOf('SWIGGY'), 'Swiggy');
    expect(merchantOf('swiggy.stores@axb'), 'Swiggy');
    expect(merchantOf('Swiggy Instamart'), 'Swiggy Instamart');
    expect(merchantOf('AMAZON PAY INDIA'), 'Amazon');
    expect(merchantOf('amazonpay@apl'), 'Amazon');
    expect(merchantOf('Prime Video'), 'Prime Video');
    expect(merchantOf('JIOHOTSTAR'), 'JioHotstar');
    expect(merchantOf('Jio Prepaid'), 'Jio');
    expect(merchantOf('MYNTRA DESIGNS PVT LTD'), 'Myntra');
    expect(merchantOf('flipkart@axisbank'), 'Flipkart');
  });

  test('whole words only', () {
    expect(knownMerchant('bholanath sweets'), isNull);
    expect(knownMerchant('violet cafe'), isNull);
  });

  test('unknown payees pass through, trimmed', () {
    expect(knownMerchant('RAHUL KUMAR'), isNull);
    expect(merchantOf('  RAHUL   KUMAR '), 'RAHUL KUMAR');
    expect(merchantOf('rahul@okaxis'), 'rahul@okaxis');
  });

  test('longer names win over their prefixes', () {
    expect(merchantOf('swiggyinstamart'), isNot('Swiggy'));
    expect(merchantOf('JioMart'), 'JioMart');
  });
}
```

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/parser/merchant_test.dart`
Expected: compile error — `package:upitrack/parser/merchant.dart` not found.

- [ ] **Step 3: Implement**

Create `lib/parser/merchant.dart`:

```dart
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
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/parser/merchant_test.dart`
Expected: 4 passed. (`'swiggyinstamart'` is matched by its own keyword before `'swiggy'`, which can't match it anyway because of the whole-word rule.)

- [ ] **Step 5: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/parser/merchant.dart test/parser/merchant_test.dart
git commit -m "Add merchantOf(): group payee strings into merchants" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 2: Self-transfer category, per-merchant totals, monthly totals (spec §2.2, §3.3)

**Files:**
- Modify: `lib/parser/categorizer.dart` (constant)
- Modify: `lib/models/category.dart` (`kCategories`)
- Modify: `lib/models/summary.dart`
- Test: `test/categorizer_test.dart`

**Interfaces:**
- Consumes: `merchantOf` (Task 1).
- Produces: `static const String Categorizer.selfTransfer = 'Self transfer'`; `MonthSummary.byMerchant: Map<String, ({int count, int totalPaise})>` (largest first); top-level `List<({DateTime month, int paise})> monthlyTotals(List<Txn> txns, DateTime lastMonth, {int months = 6})` in `summary.dart`.

- [ ] **Step 1: Write the failing tests**

In `test/categorizer_test.dart`, replace the `txn(...)` helper inside the `MonthSummary` group with one that takes a counterparty, and add two tests:

```dart
    Txn txn(int paise, bool debit, String category, DateTime time,
            {String counterparty = 'x'}) =>
        Txn(
          key: '$paise$time$counterparty',
          amountPaise: paise,
          isDebit: debit,
          counterparty: counterparty,
          channel: 'UPI',
          category: category,
          time: time,
        );
```

(the existing `totals, today and sorted categories` test keeps working unchanged), then append inside the group:

```dart
    test('byMerchant groups payee spellings and sorts by total', () {
      final s = MonthSummary.from([
        txn(10000, true, 'Food', DateTime(2026, 10, 2), counterparty: 'SWIGGY'),
        txn(20000, true, 'Food', DateTime(2026, 10, 3), counterparty: 'swiggy.stores@axb'),
        txn(50000, true, 'Shopping', DateTime(2026, 10, 4), counterparty: 'AMAZON PAY'),
        txn(99900, false, 'Income', DateTime(2026, 10, 4), counterparty: 'AMAZON PAY'),
      ], now: DateTime(2026, 10, 5));
      expect(s.byMerchant.keys.toList(), ['Amazon', 'Swiggy']);
      expect(s.byMerchant['Swiggy'], (count: 2, totalPaise: 30000));
      expect(s.byMerchant['Amazon'], (count: 1, totalPaise: 50000));
    });

    test('self transfers count for nothing', () {
      final s = MonthSummary.from([
        txn(500000, true, Categorizer.selfTransfer, DateTime(2026, 10, 2), counterparty: 'me@okaxis'),
        txn(500000, false, Categorizer.selfTransfer, DateTime(2026, 10, 2), counterparty: 'HDFC'),
        txn(10000, true, 'Food', DateTime(2026, 10, 2), counterparty: 'SWIGGY'),
      ], now: DateTime(2026, 10, 2));
      expect(s.spentPaise, 10000);
      expect(s.receivedPaise, 0);
      expect(s.todaySpentPaise, 10000);
      expect(s.byCategory.keys, ['Food']);
      expect(s.byMerchant.keys, ['Swiggy']);
    });
```

and a new top-level group:

```dart
  group('monthlyTotals', () {
    Txn spend(int paise, DateTime time, {String category = 'Food'}) => Txn(
          key: '$paise$time',
          amountPaise: paise,
          isDebit: true,
          counterparty: 'SWIGGY',
          channel: 'UPI',
          category: category,
          time: time,
        );

    test('one entry per month ending at lastMonth, zeros kept, self transfers out', () {
      final rows = monthlyTotals([
        spend(10000, DateTime(2026, 10, 3)),
        spend(5000, DateTime(2026, 10, 20)),
        spend(7000, DateTime(2026, 8, 1)),
        spend(99999, DateTime(2026, 9, 9), category: Categorizer.selfTransfer),
        spend(1, DateTime(2026, 4, 30)), // before the window
      ], DateTime(2026, 10));
      expect(rows.map((r) => r.month), [
        DateTime(2026, 5), DateTime(2026, 6), DateTime(2026, 7),
        DateTime(2026, 8), DateTime(2026, 9), DateTime(2026, 10),
      ]);
      expect(rows.map((r) => r.paise), [0, 0, 0, 7000, 0, 15000]);
    });
  });
```

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/categorizer_test.dart`
Expected: compile errors — `Categorizer.selfTransfer`, `byMerchant`, `monthlyTotals` undefined.

- [ ] **Step 3: Implement**

`lib/parser/categorizer.dart`, next to the other constants:

```dart
  /// Money moved between the user's own accounts. Never guessed here; only
  /// TxnRepository's pairing assigns it (spec §3.3).
  static const String selfTransfer = 'Self transfer';
```

`lib/models/category.dart`: add `import '../parser/categorizer.dart';` and, in `kCategories`, insert before the `'Others'` entry:

```dart
  CategoryInfo(Categorizer.selfTransfer, Icons.swap_vert, Color(0xFF9E9E9E)),
```

`lib/models/summary.dart` — replace the file with:

```dart
import '../parser/categorizer.dart';
import '../parser/merchant.dart';
import 'txn.dart';

/// Totals for the transactions currently on screen. Self transfers (money
/// moved between the user's own accounts) count for nothing.
class MonthSummary {
  const MonthSummary({
    required this.spentPaise,
    required this.receivedPaise,
    required this.todaySpentPaise,
    required this.byCategory,
    required this.byMerchant,
  });

  final int spentPaise;
  final int receivedPaise;
  final int todaySpentPaise;

  /// Spending per category, largest first.
  final Map<String, int> byCategory;

  /// Spending per merchant (see [merchantOf]), largest first.
  final Map<String, ({int count, int totalPaise})> byMerchant;

  int get netPaise => receivedPaise - spentPaise;

  factory MonthSummary.from(List<Txn> txns, {DateTime? now}) {
    final today = now ?? DateTime.now();
    var spent = 0;
    var received = 0;
    var todaySpent = 0;
    final byCategory = <String, int>{};
    final byMerchant = <String, ({int count, int totalPaise})>{};

    for (final t in txns) {
      if (t.category == Categorizer.selfTransfer) continue;
      if (t.isDebit) {
        spent += t.amountPaise;
        byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amountPaise;
        final m = merchantOf(t.counterparty);
        final prev = byMerchant[m] ?? (count: 0, totalPaise: 0);
        byMerchant[m] = (count: prev.count + 1, totalPaise: prev.totalPaise + t.amountPaise);
        if (t.time.year == today.year &&
            t.time.month == today.month &&
            t.time.day == today.day) {
          todaySpent += t.amountPaise;
        }
      } else {
        received += t.amountPaise;
      }
    }

    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final merchants = byMerchant.entries.toList()
      ..sort((a, b) => b.value.totalPaise.compareTo(a.value.totalPaise));

    return MonthSummary(
      spentPaise: spent,
      receivedPaise: received,
      todaySpentPaise: todaySpent,
      byCategory: Map.fromEntries(categories),
      byMerchant: Map.fromEntries(merchants),
    );
  }
}

/// Spending per calendar month for the [months] months ending at
/// [lastMonth] (first-of-month), oldest first, with zeros for empty months.
/// Debits only; self transfers excluded.
List<({DateTime month, int paise})> monthlyTotals(
  List<Txn> txns,
  DateTime lastMonth, {
  int months = 6,
}) {
  final rows = <({DateTime month, int paise})>[];
  for (var i = months - 1; i >= 0; i--) {
    final month = DateTime(lastMonth.year, lastMonth.month - i);
    final next = DateTime(month.year, month.month + 1);
    var sum = 0;
    for (final t in txns) {
      if (!t.isDebit || t.category == Categorizer.selfTransfer) continue;
      if (!t.time.isBefore(month) && t.time.isBefore(next)) sum += t.amountPaise;
    }
    rows.add((month: month, paise: sum));
  }
  return rows;
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/categorizer_test.dart`
Expected: all pass (the pre-existing summary test too).

- [ ] **Step 5: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/parser/categorizer.dart lib/models/category.dart lib/models/summary.dart test/categorizer_test.dart
git commit -m "Add per-merchant totals, monthly totals and the Self transfer category" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 3: Shared day list, `MerchantBars`, and the merchant screen (spec §2.3–2.4)

**Files:**
- Create: `lib/widgets/txn_day_list.dart`, `lib/widgets/merchant_bars.dart`, `lib/screens/merchant_screen.dart`
- Modify: `lib/screens/home_screen.dart` (use the shared day list)
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: `merchantOf` (Task 1); `monthlyTotals`, `Categorizer.selfTransfer`, `Categorizer.income`, `kCategories` (Task 2); existing `TxnTile(txn:, onTap:, onHide:)`, `showTxnSheet`, `TxnRepository.between`, `TxnRepository.setCategory(t, category, forPayee:)`, `dayLabel`, `formatPaise`.
- Produces: `List<Widget> txnsGroupedByDay(BuildContext context, List<Txn> txns, {required void Function(Txn) onTap, void Function(Txn)? onHide})`; `class MerchantBars extends StatelessWidget { MerchantBars({required Map<String, ({int count, int totalPaise})> totals, required ValueChanged<String> onTap, int? limit}) }`; `class MerchantScreen extends StatefulWidget { MerchantScreen({required TxnRepository repository, required String merchant, required DateTime month}) }`.

- [ ] **Step 1: Write the failing widget test**

Append inside `main()` in `test/widget_test.dart`:

```dart
  testWidgets('MerchantBars shows limited rows and reports taps', (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MerchantBars(
          totals: {
            'Amazon': (count: 3, totalPaise: 450000),
            'Swiggy': (count: 2, totalPaise: 30000),
          },
          limit: 1,
          onTap: (m) => tapped = m,
        ),
      ),
    ));
    expect(find.text('Amazon'), findsOneWidget);
    expect(find.text('Swiggy'), findsNothing);
    expect(find.text('3 payments'), findsOneWidget);
    expect(find.textContaining('4,500'), findsOneWidget);
    await tester.tap(find.text('Amazon'));
    expect(tapped, 'Amazon');
  });
```

with the import `import 'package:upitrack/widgets/merchant_bars.dart';`.

Run: `flutter test test/widget_test.dart` → compile error, `merchant_bars.dart` not found.

- [ ] **Step 2: Create the shared day list**

Create `lib/widgets/txn_day_list.dart` (this is the home screen's `_groupedByDay` moved out so the merchant screen can reuse it):

```dart
import 'package:flutter/material.dart';

import '../models/txn.dart';
import '../util/format.dart';
import 'txn_tile.dart';

/// [txns] (newest first) as day headers and tiles, for use inside a ListView.
List<Widget> txnsGroupedByDay(
  BuildContext context,
  List<Txn> txns, {
  required void Function(Txn) onTap,
  void Function(Txn)? onHide,
}) {
  final text = Theme.of(context).textTheme;
  final widgets = <Widget>[];
  DateTime? currentDay;
  for (final t in txns) {
    final day = DateTime(t.time.year, t.time.month, t.time.day);
    if (day != currentDay) {
      currentDay = day;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(dayLabel(day),
            style: text.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ));
    }
    widgets.add(TxnTile(
      txn: t,
      onTap: () => onTap(t),
      onHide: onHide == null ? null : () => onHide(t),
    ));
  }
  return widgets;
}
```

In `lib/screens/home_screen.dart`: add `import '../widgets/txn_day_list.dart';`, replace the `..._groupedByDay(visible, text)` spread in `build` with `...txnsGroupedByDay(context, visible, onTap: _openTxn, onHide: _hideTxn)`, delete the `_groupedByDay` method, and remove any import `flutter analyze` then reports as unused (`txn_tile.dart`, and `format.dart` if `dayLabel` was its only use).

- [ ] **Step 3: Create `MerchantBars`**

Create `lib/widgets/merchant_bars.dart`:

```dart
import 'package:flutter/material.dart';

import '../util/format.dart';

/// Rows with bars showing spending per merchant, largest first.
class MerchantBars extends StatelessWidget {
  const MerchantBars({
    super.key,
    required this.totals,
    required this.onTap,
    this.limit,
  });

  /// merchant → (count, total), already sorted largest first.
  final Map<String, ({int count, int totalPaise})> totals;
  final ValueChanged<String> onTap;

  /// Show only the first [limit] rows (null = all).
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.take(limit ?? totals.length).toList();
    final max = entries.fold<int>(
        0, (a, e) => e.value.totalPaise > a ? e.value.totalPaise : a);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (final e in entries)
          InkWell(
            onTap: () => onTap(e.key),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: scheme.secondaryContainer,
                    child: Icon(Icons.storefront_outlined,
                        size: 18, color: scheme.onSecondaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(e.key,
                                  style: text.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Text(formatPaise(e.value.totalPaise),
                                style: text.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        Text(
                          e.value.count == 1
                              ? '1 payment'
                              : '${e.value.count} payments',
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: max == 0 ? 0 : e.value.totalPaise / max,
                            minHeight: 6,
                            color: scheme.primary,
                            backgroundColor:
                                scheme.primary.withValues(alpha: 0.12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
```

Run: `flutter test test/widget_test.dart` → all pass.

- [ ] **Step 4: Create the merchant screen**

Create `lib/screens/merchant_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../models/category.dart';
import '../models/summary.dart';
import '../models/txn.dart';
import '../parser/categorizer.dart';
import '../parser/merchant.dart';
import '../util/format.dart';
import '../widgets/txn_day_list.dart';
import 'txn_sheet.dart';

/// One merchant: this month's total, the last six months, its category and
/// every payment in that window.
class MerchantScreen extends StatefulWidget {
  const MerchantScreen({
    super.key,
    required this.repository,
    required this.merchant,
    required this.month,
  });

  final TxnRepository repository;
  final String merchant;

  /// First day of the month that was on screen; the six-month view ends here.
  final DateTime month;

  @override
  State<MerchantScreen> createState() => _MerchantScreenState();
}

class _MerchantScreenState extends State<MerchantScreen> {
  List<Txn>? _txns;

  DateTime get _from => DateTime(widget.month.year, widget.month.month - 5);
  DateTime get _to => DateTime(widget.month.year, widget.month.month + 1);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.repository.between(_from, _to);
    final mine =
        all.where((t) => merchantOf(t.counterparty) == widget.merchant).toList();
    if (mounted) setState(() => _txns = mine);
  }

  Iterable<Txn> get _debits => (_txns ?? const []).where(
      (t) => t.isDebit && t.category != Categorizer.selfTransfer);

  /// The category most of this merchant's payments carry.
  String? get _category {
    final counts = <String, int>{};
    for (final t in _debits) {
      counts[t.category] = (counts[t.category] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  /// Remembers [category] for every payee spelling behind this merchant.
  Future<void> _setCategory(String category) async {
    final seen = <String>{};
    for (final t in _debits) {
      if (seen.add(t.counterparty)) {
        await widget.repository.setCategory(t, category, forPayee: true);
      }
    }
    await _load();
  }

  Future<void> _openTxn(Txn t) async {
    final changed = await showTxnSheet(context, t, widget.repository);
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final txns = _txns;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (txns == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.merchant)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final thisMonth = _debits
        .where((t) => !t.time.isBefore(widget.month) && t.time.isBefore(_to))
        .toList();
    final thisMonthTotal = thisMonth.fold<int>(0, (a, t) => a + t.amountPaise);
    final history = monthlyTotals(txns, widget.month);
    final maxMonth = history.fold<int>(0, (a, r) => r.paise > a ? r.paise : a);
    final category = _category;

    return Scaffold(
      appBar: AppBar(title: Text(widget.merchant)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '${DateFormat('MMMM').format(widget.month)}: ${formatPaise(thisMonthTotal)}',
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            thisMonth.length == 1 ? '1 payment' : '${thisMonth.length} payments',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Text('Last 6 months', style: text.titleMedium),
          const SizedBox(height: 8),
          for (final r in history)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(DateFormat('MMM').format(r.month),
                        style: text.bodySmall),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxMonth == 0 ? 0 : r.paise / maxMonth,
                        minHeight: 10,
                        color: scheme.primary,
                        backgroundColor: scheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: Text(formatPaise(r.paise),
                        textAlign: TextAlign.right, style: text.bodySmall),
                  ),
                ],
              ),
            ),
          if (category != null) ...[
            const SizedBox(height: 24),
            Text('Category', style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in kCategories)
                  if (c.name != Categorizer.income)
                    ChoiceChip(
                      label: Text(c.name),
                      avatar: Icon(c.icon, size: 18, color: c.color),
                      selected: category == c.name,
                      onSelected: (_) => _setCategory(c.name),
                    ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text('Payments', style: text.titleMedium),
          if (txns.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No payments in the last six months.'),
            )
          else
            ...txnsGroupedByDay(context, txns, onTap: _openTxn),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/widgets/txn_day_list.dart lib/widgets/merchant_bars.dart lib/screens/merchant_screen.dart lib/screens/home_screen.dart test/widget_test.dart
git commit -m "Add MerchantBars and the merchant screen; share the day-grouped list" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 4: Top merchants on the home screen and the all-merchants screen (spec §2.3)

**Files:**
- Create: `lib/screens/merchants_screen.dart`
- Modify: `lib/screens/home_screen.dart`

**Interfaces:**
- Consumes: `MerchantBars`, `MerchantScreen` (Task 3); `MonthSummary.byMerchant` (Task 2).
- Produces: `class MerchantsScreen extends StatelessWidget { MerchantsScreen({required TxnRepository repository, required DateTime month, required Map<String, ({int count, int totalPaise})> totals}) }`.

- [ ] **Step 1: Create the all-merchants screen**

Create `lib/screens/merchants_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../widgets/merchant_bars.dart';
import 'merchant_screen.dart';

/// Every merchant for one month, largest first.
class MerchantsScreen extends StatelessWidget {
  const MerchantsScreen({
    super.key,
    required this.repository,
    required this.month,
    required this.totals,
  });

  final TxnRepository repository;
  final DateTime month;
  final Map<String, ({int count, int totalPaise})> totals;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Merchants · ${DateFormat('MMMM').format(month)}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          MerchantBars(
            totals: totals,
            onTap: (merchant) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => MerchantScreen(
                repository: repository,
                merchant: merchant,
                month: month,
              ),
            )),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Home screen block and navigation**

In `lib/screens/home_screen.dart`:

Imports:
```dart
import '../widgets/merchant_bars.dart';
import 'merchant_screen.dart';
import 'merchants_screen.dart';
```

Methods, next to `_openHidden`:
```dart
  Future<void> _openMerchant(String merchant) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MerchantScreen(
        repository: widget.repository,
        merchant: merchant,
        month: _month,
      ),
    ));
    await _load();
  }

  Future<void> _openMerchants(MonthSummary summary) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MerchantsScreen(
        repository: widget.repository,
        month: _month,
        totals: summary.byMerchant,
      ),
    ));
    await _load();
  }
```

In `build`, directly after the `if (summary.byCategory.isNotEmpty) ...[ … CategoryBars … ]` block:
```dart
            if (summary.byMerchant.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Text('Top merchants', style: text.titleMedium)),
                  if (summary.byMerchant.length > 5)
                    TextButton(
                      onPressed: () => _openMerchants(summary),
                      child: const Text('See all'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              MerchantBars(
                totals: summary.byMerchant,
                limit: 5,
                onTap: _openMerchant,
              ),
            ],
```

- [ ] **Step 3: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/screens/merchants_screen.dart lib/screens/home_screen.dart
git commit -m "Show top merchants on the home screen with a See-all screen" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

Manual check (on the next test APK): the home screen shows up to five merchants under "Where it went"; tapping one opens its screen with six month bars; changing the category there re-categorises every payment to that merchant; "See all" appears only with more than five merchants.

---

### Task 5: Search (spec §2.5)

**Files:**
- Create: `lib/util/search.dart`, `test/util/search_test.dart`
- Modify: `lib/screens/home_screen.dart`

**Interfaces:**
- Consumes: `merchantOf` (Task 1).
- Produces: `bool matchesSearch(Txn t, String query)` (top-level).

- [ ] **Step 1: Write the failing tests**

Create `test/util/search_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/util/search.dart';

void main() {
  Txn txn(String counterparty) => Txn(
        key: counterparty,
        amountPaise: 100,
        isDebit: true,
        counterparty: counterparty,
        channel: 'UPI',
        category: 'Others',
        time: DateTime(2026, 10, 1),
      );

  test('matches payee text and merchant name, case-insensitive', () {
    expect(matchesSearch(txn('MYNTRA DESIGNS'), 'myntra'), isTrue);
    expect(matchesSearch(txn('amazonpay@apl'), 'Amazon'), isTrue); // via merchant
    expect(matchesSearch(txn('rahul@okaxis'), 'RAHUL'), isTrue);
    expect(matchesSearch(txn('SWIGGY'), 'zomato'), isFalse);
  });

  test('empty or blank query matches everything', () {
    expect(matchesSearch(txn('x'), ''), isTrue);
    expect(matchesSearch(txn('x'), '   '), isTrue);
  });
}
```

Run: `flutter test test/util/search_test.dart` → compile error, file not found.

- [ ] **Step 2: Implement**

Create `lib/util/search.dart`:

```dart
import '../models/txn.dart';
import '../parser/merchant.dart';

/// True when [query] (trimmed, case-insensitive) is empty or appears in the
/// payee string or in its merchant name.
bool matchesSearch(Txn t, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return t.counterparty.toLowerCase().contains(q) ||
      merchantOf(t.counterparty).toLowerCase().contains(q);
}
```

Run: `flutter test test/util/search_test.dart` → 2 passed.

- [ ] **Step 3: Home screen search field**

In `lib/screens/home_screen.dart`:

Import: `import '../util/search.dart';`

State fields, next to `_upiOnly`:
```dart
  bool _searching = false;
  final TextEditingController _search = TextEditingController();
```

In `initState`, after `WidgetsBinding.instance.addObserver(this);`:
```dart
    _search.addListener(() => setState(() {}));
```
In `dispose`, before `super.dispose()`:
```dart
    _search.dispose();
```

Add a method next to `_changeMonth`:
```dart
  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _search.clear();
    });
  }
```

In the `AppBar` `actions`, as the FIRST action (before the sync/refresh widget):
```dart
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.search_off : Icons.search),
            onPressed: _toggleSearch,
          ),
```

Replace the `visible` computation at the top of `build` with:
```dart
    final visible = _txns
        .where((t) => !_upiOnly || t.channel == 'UPI')
        .where((t) => matchesSearch(t, _search.text))
        .toList();
```

In the `ListView` children, directly before the `Row` that holds `Text('Transactions', …)` and the "UPI only" chip:
```dart
            if (_searching) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search payee or merchant',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _search.clear,
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
```

Replace the empty-state branch `if (visible.isEmpty) _EmptyState(...)` with:
```dart
            if (visible.isEmpty && _search.text.trim().isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text('No payments match.', textAlign: TextAlign.center),
              )
            else if (visible.isEmpty)
              _EmptyState(
                  waitingForAccess: _access != _Access.granted &&
                      !(_access == _Access.iphone && _shortcutCount > 0))
            else
              ...txnsGroupedByDay(context, visible, onTap: _openTxn, onHide: _hideTxn),
```

- [ ] **Step 4: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/util/search.dart test/util/search_test.dart lib/screens/home_screen.dart
git commit -m "Add search by payee or merchant on the home screen" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 6: Accounts — discovery and filter chips (spec §3.1–3.2)

**Files:**
- Create: `lib/models/account.dart`, `test/models/account_test.dart`
- Modify: `lib/data/db.dart`, `lib/data/repository.dart`, `lib/screens/home_screen.dart`
- Test: `test/data/repository_test.dart`

**Interfaces:**
- Consumes: `hdfcSwiggy`, `FakeSms`, `FakeInbox` (existing test helpers).
- Produces: `typedef AccountRef = ({String? bank, String last4})`; `String accountLabel(AccountRef a)`; `Future<List<AccountRef>> AppDb.accounts()`; `Future<List<AccountRef>> TxnRepository.accounts()`.

- [ ] **Step 1: Write the failing tests**

Create `test/models/account_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/models/account.dart';

void main() {
  test('accountLabel uses the bank\'s first word', () {
    expect(accountLabel((bank: 'HDFC Bank', last4: '1234')), 'HDFC •••1234');
    expect(accountLabel((bank: 'Bank of Baroda', last4: '99')), 'Bank •••99');
    expect(accountLabel((bank: null, last4: '5678')), '•••5678');
    expect(accountLabel((bank: '', last4: '5678')), '•••5678');
  });
}
```

Append inside `main()` in `test/data/repository_test.dart`:

```dart
  group('accounts', () {
    const hdfcChai = 'Sent Rs.50.00\nFrom HDFC Bank A/C *1234\nTo CHAI POINT\n'
        'On 04/10/26\nRef 427600000055';
    const sbiZomato = 'Dear UPI user A/C X5678 debited by 120.0 on date 03Oct26 '
        'trf to ZOMATO Refno 427698765432. If not u? call 1800111109. -SBI';

    test('discovered from SMS, most-used first', () async {
      final repo = TxnRepository(
        db,
        FakeSms([
          RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcSwiggy, date: DateTime(2026, 10, 3, 9)),
          RawSms(id: 2, address: 'VM-HDFCBK', body: hdfcChai, date: DateTime(2026, 10, 4, 9)),
          RawSms(id: 3, address: 'AD-SBIUPI-S', body: sbiZomato, date: DateTime(2026, 10, 3, 10)),
        ]),
        FakeInbox(),
      );
      await repo.syncSms();
      expect(await repo.accounts(), [
        (bank: 'HDFC Bank', last4: '1234'),
        (bank: 'SBI', last4: '5678'),
      ]);
    });

    test('empty when nothing names an account', () async {
      final repo = TxnRepository(db, FakeSms(const []), FakeInbox());
      await repo.addManual(amountPaise: 100, isDebit: true, counterparty: 'Cash',
          category: 'Food', time: DateTime(2026, 10, 1));
      expect(await repo.accounts(), isEmpty);
    });
  });
```

with the import `import 'package:upitrack/models/account.dart';` (needed for the record type to resolve in `expect`).

Run: `flutter test test/models/account_test.dart test/data/repository_test.dart` → compile errors.

- [ ] **Step 2: Model**

Create `lib/models/account.dart`:

```dart
/// One bank account seen in the SMS: the bank (may be unknown) and the last
/// digits the SMS mentioned.
typedef AccountRef = ({String? bank, String last4});

/// "HDFC •••1234", or "•••1234" when the bank is unknown.
String accountLabel(AccountRef a) {
  final bank = a.bank?.split(' ').first ?? '';
  return bank.isEmpty ? '•••${a.last4}' : '$bank •••${a.last4}';
}
```

- [ ] **Step 3: Database and repository**

`lib/data/db.dart`: add `import '../models/account.dart';` and, after `betweenIncludingHidden`:

```dart
  /// Accounts seen in the SMS, most-used first.
  Future<List<AccountRef>> accounts() async {
    final rows = await _db.rawQuery(
        'SELECT bank, account, COUNT(*) AS n FROM txns '
        'WHERE account IS NOT NULL AND hidden = 0 '
        'GROUP BY bank, account ORDER BY n DESC');
    return [
      for (final r in rows)
        (bank: r['bank'] as String?, last4: r['account'] as String),
    ];
  }
```

`lib/data/repository.dart`: add `import '../models/account.dart';` and, in the shared section after `unhide`:

```dart
  Future<List<AccountRef>> accounts() => _db.accounts();
```

Run: `flutter test test/models/account_test.dart test/data/repository_test.dart` → all pass.

- [ ] **Step 4: Account chips on the home screen**

In `lib/screens/home_screen.dart`:

Import: `import '../models/account.dart';`

State fields:
```dart
  List<AccountRef> _accounts = const [];
  AccountRef? _account;
```

Replace `_load`:
```dart
  Future<void> _load() async {
    final txns = await widget.repository
        .between(_month, DateTime(_month.year, _month.month + 1));
    final unparsed = await widget.repository.unparsed();
    final accounts = await widget.repository.accounts();
    if (mounted) {
      setState(() {
        _txns = txns;
        _unparsedCount = unparsed.length;
        _accounts = accounts;
        if (_account != null && !accounts.contains(_account)) _account = null;
      });
    }
  }
```

Extend the `visible` chain with the account filter (keep the search filter from Task 5):
```dart
    final visible = _txns
        .where((t) => !_upiOnly || t.channel == 'UPI')
        .where((t) =>
            _account == null ||
            (t.bank == _account!.bank && t.account == _account!.last4))
        .where((t) => matchesSearch(t, _search.text))
        .toList();
```

In the `ListView` children, directly after `_MonthSwitcher(...)` and before `const SizedBox(height: 8)` + `SummaryCard`, so the chips visibly scope the whole screen (a deliberate placement; spec §3.2 says "next to UPI only" — under the month name reads better because the summary above the list changes with it):
```dart
            if (_accounts.length >= 2)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _account == null,
                      onSelected: (_) => setState(() => _account = null),
                    ),
                    for (final a in _accounts) ...[
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(accountLabel(a)),
                        selected: _account == a,
                        onSelected: (_) => setState(() => _account = a),
                      ),
                    ],
                  ],
                ),
              ),
```

- [ ] **Step 5: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/models/account.dart test/models/account_test.dart lib/data/db.dart lib/data/repository.dart lib/screens/home_screen.dart test/data/repository_test.dart
git commit -m "Discover bank accounts from SMS and filter the month view by account" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 7: Self-transfer pairing (spec §3.3)

**Files:**
- Modify: `lib/data/repository.dart`
- Test: `test/data/repository_test.dart`

**Interfaces:**
- Consumes: `Categorizer.selfTransfer`, `Categorizer.categorizeWith` (Task 2 / existing); `AppDb.between`, `AppDb.rules`, `AppDb.setCategory(id, category)` (existing); the repository's private `_ymd`.
- Produces: `Future<int> TxnRepository.pairSelfTransfers(DateTime from, DateTime to)` (public so it can be called directly; the spec's `_pairSelfTransfers` name is relaxed for testability) and the private hook `_pairAround(List<Txn> added)` called after every sync/import that added rows.

- [ ] **Step 1: Write the failing tests**

Append inside `main()` in `test/data/repository_test.dart` (add imports `import 'package:upitrack/models/summary.dart';` and `import 'package:upitrack/parser/categorizer.dart';`):

```dart
  group('self transfers', () {
    const hdfcOut = 'Sent Rs.5,000.00\nFrom HDFC Bank A/C *1234\nTo me@oksbi\n'
        'On 03/10/26\nRef 427600000101';
    const sbiIn = 'Dear SBI UPI User, ur A/cX5678 credited by Rs5000 on 03Oct26 by '
        '(Ref no 427600000102)';
    const hdfcIn = 'Received Rs.5,000.00 in your HDFC Bank A/c XX1234 from VPA me@oksbi '
        'on 03-10-26. UPI Ref: 427600000103';
    final day = DateTime(2026, 10, 3, 9);
    TxnRepository repo(List<RawSms> sms) => TxnRepository(db, FakeSms(sms), FakeInbox());
    Future<List<Txn>> october(TxnRepository r) =>
        r.between(DateTime(2026, 10), DateTime(2026, 11));

    test('a debit and a credit across two own accounts become Self transfer', () async {
      final r = repo([
        RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcOut, date: day),
        RawSms(id: 2, address: 'AD-SBIUPI', body: sbiIn, date: day.add(const Duration(minutes: 1))),
      ]);
      await r.syncSms();
      final txns = await october(r);
      expect(txns, hasLength(2));
      expect(txns.map((t) => t.category), everyElement(Categorizer.selfTransfer));
      final s = MonthSummary.from(txns, now: day);
      expect(s.spentPaise, 0);
      expect(s.receivedPaise, 0);

      // A second sync changes nothing.
      await r.syncSms();
      expect((await october(r)).map((t) => t.category), everyElement(Categorizer.selfTransfer));
    });

    test('same account on both sides is not a self transfer', () async {
      final r = repo([
        RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcOut, date: day),
        RawSms(id: 2, address: 'VM-HDFCBK', body: hdfcIn, date: day),
      ]);
      await r.syncSms();
      expect((await october(r)).map((t) => t.category),
          isNot(contains(Categorizer.selfTransfer)));
    });

    test('a category the user set by hand is left alone', () async {
      final first = repo([RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcOut, date: day)]);
      await first.syncSms();
      await first.setCategory((await october(first)).single, 'Groceries', forPayee: false);

      final second = repo([
        RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcOut, date: day),
        RawSms(id: 2, address: 'AD-SBIUPI', body: sbiIn, date: day),
      ]);
      await second.syncSms();
      final byDirection = {for (final t in await october(second)) t.isDebit: t.category};
      expect(byDirection[true], 'Groceries');
      expect(byDirection[false], 'Income');
    });

    test('pairSelfTransfers reports how many pairs it made', () async {
      final r = repo([
        RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcOut, date: day),
        RawSms(id: 2, address: 'AD-SBIUPI', body: sbiIn, date: day),
      ]);
      await r.syncSms(); // pairs once here
      expect(await r.pairSelfTransfers(DateTime(2026, 10), DateTime(2026, 11)), 0,
          reason: 'already paired rows are skipped');
    });
  });
```

Run: `flutter test test/data/repository_test.dart` → the first test fails (categories are `Transfers` and `Income`), the last fails to compile (`pairSelfTransfers` undefined).

- [ ] **Step 2: Implement pairing and the hooks**

In `lib/data/repository.dart`, add a section before `// ---------------------------------------------------------------- shared`:

```dart
  // -------------------------------------------------------- self transfers

  /// Labels debit/credit pairs that move money between the user's own
  /// accounts (spec §3.3): same amount, same day, both with an account, and
  /// different accounts. Only rows still carrying their automatic category
  /// are touched, so a category the user set by hand is never overridden.
  /// Returns the number of pairs found.
  Future<int> pairSelfTransfers(DateTime from, DateTime to) async {
    final rules = await _db.rules();
    final txns = await _db.between(from, to); // newest first
    bool automatic(Txn t) =>
        t.category ==
        Categorizer.categorizeWith(rules, t.counterparty, isDebit: t.isDebit);
    final candidates = txns
        .where((t) =>
            t.account != null &&
            t.category != Categorizer.selfTransfer &&
            automatic(t))
        .toList();

    final usedCredits = <int>{};
    var pairs = 0;
    for (final d in candidates.where((t) => t.isDebit)) {
      for (final c in candidates.where((t) => !t.isDebit)) {
        if (usedCredits.contains(c.id)) continue;
        if (c.amountPaise != d.amountPaise) continue;
        if (_ymd(c.time) != _ymd(d.time)) continue;
        if (c.bank == d.bank && c.account == d.account) continue;
        await _db.setCategory(d.id!, Categorizer.selfTransfer);
        await _db.setCategory(c.id!, Categorizer.selfTransfer);
        usedCredits.add(c.id!);
        pairs++;
        break;
      }
    }
    return pairs;
  }

  /// Runs [pairSelfTransfers] over the days around rows a sync or import
  /// just added (one day either side, since the two SMS can straddle
  /// midnight).
  Future<void> _pairAround(List<Txn> added) async {
    if (added.isEmpty) return;
    var first = added.first.time;
    var last = added.first.time;
    for (final t in added) {
      if (t.time.isBefore(first)) first = t.time;
      if (t.time.isAfter(last)) last = t.time;
    }
    await pairSelfTransfers(
      DateTime(first.year, first.month, first.day - 1),
      DateTime(last.year, last.month, last.day + 2),
    );
  }
```

Hooks — in each of `syncSms`, `syncShortcutInbox` and `importStatement`, directly after the line `final added = await _db.insertAll(txns);` add:

```dart
    if (added > 0) await _pairAround(txns);
```

(`txns` is the list each method built before inserting; rows the insert skipped as duplicates only widen the date range, which is harmless.)

- [ ] **Step 3: Run the tests**

Run: `flutter test test/data/repository_test.dart`
Expected: all pass, including the four new ones and every earlier group (the `importStatement` and `hide / unhide` tests use single transactions, so nothing pairs).

- [ ] **Step 4: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/data/repository.dart test/data/repository_test.dart
git commit -m "Label transfers between the user's own accounts as Self transfer" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 8: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Features**

Under `## Features`, after the bullet that starts `- Tells you when a new version is available`, add:

```markdown
- **Merchants:** payees are grouped into merchants (Swiggy, Amazon, Flipkart, Myntra, Zomato…). The home screen shows your top merchants for the month; tap one for the last six months and every payment to it
- **Search** by payee or merchant
- **Accounts:** every bank account seen in your SMS becomes a chip (HDFC •••1234, SBI •••5678) that filters the whole month, no setup needed
- **Self transfers:** moving money between your own accounts is labelled "Self transfer" and left out of spent and received
```

- [ ] **Step 2: How it works table and adding a merchant**

In the `## How it works` table, add a row after the `lib/parser/categorizer.dart` row:

```markdown
| `lib/parser/merchant.dart` | Payee string → merchant name. One line per merchant. |
```

Under `## Adding a bank or fixing a missed transaction`, append a short paragraph after the numbered list:

```markdown
To add a merchant (so its payments are grouped and totalled), add one `('keyword', 'Name')` line to `merchantKeywords` in `lib/parser/merchant.dart`, longest keyword first, and a line to `test/parser/merchant_test.dart`.
```

- [ ] **Step 3: Limitations**

Under `## Limitations`, add:

```markdown
- Self transfers are detected by "same amount, same day, two different accounts of yours". A friend paying you back the exact amount you paid someone else, into a different account, on the same day, is mis-labelled — change its category to fix it.
- Statement rows carry no account, so they appear under "All" only and are never paired as self transfers.
```

- [ ] **Step 4: Commit**

```bash
flutter analyze && flutter test
git add README.md
git commit -m "Document merchants, search, accounts and self transfers" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

## Self-review against the spec

| Spec | Task |
| --- | --- |
| §2.1 merchant names, keyword table, tests | Task 1 |
| §2.2 `byMerchant`, self-transfer exclusion from all totals | Task 2 |
| §2.3 Top merchants block (5 + See all), `MerchantBars` | Tasks 3, 4 |
| §2.4 merchant screen: header, 6-month bars (`monthlyTotals`), category for every payee spelling, payments; `MerchantsScreen` | Tasks 2, 3, 4 |
| §2.5 search, `matchesSearch` | Task 5 |
| §3.1 `AccountRef`, `accounts()` query, label | Task 6 |
| §3.2 chips when ≥ 2 accounts, filter before summary, reset on restart | Task 6 (chips placed under the month switcher — a deliberate, documented placement) |
| §3.3 `Self transfer` category, pairing rule, hooks after sync/import, hand-set categories respected, idempotent | Tasks 2, 7 |
| §4 files / no schema change / no dependencies | all |
| §5 README | Task 8 |

Name consistency across tasks: `merchantOf`/`knownMerchant` (1 → 2, 3, 5); `Categorizer.selfTransfer` (2 → 3, 7); `MonthSummary.byMerchant` record shape `({int count, int totalPaise})` (2 → 3, 4); `monthlyTotals(txns, lastMonth)` (2 → 3); `txnsGroupedByDay(context, txns, onTap:, onHide:)` (3 → 3, 5); `MerchantBars(totals:, onTap:, limit:)` (3 → 4); `MerchantScreen(repository:, merchant:, month:)` (3 → 4); `matchesSearch` (5 → 6's `visible` chain); `AccountRef`/`accountLabel`/`accounts()` (6); `pairSelfTransfers`/`_pairAround` (7).
