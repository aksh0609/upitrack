# Phase 1 — Safe to Share Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make UPI Track safe to hand to friends and family: no silently lost payments, an undo for Hide, a way to report bank SMS the parser missed, an "update available" banner, and instant notifications when a bank SMS arrives on Android.

**Architecture:** The app stays a single Flutter codebase with pure-Dart parsers (`lib/parser/`), a SQLite layer (`lib/data/db.dart`), a repository that ties sources to storage (`lib/data/repository.dart`) and Material screens (`lib/screens/`). This plan adds a database test harness (`sqflite_common_ffi`), one new table (`unparsed`), two screens, a pure anonymiser, a GitHub-release checker, and an Android `BroadcastReceiver` that runs a background Dart entrypoint for notifications only (it never writes to the database).

**Tech Stack:** Flutter 3.47 stable / Dart 3.13, sqflite + sqflite_common_ffi (tests), flutter_local_notifications, share_plus, package_info_plus, url_launcher, http, Kotlin (Android receiver), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-07-upitrack-v2-design.md` — this plan implements §2 (prerequisite, owner's action), §3.1–§3.6 and the Phase 1 part of §6/§7.

## Global Constraints

- Flutter is at `~/flutter/bin` on this machine; every `flutter`/`dart` command below assumes `export PATH=$HOME/flutter/bin:$PATH`.
- Work on branch `v2-sync-web` (already created). Commit after every task.
- Every commit message ends with these two lines:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY`
- Parsers (`lib/parser/*`) stay pure Dart: no Flutter imports.
- Add dependencies with `flutter pub add <name>` (and `flutter pub add dev:<name>` for dev deps) so versions resolve against the installed Flutter; never hand-pin a version.
- `flutter analyze` must report no issues and `flutter test` must pass before each commit.
- Nothing in the background SMS path writes transactions (spec §3.5).
- GitHub owner is `aksh0609`; repo `aksh0609/upitrack`.
- Database schema version goes from 1 to **2** in this plan (adds `unparsed`). Phase 2 will go to 3.
- Amounts are always integers in paise. Keys for `txns.key` are never changed in this plan.
- No Android SDK on this machine: `flutter build apk` is verified by the GitHub Actions workflow after push, not locally. Local verification is `flutter analyze` + `flutter test`.

---

## File structure

| File | Responsibility | Task |
| --- | --- | --- |
| `lib/data/db.dart` (modify) | Open with injectable factory/path; `close()`; `unparsed` table (v2); hidden/unhide queries | 1, 3, 5 |
| `lib/data/repository.dart` (modify) | Dedup fix; hidden/unhide; record unparsed SMS; `addManual(raw:)` | 2, 3, 5, 7 |
| `lib/models/unparsed.dart` (create) | `UnparsedSms` row model | 5 |
| `lib/parser/sms_parser.dart` (modify) | `looksLikeTransaction`, `firstAmountPaise` | 4, 7 |
| `lib/parser/categorizer.dart` (modify) | `categorizeWith(rules, …)` shared by repository and background path | 10 |
| `lib/parser/anonymise.dart` (create) | Mask a bank SMS for sharing | 6 |
| `lib/screens/hidden_screen.dart` (create) | List hidden payments, Unhide | 3 |
| `lib/screens/unparsed_screen.dart` (create) | "Not recognised" list: Add / Ignore / Report | 7 |
| `lib/screens/add_txn_sheet.dart` (modify) | Prefill amount/date, carry `raw` | 7 |
| `lib/screens/home_screen.dart` (modify) | Menu entries, unparsed card, update banner, notification permission | 3, 7, 8, 10 |
| `lib/util/update_check.dart` (create) | `isNewerVersion`, `UpdateChecker` | 8 |
| `lib/background/sms_notification.dart` (create) | Pure notification text | 10 |
| `lib/background/sms_background.dart` (create) | Background entrypoint body | 10 |
| `lib/main.dart` (modify) | `smsBackground` entrypoint, `UpdateChecker` wiring | 8, 10 |
| `android/` (generate + commit) | Gradle files with desugaring; `SmsReceiver.kt`; manifest | 9, 10 |
| `.github/workflows/release.yml` (create) | Tag `v*` → GitHub Release with APK | 8 |
| `test/data/repository_test.dart` (create) | DB-backed tests | 1, 2, 3, 5 |
| `test/parser/anonymise_test.dart` (create) | | 6 |
| `test/util/update_check_test.dart` (create) | | 8 |
| `test/background/sms_notification_test.dart` (create) | | 10 |
| `README.md` (modify) | New features, limits, release how-to | 11 |

---

### Task 1: Database test harness

Lets tests open a real SQLite database in memory. Everything later in this plan depends on it.

**Files:**
- Modify: `lib/data/db.dart:12-46` (`open`) and add `close()`
- Create: `test/data/repository_test.dart`
- Modify: `pubspec.yaml` (dev dependency)

**Interfaces:**
- Produces: `AppDb.open({DatabaseFactory? factory, String? path})`, `Future<void> AppDb.close()`.
- Produces (test helpers, in the test file): `class FakeSms extends SmsSource`, `class FakeInbox extends ShortcutInbox`, `Future<AppDb> openTestDb()`.

- [ ] **Step 1: Add the dev dependency**

Run: `cd ~/upitrack && flutter pub add dev:sqflite_common_ffi`
Expected: `pubspec.yaml` gains `sqflite_common_ffi` under `dev_dependencies`; `flutter pub get` succeeds.

- [ ] **Step 2: Write the failing test**

Create `test/data/repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/data/repository.dart';
import 'package:upitrack/data/shortcut_inbox.dart';
import 'package:upitrack/data/sms_source.dart';

/// Returns canned SMS instead of reading the Android inbox.
class FakeSms extends SmsSource {
  FakeSms(this.messages);
  final List<RawSms> messages;

  @override
  Future<List<RawSms>> readInbox({required DateTime since}) async => messages;
}

/// No iPhone shortcut messages.
class FakeInbox extends ShortcutInbox {
  @override
  Future<List<InboxMessage>> pending() async => const [];

  @override
  Future<void> remove(List<InboxMessage> messages) async {}
}

Future<AppDb> openTestDb() =>
    AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);

const hdfcSwiggy = 'Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\n'
    'On 03/10/26\nRef 427612345678\nNot You?\nCall 18002586161';

void main() {
  sqfliteFfiInit();
  late AppDb db;

  setUp(() async => db = await openTestDb());
  tearDown(() => db.close());

  group('syncSms', () {
    test('stores a parsed bank SMS once, ignores an OTP', () async {
      final repo = TxnRepository(
        db,
        FakeSms([
          RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcSwiggy, date: DateTime(2026, 10, 3, 9)),
          RawSms(id: 2, address: 'VM-HDFCBK', body: '123456 is your OTP for Rs 500.', date: DateTime(2026, 10, 3, 9)),
        ]),
        FakeInbox(),
      );

      expect(await repo.syncSms(), 1);
      // Second sync of the same inbox adds nothing.
      expect(await repo.syncSms(), 0);

      final txns = await repo.between(DateTime(2026, 10), DateTime(2026, 11));
      expect(txns, hasLength(1));
      expect(txns.single.counterparty, 'SWIGGY');
      expect(txns.single.key, 'ref:427612345678:d');
    });
  });
}
```

- [ ] **Step 3: Run it to see it fail**

Run: `flutter test test/data/repository_test.dart`
Expected: compile error — `AppDb.open` takes no named parameters and `close` does not exist.

- [ ] **Step 4: Make `AppDb.open` injectable and add `close`**

In `lib/data/db.dart` replace the `open` method (lines 12–46) with:

```dart
  /// Opens the on-device database. Tests pass [factory] (sqflite_common_ffi)
  /// and [path] (`inMemoryDatabasePath`) to get a throwaway in-memory copy.
  static Future<AppDb> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'upitrack.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
          CREATE TABLE txns(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key TEXT NOT NULL UNIQUE,
            sms_id INTEGER,
            amount_paise INTEGER NOT NULL,
            is_debit INTEGER NOT NULL,
            counterparty TEXT NOT NULL,
            bank TEXT,
            account TEXT,
            ref TEXT,
            channel TEXT NOT NULL,
            category TEXT NOT NULL,
            ts INTEGER NOT NULL,
            raw TEXT,
            manual INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'sms',
            hidden INTEGER NOT NULL DEFAULT 0
          )''');
          await db.execute('CREATE INDEX idx_txns_ts ON txns(ts)');
          // Category the user picked for a payee, applied to future payments.
          await db.execute(
              'CREATE TABLE rules(counterparty TEXT PRIMARY KEY, category TEXT NOT NULL)');
          await db.execute(
              'CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT NOT NULL)');
        },
      ),
    );
    return AppDb._(db);
  }

  Future<void> close() => _db.close();
```

`databaseFactory`, `DatabaseFactory` and `OpenDatabaseOptions` all come from the existing `package:sqflite/sqflite.dart` import.

- [ ] **Step 5: Run the test to see it pass**

Run: `flutter test test/data/repository_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Analyze and run everything**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` (the pre-existing `unnecessary_import` info in `statement_reader.dart` is acceptable) and all tests pass.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/data/db.dart test/data/repository_test.dart
git commit -m "Make AppDb open injectable and add a DB-backed test harness" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 2: Statement-import duplicate fix (spec §3.1)

**Files:**
- Modify: `lib/data/repository.dart:142-195` (`importStatement`)
- Test: `test/data/repository_test.dart`

**Interfaces:**
- Consumes: `openTestDb`, `FakeSms`, `FakeInbox`, `hdfcSwiggy` from Task 1.
- Produces: no new API; `ImportSummary` unchanged.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/data/repository_test.dart`, after the `syncSms` group:

```dart
  group('importStatement', () {
    const chai50 = 'Sent Rs.50.00\nFrom HDFC Bank A/C *1234\nTo CHAI POINT\n'
        'On 03/10/26\nRef 427600000001';

    test('two same-day same-amount rows with one SMS caught: one is added', () async {
      final repo = TxnRepository(
        db,
        FakeSms([RawSms(id: 1, address: 'VM-HDFCBK', body: chai50, date: DateTime(2026, 10, 3, 9))]),
        FakeInbox(),
      );
      await repo.syncSms();

      // Statement narrations without a 12-digit ref, so only the
      // same-day/amount/direction rule can match them.
      final rows = [
        StatementRow(date: DateTime(2026, 10, 3, 12), amountPaise: 5000, isDebit: true,
            narration: 'UPI-CHAI POINT-MORNING', counterparty: 'CHAI POINT'),
        StatementRow(date: DateTime(2026, 10, 3, 12), amountPaise: 5000, isDebit: true,
            narration: 'UPI-CHAI POINT-EVENING', counterparty: 'CHAI POINT'),
      ];
      final s = await repo.importStatement(StatementResult(rows, 0));

      expect(s.added, 1, reason: 'the second ₹50 was never caught by SMS');
      expect(s.duplicates, 1);
      final txns = await repo.between(DateTime(2026, 10), DateTime(2026, 11));
      expect(txns, hasLength(2));
    });

    test('re-importing the same statement adds nothing', () async {
      final repo = TxnRepository(db, FakeSms(const []), FakeInbox());
      final rows = [
        StatementRow(date: DateTime(2026, 10, 1, 12), amountPaise: 25000, isDebit: true,
            narration: 'UPI-SWIGGY-427612345678', counterparty: 'SWIGGY', ref: '427612345678'),
      ];
      expect((await repo.importStatement(StatementResult(rows, 0))).added, 1);
      final again = await repo.importStatement(StatementResult(rows, 0));
      expect(again.added, 0);
      expect(again.duplicates, 1);
    });
  });
```

Add the import at the top of the test file:

```dart
import 'package:upitrack/parser/statement_parser.dart';
```

- [ ] **Step 2: Run to see the first test fail**

Run: `flutter test test/data/repository_test.dart`
Expected: `two same-day…` fails with `Expected: <1> Actual: <0>` (both rows were treated as duplicates). The re-import test passes already.

- [ ] **Step 3: Consume matches instead of re-using them**

In `lib/data/repository.dart`, inside `importStatement`, replace the `present` set and its use:

```dart
    // How many non-statement payments exist per day/amount/direction. Each
    // statement row consumes one match, so two ₹50 payments on one day with
    // only one SMS caught still import the second one.
    final present = <String, int>{};
    for (final t in existing) {
      if (t.source == 'statement') continue;
      final k = _sameDayKey(t.time, t.amountPaise, t.isDebit);
      present[k] = (present[k] ?? 0) + 1;
    }
```

and in the row loop replace

```dart
      if (present.contains(_sameDayKey(r.date, r.amountPaise, r.isDebit))) {
        duplicates++;
        continue;
      }
```

with

```dart
      final dayKey = _sameDayKey(r.date, r.amountPaise, r.isDebit);
      final left = present[dayKey] ?? 0;
      if (left > 0) {
        present[dayKey] = left - 1;
        duplicates++;
        continue;
      }
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/data/repository_test.dart`
Expected: all pass.

- [ ] **Step 5: Analyze, full test run, commit**

```bash
flutter analyze && flutter test
git add lib/data/repository.dart test/data/repository_test.dart
git commit -m "Fix statement import dropping a second same-amount payment" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 3: Unhide (spec §3.2)

**Files:**
- Modify: `lib/data/db.dart` (add `hidden()`, `unhide()`)
- Modify: `lib/data/repository.dart` (add `hidden()`, `unhide()`)
- Create: `lib/screens/hidden_screen.dart`
- Modify: `lib/screens/home_screen.dart:184-208` (menu)
- Test: `test/data/repository_test.dart`

**Interfaces:**
- Produces: `Future<List<Txn>> AppDb.hidden()`, `Future<void> AppDb.unhide(int id)`, `Future<List<Txn>> TxnRepository.hidden()`, `Future<void> TxnRepository.unhide(Txn t)`, `class HiddenScreen extends StatefulWidget { HiddenScreen({required TxnRepository repository}) }`.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/data/repository_test.dart`:

```dart
  group('hide / unhide', () {
    test('hidden payments leave the month view and can come back', () async {
      final repo = TxnRepository(
        db,
        FakeSms([RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcSwiggy, date: DateTime(2026, 10, 3, 9))]),
        FakeInbox(),
      );
      await repo.syncSms();
      final t = (await repo.between(DateTime(2026, 10), DateTime(2026, 11))).single;

      await repo.hide(t);
      expect(await repo.between(DateTime(2026, 10), DateTime(2026, 11)), isEmpty);
      final hidden = await repo.hidden();
      expect(hidden.single.key, t.key);

      await repo.unhide(hidden.single);
      expect(await repo.hidden(), isEmpty);
      expect(await repo.between(DateTime(2026, 10), DateTime(2026, 11)), hasLength(1));
    });
  });
```

- [ ] **Step 2: Run to see it fail**

Run: `flutter test test/data/repository_test.dart`
Expected: compile error — `hidden` / `unhide` undefined.

- [ ] **Step 3: Add the DB methods**

In `lib/data/db.dart`, after `hide(int id)`:

```dart
  /// Everything the user hid, newest first, across all months.
  Future<List<Txn>> hidden() async {
    final rows = await _db.query('txns', where: 'hidden = 1', orderBy: 'ts DESC');
    return rows.map(Txn.fromMap).toList();
  }

  Future<void> unhide(int id) =>
      _db.update('txns', {'hidden': 0}, where: 'id = ?', whereArgs: [id]);
```

- [ ] **Step 4: Add the repository methods**

In `lib/data/repository.dart`, after `hide(Txn t)`:

```dart
  Future<List<Txn>> hidden() => _db.hidden();

  Future<void> unhide(Txn t) => _db.unhide(t.id!);
```

- [ ] **Step 5: Run the test**

Run: `flutter test test/data/repository_test.dart`
Expected: all pass.

- [ ] **Step 6: Create the Hidden screen**

Create `lib/screens/hidden_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/txn.dart';
import '../widgets/txn_tile.dart';

/// Payments the user hid. Unhide puts them back in the month view.
class HiddenScreen extends StatefulWidget {
  const HiddenScreen({super.key, required this.repository});

  final TxnRepository repository;

  @override
  State<HiddenScreen> createState() => _HiddenScreenState();
}

class _HiddenScreenState extends State<HiddenScreen> {
  List<Txn>? _txns;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final txns = await widget.repository.hidden();
    if (mounted) setState(() => _txns = txns);
  }

  Future<void> _unhide(Txn t) async {
    await widget.repository.unhide(t);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final txns = _txns;
    return Scaffold(
      appBar: AppBar(title: const Text('Hidden')),
      body: txns == null
          ? const Center(child: CircularProgressIndicator())
          : txns.isEmpty
              ? const Center(child: Text('Nothing hidden.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    for (final t in txns)
                      Row(
                        children: [
                          Expanded(child: TxnTile(txn: t, onTap: () {})),
                          TextButton(
                            onPressed: () => _unhide(t),
                            child: const Text('Unhide'),
                          ),
                        ],
                      ),
                  ],
                ),
    );
  }
}
```

- [ ] **Step 7: Add the menu entry on the home screen**

In `lib/screens/home_screen.dart`:

Add the import:
```dart
import 'hidden_screen.dart';
```

Add a method next to `_openIphoneSetup`:
```dart
  Future<void> _openHidden() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HiddenScreen(repository: widget.repository),
    ));
    await _load();
  }
```

In the `PopupMenuButton`, extend `onSelected`:
```dart
            onSelected: (v) {
              if (v == 'import') _importStatement();
              if (v == 'iphone') _openIphoneSetup();
              if (v == 'hidden') _openHidden();
            },
```
and add an item after the `'import'` one:
```dart
              const PopupMenuItem(
                value: 'hidden',
                child: ListTile(
                  leading: Icon(Icons.visibility_off_outlined),
                  title: Text('Hidden'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
```

- [ ] **Step 8: Analyze, test, commit**

```bash
flutter analyze && flutter test
git add lib/data/db.dart lib/data/repository.dart lib/screens/hidden_screen.dart lib/screens/home_screen.dart test/data/repository_test.dart
git commit -m "Add a Hidden screen so hidden payments can be restored" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 4: `SmsParser.looksLikeTransaction` (spec §3.3)

Decides whether an SMS the parser rejected still looks like a bank payment worth showing in the "not recognised" list.

**Files:**
- Modify: `lib/parser/sms_parser.dart` (after `isLikelyBankSender`, line ~175)
- Test: `test/sms_parser_test.dart`

**Interfaces:**
- Produces: `static bool SmsParser.looksLikeTransaction(String address, String body)`.

- [ ] **Step 1: Write the failing tests**

Append a group inside `main()` in `test/sms_parser_test.dart`:

```dart
  group('looksLikeTransaction', () {
    test('unfamiliar bank wording with an amount', () {
      const body = 'Your a/c 1234 has a withdrawal of INR 320.00 at 10:12 towards UPI/9876';
      expect(SmsParser.parse('AD-UCOBNK', body), isNull, reason: 'not parsed today');
      expect(SmsParser.looksLikeTransaction('AD-UCOBNK', body), isTrue);
    });

    test('debit word without a currency symbol', () {
      expect(SmsParser.looksLikeTransaction('AD-SBIUPI', 'A/c X1234 debited 300 for a new format'), isTrue);
    });

    test('OTP, promotion and personal numbers are not transactions', () {
      expect(SmsParser.looksLikeTransaction('VM-HDFCBK', '123456 is your OTP for Rs 500'), isFalse);
      expect(SmsParser.looksLikeTransaction('AD-PAYTMB', 'Get Rs 100 cashback! Limited offer.'), isFalse);
      expect(SmsParser.looksLikeTransaction('+919876543210', 'Rs 5000 credited to your A/c'), isFalse);
    });

    test('no amount and no money word', () {
      expect(SmsParser.looksLikeTransaction('VM-HDFCBK', 'Thank you for banking with us.'), isFalse);
    });
  });
```

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/sms_parser_test.dart`
Expected: compile error — `looksLikeTransaction` undefined.

- [ ] **Step 3: Implement**

In `lib/parser/sms_parser.dart`, directly after `isLikelyBankSender`:

```dart
  /// True when an SMS that [parse] rejected still looks like a bank payment:
  /// bank sender, not an OTP/promo/reminder, and it mentions an amount or a
  /// debit/credit word. Used to show "we couldn't read this" to the user.
  static bool looksLikeTransaction(String address, String body) {
    if (body.trim().isEmpty || !isLikelyBankSender(address)) return false;
    if (_exclude.hasMatch(body)) return false;
    return _currencyAmount.hasMatch(body) ||
        _debitWord.hasMatch(body) ||
        _creditWord.hasMatch(body);
  }
```

- [ ] **Step 4: Run the tests, analyze, commit**

```bash
flutter test test/sms_parser_test.dart && flutter analyze
git add lib/parser/sms_parser.dart test/sms_parser_test.dart
git commit -m "Add SmsParser.looksLikeTransaction for unrecognised bank SMS" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 5: `unparsed` table and recording during sync (spec §3.3)

**Files:**
- Create: `lib/models/unparsed.dart`
- Modify: `lib/data/db.dart` (schema v2 + four methods)
- Modify: `lib/data/repository.dart:40-93` (`syncSms`, `syncShortcutInbox`) and new methods
- Test: `test/data/repository_test.dart`

**Interfaces:**
- Produces: `class UnparsedSms { int? id; String key; String sender; String body; DateTime time; String state; toMap(); fromMap() }` with `state` ∈ `'open' | 'added' | 'ignored'`.
- Produces: `AppDb.insertUnparsed(List<UnparsedSms>)`, `Future<List<UnparsedSms>> AppDb.openUnparsed()`, `AppDb.setUnparsedState(int id, String state)`, `AppDb.purgeUnparsed({required DateTime before})`.
- Produces: `Future<List<UnparsedSms>> TxnRepository.unparsed()`, `Future<void> TxnRepository.resolveUnparsed(UnparsedSms u, {required String state})`.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/data/repository_test.dart`:

```dart
  group('unparsed SMS', () {
    const ucoBody = 'Your a/c 1234 has a withdrawal of INR 320.00 at 10:12 towards UPI/9876';

    test('bank-looking SMS the parser rejects are kept; OTPs are not', () async {
      final repo = TxnRepository(
        db,
        FakeSms([
          RawSms(id: 7, address: 'AD-UCOBNK', body: ucoBody, date: DateTime(2026, 10, 3, 10)),
          RawSms(id: 8, address: 'VM-HDFCBK', body: '123456 is your OTP for Rs 500.', date: DateTime(2026, 10, 3, 9)),
          RawSms(id: 9, address: 'VM-HDFCBK', body: hdfcSwiggy, date: DateTime(2026, 10, 3, 9)),
        ]),
        FakeInbox(),
      );
      expect(await repo.syncSms(), 1);

      final open = await repo.unparsed();
      expect(open, hasLength(1));
      expect(open.single.key, 'sms:7');
      expect(open.single.sender, 'AD-UCOBNK');
      expect(open.single.body, ucoBody);

      // Syncing again doesn't duplicate it.
      await repo.syncSms();
      expect(await repo.unparsed(), hasLength(1));

      await repo.resolveUnparsed(open.single, state: 'ignored');
      expect(await repo.unparsed(), isEmpty);
    });

    test('resolved rows older than 90 days are purged on sync', () async {
      await db.insertUnparsed([
        UnparsedSms(key: 'sms:1', sender: 'AD-UCOBNK', body: ucoBody,
            time: DateTime.now().subtract(const Duration(days: 120)), state: 'ignored'),
        UnparsedSms(key: 'sms:2', sender: 'AD-UCOBNK', body: ucoBody,
            time: DateTime.now().subtract(const Duration(days: 120))),
      ]);
      final repo = TxnRepository(db, FakeSms(const []), FakeInbox());
      await repo.syncSms();
      final left = await repo.unparsed();
      expect(left.map((u) => u.key), ['sms:2'], reason: 'open rows are never purged');
    });
  });
```

Add the import:
```dart
import 'package:upitrack/models/unparsed.dart';
```

- [ ] **Step 2: Run to see it fail**

Run: `flutter test test/data/repository_test.dart`
Expected: compile error — `UnparsedSms` undefined.

- [ ] **Step 3: Create the model**

Create `lib/models/unparsed.dart`:

```dart
/// A bank-looking SMS the parser could not read. Shown to the user so it
/// can be added by hand, ignored, or reported.
class UnparsedSms {
  const UnparsedSms({
    this.id,
    required this.key,
    required this.sender,
    required this.body,
    required this.time,
    this.state = 'open',
  });

  final int? id;

  /// 'sms:<inbox id>' on Android, 'shortcut:<file id>' on iPhone.
  final String key;
  final String sender;
  final String body;
  final DateTime time;

  /// 'open', 'added' (user entered it manually) or 'ignored'.
  final String state;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'key': key,
        'sender': sender,
        'body': body,
        'ts': time.millisecondsSinceEpoch,
        'state': state,
      };

  factory UnparsedSms.fromMap(Map<String, Object?> m) => UnparsedSms(
        id: m['id'] as int?,
        key: m['key'] as String,
        sender: m['sender'] as String,
        body: m['body'] as String,
        time: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        state: m['state'] as String,
      );
}
```

- [ ] **Step 4: Schema v2 and DB methods**

In `lib/data/db.dart`:

Add the import:
```dart
import '../models/unparsed.dart';
```

In `open`, change `version: 1` to `version: 2`, add `await _createUnparsed(db);` as the last line of `onCreate`, and add an `onUpgrade` right after `onCreate`:

```dart
        onUpgrade: (db, from, to) async {
          if (from < 2) await _createUnparsed(db);
        },
```

Add after `open`:

```dart
  /// v2: bank SMS the parser couldn't read (spec §3.3).
  static Future<void> _createUnparsed(Database db) => db.execute('''
          CREATE TABLE unparsed(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key TEXT NOT NULL UNIQUE,
            sender TEXT NOT NULL,
            body TEXT NOT NULL,
            ts INTEGER NOT NULL,
            state TEXT NOT NULL DEFAULT 'open'
          )''');
```

Add after `setMeta`:

```dart
  // ---------------------------------------------------------------- unparsed

  /// Inserts rows, skipping keys already stored.
  Future<void> insertUnparsed(List<UnparsedSms> rows) async {
    if (rows.isEmpty) return;
    final batch = _db.batch();
    for (final u in rows) {
      batch.insert('unparsed', u.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<List<UnparsedSms>> openUnparsed() async {
    final rows = await _db.query('unparsed', where: "state = 'open'", orderBy: 'ts DESC');
    return rows.map(UnparsedSms.fromMap).toList();
  }

  Future<void> setUnparsedState(int id, String state) =>
      _db.update('unparsed', {'state': state}, where: 'id = ?', whereArgs: [id]);

  /// Deletes handled rows older than [before]. Open rows are kept.
  Future<void> purgeUnparsed({required DateTime before}) => _db.delete('unparsed',
      where: "state != 'open' AND ts < ?", whereArgs: [before.millisecondsSinceEpoch]);
```

- [ ] **Step 5: Record unparsed SMS in the repository**

In `lib/data/repository.dart`:

Add the import:
```dart
import '../models/unparsed.dart';
```

Add a constant next to `firstSyncWindow`:
```dart
  /// Handled "not recognised" rows are deleted after this long.
  static const Duration unparsedRetention = Duration(days: 90);
```

Replace the body of `syncSms` from `final messages = …` to `return added;` with:

```dart
    final messages = await _sms.readInbox(since: since);
    final rules = await _db.rules();
    final txns = <Txn>[];
    final unparsed = <UnparsedSms>[];
    for (final m in messages) {
      final t = _fromSms(
        sender: m.address,
        body: m.body,
        time: m.date,
        fallbackKey: 'sms:${m.id}',
        smsId: m.id,
        source: 'sms',
        rules: rules,
      );
      if (t != null) {
        txns.add(t);
      } else if (SmsParser.looksLikeTransaction(m.address, m.body)) {
        unparsed.add(UnparsedSms(key: 'sms:${m.id}', sender: m.address, body: m.body, time: m.date));
      }
    }

    final added = await _db.insertAll(txns);
    await _db.insertUnparsed(unparsed);
    await _db.purgeUnparsed(before: now.subtract(unparsedRetention));
    await _db.setMeta('last_sync_ms', now.millisecondsSinceEpoch.toString());
    return added;
```

Replace the body of `syncShortcutInbox` from `final rules = …` to `final added = await _db.insertAll(txns);` with:

```dart
    final rules = await _db.rules();
    final txns = <Txn>[];
    final unparsed = <UnparsedSms>[];
    for (final m in messages) {
      final t = _fromSms(
        sender: m.sender,
        body: m.body,
        time: m.date,
        fallbackKey: 'shortcut:${m.id}',
        source: 'shortcut',
        rules: rules,
      );
      if (t != null) {
        txns.add(t);
      } else if (SmsParser.looksLikeTransaction(m.sender, m.body)) {
        unparsed.add(UnparsedSms(key: 'shortcut:${m.id}', sender: m.sender, body: m.body, time: m.date));
      }
    }
    final added = await _db.insertAll(txns);
    await _db.insertUnparsed(unparsed);
```

Add in the `shared` section, after `unhide`:

```dart
  // ----------------------------------------------------------- unparsed

  /// Bank-looking SMS the parser couldn't read, newest first.
  Future<List<UnparsedSms>> unparsed() => _db.openUnparsed();

  /// [state] is 'added' (user entered it by hand) or 'ignored'.
  Future<void> resolveUnparsed(UnparsedSms u, {required String state}) =>
      _db.setUnparsedState(u.id!, state);
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/data/repository_test.dart`
Expected: all pass, including both new tests.

- [ ] **Step 7: Analyze, full tests, commit**

```bash
flutter analyze && flutter test
git add lib/models/unparsed.dart lib/data/db.dart lib/data/repository.dart test/data/repository_test.dart
git commit -m "Keep bank SMS the parser couldn't read in an unparsed table" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 6: Anonymiser (spec §3.4)

Pure Dart. Masks what identifies a person; keeps amounts and the bank's wording, which is what the parser keys on.

**Files:**
- Create: `lib/parser/anonymise.dart`
- Create: `test/parser/anonymise_test.dart`

**Interfaces:**
- Produces: `String anonymise(String body)` (top-level function).

- [ ] **Step 1: Write the failing tests**

Create `test/parser/anonymise_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/parser/anonymise.dart';

void main() {
  test('masks account digits, reference and payee; keeps amount and bank words', () {
    expect(
      anonymise('Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 03/10/26\nRef 427612345678'),
      'Sent Rs.250.00\nFrom NAME Bank A/C *XXXX\nTo NAME\nOn 03/10/26\nRef XXXXXXXXXXXX',
    );
  });

  test('masks the UPI ID local part, keeps the handle and structure words', () {
    expect(
      anonymise('Rs.1,250.50 debited from A/c XX5678 on 03-10-2026 to VPA abc@ybl '
          '(UPI Ref No 427612343333). Avl Bal Rs.10,000.00'),
      // Years are 4 digits and get masked too; the parser never reads dates.
      'Rs.1,250.50 debited from A/c XXXXXX on 03-10-XXXX to VPA xxxx@ybl '
      '(UPI Ref No XXXXXXXXXXXX). Avl Bal Rs.10,000.00',
    );
  });

  test('keeps an amount written without a currency symbol', () {
    expect(
      anonymise('A/C X1234 debited by 12000 on date 03Oct26 trf to ZOMATO Refno 427698765432'),
      'A/C XXXXX debited by 12000 on date 03Oct26 trf to NAME Refno XXXXXXXXXXXX',
    );
  });

  test('masks a Title Case person name', () {
    expect(
      anonymise('credited with Rs 1000.00 on 03-Oct-26 from Rahul Kumar. UPI:427612340001'),
      'credited with Rs 1000.00 on 03-Oct-26 from NAME. UPI:XXXXXXXXXXXX',
    );
  });
}
```

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/parser/anonymise_test.dart`
Expected: compile error — `package:upitrack/parser/anonymise.dart` not found.

- [ ] **Step 3: Implement**

Create `lib/parser/anonymise.dart`:

```dart
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
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/parser/anonymise_test.dart`
Expected: 4 passed. If one fails, fix the regex, not the expectation — the expectations are the spec.

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze && flutter test
git add lib/parser/anonymise.dart test/parser/anonymise_test.dart
git commit -m "Add anonymise() for sharing unrecognised bank SMS" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 7: "Not recognised" screen, Add prefill, Report (spec §3.3)

**Files:**
- Modify: `lib/parser/sms_parser.dart` (add `firstAmountPaise`)
- Modify: `lib/screens/add_txn_sheet.dart` (prefill + `raw`)
- Modify: `lib/data/repository.dart:226-245` (`addManual` gets `raw`)
- Create: `lib/screens/unparsed_screen.dart`
- Modify: `lib/screens/home_screen.dart` (card + navigation)
- Test: `test/sms_parser_test.dart`
- Modify: `pubspec.yaml` (`share_plus`)

**Interfaces:**
- Consumes: `anonymise()` (Task 6); `TxnRepository.unparsed()`, `resolveUnparsed()`, `UnparsedSms` (Task 5); `dayLabel()` from `lib/util/format.dart`.
- Produces: `static int? SmsParser.firstAmountPaise(String body)`; `showAddTxnSheet(BuildContext, TxnRepository, {int? amountPaise, DateTime? date, String? raw})`; `TxnRepository.addManual({…, String? raw})`; `class UnparsedScreen extends StatefulWidget { UnparsedScreen({required TxnRepository repository}) }`.

- [ ] **Step 1: Failing test for `firstAmountPaise`**

Append inside `main()` in `test/sms_parser_test.dart`:

```dart
  group('firstAmountPaise', () {
    test('first transaction amount, skipping balances', () {
      expect(SmsParser.firstAmountPaise('withdrawal of INR 320.00 towards UPI'), 32000);
      expect(SmsParser.firstAmountPaise('A/c debited by 120.0 trf to X'), 12000);
      expect(SmsParser.firstAmountPaise('Avl Bal Rs.10,000.00 only'), isNull);
    });
  });
```

Run: `flutter test test/sms_parser_test.dart` → compile error, `firstAmountPaise` undefined.

- [ ] **Step 2: Implement `firstAmountPaise`**

In `lib/parser/sms_parser.dart`, after `looksLikeTransaction`:

```dart
  /// The transaction amount in an SMS [parse] rejected, used to prefill
  /// manual entry. Skips "Avl Bal" style amounts like [parse] does.
  static int? firstAmountPaise(String body) => _amount(body);
```

Run: `flutter test test/sms_parser_test.dart` → all pass.

- [ ] **Step 3: Add `share_plus`**

Run: `flutter pub add share_plus`
Expected: resolves to 11.x or newer (the `SharePlus.instance.share(ShareParams(...))` API). If `flutter pub add` resolved below 11, run `flutter pub add share_plus:^11.0.0`.

- [ ] **Step 4: `addManual` carries the original SMS**

In `lib/data/repository.dart`, change `addManual`:

```dart
  /// For cash, UPI Lite or anything that didn't come with a bank SMS.
  /// [raw] is the original SMS when the entry comes from the
  /// "not recognised" list, so the detail sheet can still show it.
  Future<void> addManual({
    required int amountPaise,
    required bool isDebit,
    required String counterparty,
    required String category,
    required DateTime time,
    String? raw,
  }) =>
      _db.insertAll([
        Txn(
          key: 'manual:${DateTime.now().microsecondsSinceEpoch}',
          amountPaise: amountPaise,
          isDebit: isDebit,
          counterparty: counterparty,
          channel: 'Cash',
          category: category,
          time: time,
          raw: raw,
          manual: true,
          source: 'manual',
        ),
      ]);
```

- [ ] **Step 5: Prefill the Add sheet**

In `lib/screens/add_txn_sheet.dart`:

Replace `showAddTxnSheet` and the widget's constructor/fields:

```dart
/// Manual entry for cash, UPI Lite, or anything without a bank SMS.
/// [amountPaise], [date] and [raw] prefill it from an unrecognised SMS.
/// Returns true if a transaction was added.
Future<bool?> showAddTxnSheet(
  BuildContext context,
  TxnRepository repository, {
  int? amountPaise,
  DateTime? date,
  String? raw,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AddTxnSheet(
      repository: repository,
      amountPaise: amountPaise,
      date: date,
      raw: raw,
    ),
  );
}

class _AddTxnSheet extends StatefulWidget {
  const _AddTxnSheet({
    required this.repository,
    this.amountPaise,
    this.date,
    this.raw,
  });

  final TxnRepository repository;
  final int? amountPaise;
  final DateTime? date;
  final String? raw;

  @override
  State<_AddTxnSheet> createState() => _AddTxnSheetState();
}
```

In `_AddTxnSheetState`, replace the two field declarations:

```dart
  late final _amount = TextEditingController(
      text: widget.amountPaise == null ? '' : _amountText(widget.amountPaise!));
  late DateTime _date = widget.date ?? DateTime.now();
```

(keep `_payee`, `_isDebit`, `_category`, `_error` as they are), add the helper:

```dart
  /// 25000 → "250", 12050 → "120.50".
  static String _amountText(int paise) =>
      paise % 100 == 0 ? '${paise ~/ 100}' : (paise / 100).toStringAsFixed(2);
```

and pass `raw` in `_save`:

```dart
    await widget.repository.addManual(
      amountPaise: (value * 100).round(),
      isDebit: _isDebit,
      counterparty: payee.isEmpty ? (_isDebit ? 'Cash' : 'Cash received') : payee,
      category: _isDebit ? _category : 'Income',
      time: _date,
      raw: widget.raw,
    );
```

- [ ] **Step 6: Create the screen**

Create `lib/screens/unparsed_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repository.dart';
import '../models/unparsed.dart';
import '../parser/anonymise.dart';
import '../parser/sms_parser.dart';
import '../util/format.dart';
import 'add_txn_sheet.dart';

/// Bank SMS the parser couldn't read. Each can be added by hand, ignored, or
/// shared (anonymised) so the parser can be taught the new format.
class UnparsedScreen extends StatefulWidget {
  const UnparsedScreen({super.key, required this.repository});

  final TxnRepository repository;

  @override
  State<UnparsedScreen> createState() => _UnparsedScreenState();
}

class _UnparsedScreenState extends State<UnparsedScreen> {
  List<UnparsedSms>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.repository.unparsed();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _add(UnparsedSms u) async {
    final added = await showAddTxnSheet(
      context,
      widget.repository,
      amountPaise: SmsParser.firstAmountPaise(u.body),
      date: u.time,
      raw: u.body,
    );
    if (added == true) {
      await widget.repository.resolveUnparsed(u, state: 'added');
      await _load();
    }
  }

  Future<void> _ignore(UnparsedSms u) async {
    await widget.repository.resolveUnparsed(u, state: 'ignored');
    await _load();
  }

  Future<void> _report(UnparsedSms u) => SharePlus.instance.share(ShareParams(
        subject: 'UPI Track: bank SMS not recognised',
        text: 'Sender: ${u.sender}\n\n${anonymise(u.body)}\n\n'
            'Shared from UPI Track. Names, account numbers, references and '
            'UPI IDs have been masked.',
      ));

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Not recognised')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('Every bank SMS was understood.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Text(
                      'These look like bank payments but the app could not read '
                      'them. Add them by hand, or report one so the next version '
                      'understands it. Reports are anonymised.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final u in items)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${u.sender} · ${dayLabel(u.time)}',
                                  style: text.labelLarge),
                              const SizedBox(height: 6),
                              Text(u.body,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                      onPressed: () => _report(u),
                                      child: const Text('Report')),
                                  TextButton(
                                      onPressed: () => _ignore(u),
                                      child: const Text('Ignore')),
                                  FilledButton.tonal(
                                      onPressed: () => _add(u),
                                      child: const Text('Add')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
```

- [ ] **Step 7: Home screen card**

In `lib/screens/home_screen.dart`:

Import:
```dart
import 'unparsed_screen.dart';
```

Add a field next to `_shortcutCount`:
```dart
  int _unparsedCount = 0;
```

Replace `_load`:
```dart
  Future<void> _load() async {
    final txns = await widget.repository
        .between(_month, DateTime(_month.year, _month.month + 1));
    final unparsed = await widget.repository.unparsed();
    if (mounted) {
      setState(() {
        _txns = txns;
        _unparsedCount = unparsed.length;
      });
    }
  }
```

Add next to `_openHidden`:
```dart
  Future<void> _openUnparsed() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => UnparsedScreen(repository: widget.repository),
    ));
    await _load();
  }
```

In `build`, insert directly before `_MonthSwitcher(`:
```dart
            if (_unparsedCount > 0)
              _UnparsedCard(count: _unparsedCount, onTap: _openUnparsed),
```

Add the widget at the end of the file:
```dart
class _UnparsedCard extends StatelessWidget {
  const _UnparsedCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.help_outline),
        title: Text(count == 1
            ? '1 bank SMS could not be read'
            : '$count bank SMS could not be read'),
        subtitle: const Text('Add them by hand or report them'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
```

- [ ] **Step 8: Analyze, test, commit**

```bash
flutter analyze && flutter test
git add pubspec.yaml pubspec.lock lib/parser/sms_parser.dart lib/data/repository.dart lib/screens/add_txn_sheet.dart lib/screens/unparsed_screen.dart lib/screens/home_screen.dart test/sms_parser_test.dart
git commit -m "Add the Not recognised screen: add by hand, ignore or report" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

Manual check (when an APK is available): on a phone, the card appears after a sync that finds an unreadable bank SMS; Add opens the sheet with the amount and date filled; Report opens the share sheet with masked text.

---

### Task 8: Commit the Android platform files with desugaring

`flutter_local_notifications` (Task 10) needs Java core-library desugaring in `android/app/build.gradle.kts`, and that file is not in the repo today — CI generates it with `flutter create` on every run. This task generates the Android folder once, edits it, and commits it so builds are deterministic.

**Files:**
- Generate + commit: `android/**` (Gradle scripts, launcher icons, themes), `.metadata`
- Modify: `android/app/build.gradle.kts`
- Modify: `.github/workflows/build.yml` (android job)

**Interfaces:**
- Produces: a committed `android/` project where `flutter build apk --release` works without `flutter create`.

- [ ] **Step 1: Generate the Android project**

Run: `cd ~/upitrack && flutter create --platforms=android --org com.piyush --project-name upitrack .`
Expected: output lists created files under `android/`; existing files (`AndroidManifest.xml`, `MainActivity.kt`, `pubspec.yaml`, `lib/`, `test/`) are untouched. Confirm with `git status --short` — no `M` next to `lib/`, `test/` or `pubspec.yaml`. If `pubspec.yaml` or `lib/main.dart` shows as modified, run `git checkout -- pubspec.yaml lib/main.dart`.

- [ ] **Step 2: Enable desugaring**

Open `android/app/build.gradle.kts`. Inside the existing `android { … compileOptions { … } }` block add the first line so it reads:

```kotlin
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
```

and append at the end of the file:

```kotlin
dependencies {
    // Required by flutter_local_notifications (java.time on older Android).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

- [ ] **Step 3: Stop CI from regenerating Android files**

In `.github/workflows/build.yml`, in the `android` job, delete the step named `Generate missing platform files` (the `flutter create --platforms=android …` run). Leave the `ios` job's `flutter create --platforms=ios` step as is.

- [ ] **Step 4: Check what will be committed**

Run: `git status --short | grep -v '^??.*local.properties'`
Expected: new files under `android/` (no `local.properties`, no `GeneratedPluginRegistrant.java` — both are gitignored), `.metadata`, and `M .github/workflows/build.yml`. Then `flutter analyze && flutter test` still pass (the analyzer excludes `android/`).

- [ ] **Step 5: Commit**

```bash
git add android .metadata .github/workflows/build.yml
git commit -m "Commit the Android project with core-library desugaring" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

Verification happens in CI after the branch is pushed: the `Tests + Android APK` job must still produce `upitrack-apk`.

---

### Task 9: Update check and release workflow (spec §3.6)

**Files:**
- Create: `lib/util/update_check.dart`
- Create: `test/util/update_check_test.dart`
- Modify: `lib/main.dart`, `lib/screens/home_screen.dart`
- Create: `.github/workflows/release.yml`
- Modify: `pubspec.yaml` (`http`, `package_info_plus`, `url_launcher`)

**Interfaces:**
- Consumes: `AppDb.getMeta/setMeta`, `AppDb.open(factory:, path:)` (Task 1).
- Produces: `bool isNewerVersion(String tag, String current)`; `class UpdateInfo { String tag; String url; }`; `class UpdateChecker { UpdateChecker(AppDb db, {required String currentVersion, http.Client? client, String repo}); Future<UpdateInfo?> check({DateTime? now}); Future<void> dismiss(String tag); }`; `HomeScreen({required repository, UpdateChecker? updateChecker})`.

- [ ] **Step 1: Add dependencies**

Run: `flutter pub add http package_info_plus url_launcher`

- [ ] **Step 2: Write the failing tests**

Create `test/util/update_check_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/util/update_check.dart';

void main() {
  sqfliteFfiInit();

  test('isNewerVersion compares major.minor.patch and ignores v/+/-', () {
    expect(isNewerVersion('v0.2.0', '0.1.0'), isTrue);
    expect(isNewerVersion('v0.1.0', '0.1.0'), isFalse);
    expect(isNewerVersion('v0.1.0', '0.2.0'), isFalse);
    expect(isNewerVersion('v1.0.0', '0.9.9'), isTrue);
    expect(isNewerVersion('v0.1.1-beta', '0.1.0+5'), isTrue);
  });

  group('UpdateChecker', () {
    late AppDb db;
    var calls = 0;
    late UpdateChecker checker;

    setUp(() async {
      db = await AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      calls = 0;
      checker = UpdateChecker(
        db,
        currentVersion: '0.1.0',
        client: MockClient((req) async {
          calls++;
          expect(req.url.path, '/repos/aksh0609/upitrack/releases/latest');
          return http.Response(
            '{"tag_name":"v0.2.0","html_url":"https://github.com/aksh0609/upitrack/releases/tag/v0.2.0"}',
            200,
          );
        }),
      );
    });
    tearDown(() => db.close());

    test('asks GitHub once a day and reports a newer release', () async {
      final t0 = DateTime(2026, 10, 7, 9);
      final info = await checker.check(now: t0);
      expect(info?.tag, 'v0.2.0');
      expect(info?.url, endsWith('/tag/v0.2.0'));
      expect(calls, 1);

      await checker.check(now: t0.add(const Duration(hours: 23)));
      expect(calls, 1, reason: 'within 24 h the stored answer is reused');
      await checker.check(now: t0.add(const Duration(hours: 25)));
      expect(calls, 2);
    });

    test('a dismissed version is not shown again', () async {
      await checker.dismiss('v0.2.0');
      expect(await checker.check(now: DateTime(2026, 10, 7)), isNull);
    });

    test('the installed version is not an update', () async {
      final same = UpdateChecker(
        db,
        currentVersion: '0.2.0',
        client: MockClient((_) async => http.Response('{"tag_name":"v0.2.0","html_url":"u"}', 200)),
      );
      expect(await same.check(now: DateTime(2026, 10, 7)), isNull);
    });

    test('network failure is silent and retried next time', () async {
      final failing = UpdateChecker(
        db,
        currentVersion: '0.1.0',
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await failing.check(now: DateTime(2026, 10, 7)), isNull);
      expect(await db.getMeta('update_checked_ms'), isNull);
    });
  });
}
```

- [ ] **Step 3: Run to see them fail**

Run: `flutter test test/util/update_check_test.dart`
Expected: compile error — `package:upitrack/util/update_check.dart` not found.

- [ ] **Step 4: Implement**

Create `lib/util/update_check.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/db.dart';

/// 'v0.2.0' is newer than '0.1.5'. Compares major.minor.patch; ignores a
/// leading 'v', build numbers ('+5') and pre-release tags ('-beta').
bool isNewerVersion(String tag, String current) {
  List<int> parse(String v) => RegExp(r'\d+')
      .allMatches(v.split(RegExp(r'[-+]')).first)
      .map((m) => int.parse(m.group(0)!))
      .toList();
  final a = parse(tag);
  final b = parse(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

class UpdateInfo {
  const UpdateInfo({required this.tag, required this.url});

  /// Git tag of the release, e.g. 'v0.2.0'.
  final String tag;

  /// The release page, where the APK is attached.
  final String url;
}

/// Asks GitHub for the latest release at most once a day and remembers the
/// answer in `meta`. Only shown on Android: the web app is always current
/// and iPhones update through TestFlight.
class UpdateChecker {
  UpdateChecker(
    this._db, {
    required this.currentVersion,
    http.Client? client,
    this.repo = 'aksh0609/upitrack',
  }) : _client = client ?? http.Client();

  final AppDb _db;
  final String currentVersion;
  final http.Client _client;
  final String repo;

  static const Duration interval = Duration(hours: 24);

  /// A newer release the user hasn't dismissed, or null.
  Future<UpdateInfo?> check({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final last = int.tryParse(await _db.getMeta('update_checked_ms') ?? '') ?? 0;
    if (t.millisecondsSinceEpoch - last >= interval.inMilliseconds) {
      await _fetch(t);
    }
    final tag = await _db.getMeta('update_tag');
    final url = await _db.getMeta('update_url');
    if (tag == null || url == null) return null;
    if (tag == await _db.getMeta('update_dismissed')) return null;
    return isNewerVersion(tag, currentVersion) ? UpdateInfo(tag: tag, url: url) : null;
  }

  Future<void> _fetch(DateTime now) async {
    try {
      final r = await _client
          .get(
            Uri.https('api.github.com', '/repos/$repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      await _db.setMeta('update_tag', json['tag_name'] as String);
      await _db.setMeta('update_url', json['html_url'] as String);
      await _db.setMeta('update_checked_ms', now.millisecondsSinceEpoch.toString());
    } catch (_) {
      // Offline, rate-limited or GitHub down: try again on the next open.
    }
  }

  /// Hide this tag's banner. A later release shows a banner again.
  Future<void> dismiss(String tag) => _db.setMeta('update_dismissed', tag);
}
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/util/update_check_test.dart`
Expected: 5 passed.

- [ ] **Step 6: Wire it into the app**

`lib/main.dart` — replace `main()` and add the parameter:

```dart
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'data/db.dart';
import 'data/repository.dart';
import 'data/shortcut_inbox.dart';
import 'data/sms_source.dart';
import 'screens/home_screen.dart';
import 'util/update_check.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDb.open();
  final info = await PackageInfo.fromPlatform();
  runApp(UpiTrackApp(
    repository: TxnRepository(db, SmsSource(), ShortcutInbox()),
    updateChecker: UpdateChecker(db, currentVersion: info.version),
  ));
}

class UpiTrackApp extends StatelessWidget {
  const UpiTrackApp({super.key, required this.repository, this.updateChecker});

  final TxnRepository repository;
  final UpdateChecker? updateChecker;
```

and pass it on: `home: HomeScreen(repository: repository, updateChecker: updateChecker),`.

`lib/screens/home_screen.dart`:

Imports:
```dart
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../util/update_check.dart';
```

Constructor:
```dart
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, this.updateChecker});

  final TxnRepository repository;
  final UpdateChecker? updateChecker;
```

State field next to `_unparsedCount`:
```dart
  UpdateInfo? _update;
```

In `initState`, after `_checkAccess();` add `_checkUpdate();` and add the method:
```dart
  /// Android only: the APK is installed by hand, so tell people about new
  /// releases. Web is always current; iPhone updates through TestFlight.
  Future<void> _checkUpdate() async {
    final checker = widget.updateChecker;
    if (checker == null || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final info = await checker.check();
    if (mounted) setState(() => _update = info);
  }

  Future<void> _dismissUpdate() async {
    await widget.updateChecker!.dismiss(_update!.tag);
    if (mounted) setState(() => _update = null);
  }
```

In `build`, as the first child of the `ListView` (before the permission card):
```dart
            if (_update != null)
              _UpdateCard(
                info: _update!,
                onDownload: () => launchUrl(Uri.parse(_update!.url),
                    mode: LaunchMode.externalApplication),
                onDismiss: _dismissUpdate,
              ),
```

Widget at the end of the file:
```dart
class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.info,
    required this.onDownload,
    required this.onDismiss,
  });

  final UpdateInfo info;
  final VoidCallback onDownload;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${info.tag.replaceFirst('v', '')} is available',
                style: text.titleMedium),
            const SizedBox(height: 4),
            Text('Download the new APK and open it to update.',
                style: text.bodyMedium),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDismiss, child: const Text('Later')),
                FilledButton(onPressed: onDownload, child: const Text('Download')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Release workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release

# Tag a commit `vX.Y.Z` (matching `version:` in pubspec.yaml) and push the
# tag: this builds the APK and attaches it to a GitHub Release. The app's
# update banner reads that release.
on:
  push:
    tags: ['v*']

permissions:
  contents: write

jobs:
  apk:
    name: Release APK
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check the tag matches pubspec.yaml
        run: |
          v=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)
          [ "v$v" = "$GITHUB_REF_NAME" ] || { echo "pubspec version $v but tag is $GITHUB_REF_NAME"; exit 1; }

      - uses: actions/setup-java@v4
        with:
          distribution: zulu
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - run: flutter pub get
      - run: flutter test
      - run: flutter build apk --release

      - uses: softprops/action-gh-release@v2
        with:
          files: build/app/outputs/flutter-apk/app-release.apk
          generate_release_notes: true
```

- [ ] **Step 8: Analyze, test, commit**

```bash
flutter analyze && flutter test
git add pubspec.yaml pubspec.lock lib/util/update_check.dart test/util/update_check_test.dart lib/main.dart lib/screens/home_screen.dart .github/workflows/release.yml
git commit -m "Show an update banner on Android from GitHub Releases" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

### Task 10: Live SMS notification on Android (spec §3.5)

A manifest `BroadcastReceiver` starts a background Dart entrypoint that parses the SMS with the existing parser and shows a notification. **It never writes to the database**; the inbox sync on next open records the payment.

**Files:**
- Modify: `lib/parser/categorizer.dart` (add `categorizeWith`)
- Modify: `lib/data/repository.dart:131-133` (`_category` uses it)
- Create: `lib/background/sms_notification.dart`, `lib/background/sms_background.dart`
- Modify: `lib/main.dart` (entrypoint)
- Create: `android/app/src/main/kotlin/com/piyush/upitrack/SmsReceiver.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `lib/screens/home_screen.dart:83-92` (`_requestAccess`)
- Test: `test/categorizer_test.dart`, `test/background/sms_notification_test.dart`
- Modify: `pubspec.yaml` (`flutter_local_notifications`)

**Interfaces:**
- Consumes: `SmsParser.parse`, `ParsedTxn` (existing); `AppDb.open()`, `AppDb.rules()`, `AppDb.close()` (Task 1); `formatPaise` (existing).
- Produces: `static String Categorizer.categorizeWith(Map<String, String> rules, String counterparty, {required bool isDebit})`; `({String title, String body}) notificationText(ParsedTxn t, String category)`; `Future<void> runSmsBackground()`; `Future<void> notifyForSms({required String address, required String body})`; Dart entrypoint `smsBackground` in `lib/main.dart`; Kotlin `SmsReceiver` on method channel `upitrack/sms_bg` with methods `ready` (Dart → Kotlin) and `sms` (Kotlin → Dart, args `{address, body}`).

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add flutter_local_notifications`

- [ ] **Step 2: Failing test for `categorizeWith`**

Append inside the `Categorizer` group in `test/categorizer_test.dart`:

```dart
    test('categorizeWith prefers the remembered rule for debits only', () {
      const rules = {'SWIGGY': 'Groceries'};
      expect(Categorizer.categorizeWith(rules, 'SWIGGY', isDebit: true), 'Groceries');
      expect(Categorizer.categorizeWith(rules, 'ZOMATO', isDebit: true), 'Food');
      expect(Categorizer.categorizeWith(rules, 'SWIGGY', isDebit: false), 'Income');
    });
```

Run: `flutter test test/categorizer_test.dart` → compile error, `categorizeWith` undefined.

- [ ] **Step 3: Implement and reuse it in the repository**

In `lib/parser/categorizer.dart`, after `categorize`:

```dart
  /// The user's remembered choice for this payee, else the keyword guess.
  /// Rules only apply to money going out.
  static String categorizeWith(
    Map<String, String> rules,
    String counterparty, {
    required bool isDebit,
  }) =>
      (isDebit ? rules[counterparty] : null) ??
      categorize(counterparty, isDebit: isDebit);
```

In `lib/data/repository.dart`, replace `_category`:

```dart
  String _category(String counterparty, bool isDebit, Map<String, String> rules) =>
      Categorizer.categorizeWith(rules, counterparty, isDebit: isDebit);
```

Run: `flutter test` → all pass.

- [ ] **Step 4: Failing test for the notification text**

Create `test/background/sms_notification_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/background/sms_notification.dart';
import 'package:upitrack/parser/sms_parser.dart';

void main() {
  test('debit: amount, payee, category, bank and account', () {
    final t = SmsParser.parse(
      'VM-HDFCBK',
      'Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 03/10/26\nRef 427612345678',
    )!;
    final n = notificationText(t, 'Food');
    expect(n.title, '-₹250 to SWIGGY');
    expect(n.body, 'Food · HDFC Bank · •••1234');
  });

  test('credit: no category line', () {
    final t = SmsParser.parse(
      'VM-HDFCBK',
      'Received Rs.500.00 in your HDFC Bank A/c XX1234 from VPA rahul@okicici '
          'on 03-10-26. UPI Ref: 427612345679',
    )!;
    final n = notificationText(t, 'Income');
    expect(n.title, '+₹500 from rahul@okicici');
    expect(n.body, 'HDFC Bank · •••1234');
  });

  test('unknown payee', () {
    final t = SmsParser.parse(
      'AD-SBIUPI',
      'Dear SBI UPI User, ur A/cX1234 credited by Rs500 on 03Oct26 by (Ref no 427612345670)',
    )!;
    expect(notificationText(t, 'Income').title, '+₹500 from Unknown');
  });
}
```

Run: `flutter test test/background/sms_notification_test.dart` → compile error, file not found.

- [ ] **Step 5: Implement the pure part**

Create `lib/background/sms_notification.dart`:

```dart
import '../parser/sms_parser.dart';
import '../util/format.dart';

/// Title and body of the "payment caught" notification, e.g.
/// "-₹250 to SWIGGY" / "Food · HDFC Bank · •••1234". Pure, tested in
/// `test/background/sms_notification_test.dart`.
({String title, String body}) notificationText(ParsedTxn t, String category) {
  final who = t.counterparty ?? 'Unknown';
  final amount = formatPaise(t.amountPaise);
  final title = t.isDebit ? '-$amount to $who' : '+$amount from $who';
  final body = [
    if (t.isDebit) category,
    if (t.bank != null) t.bank!,
    if (t.account != null) '•••${t.account}',
  ].join(' · ');
  return (title: title, body: body);
}
```

Run: `flutter test test/background/sms_notification_test.dart` → 3 passed.

- [ ] **Step 6: Background entrypoint**

Create `lib/background/sms_background.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/db.dart';
import '../parser/categorizer.dart';
import '../parser/sms_parser.dart';
import 'sms_notification.dart';

/// Body of the `smsBackground` entrypoint in main.dart. Started by
/// android/.../SmsReceiver.kt when an SMS arrives while the app may be
/// closed. Shows a notification and nothing else: the inbox sync on next
/// open records the payment, so nothing is written here (spec §3.5).
Future<void> runSmsBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('upitrack/sms_bg');
  channel.setMethodCallHandler((call) async {
    if (call.method != 'sms') return null;
    final args = (call.arguments as Map).cast<String, Object?>();
    await notifyForSms(
      address: args['address'] as String? ?? '',
      body: args['body'] as String? ?? '',
    );
    return null;
  });
  // Tell Kotlin the handler is in place; it answers with the 'sms' call.
  await channel.invokeMethod<void>('ready');
}

Future<void> notifyForSms({required String address, required String body}) async {
  final parsed = SmsParser.parse(address, body);
  if (parsed == null) return;

  final db = await AppDb.open();
  final rules = await db.rules();
  await db.close();
  final who = parsed.counterparty ?? 'Unknown';
  final category = Categorizer.categorizeWith(rules, who, isDebit: parsed.isDebit);
  final text = notificationText(parsed, category);

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));
  await plugin.show(
    (parsed.ref ?? body).hashCode,
    text.title,
    text.body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'payments',
        'Payments',
        channelDescription: 'A payment was caught from a bank SMS',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    ),
  );
}
```

In `lib/main.dart` add the import and the entrypoint (top level, after `main`):

```dart
import 'background/sms_background.dart';
```

```dart
/// Started by android/.../SmsReceiver.kt when a bank SMS arrives. It must be
/// a top-level function in a library the app imports, or the compiler
/// tree-shakes it away.
@pragma('vm:entry-point')
Future<void> smsBackground() => runSmsBackground();
```

- [ ] **Step 7: The Kotlin receiver**

Create `android/app/src/main/kotlin/com/piyush/upitrack/SmsReceiver.kt`:

```kotlin
package com.piyush.upitrack

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Runs when any SMS arrives. Starts a small background Flutter engine on the
 * Dart entrypoint `smsBackground` (lib/main.dart), hands it the sender and
 * body, and tears the engine down once Dart has shown its notification.
 * Nothing is stored here; the app's inbox sync records the payment later.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (parts.isEmpty()) return
        val address = parts[0].displayOriginatingAddress ?: ""
        val body = parts.joinToString("") { it.messageBody ?: "" }

        val pending = goAsync()
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)

        val engine = FlutterEngine(app)
        val handler = Handler(Looper.getMainLooper())
        var finished = false
        lateinit var timeout: Runnable
        fun finish() {
            if (finished) return
            finished = true
            handler.removeCallbacks(timeout)
            engine.destroy()
            pending.finish()
        }
        // Android ends a broadcast at 10 s; stop a little before that.
        timeout = Runnable { finish() }
        handler.postDelayed(timeout, 9_000)

        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                result.success(null)
                channel.invokeMethod(
                    "sms",
                    mapOf("address" to address, "body" to body),
                    object : MethodChannel.Result {
                        override fun success(r: Any?) { finish() }
                        override fun error(code: String, msg: String?, details: Any?) { finish() }
                        override fun notImplemented() { finish() }
                    }
                )
            } else {
                result.notImplemented()
            }
        }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "smsBackground")
        )
    }

    companion object {
        const val CHANNEL = "upitrack/sms_bg"
    }
}
```

- [ ] **Step 8: Manifest**

In `android/app/src/main/AndroidManifest.xml`, after the `READ_SMS` permission add:

```xml
    <!-- Wake up when a bank SMS arrives, to show "₹250 to Swiggy" at once. -->
    <uses-permission android:name="android.permission.RECEIVE_SMS" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

and inside `<application>`, after the `</activity>` closing tag:

```xml
        <!-- Only the system can send this broadcast (BROADCAST_SMS). -->
        <receiver
            android:name=".SmsReceiver"
            android:exported="true"
            android:permission="android.permission.BROADCAST_SMS">
            <intent-filter>
                <action android:name="android.provider.Telephony.SMS_RECEIVED" />
            </intent-filter>
        </receiver>
```

- [ ] **Step 9: Ask for notification permission after SMS is granted**

In `lib/screens/home_screen.dart`, in `_requestAccess`, after `final status = await Permission.sms.request();` add:

```dart
    // Android 13+: notifications need their own permission. Older versions
    // return granted at once.
    if (status.isGranted) await Permission.notification.request();
```

- [ ] **Step 10: Analyze, test, commit**

```bash
flutter analyze && flutter test
git add pubspec.yaml pubspec.lock lib/parser/categorizer.dart lib/data/repository.dart lib/background lib/main.dart lib/screens/home_screen.dart android/app/src/main/kotlin/com/piyush/upitrack/SmsReceiver.kt android/app/src/main/AndroidManifest.xml test/categorizer_test.dart test/background/sms_notification_test.dart
git commit -m "Notify at once when a bank SMS arrives (Android)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

Manual check (needs the CI APK or an emulator with the Android SDK): install, allow SMS and notifications, then on an emulator run
`adb emu sms send VM-HDFCBK "Sent Rs.250.00 From HDFC Bank A/C *1234 To SWIGGY On 03/10/26 Ref 427612345678"`.
Expected: a notification "-₹250 to SWIGGY" / "Food · HDFC Bank · •••1234" within a second; opening the app then lists the payment once (not twice). On a real phone, pay yourself ₹1 by UPI instead.

---

### Task 11: README and small cleanups

**Files:**
- Modify: `README.md`
- Modify: `lib/data/statement_reader.dart:2` (drop the unneeded `dart:typed_data` import flagged by `flutter analyze`)
- Modify: `analysis_options.yaml` (already changed by `flutter pub get`: excludes `build/`, `android/`, `ios/` — keep it)

- [ ] **Step 1: Remove the unneeded import**

In `lib/data/statement_reader.dart` delete the line `import 'dart:typed_data';` (`Uint8List` comes from `package:flutter/foundation.dart`). Run `flutter analyze` → `No issues found!`.

- [ ] **Step 2: README — features**

In `README.md`, under `## Features`, add these bullets after `- Light and dark mode`:

```markdown
- **Didn't catch this?** A bank SMS the app can't read is kept in a "Not recognised" list: add it by hand, ignore it, or report an anonymised copy so the next version understands it
- **Instant notifications (Android):** "-₹250 to SWIGGY · Food" the moment the bank SMS arrives, even with the app closed
- Hidden payments can be restored from menu → Hidden
- Tells you when a new version is available (Android; the APK is installed by hand)
```

- [ ] **Step 3: README — downloads and releases**

Replace the `## Get the Android APK without installing anything` section with:

```markdown
## Get the Android APK

The latest release is on the [Releases page](https://github.com/aksh0609/upitrack/releases/latest): download `app-release.apk`, copy it to your Android phone and open it (allow "Install unknown apps" when asked). The app shows a banner when a newer release exists.

Every push to `main` also builds a test APK: open the **Actions** tab, pick the latest **Test and build** run and download the **upitrack-apk** artifact.

### Releasing a new version

1. Bump `version:` in `pubspec.yaml` (e.g. `0.2.0+2`).
2. Commit, then tag and push: `git tag v0.2.0 && git push origin main v0.2.0`.
3. The **Release** workflow builds the APK and attaches it to a GitHub Release. The tag must match the pubspec version or the workflow stops.
```

- [ ] **Step 4: README — build locally and limits**

In `## Build locally`, replace the `flutter create --platforms=android,ios …` line and its comment with:

```bash
# The Android project is committed. iOS files are generated once:
flutter create --platforms=ios --org com.piyush --project-name upitrack .
```

Under `## Limitations` add:

```markdown
- Instant notifications depend on Android delivering the SMS broadcast; some phones (Xiaomi, Vivo, Oppo) block it under battery saving. Opening the app still catches up from the inbox.
```

Under `## Adding a bank or fixing a missed transaction`, replace step 1 with:

```markdown
1. On the phone, open the "Not recognised" card and tap **Report** on the message — it shares an anonymised copy (names, account numbers, references and UPI IDs masked). Or copy the SMS and anonymise it by hand.
```

- [ ] **Step 5: Commit**

```bash
flutter analyze && flutter test
git add README.md lib/data/statement_reader.dart analysis_options.yaml
git commit -m "Document Phase 1: unrecognised SMS, notifications, hidden, releases" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015XMeTdAvdZkoVQhxR4LeXY"
```

---

## Self-review against the spec

| Spec | Task |
| --- | --- |
| §2 Phase 0 | Owner's action (push to GitHub, install, collect misses) — not a code task; Task 8/9 make the push produce an APK and releases |
| §3.1 duplicate fix | Task 2 |
| §3.2 unhide | Task 3 (`edit_ts = now` on unhide arrives with schema v3 in the Phase 2 plan) |
| §3.3 `looksLikeTransaction`, `unparsed` table, card, screen, Add/Ignore/Report, 90-day purge | Tasks 4, 5, 7 |
| §3.4 anonymiser | Task 6 |
| §3.5 receiver, background entrypoint, notification text, no DB writes, notification permission, battery-saver note | Tasks 8 (desugaring), 10, 11 |
| §3.6 update check, dismiss, release workflow, not on web/iOS | Task 9 |
| §6 README limits | Task 11 |

Names used across tasks were checked: `openTestDb`/`FakeSms`/`FakeInbox` (1 → 2, 3, 5), `UnparsedSms`/`unparsed()`/`resolveUnparsed()` (5 → 7), `anonymise()` (6 → 7), `showAddTxnSheet(…, {amountPaise, date, raw})` (7), `UpdateChecker.check({now})`/`dismiss(tag)` (9), `Categorizer.categorizeWith(rules, counterparty, isDebit:)` (10, used by repository and background), `notificationText(ParsedTxn, String)` (10).
