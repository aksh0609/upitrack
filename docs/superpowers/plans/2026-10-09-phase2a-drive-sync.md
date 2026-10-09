# Phase 2a — Google Drive Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every device keeps a full local copy and syncs it, encrypted, through a hidden folder in the user's Google Drive, so a second phone (and, in Phase 2b, the web app) shows the same payments, categories and hidden rows.

**Architecture:** Schema v3 adds `txns.edit_ts` and `rules.ts` so a human correction always beats an automatic import. A pure-Dart snapshot/merge layer (`lib/sync/snapshot.dart`, `merge.dart`) and a pure-Dart crypto layer (`lib/sync/crypto.dart`, PBKDF2 + AES-256-GCM) sit under a `SyncService` that talks to a four-method `SyncStore`. The only Drive-specific code is `DriveSyncStore` plus a thin `GoogleAuth` wrapper; tests use an in-memory store. A `SyncController` (ChangeNotifier) owns sign-in state, the key, debounced triggers and "last synced" for the UI; a Settings screen hosts the flow.

**Tech Stack:** Flutter 3.47 stable / Dart 3.13, sqflite 2.4 (+ sqflite_common_ffi in tests), `cryptography` 2.9, `flutter_secure_storage` 11.2, `google_sign_in` 7.2, `googleapis` 17 (Drive v3), `extension_google_sign_in_as_googleapis_auth` 3.0, existing `http` 1.6.

**Spec:** `docs/superpowers/specs/2026-10-07-upitrack-v2-design.md` §4.1–§4.7 and §4.9 (sync). §4.8 (web build) is Phase 2b, a separate plan. Spec §3.3's "Phase 2's `edit_ts` makes this exact" is honoured here: pairing switches to `edit_ts`, and Phase 1b's `unpaired_ids` meta key is migrated away.

## Global Constraints

- Flutter is at `~/flutter/bin`; every `flutter`/`dart` command assumes `export PATH=$HOME/flutter/bin:$PATH`.
- Work on branch `phase2a-drive-sync`, created from `main` (at or after `f639cf6`). Commit after every task.
- Every commit message ends with the two lines
  `Co-Authored-By: <model that wrote it> <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01JRLLy55rhHqrkMzo7AVgEa` (the second line verbatim).
- `flutter analyze` must report `No issues found!` and the full `flutter test` suite must pass before each commit (79 tests at the start of this plan).
- Pure Dart, **no Flutter imports**: `lib/parser/*`, `lib/models/*`, `lib/sync/snapshot.dart`, `lib/sync/merge.dart`, `lib/sync/crypto.dart`, `lib/sync/sync_store.dart`, `lib/sync/sync_service.dart`, `lib/sync/sync_setup.dart`, `lib/sync/drive_sync_store.dart`. (`lib/sync/sync_controller.dart`, `sync_keys.dart`, `google_auth.dart` may import Flutter/plugins.)
- Schema: `AppDb.open` moves to `version: 3`. The only DDL is in `_upgradeToV3`: `ALTER TABLE txns ADD COLUMN edit_ts INTEGER NOT NULL DEFAULT 0` and `ALTER TABLE rules ADD COLUMN ts INTEGER NOT NULL DEFAULT 0`. `txns.key` values are never changed.
- `edit_ts` is `0` for every automatically inserted or automatically relabelled row (SMS, shortcut, statement, self-transfer pairing) and `now` (ms since epoch) only when the user changes a category or hides/unhides. Manual entries get `edit_ts = now` at creation and key `manual:<deviceId>:<micros>`.
- `rules.ts = now` on every `setCategoryForPayee`. Every write that changes `txns` or `rules` sets meta `sync_dirty = '1'`.
- Meta keys (exact): `device_id`, `sync_dirty`, `seen:<file name>`, `drive_last_ok_ms`. Phase 1b's `unpaired_ids` is removed by the v3 migration.
- Drive layout (exact): folder `appDataFolder`, scope `https://www.googleapis.com/auth/drive.appdata`; files `meta.json` (plain) and `dev-<deviceId>.json.enc` (encrypted snapshot). Each device writes only its own `dev-*` file.
- Crypto (exact): PBKDF2-HMAC-SHA256, 200 000 iterations, 16-byte random salt, 32-byte key; each file is `12-byte nonce ‖ AES-256-GCM ciphertext ‖ 16-byte tag`; `meta.check` is the encryption of the ASCII string `upitrack-key-ok`. The derived key, never the passphrase, is stored with `flutter_secure_storage`.
- Snapshot JSON (exact): `{"v": 1, "device": "<deviceId>", "exported_ms": <int>, "txns": [...Txn.toMap() incl. hidden, edit_ts...], "rules": [{"counterparty", "category", "ts"}]}`. No gzip in this plan (see Deviations).
- The category name `Self transfer` (`Categorizer.selfTransfer`) is never written as a payee rule (Phase 1b guard stays).
- No Android SDK on this machine: `flutter analyze` + `flutter test` are the local verification; the APK is built by CI. `minSdk` is Flutter's default 24.
- Dependencies added, exactly these: `cryptography: ^2.9.0`, `flutter_secure_storage: ^11.2.0`, `google_sign_in: ^7.2.0`, `googleapis: ^17.0.0`, `extension_google_sign_in_as_googleapis_auth: ^3.0.0`.

### Deviations from the spec, decided in this plan

- **No gzip.** Spec §4.4 gzips before encrypting. `dart:io`'s `GZipCodec` is unavailable on web (Phase 2b), the pure-Dart `archive` package would be a new dependency, and a personal-finance snapshot is ~300 B/row (one year ≈ 1 MB). Add gzip inside `encodeSnapshot`/`decodeSnapshot` with a `v: 2` bump if a snapshot ever passes a few MB.
- **Device id is 32 random hex chars** from `Random.secure()`, not a UUID v4 from the `uuid` package. Same 128 bits of entropy, no dependency.
- **`seen:<file name>` instead of `seen_md5:<deviceId>`**: the marker is Drive's `md5Checksum`, keyed by file name; same meaning, simpler lookup.
- **Pairing's "automatic" test becomes `edit_ts == 0`** (spec §3.3 says this is the Phase 2 form). The migration stamps `edit_ts = now` on every existing row whose category differs from the automatic guess (except `Self transfer` rows) and on every id in `unpaired_ids`, so no hand-set category is lost.

---

## File structure

| File | Responsibility | Task |
| --- | --- | --- |
| `lib/models/txn.dart` (modify) | `editTs`, `hidden` fields + map round-trip | 1 |
| `lib/data/db.dart` (modify) | v3 migration; `edit_ts`/`rules.ts`/`sync_dirty` stamping; `deviceId()`, `rulesRows()`, `deleteMeta()`; `snapshot()`, `applySnapshot()` | 1, 2, 4 |
| `lib/data/repository.dart` (modify) | manual key with device id; pairing on `edit_ts`; drop `unpaired_ids` | 2 |
| `lib/sync/snapshot.dart` (create) | `buildSnapshot`, `encodeSnapshot`, `decodeSnapshot` | 3 |
| `lib/sync/merge.dart` (create) | `mergeTxn`, `ruleWins` — the pure merge rules | 3 |
| `lib/sync/crypto.dart` (create) | `SyncCrypto`: derive, encrypt, decrypt, check | 5 |
| `lib/sync/sync_store.dart` (create) | `RemoteFile`, `SyncStore` interface | 6 |
| `lib/sync/sync_service.dart` (create) | `SyncService.sync()` — §4.5 | 6 |
| `lib/sync/sync_setup.dart` (create) | `SyncSetup`: read/create `meta.json`, join, reset | 6 |
| `lib/sync/drive_sync_store.dart` (create) | `DriveSyncStore` over googleapis Drive v3 | 7 |
| `lib/sync/google_auth.dart` (create) | `SyncAuth` interface + `GoogleAuth` (google_sign_in 7) | 7 |
| `lib/sync/sync_keys.dart` (create) | `SyncKeys` interface + `SecureSyncKeys` | 7 |
| `lib/sync/sync_controller.dart` (create) | `SyncController` ChangeNotifier: state machine, debounce, last synced | 8 |
| `lib/screens/settings_screen.dart` (create) | Sync card: sign in, passphrase, status, reset, sign out | 8 |
| `lib/screens/home_screen.dart`, `lib/main.dart` (modify) | menu item, "Last synced" line, triggers, wiring | 8 |
| `test/data/repository_test.dart`, `test/data/sync_db_test.dart`, `test/sync/merge_test.dart`, `test/sync/snapshot_test.dart`, `test/sync/crypto_test.dart`, `test/sync/memory_sync_store.dart`, `test/sync/sync_service_test.dart`, `test/sync/fakes.dart`, `test/sync/sync_controller_test.dart`, `test/widget_test.dart` | tests | 1–8 |
| `README.md` (modify) | Sync section, owner setup, limits | 9 |

---

### Task 1: Schema v3 — `edit_ts`, `rules.ts`, migration (spec §4.3)

**Files:**
- Modify: `lib/models/txn.dart`
- Modify: `lib/data/db.dart`
- Test: `test/data/repository_test.dart`

**Interfaces:**
- Produces: `Txn.editTs` (`int`, default 0), `Txn.hidden` (`bool`, default false), both in `toMap()`/`fromMap()`; `AppDb.open` at `version: 3`; `Future<List<Map<String, Object?>>> AppDb.rulesRows()` (rows with `counterparty`, `category`, `ts`); `Future<void> AppDb.deleteMeta(String k)`.

- [ ] **Step 1: Write the failing tests**

Append inside `main()` in `test/data/repository_test.dart`, after the existing `schema migration` group:

```dart
  group('schema v3', () {
    test('a version-2 database gains edit_ts and rules.ts; hand-set categories are stamped', () async {
      final dir = await Directory.systemTemp.createTemp('upitrack_v2');
      final path = p.join(dir.path, 'upitrack.db');
      final v2 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
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
            await db.execute(
                'CREATE TABLE rules(counterparty TEXT PRIMARY KEY, category TEXT NOT NULL)');
            await db.execute('CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT NOT NULL)');
            await db.execute('''
              CREATE TABLE unparsed(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                key TEXT NOT NULL UNIQUE,
                sender TEXT NOT NULL,
                body TEXT NOT NULL,
                ts INTEGER NOT NULL,
                state TEXT NOT NULL DEFAULT 'open'
              )''');
          },
        ),
      );
      final ts = DateTime(2026, 10, 3).millisecondsSinceEpoch;
      Map<String, Object?> row(String key, String cp, bool debit, String cat) => {
            'key': key, 'amount_paise': 1000, 'is_debit': debit ? 1 : 0,
            'counterparty': cp, 'channel': 'UPI', 'category': cat, 'ts': ts,
          };
      await v2.insert('txns', row('a', 'SWIGGY', true, 'Food')); // the automatic guess
      await v2.insert('txns', row('b', 'SWIGGY', true, 'Groceries')); // hand-set
      await v2.insert('txns', row('c', 'me@oksbi', true, 'Self transfer')); // paired
      final d = await v2.insert('txns', row('d', 'HDFC', false, 'Income')); // un-paired by hand
      await v2.insert('rules', {'counterparty': 'ZOMATO', 'category': 'Groceries'});
      await v2.insert('meta', {'k': 'unpaired_ids', 'v': '$d'});
      await v2.close();

      final db = await AppDb.open(factory: databaseFactoryFfi, path: path);
      final byKey = {for (final t in await db.between(DateTime(2026, 10), DateTime(2026, 11))) t.key: t};
      expect(byKey['a']!.editTs, 0);
      expect(byKey['b']!.editTs, greaterThan(0));
      expect(byKey['c']!.editTs, 0);
      expect(byKey['d']!.editTs, greaterThan(0));
      expect((await db.rulesRows()).single['ts'], greaterThan(0));
      expect(await db.getMeta('unpaired_ids'), isNull);
      expect(await db.getMeta('sync_dirty'), '1');
      await db.close();
      await dir.delete(recursive: true);
    });

    test('Txn round-trips hidden and edit_ts', () {
      final t = Txn(
        key: 'k', amountPaise: 1, isDebit: true, counterparty: 'x', channel: 'UPI',
        category: 'Food', time: DateTime(2026, 10, 3), hidden: true, editTs: 42,
      );
      final back = Txn.fromMap(t.toMap());
      expect(back.hidden, isTrue);
      expect(back.editTs, 42);
      expect(Txn.fromMap({...t.toMap()}..remove('edit_ts')..remove('hidden')).editTs, 0);
    });
  });
```

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/data/repository_test.dart`
Expected: compile errors — `editTs`, `hidden:` named parameter, `rulesRows` undefined.

- [ ] **Step 3: Implement**

`lib/models/txn.dart` — constructor gains two optional parameters, placed after `this.source = 'sms'`:

```dart
    this.hidden = false,
    this.editTs = 0,
```

fields, after `final String source;`:

```dart
  /// Hidden rows stay in the table (and in sync snapshots) so a later sync
  /// doesn't re-add them.
  final bool hidden;

  /// Milliseconds since epoch of the last change the *user* made to this
  /// row (category, hide/unhide); 0 for rows that only ever had automatic
  /// values. Sync lets the higher edit_ts win (spec §4.3).
  final int editTs;
```

`toMap()` — add after `'source': source,`:

```dart
        'hidden': hidden ? 1 : 0,
        'edit_ts': editTs,
```

`fromMap` — add after `source: m['source'] as String? ?? 'sms',`:

```dart
        hidden: (m['hidden'] as int? ?? 0) == 1,
        editTs: m['edit_ts'] as int? ?? 0,
```

`lib/data/db.dart`:

Add `import '../parser/categorizer.dart';` with the other relative imports.

In `open`, change `version: 2,` to `version: 3,`. In `onCreate`, change the `txns` DDL's last line `hidden INTEGER NOT NULL DEFAULT 0` to

```sql
            hidden INTEGER NOT NULL DEFAULT 0,
            edit_ts INTEGER NOT NULL DEFAULT 0
```

and the rules DDL to

```dart
          await db.execute(
              'CREATE TABLE rules(counterparty TEXT PRIMARY KEY, category TEXT NOT NULL, ts INTEGER NOT NULL DEFAULT 0)');
```

Replace `onUpgrade` with:

```dart
        onUpgrade: (db, from, to) async {
          if (from < 2) await _createUnparsed(db);
          if (from < 3) await _upgradeToV3(db);
        },
```

Add after `_createUnparsed`:

```dart
  /// v3 (spec §4.3): `edit_ts` on txns and `ts` on rules. Existing rows
  /// whose category differs from the automatic guess were set by hand, so
  /// they are stamped as edits; so are the ids Phase 1b kept in
  /// `unpaired_ids`. Self-transfer rows stay automatic.
  static Future<void> _upgradeToV3(Database db) async {
    await db.execute('ALTER TABLE txns ADD COLUMN edit_ts INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE rules ADD COLUMN ts INTEGER NOT NULL DEFAULT 0');
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('rules', {'ts': now});

    final rules = {
      for (final r in await db.query('rules'))
        r['counterparty'] as String: r['category'] as String
    };
    final batch = db.batch();
    for (final r in await db.query('txns',
        columns: ['id', 'counterparty', 'is_debit', 'category'])) {
      final category = r['category'] as String;
      if (category == Categorizer.selfTransfer) continue;
      final guess = Categorizer.categorizeWith(rules, r['counterparty'] as String,
          isDebit: (r['is_debit'] as int) == 1);
      if (category != guess) {
        batch.update('txns', {'edit_ts': now}, where: 'id = ?', whereArgs: [r['id']]);
      }
    }
    final unpaired = await db.query('meta', where: "k = 'unpaired_ids'");
    if (unpaired.isNotEmpty) {
      for (final s in (unpaired.first['v'] as String).split(',')) {
        if (s.isEmpty) continue;
        batch.update('txns', {'edit_ts': now}, where: 'id = ?', whereArgs: [int.parse(s)]);
      }
      batch.delete('meta', where: "k = 'unpaired_ids'");
    }
    batch.insert('meta', {'k': 'sync_dirty', 'v': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }
```

Add next to `rules()`:

```dart
  /// Every rule row with its timestamp, for snapshots.
  Future<List<Map<String, Object?>>> rulesRows() async =>
      [for (final r in await _db.query('rules')) Map<String, Object?>.from(r)];
```

Add next to `setMeta`:

```dart
  Future<void> deleteMeta(String k) =>
      _db.delete('meta', where: 'k = ?', whereArgs: [k]);
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/data/repository_test.dart`
Expected: all pass, including the Phase 1 `schema migration` test (a v1 file now passes through both upgrades).

- [ ] **Step 5: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/models/txn.dart lib/data/db.dart test/data/repository_test.dart
git commit -m "Schema v3: edit_ts on transactions, ts on rules, stamp hand-set categories" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JRLLy55rhHqrkMzo7AVgEa"
```

Expected suite: 81 tests.

---

### Task 2: Edit stamping, dirty flag, device id, pairing on `edit_ts` (spec §4.3, §3.3)

**Files:**
- Modify: `lib/data/db.dart`
- Modify: `lib/data/repository.dart`
- Test: `test/data/repository_test.dart`

**Interfaces:**
- Consumes: Task 1.
- Produces: `AppDb.setCategory(int id, String category, {bool byUser = true})`; `Future<String> AppDb.deviceId()`; `insertAll`, `setCategoryForPayee`, `hide`, `unhide` all set `sync_dirty = '1'`; `TxnRepository.pairSelfTransfers` treats `editTs == 0` as automatic; `_unpairedIds` is gone.

- [ ] **Step 1: Write the failing tests**

Append inside `main()` in `test/data/repository_test.dart`:

```dart
  group('edit stamping and dirty flag', () {
    TxnRepository repo(List<RawSms> sms) => TxnRepository(db, FakeSms(sms), FakeInbox());
    Future<Txn> only(TxnRepository r) async =>
        (await r.between(DateTime(2026, 10), DateTime(2026, 11))).single;

    test('a new sync sets sync_dirty; a category change stamps edit_ts', () async {
      final r = repo([RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcSwiggy, date: DateTime(2026, 10, 3, 9))]);
      expect(await db.getMeta('sync_dirty'), isNull);
      await r.syncSms();
      expect(await db.getMeta('sync_dirty'), '1');
      expect((await only(r)).editTs, 0);

      await db.setMeta('sync_dirty', '0');
      await r.setCategory(await only(r), 'Groceries', forPayee: false);
      expect((await only(r)).editTs, greaterThan(0));
      expect(await db.getMeta('sync_dirty'), '1');
    });

    test('a payee rule stamps rules.ts and leaves edit_ts alone', () async {
      final r = repo([RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcSwiggy, date: DateTime(2026, 10, 3, 9))]);
      await r.syncSms();
      await r.setCategory(await only(r), 'Groceries', forPayee: true);
      final t = await only(r);
      expect(t.category, 'Groceries');
      expect(t.editTs, 0);
      expect((await db.rulesRows()).single['ts'], greaterThan(0));
    });

    test('hide and unhide stamp edit_ts and set sync_dirty', () async {
      final r = repo([RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcSwiggy, date: DateTime(2026, 10, 3, 9))]);
      await r.syncSms();
      await db.setMeta('sync_dirty', '0');
      await r.hide(await only(r));
      final hidden = (await r.hidden()).single;
      expect(hidden.hidden, isTrue);
      expect(hidden.editTs, greaterThan(0));
      expect(await db.getMeta('sync_dirty'), '1');
      await r.unhide(hidden);
      expect((await only(r)).hidden, isFalse);
    });

    test('manual entries carry the device id and an edit stamp', () async {
      final r = repo(const []);
      final id = await db.deviceId();
      expect(id, hasLength(32));
      expect(await db.deviceId(), id, reason: 'generated once');
      await r.addManual(amountPaise: 100, isDebit: true, counterparty: 'Cash',
          category: 'Food', time: DateTime(2026, 10, 1));
      final t = await only(r);
      expect(t.key, startsWith('manual:$id:'));
      expect(t.editTs, greaterThan(0));
    });

    test('pairing never touches an edited row and stamps nothing itself', () async {
      const hdfcOut = 'Sent Rs.5,000.00\nFrom HDFC Bank A/C *1234\nTo me@oksbi\n'
          'On 03/10/26\nRef 427600000201';
      const sbiIn = 'Dear SBI UPI User, ur A/cX5678 credited by Rs5000 on 03Oct26 by '
          '(Ref no 427600000202)';
      final day = DateTime(2026, 10, 3, 9);
      final r = repo([
        RawSms(id: 1, address: 'VM-HDFCBK', body: hdfcOut, date: day),
        RawSms(id: 2, address: 'AD-SBIUPI', body: sbiIn, date: day),
      ]);
      await r.syncSms();
      final paired = await r.between(DateTime(2026, 10), DateTime(2026, 11));
      expect(paired.map((t) => t.category), everyElement(Categorizer.selfTransfer));
      expect(paired.map((t) => t.editTs), everyElement(0), reason: 'pairing is automatic');
      expect(await db.getMeta('unpaired_ids'), isNull);
    });
  });
```

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/data/repository_test.dart`
Expected: compile error — `deviceId` undefined; once that is stubbed the stamping tests fail on `editTs == 0` / `sync_dirty == null`.

- [ ] **Step 3: Implement**

`lib/data/db.dart`:

Add `import 'dart:math';` at the top (first import).

Add private helpers after `Future<void> close()`:

```dart
  static int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Spec §4.3: every write that changes txns or rules flags the device for
  /// upload. [e] is the connection or the transaction doing the write.
  static Future<void> _markDirty(DatabaseExecutor e) => e.insert(
      'meta', {'k': 'sync_dirty', 'v': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace);
```

Replace `insertAll` with:

```dart
  /// Inserts new transactions, silently skipping ones already stored.
  /// Returns how many were actually added.
  Future<int> insertAll(List<Txn> txns) async {
    if (txns.isEmpty) return 0;
    final before = await _count();
    final batch = _db.batch();
    for (final t in txns) {
      batch.insert('txns', t.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    final added = await _count() - before;
    if (added > 0) await _markDirty(_db);
    return added;
  }
```

Replace `setCategory`, `setCategoryForPayee`, `hide`, `unhide` with:

```dart
  /// [byUser] stamps `edit_ts` so the change wins on other devices and is
  /// never undone by self-transfer pairing. Pairing itself passes false.
  Future<void> setCategory(int id, String category, {bool byUser = true}) =>
      _db.transaction((txn) async {
        await txn.update(
            'txns', {'category': category, if (byUser) 'edit_ts': _now},
            where: 'id = ?', whereArgs: [id]);
        await _markDirty(txn);
      });

  /// Re-categorises every payment to [counterparty] and remembers it. Rows
  /// keep their own `edit_ts`; the rule carries its time, so on another
  /// device a later direct edit of one payment still wins (spec §4.5).
  Future<void> setCategoryForPayee(String counterparty, String category) async {
    final now = _now;
    await _db.transaction((txn) async {
      await txn.update('txns', {'category': category},
          where: 'counterparty = ? AND is_debit = 1 AND edit_ts < ?',
          whereArgs: [counterparty, now]);
      await txn.insert(
          'rules', {'counterparty': counterparty, 'category': category, 'ts': now},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _markDirty(txn);
    });
  }

  /// Hidden rather than deleted, so the next SMS sync doesn't re-add it.
  Future<void> hide(int id) => _setHidden(id, 1);

  Future<void> unhide(int id) => _setHidden(id, 0);

  Future<void> _setHidden(int id, int hidden) => _db.transaction((txn) async {
        await txn.update('txns', {'hidden': hidden, 'edit_ts': _now},
            where: 'id = ?', whereArgs: [id]);
        await _markDirty(txn);
      });
```

(`hidden()` stays where it is.) Add next to `getMeta`:

```dart
  /// This install's id, generated once: 32 hex chars from a secure RNG.
  /// Names this device's snapshot file and keys its manual entries.
  Future<String> deviceId() async {
    final existing = await getMeta('device_id');
    if (existing != null) return existing;
    final rng = Random.secure();
    final id = List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await setMeta('device_id', id);
    return id;
  }
```

`lib/data/repository.dart`:

Replace `pairSelfTransfers` and delete `_unpairedIds` (and its `ponytail:` comment):

```dart
  /// Labels debit/credit pairs that move money between the user's own
  /// accounts (spec §3.3): same amount, same day, both with an account, and
  /// different accounts. Only rows the user never touched (`edit_ts == 0`)
  /// are candidates, so a hand-set category — including taking a row out
  /// of a pair — is never overridden. Returns the number of pairs found.
  Future<int> pairSelfTransfers(DateTime from, DateTime to) async {
    final txns = await _db.between(from, to); // newest first
    final candidates = txns
        .where((t) =>
            t.account != null &&
            t.editTs == 0 &&
            t.category != Categorizer.selfTransfer)
        .toList();

    final usedCredits = <int>{};
    var pairs = 0;
    for (final d in candidates.where((t) => t.isDebit)) {
      for (final c in candidates.where((t) => !t.isDebit)) {
        if (usedCredits.contains(c.id)) continue;
        if (c.amountPaise != d.amountPaise) continue;
        if (_ymd(c.time) != _ymd(d.time)) continue;
        if (c.bank == d.bank && c.account == d.account) continue;
        await _db.setCategory(d.id!, Categorizer.selfTransfer, byUser: false);
        await _db.setCategory(c.id!, Categorizer.selfTransfer, byUser: false);
        usedCredits.add(c.id!);
        pairs++;
        break;
      }
    }
    return pairs;
  }
```

Replace the repository's `setCategory` with:

```dart
  Future<void> setCategory(Txn t, String category,
      {required bool forPayee}) async {
    // Spec §3.3: Self transfer is never a payee rule.
    if (forPayee && category != Categorizer.selfTransfer) {
      await _db.setCategoryForPayee(t.counterparty, category);
    } else {
      await _db.setCategory(t.id!, category);
    }
  }
```

Replace `addManual` with:

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
  }) async {
    final now = DateTime.now();
    await _db.insertAll([
      Txn(
        key: 'manual:${await _db.deviceId()}:${now.microsecondsSinceEpoch}',
        amountPaise: amountPaise,
        isDebit: isDebit,
        counterparty: counterparty,
        channel: 'Cash',
        category: category,
        time: time,
        raw: raw,
        manual: true,
        source: 'manual',
        editTs: now.millisecondsSinceEpoch,
      ),
    ]);
  }
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/data/repository_test.dart`
Expected: all pass, including the Phase 1b self-transfer group (`a manually un-paired self transfer stays un-paired` now holds through `edit_ts`).

- [ ] **Step 5: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/data/db.dart lib/data/repository.dart test/data/repository_test.dart
git commit -m "Stamp user edits, flag the device dirty, pair self transfers on edit_ts" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JRLLy55rhHqrkMzo7AVgEa"
```

Expected suite: 86 tests.

---

### Task 3: Pure merge rules and snapshot codec (spec §4.4, §4.5)

**Files:**
- Create: `lib/sync/merge.dart`, `lib/sync/snapshot.dart`
- Test: `test/sync/merge_test.dart`, `test/sync/snapshot_test.dart`

**Interfaces:**
- Produces: `enum TxnMerge { insert, update, keep }`; `TxnMerge mergeTxn(Map<String, Object?>? local, Map<String, Object?> remote)`; `bool ruleWins(Map<String, Object?>? local, Map<String, Object?> remote)`; `const int kSnapshotVersion = 1`; `Map<String, Object?> buildSnapshot({required String deviceId, required int exportedMs, required List<Map<String, Object?>> txns, required List<Map<String, Object?>> rules})`; `Uint8List encodeSnapshot(Map<String, Object?> snapshot)`; `Map<String, Object?> decodeSnapshot(List<int> bytes)` (throws `FormatException` on an unknown `v`).

- [ ] **Step 1: Write the failing tests**

Create `test/sync/merge_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/sync/merge.dart';

void main() {
  Map<String, Object?> txn(int editTs, {String category = 'Food'}) =>
      {'key': 'k', 'category': category, 'edit_ts': editTs};

  test('a row the device has never seen is inserted', () {
    expect(mergeTxn(null, txn(0)), TxnMerge.insert);
  });

  test('an edit beats an automatic row and an older edit', () {
    expect(mergeTxn(txn(0), txn(5)), TxnMerge.update);
    expect(mergeTxn(txn(3), txn(5)), TxnMerge.update);
  });

  test('an automatic row never beats an edit; equal stamps keep local', () {
    expect(mergeTxn(txn(5), txn(0)), TxnMerge.keep);
    expect(mergeTxn(txn(5), txn(5)), TxnMerge.keep);
    expect(mergeTxn(txn(0), txn(0)), TxnMerge.keep);
  });

  test('a missing edit_ts counts as 0', () {
    expect(mergeTxn({'key': 'k'}, {'key': 'k', 'edit_ts': 1}), TxnMerge.update);
    expect(mergeTxn({'key': 'k', 'edit_ts': 1}, {'key': 'k'}), TxnMerge.keep);
  });

  test('a rule wins when unknown locally or newer', () {
    Map<String, Object?> rule(int ts) => {'counterparty': 'SWIGGY', 'category': 'Food', 'ts': ts};
    expect(ruleWins(null, rule(1)), isTrue);
    expect(ruleWins(rule(1), rule(2)), isTrue);
    expect(ruleWins(rule(2), rule(2)), isFalse);
    expect(ruleWins(rule(3), rule(2)), isFalse);
  });
}
```

Create `test/sync/snapshot_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/sync/snapshot.dart';

void main() {
  test('build → encode → decode round-trips, with the version tag', () {
    final snap = buildSnapshot(
      deviceId: 'abc',
      exportedMs: 1760000000000,
      txns: [
        {'key': 'k1', 'amount_paise': 100, 'is_debit': 1, 'counterparty': 'SWIGGY',
         'channel': 'UPI', 'category': 'Food', 'ts': 1, 'hidden': 0, 'edit_ts': 0, 'raw': null},
      ],
      rules: [{'counterparty': 'SWIGGY', 'category': 'Food', 'ts': 7}],
    );
    expect(snap['v'], kSnapshotVersion);
    expect(snap['device'], 'abc');
    final back = decodeSnapshot(encodeSnapshot(snap));
    expect(back, snap);
    expect(((back['txns'] as List).single as Map)['amount_paise'], 100);
  });

  test('an unknown version is refused', () {
    final bytes = encodeSnapshot({'v': 99, 'device': 'x', 'exported_ms': 0, 'txns': [], 'rules': []});
    expect(() => decodeSnapshot(bytes), throwsFormatException);
  });

  test('garbage is refused', () {
    expect(() => decodeSnapshot([1, 2, 3]), throwsFormatException);
  });
}
```

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/sync/`
Expected: compile errors — `package:upitrack/sync/merge.dart` and `snapshot.dart` not found.

- [ ] **Step 3: Implement**

Create `lib/sync/merge.dart`:

```dart
/// The merge rules of spec §4.5, as pure functions over row maps so they
/// can be tested without a database. `edit_ts` / `ts` missing means 0.
library;

enum TxnMerge { insert, update, keep }

int _stamp(Map<String, Object?> row, String field) => (row[field] as num?)?.toInt() ?? 0;

/// What to do with [remote] given the [local] row with the same key (null
/// when the device has never seen it). Payments are only ever added, so an
/// unknown row is inserted; a known row changes only when the remote edit
/// is strictly newer — an automatic row (0) never beats a human edit.
TxnMerge mergeTxn(Map<String, Object?>? local, Map<String, Object?> remote) {
  if (local == null) return TxnMerge.insert;
  return _stamp(remote, 'edit_ts') > _stamp(local, 'edit_ts')
      ? TxnMerge.update
      : TxnMerge.keep;
}

/// A payee rule from another device replaces ours when we have none or
/// theirs is strictly newer.
bool ruleWins(Map<String, Object?>? local, Map<String, Object?> remote) =>
    local == null || _stamp(remote, 'ts') > _stamp(local, 'ts');
```

Create `lib/sync/snapshot.dart`:

```dart
/// One device's whole table as JSON (spec §4.4): built, encoded to bytes
/// for encryption, and decoded back. Pure Dart so it runs on web too.
library;

import 'dart:convert';
import 'dart:typed_data';

const int kSnapshotVersion = 1;

Map<String, Object?> buildSnapshot({
  required String deviceId,
  required int exportedMs,
  required List<Map<String, Object?>> txns,
  required List<Map<String, Object?>> rules,
}) =>
    {
      'v': kSnapshotVersion,
      'device': deviceId,
      'exported_ms': exportedMs,
      'txns': txns,
      'rules': rules,
    };

/// UTF-8 JSON. ponytail: no compression; ~300 B per row is fine for personal
/// data. Gzip here (and bump kSnapshotVersion) if a snapshot passes a few MB.
Uint8List encodeSnapshot(Map<String, Object?> snapshot) =>
    Uint8List.fromList(utf8.encode(jsonEncode(snapshot)));

/// Throws [FormatException] for anything that isn't a version-1 snapshot.
Map<String, Object?> decodeSnapshot(List<int> bytes) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Exception catch (e) {
    throw FormatException('not a snapshot: $e');
  }
  if (decoded is! Map<String, Object?> ||
      decoded['v'] != kSnapshotVersion ||
      decoded['txns'] is! List ||
      decoded['rules'] is! List) {
    throw const FormatException('unsupported snapshot');
  }
  return decoded;
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/sync/`
Expected: 8 passed.

- [ ] **Step 5: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/sync/merge.dart lib/sync/snapshot.dart test/sync/merge_test.dart test/sync/snapshot_test.dart
git commit -m "Add the pure sync merge rules and snapshot codec" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JRLLy55rhHqrkMzo7AVgEa"
```

Expected suite: 94 tests.

---

### Task 4: Export and apply snapshots in the database (spec §4.4, §4.5)

**Files:**
- Modify: `lib/data/db.dart`
- Test: `test/data/sync_db_test.dart` (create)

**Interfaces:**
- Consumes: `buildSnapshot`, `mergeTxn`, `ruleWins`, `TxnMerge` (Task 3); `deviceId()`, `rulesRows()`, `_markDirty` (Tasks 1–2).
- Produces: `Future<Map<String, Object?>> AppDb.snapshot()` (all rows incl. hidden, no `id`); `Future<bool> AppDb.applySnapshot(Map<String, Object?> snapshot)` — one transaction, returns whether anything changed (and marks dirty when it did).

- [ ] **Step 1: Write the failing tests**

Create `test/data/sync_db_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/models/txn.dart';

/// Two "devices" need two databases; ':memory:' is shared per process, so
/// each gets its own temp file.
Future<AppDb> openDevice(Directory dir, String name) =>
    AppDb.open(factory: databaseFactoryFfi, path: p.join(dir.path, '$name.db'));

Txn txn(String key, {String category = 'Food', int editTs = 0, bool hidden = false}) => Txn(
      key: key,
      amountPaise: 25000,
      isDebit: true,
      counterparty: 'SWIGGY',
      bank: 'HDFC Bank',
      account: '1234',
      channel: 'UPI',
      category: category,
      time: DateTime(2026, 10, 3, 9),
      raw: 'Sent Rs.250.00 ...',
      editTs: editTs,
      hidden: hidden,
    );

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late AppDb a;
  late AppDb b;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('upitrack_sync');
    a = await openDevice(dir, 'a');
    b = await openDevice(dir, 'b');
  });
  tearDown(() async {
    await a.close();
    await b.close();
    await dir.delete(recursive: true);
  });

  Future<List<Txn>> all(AppDb db) => db.betweenIncludingHidden(DateTime(2026, 10), DateTime(2026, 11));

  test('snapshot has every row without ids, plus rules and the device id', () async {
    await a.insertAll([txn('k1'), txn('k2', hidden: true)]);
    await a.setCategoryForPayee('SWIGGY', 'Groceries');
    final snap = await a.snapshot();
    expect(snap['v'], 1);
    expect(snap['device'], await a.deviceId());
    final txns = snap['txns'] as List;
    expect(txns, hasLength(2));
    expect(txns.every((t) => !(t as Map).containsKey('id')), isTrue);
    expect((txns.firstWhere((t) => t['key'] == 'k2') as Map)['hidden'], 1);
    expect((snap['rules'] as List).single['category'], 'Groceries');
  });

  test('apply inserts unknown rows and rules, and flags dirty', () async {
    await a.insertAll([txn('k1')]);
    await a.setCategoryForPayee('SWIGGY', 'Groceries');
    await b.setMeta('sync_dirty', '0');
    expect(await b.applySnapshot(await a.snapshot()), isTrue);
    final rows = await all(b);
    expect(rows.single.key, 'k1');
    expect(rows.single.category, 'Groceries');
    expect(await b.rules(), {'SWIGGY': 'Groceries'});
    expect(await b.getMeta('sync_dirty'), '1');
  });

  test('a newer edit wins; an automatic row never overwrites an edit', () async {
    await a.insertAll([txn('k1')]);
    await b.insertAll([txn('k1')]);
    final local = (await all(b)).single;
    await b.setCategory(local.id!, 'Travel'); // b edits (edit_ts = now)
    expect(await b.applySnapshot(await a.snapshot()), isFalse, reason: "a's row is automatic");
    expect((await all(b)).single.category, 'Travel');

    expect(await a.applySnapshot(await b.snapshot()), isTrue);
    final onA = (await all(a)).single;
    expect(onA.category, 'Travel');
    expect(onA.editTs, greaterThan(0));
  });

  test('hiding propagates and is idempotent', () async {
    await a.insertAll([txn('k1')]);
    await b.applySnapshot(await a.snapshot());
    await a.hide((await all(a)).single.id!);
    expect(await b.applySnapshot(await a.snapshot()), isTrue);
    expect((await all(b)).single.hidden, isTrue);
    expect(await b.applySnapshot(await a.snapshot()), isFalse, reason: 'second apply changes nothing');
  });

  test('a rule applies to automatic rows but not to a later direct edit', () async {
    await b.insertAll([txn('k1'), txn('k2')]);
    final rows = await all(b);
    await b.setCategory(rows.firstWhere((t) => t.key == 'k2').id!, 'Travel'); // now
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await a.insertAll([txn('k1')]);
    await a.setCategoryForPayee('SWIGGY', 'Groceries'); // rule ts later than b's edit
    await b.applySnapshot(await a.snapshot());
    final byKey = {for (final t in await all(b)) t.key: t.category};
    expect(byKey['k1'], 'Groceries');
    expect(byKey['k2'], 'Groceries', reason: 'rule is newer than the edit, so it wins — same as locally');

    // And the other way round: an edit newer than the rule stays.
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await b.setCategory((await all(b)).firstWhere((t) => t.key == 'k2').id!, 'Travel');
    await b.applySnapshot(await a.snapshot());
    expect((await all(b)).firstWhere((t) => t.key == 'k2').category, 'Travel');
  });
}
```

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/data/sync_db_test.dart`
Expected: compile errors — `snapshot`, `applySnapshot` undefined.

- [ ] **Step 3: Implement**

`lib/data/db.dart`: add imports

```dart
import '../sync/merge.dart';
import '../sync/snapshot.dart';
```

Add a new section before `// ---------------------------------------------------------------- unparsed`:

```dart
  // -------------------------------------------------------------- sync

  /// This device's whole table for upload (spec §4.4): every row including
  /// hidden ones and `raw`, without local ids, plus every rule.
  Future<Map<String, Object?>> snapshot() async {
    final rows = await _db.query('txns', orderBy: 'ts');
    return buildSnapshot(
      deviceId: await deviceId(),
      exportedMs: _now,
      txns: [for (final r in rows) Map<String, Object?>.from(r)..remove('id')],
      rules: await rulesRows(),
    );
  }

  /// Merges another device's snapshot (spec §4.5) in one transaction:
  /// unknown rows are inserted as they are, a row changes only when the
  /// remote edit is newer, a newer rule is adopted and applied to rows it
  /// outranks. Idempotent. Returns true (and flags dirty) when anything
  /// changed, so this device's next upload carries what it learned.
  Future<bool> applySnapshot(Map<String, Object?> snapshot) async {
    var changed = false;
    await _db.transaction((txn) async {
      final local = {
        for (final r in await txn.query('txns', columns: ['key', 'edit_ts']))
          r['key'] as String: r
      };
      for (final raw in snapshot['txns'] as List) {
        final t = Map<String, Object?>.from(raw as Map)..remove('id');
        final action = mergeTxn(local[t['key']], t);
        if (action == TxnMerge.insert) {
          await txn.insert('txns', t, conflictAlgorithm: ConflictAlgorithm.ignore);
          changed = true;
        } else if (action == TxnMerge.update) {
          await txn.update(
            'txns',
            {'category': t['category'], 'hidden': t['hidden'] ?? 0, 'edit_ts': t['edit_ts'] ?? 0},
            where: 'key = ?',
            whereArgs: [t['key']],
          );
          changed = true;
        }
      }

      final localRules = {
        for (final r in await txn.query('rules')) r['counterparty'] as String: r
      };
      for (final raw in snapshot['rules'] as List) {
        final r = Map<String, Object?>.from(raw as Map);
        if (!ruleWins(localRules[r['counterparty']], r)) continue;
        await txn.insert('rules', r, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.update('txns', {'category': r['category']},
            where: 'counterparty = ? AND is_debit = 1 AND edit_ts < ?',
            whereArgs: [r['counterparty'], r['ts']]);
        changed = true;
      }
      if (changed) await _markDirty(txn);
    });
    return changed;
  }
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/data/sync_db_test.dart`
Expected: 5 passed.

- [ ] **Step 5: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/data/db.dart test/data/sync_db_test.dart
git commit -m "Export and merge sync snapshots in the database" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JRLLy55rhHqrkMzo7AVgEa"
```

Expected suite: 99 tests.

---

### Task 5: Encryption (spec §4.6)

**Files:**
- Modify: `pubspec.yaml` (add `cryptography: ^2.9.0`)
- Create: `lib/sync/crypto.dart`
- Test: `test/sync/crypto_test.dart`

**Interfaces:**
- Produces: `class SyncCrypto` with `static const int iterations = 200000`; `static const String checkPlain = 'upitrack-key-ok'`; `static List<int> newSalt()` (16 bytes); `static Future<SecretKey> deriveKey(String passphrase, List<int> salt, {int iterations = SyncCrypto.iterations})`; `static Future<Uint8List> encrypt(SecretKey key, List<int> plain)`; `static Future<Uint8List> decrypt(SecretKey key, List<int> data)` (throws `SecretBoxAuthenticationError` on a wrong key, `FormatException` when too short); `static Future<String> makeCheck(SecretKey key)`; `static Future<bool> verifyCheck(SecretKey key, String check)`. `SecretKey` is `package:cryptography`'s.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml` under `dependencies:`, after `flutter_local_notifications: ^22.3.1`, add:

```yaml
  cryptography: ^2.9.0
```

Run: `flutter pub get`

- [ ] **Step 2: Write the failing tests**

Create `test/sync/crypto_test.dart`:

```dart
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/sync/crypto.dart';

void main() {
  // 1000 iterations keep the suite fast; production uses SyncCrypto.iterations.
  Future<SecretKey> key(String pass, List<int> salt) =>
      SyncCrypto.deriveKey(pass, salt, iterations: 1000);

  test('encrypt → decrypt round-trips and never repeats a nonce', () async {
    final k = await key('correct horse', SyncCrypto.newSalt());
    final plain = utf8.encode('{"v":1}');
    final one = await SyncCrypto.encrypt(k, plain);
    final two = await SyncCrypto.encrypt(k, plain);
    expect(one.length, 12 + plain.length + 16);
    expect(one.sublist(0, 12), isNot(two.sublist(0, 12)));
    expect(await SyncCrypto.decrypt(k, one), plain);
    expect(await SyncCrypto.decrypt(k, two), plain);
  });

  test('the wrong key fails authentication; a tampered byte too', () async {
    final salt = SyncCrypto.newSalt();
    final good = await key('correct horse', salt);
    final bad = await key('battery staple', salt);
    final data = await SyncCrypto.encrypt(good, utf8.encode('secret'));
    expect(() => SyncCrypto.decrypt(bad, data), throwsA(isA<SecretBoxAuthenticationError>()));
    data[15] ^= 0xff;
    expect(() => SyncCrypto.decrypt(good, data), throwsA(isA<SecretBoxAuthenticationError>()));
    expect(() => SyncCrypto.decrypt(good, [1, 2, 3]), throwsFormatException);
  });

  test('the same passphrase and salt give the same key; a different salt does not', () async {
    final salt = SyncCrypto.newSalt();
    expect(salt, hasLength(16));
    final a = await (await key('p', salt)).extractBytes();
    final b = await (await key('p', salt)).extractBytes();
    final c = await (await key('p', SyncCrypto.newSalt())).extractBytes();
    expect(a, b);
    expect(a, hasLength(32));
    expect(a, isNot(c));
  });

  test('the key check tells a matching passphrase from a wrong one', () async {
    final salt = SyncCrypto.newSalt();
    final k = await key('p', salt);
    final check = await SyncCrypto.makeCheck(k);
    expect(await SyncCrypto.verifyCheck(k, check), isTrue);
    expect(await SyncCrypto.verifyCheck(await key('q', salt), check), isFalse);
    expect(await SyncCrypto.verifyCheck(k, 'not base64!'), isFalse);
  });
}
```

- [ ] **Step 3: Run to see them fail**

Run: `flutter test test/sync/crypto_test.dart`
Expected: compile error — `package:upitrack/sync/crypto.dart` not found.

- [ ] **Step 4: Implement**

Create `lib/sync/crypto.dart`:

```dart
/// Passphrase → key and file encryption for sync (spec §4.6). Pure Dart via
/// package:cryptography, so it runs on Android, iOS and web alike.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class SyncCrypto {
  SyncCrypto._();

  static const int iterations = 200000;
  static const String checkPlain = 'upitrack-key-ok';
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  static final AesGcm _aes = AesGcm.with256bits();

  static List<int> newSalt() {
    final rng = Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256));
  }

  /// PBKDF2-HMAC-SHA256 → 32-byte key. Tests pass a small [iterations].
  static Future<SecretKey> deriveKey(String passphrase, List<int> salt,
      {int iterations = SyncCrypto.iterations}) {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    return kdf.deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
  }

  /// `nonce(12) ‖ ciphertext ‖ tag(16)`. A fresh random nonce every call.
  static Future<Uint8List> encrypt(SecretKey key, List<int> plain) async {
    final box = await _aes.encrypt(plain, secretKey: key);
    return Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// Throws [SecretBoxAuthenticationError] for a wrong key or tampered data.
  static Future<Uint8List> decrypt(SecretKey key, List<int> data) async {
    if (data.length < _nonceLength + _macLength) {
      throw const FormatException('encrypted data too short');
    }
    final box = SecretBox(
      data.sublist(_nonceLength, data.length - _macLength),
      nonce: data.sublist(0, _nonceLength),
      mac: Mac(data.sublist(data.length - _macLength)),
    );
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: key));
  }

  /// The value stored as `meta.check`: [checkPlain] encrypted, base64.
  static Future<String> makeCheck(SecretKey key) async =>
      base64Encode(await encrypt(key, utf8.encode(checkPlain)));

  /// True when [key] is the one [check] was made with.
  static Future<bool> verifyCheck(SecretKey key, String check) async {
    try {
      return utf8.decode(await decrypt(key, base64Decode(check))) == checkPlain;
    } on SecretBoxAuthenticationError {
      return false;
    } on FormatException {
      return false;
    }
  }
}
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/sync/crypto_test.dart`
Expected: 4 passed.

- [ ] **Step 6: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add pubspec.yaml pubspec.lock lib/sync/crypto.dart test/sync/crypto_test.dart
git commit -m "Add PBKDF2 + AES-GCM encryption for sync files" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JRLLy55rhHqrkMzo7AVgEa"
```

Expected suite: 103 tests.

---

### Task 6: `SyncStore`, in-memory fake, `SyncSetup`, `SyncService` (spec §4.2, §4.5, §4.6)

**Files:**
- Create: `lib/sync/sync_store.dart`, `lib/sync/sync_setup.dart`, `lib/sync/sync_service.dart`
- Create: `test/sync/memory_sync_store.dart`, `test/sync/sync_service_test.dart`

**Interfaces:**
- Consumes: `AppDb.snapshot/applySnapshot/deviceId/getMeta/setMeta` (Tasks 2, 4); `encodeSnapshot/decodeSnapshot` (Task 3); `SyncCrypto` (Task 5).
- Produces: `class RemoteFile { final String id; final String name; final String? version; }`; `abstract class SyncStore { Future<List<RemoteFile>> list(); Future<Uint8List> download(String id); Future<void> upload(String name, Uint8List bytes); Future<void> deleteAll(); }`; `class SyncSetup(SyncStore store)` with `Future<Map<String, Object?>?> readMeta()`, `Future<SecretKey> create(String passphrase)`, `Future<SecretKey?> join(String passphrase, Map<String, Object?> meta)`, `Future<void> reset()`; `class SyncResult { final int applied; final bool uploaded; }`; `class SyncService(AppDb db, SyncStore store, SecretKey key)` with `Future<SyncResult> sync()` and `static String fileNameFor(String deviceId)`.

- [ ] **Step 1: Write the fake and the failing tests**

Create `test/sync/memory_sync_store.dart`:

```dart
import 'dart:typed_data';

import 'package:upitrack/sync/sync_store.dart';

/// Drive stand-in: files by name, a version that changes with content.
class MemorySyncStore implements SyncStore {
  final Map<String, Uint8List> files = {};
  int downloads = 0;
  int uploads = 0;

  @override
  Future<List<RemoteFile>> list() async => [
        for (final e in files.entries)
          RemoteFile(id: e.key, name: e.key, version: Object.hashAll(e.value).toRadixString(16)),
      ];

  @override
  Future<Uint8List> download(String id) async {
    downloads++;
    return files[id]!;
  }

  @override
  Future<void> upload(String name, Uint8List bytes) async {
    uploads++;
    files[name] = bytes;
  }

  @override
  Future<void> deleteAll() async => files.clear();
}
```

Create `test/sync/sync_service_test.dart`:

```dart
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/sync/sync_service.dart';
import 'package:upitrack/sync/sync_setup.dart';

import 'memory_sync_store.dart';

Txn txn(String key) => Txn(
      key: key, amountPaise: 25000, isDebit: true, counterparty: 'SWIGGY',
      bank: 'HDFC Bank', account: '1234', channel: 'UPI', category: 'Food',
      time: DateTime(2026, 10, 3, 9),
    );

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late AppDb a;
  late AppDb b;
  late MemorySyncStore store;
  final key = SecretKey(List<int>.filled(32, 7));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('upitrack_svc');
    a = await AppDb.open(factory: databaseFactoryFfi, path: p.join(dir.path, 'a.db'));
    b = await AppDb.open(factory: databaseFactoryFfi, path: p.join(dir.path, 'b.db'));
    store = MemorySyncStore();
  });
  tearDown(() async {
    await a.close();
    await b.close();
    await dir.delete(recursive: true);
  });

  Future<List<Txn>> all(AppDb db) => db.betweenIncludingHidden(DateTime(2026, 10), DateTime(2026, 11));

  test('two devices converge; nothing is re-downloaded or re-uploaded when quiet', () async {
    final sa = SyncService(a, store, key);
    final sb = SyncService(b, store, key);
    await a.insertAll([txn('k1')]);

    final r1 = await sa.sync();
    expect(r1.uploaded, isTrue);
    expect(store.files.keys, [SyncService.fileNameFor(await a.deviceId())]);

    final r2 = await sb.sync();
    expect(r2.applied, 1);
    expect(r2.uploaded, isTrue, reason: 'b carries what it learned');
    expect((await all(b)).single.key, 'k1');

    final r3 = await sa.sync();
    expect(r3.applied, 0, reason: "b's snapshot adds nothing a doesn't have");
    expect(r3.uploaded, isFalse);

    final before = (store.downloads, store.uploads);
    final r4 = await sa.sync();
    expect((r4.applied, r4.uploaded), (0, false));
    expect((store.downloads, store.uploads), before, reason: 'seen versions skip the download');
  });

  test('a hide on one device reaches the other', () async {
    final sa = SyncService(a, store, key);
    final sb = SyncService(b, store, key);
    await a.insertAll([txn('k1')]);
    await sa.sync();
    await sb.sync();
    await b.hide((await all(b)).single.id!);
    await sb.sync();
    await sa.sync();
    expect((await all(a)).single.hidden, isTrue);
  });

  test('the wrong key cannot read a snapshot', () async {
    await a.insertAll([txn('k1')]);
    await SyncService(a, store, key).sync();
    final wrong = SyncService(b, store, SecretKey(List<int>.filled(32, 8)));
    expect(() => wrong.sync(), throwsA(isA<SecretBoxAuthenticationError>()));
  });

  test('setup: create writes meta.json, join checks the passphrase, reset wipes', () async {
    final setup = SyncSetup(store, iterations: 1000);
    expect(await setup.readMeta(), isNull);
    final created = await setup.create('correct horse');
    final meta = await setup.readMeta();
    expect(meta, isNotNull);
    expect(meta!['kdf'], 'pbkdf2-sha256');
    expect(meta['iterations'], 1000);
    expect(await setup.join('battery staple', meta), isNull);
    final joined = await setup.join('correct horse', meta);
    expect(await joined!.extractBytes(), await created.extractBytes());
    await setup.reset();
    expect(store.files, isEmpty);
  });
}
```

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/sync/sync_service_test.dart`
Expected: compile errors — `sync_store.dart`, `sync_service.dart`, `sync_setup.dart` not found.

- [ ] **Step 3: Implement**

Create `lib/sync/sync_store.dart`:

```dart
/// The four things sync needs from remote storage (spec §4.9). One real
/// implementation (Drive); tests use an in-memory one.
library;

import 'dart:typed_data';

class RemoteFile {
  const RemoteFile({required this.id, required this.name, this.version});

  final String id;
  final String name;

  /// Changes whenever the content does (Drive's md5Checksum). Null when the
  /// store can't say; the file is then always downloaded.
  final String? version;
}

abstract class SyncStore {
  Future<List<RemoteFile>> list();
  Future<Uint8List> download(String id);

  /// Creates [name] or replaces its whole content.
  Future<void> upload(String name, Uint8List bytes);

  /// "Reset sync": removes every file in the folder.
  Future<void> deleteAll();
}
```

Create `lib/sync/sync_setup.dart`:

```dart
/// First-time setup and recovery (spec §4.6, §4.7): `meta.json` holds the
/// salt and a key check so every device derives the same key from the
/// passphrase and can tell a wrong one apart.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto.dart';
import 'sync_store.dart';

class SyncSetup {
  SyncSetup(this._store, {this.iterations = SyncCrypto.iterations});

  final SyncStore _store;

  /// PBKDF2 rounds for a *new* meta.json. Joining uses the rounds the file
  /// records. Tests lower it.
  final int iterations;

  static const String metaName = 'meta.json';

  /// The folder's `meta.json`, or null when no device has set up sync yet.
  Future<Map<String, Object?>?> readMeta() async {
    final files = await _store.list();
    for (final f in files) {
      if (f.name == metaName) {
        return jsonDecode(utf8.decode(await _store.download(f.id))) as Map<String, Object?>;
      }
    }
    return null;
  }

  /// First device: choose a passphrase, write meta.json, return the key.
  Future<SecretKey> create(String passphrase) async {
    final salt = SyncCrypto.newSalt();
    final key = await SyncCrypto.deriveKey(passphrase, salt, iterations: iterations);
    final meta = {
      'v': 1,
      'kdf': 'pbkdf2-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'check': await SyncCrypto.makeCheck(key),
    };
    await _store.upload(metaName, Uint8List.fromList(utf8.encode(jsonEncode(meta))));
    return key;
  }

  /// Another device: derive from the recorded salt; null when the
  /// passphrase doesn't match the one used on the first device.
  Future<SecretKey?> join(String passphrase, Map<String, Object?> meta) async {
    final key = await SyncCrypto.deriveKey(
      passphrase,
      base64Decode(meta['salt'] as String),
      iterations: (meta['iterations'] as num).toInt(),
    );
    return await SyncCrypto.verifyCheck(key, meta['check'] as String) ? key : null;
  }

  /// Forgotten passphrase: wipe the folder. Local data is untouched; the
  /// caller then runs [create] again and re-uploads.
  Future<void> reset() => _store.deleteAll();
}
```

Create `lib/sync/sync_service.dart`:

```dart
/// One sync round (spec §4.5): pull every other device's snapshot we haven't
/// seen, merge it, then push ours if anything changed locally.
library;

import 'package:cryptography/cryptography.dart';

import '../data/db.dart';
import 'crypto.dart';
import 'snapshot.dart';
import 'sync_store.dart';

class SyncResult {
  const SyncResult({required this.applied, required this.uploaded});

  /// Remote snapshots that changed something here.
  final int applied;
  final bool uploaded;
}

class SyncService {
  SyncService(this._db, this._store, this._key);

  final AppDb _db;
  final SyncStore _store;
  final SecretKey _key;

  static String fileNameFor(String deviceId) => 'dev-$deviceId.json.enc';

  /// Throws on network or auth failure, and [SecretBoxAuthenticationError]
  /// when the stored key no longer matches the folder (sync was reset).
  Future<SyncResult> sync() async {
    final mine = fileNameFor(await _db.deviceId());
    final files = await _store.list();

    var applied = 0;
    for (final f in files) {
      if (!f.name.startsWith('dev-') || f.name == mine) continue;
      final seenKey = 'seen:${f.name}';
      if (f.version != null && f.version == await _db.getMeta(seenKey)) continue;
      final bytes = await SyncCrypto.decrypt(_key, await _store.download(f.id));
      if (await _db.applySnapshot(decodeSnapshot(bytes))) applied++;
      if (f.version != null) await _db.setMeta(seenKey, f.version!);
    }

    var uploaded = false;
    final haveMine = files.any((f) => f.name == mine);
    if (!haveMine || await _db.getMeta('sync_dirty') == '1') {
      // ponytail: a local change landing during this upload is carried by
      // the next one; sync_dirty is cleared only after the upload succeeds.
      final snap = encodeSnapshot(await _db.snapshot());
      await _store.upload(mine, await SyncCrypto.encrypt(_key, snap));
      await _db.setMeta('sync_dirty', '0');
      uploaded = true;
    }
    return SyncResult(applied: applied, uploaded: uploaded);
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/sync/sync_service_test.dart`
Expected: 4 passed.

- [ ] **Step 5: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/sync/sync_store.dart lib/sync/sync_setup.dart lib/sync/sync_service.dart test/sync/memory_sync_store.dart test/sync/sync_service_test.dart
git commit -m "Add the sync service, setup flow and store interface with an in-memory fake" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JRLLy55rhHqrkMzo7AVgEa"
```

Expected suite: 107 tests.

---

### Task 7: Drive store, Google sign-in, key storage (spec §4.2, §4.6, §4.7)

**Files:**
- Modify: `pubspec.yaml` (add `googleapis: ^17.0.0`, `google_sign_in: ^7.2.0`, `extension_google_sign_in_as_googleapis_auth: ^3.0.0`, `flutter_secure_storage: ^11.2.0`)
- Create: `lib/sync/drive_sync_store.dart`, `lib/sync/google_auth.dart`, `lib/sync/sync_keys.dart`

**Interfaces:**
- Consumes: `SyncStore`, `RemoteFile` (Task 6).
- Produces: `class DriveSyncStore implements SyncStore { DriveSyncStore(http.Client client) }`; `abstract class SyncAuth { Future<http.Client?> signIn(); Future<http.Client?> restore(); Future<void> signOut(); }`; `class GoogleAuth implements SyncAuth` with `static const String scope = 'https://www.googleapis.com/auth/drive.appdata'`; `abstract class SyncKeys { Future<SecretKey?> read(); Future<void> write(SecretKey key); Future<void> clear(); }`; `class SecureSyncKeys implements SyncKeys`.

There are no unit tests in this task: every class is a thin adapter over a plugin that only works on a device. Verification is `flutter analyze` plus the existing suite. **Before writing `google_auth.dart`, open the installed package's example** (`~/.pub-cache/hosted/pub.dev/google_sign_in-7.*/example/lib/main.dart`) and confirm the method names used below (`initialize`, `authenticate`, `attemptLightweightAuthentication`, `authorizationClient.authorizeScopes`, `authorizationForScopes`, `GoogleSignInException`, `GoogleSignInExceptionCode.canceled`). If a name differs in the installed version, use the package's and say so in your report.

- [ ] **Step 1: Add the dependencies**

In `pubspec.yaml` under `dependencies:`, after `cryptography: ^2.9.0`, add:

```yaml
  flutter_secure_storage: ^11.2.0
  google_sign_in: ^7.2.0
  googleapis: ^17.0.0
  extension_google_sign_in_as_googleapis_auth: ^3.0.0
```

Run: `flutter pub get`

- [ ] **Step 2: Drive store**

Create `lib/sync/drive_sync_store.dart`:

```dart
/// Spec §4.2: the app's hidden `appDataFolder` in the user's Drive. Nothing
/// here knows about snapshots or keys — bytes in, bytes out.
library;

import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'sync_store.dart';

class DriveSyncStore implements SyncStore {
  DriveSyncStore(http.Client client) : _api = drive.DriveApi(client);

  final drive.DriveApi _api;
  static const String _space = 'appDataFolder';

  @override
  Future<List<RemoteFile>> list() async {
    final res = await _api.files.list(
      spaces: _space,
      pageSize: 100,
      $fields: 'files(id,name,md5Checksum)',
    );
    return [
      for (final f in res.files ?? <drive.File>[])
        RemoteFile(id: f.id!, name: f.name!, version: f.md5Checksum),
    ];
  }

  @override
  Future<Uint8List> download(String id) async {
    final media = await _api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia)
        as drive.Media;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  @override
  Future<void> upload(String name, Uint8List bytes) async {
    final existing = (await list()).where((f) => f.name == name).toList();
    final media = drive.Media(Stream.value(bytes), bytes.length);
    if (existing.isEmpty) {
      await _api.files.create(
        drive.File()
          ..name = name
          ..parents = [_space],
        uploadMedia: media,
      );
    } else {
      await _api.files.update(drive.File(), existing.first.id, uploadMedia: media);
    }
  }

  @override
  Future<void> deleteAll() async {
    for (final f in await list()) {
      await _api.files.delete(f.id);
    }
  }
}
```

- [ ] **Step 3: Sign-in wrapper**

Create `lib/sync/google_auth.dart`:

```dart
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// What the sync controller needs from Google: an authenticated HTTP client
/// for Drive, or null when the user isn't signed in. The interface exists
/// so tests can fake sign-in.
abstract class SyncAuth {
  /// Interactive sign-in plus Drive consent. Null when the user cancels.
  Future<http.Client?> signIn();

  /// Silent re-authentication on app start. Null when nobody is signed in
  /// or consent is missing.
  Future<http.Client?> restore();

  Future<void> signOut();
}

/// google_sign_in 7.x. Android needs no client id in code: the OAuth client
/// is matched by package name + signing SHA-1 in the Google Cloud console
/// (spec §4.7, README "Owner setup").
class GoogleAuth implements SyncAuth {
  static const String scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const List<String> _scopes = [scope];

  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  @override
  Future<http.Client?> signIn() async {
    await _init();
    try {
      final account = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
      final auth = await account.authorizationClient.authorizeScopes(_scopes);
      return auth.authClient(scopes: _scopes);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  @override
  Future<http.Client?> restore() async {
    await _init();
    final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) return null;
    final auth = await account.authorizationClient.authorizationForScopes(_scopes);
    return auth?.authClient(scopes: _scopes);
  }

  @override
  Future<void> signOut() async {
    await _init();
    await GoogleSignIn.instance.signOut();
  }
}
```

- [ ] **Step 4: Key storage**

Create `lib/sync/sync_keys.dart`:

```dart
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the derived sync key lives between runs (spec §4.6: the key, never
/// the passphrase). Interface so tests can keep it in memory.
abstract class SyncKeys {
  Future<SecretKey?> read();
  Future<void> write(SecretKey key);
  Future<void> clear();
}

/// Android Keystore / iOS Keychain / WebCrypto-wrapped storage on web.
class SecureSyncKeys implements SyncKeys {
  static const _key = 'sync_key';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<SecretKey?> read() async {
    final b64 = await _storage.read(key: _key);
    return b64 == null ? null : SecretKey(base64Decode(b64));
  }

  @override
  Future<void> write(SecretKey key) async =>
      _storage.write(key: _key, value: base64Encode(await key.extractBytes()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
```

- [ ] **Step 5: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add pubspec.yaml pubspec.lock lib/sync/drive_sync_store.dart lib/sync/google_auth.dart lib/sync/sync_keys.dart
git commit -m "Add the Drive store, Google sign-in wrapper and secure key storage" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JRLLy55rhHqrkMzo7AVgEa"
```

Expected suite: 107 tests (unchanged). If `flutter analyze` reports a missing Android `minSdk` or Gradle requirement from `flutter_secure_storage`/`google_sign_in`, stop and report it rather than editing Gradle files: `minSdk` is Flutter's default 24, which these versions support.

---

### Task 8: Sync controller, Settings screen, triggers (spec §4.5 triggers, §4.7 UI)

**Files:**
- Create: `lib/sync/sync_controller.dart`, `lib/screens/settings_screen.dart`
- Modify: `lib/screens/home_screen.dart`, `lib/main.dart`
- Test: `test/sync/fakes.dart` (create), `test/sync/sync_controller_test.dart` (create), `test/widget_test.dart`

**Interfaces:**
- Consumes: `SyncAuth`, `SyncKeys` (Task 7); `SyncSetup`, `SyncService`, `SyncStore`, `SyncResult` (Task 6); `MemorySyncStore` (test, Task 6); `AppDb` (`getMeta/setMeta`).
- Produces: `enum SyncState { signedOut, needsPassphrase, ready }`; `class SyncController extends ChangeNotifier { SyncController(AppDb db, {required SyncAuth auth, required SyncKeys keys, required SyncStore Function(http.Client) storeFor, Duration debounce = const Duration(seconds: 5), int iterations = SyncCrypto.iterations}) }` with `SyncState state`, `bool syncing`, `DateTime? lastOk`, `String? lastError`, `bool metaExists`, `Future<void> start()`, `Future<void> signIn()`, `Future<bool> setPassphrase(String passphrase)` (create or join depending on `metaExists`; false = wrong passphrase), `Future<void> syncNow()`, `void poke()`, `Future<void> reset()`, `Future<void> signOut()`; `class SettingsScreen extends StatelessWidget { SettingsScreen({required SyncController sync}) }`; `HomeScreen({..., SyncController? syncController})`.

- [ ] **Step 1: Write the fakes and the failing tests**

Create `test/sync/fakes.dart`:

```dart
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:upitrack/sync/google_auth.dart';
import 'package:upitrack/sync/sync_keys.dart';

/// Signs in instantly; `restore` succeeds only after a sign-in.
class FakeAuth implements SyncAuth {
  bool signedIn = false;
  bool cancelNext = false;

  @override
  Future<http.Client?> signIn() async {
    if (cancelNext) {
      cancelNext = false;
      return null;
    }
    signedIn = true;
    return http.Client();
  }

  @override
  Future<http.Client?> restore() async => signedIn ? http.Client() : null;

  @override
  Future<void> signOut() async => signedIn = false;
}

class MemorySyncKeys implements SyncKeys {
  SecretKey? key;

  @override
  Future<SecretKey?> read() async => key;

  @override
  Future<void> write(SecretKey k) async => key = k;

  @override
  Future<void> clear() async => key = null;
}
```

Create `test/sync/sync_controller_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/models/txn.dart';
import 'package:upitrack/sync/sync_controller.dart';

import 'fakes.dart';
import 'memory_sync_store.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late AppDb a;
  late AppDb b;
  late MemorySyncStore store;

  SyncController controller(AppDb db, FakeAuth auth, MemorySyncKeys keys) => SyncController(
        db,
        auth: auth,
        keys: keys,
        storeFor: (_) => store,
        debounce: const Duration(milliseconds: 10),
        iterations: 1000,
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('upitrack_ctl');
    a = await AppDb.open(factory: databaseFactoryFfi, path: p.join(dir.path, 'a.db'));
    b = await AppDb.open(factory: databaseFactoryFfi, path: p.join(dir.path, 'b.db'));
    store = MemorySyncStore();
  });
  tearDown(() async {
    await a.close();
    await b.close();
    await dir.delete(recursive: true);
  });

  test('first device: sign in → create passphrase → ready and uploaded', () async {
    final c = controller(a, FakeAuth(), MemorySyncKeys());
    await c.start();
    expect(c.state, SyncState.signedOut);
    await c.signIn();
    expect(c.state, SyncState.needsPassphrase);
    expect(c.metaExists, isFalse);
    expect(await c.setPassphrase('correct horse'), isTrue);
    expect(c.state, SyncState.ready);
    expect(c.lastOk, isNotNull);
    expect(store.files.keys, contains('meta.json'));
    expect(store.files.length, 2);
  });

  test('second device: wrong passphrase refused, right one syncs the data', () async {
    final ca = controller(a, FakeAuth(), MemorySyncKeys());
    await ca.start();
    await ca.signIn();
    await ca.setPassphrase('correct horse');
    await a.insertAll([
      Txn(key: 'k1', amountPaise: 1, isDebit: true, counterparty: 'SWIGGY', channel: 'UPI',
          category: 'Food', time: DateTime(2026, 10, 3)),
    ]);
    await ca.syncNow();

    final cb = controller(b, FakeAuth(), MemorySyncKeys());
    await cb.start();
    await cb.signIn();
    expect(cb.metaExists, isTrue);
    expect(await cb.setPassphrase('battery staple'), isFalse);
    expect(cb.state, SyncState.needsPassphrase);
    expect(await cb.setPassphrase('correct horse'), isTrue);
    expect((await b.between(DateTime(2026, 10), DateTime(2026, 11))).single.key, 'k1');
  });

  test('a stored key restores straight to ready; sign out forgets it', () async {
    final auth = FakeAuth();
    final keys = MemorySyncKeys();
    final c1 = controller(a, auth, keys);
    await c1.start();
    await c1.signIn();
    await c1.setPassphrase('p');

    final c2 = controller(a, auth, keys);
    await c2.start();
    expect(c2.state, SyncState.ready);
    await c2.signOut();
    expect(c2.state, SyncState.signedOut);
    expect(keys.key, isNull);
  });

  test('a cancelled sign-in stays signed out; poke debounces into one sync', () async {
    final auth = FakeAuth()..cancelNext = true;
    final c = controller(a, auth, MemorySyncKeys());
    await c.start();
    await c.signIn();
    expect(c.state, SyncState.signedOut);

    await c.signIn();
    await c.setPassphrase('p');
    final uploads = store.uploads;
    await a.setMeta('sync_dirty', '1');
    c.poke();
    c.poke();
    c.poke();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(store.uploads, uploads + 1);
  });

  test('reset wipes the folder and asks for a new passphrase', () async {
    final c = controller(a, FakeAuth(), MemorySyncKeys());
    await c.start();
    await c.signIn();
    await c.setPassphrase('p');
    await c.reset();
    expect(store.files, isEmpty);
    expect(c.state, SyncState.needsPassphrase);
    expect(c.metaExists, isFalse);
  });
}
```

Append inside `main()` in `test/widget_test.dart`, adding these imports at the top of that file:

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/screens/settings_screen.dart';
import 'package:upitrack/sync/sync_controller.dart';

import 'sync/fakes.dart';
import 'sync/memory_sync_store.dart';
```

```dart
  testWidgets('Settings walks from sign-in to a passphrase to ready', (tester) async {
    sqfliteFfiInit();
    final db = await AppDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final store = MemorySyncStore();
    final sync = SyncController(db,
        auth: FakeAuth(), keys: MemorySyncKeys(), storeFor: (_) => store, iterations: 1000);
    await sync.start();
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(sync: sync)));

    expect(find.text('Sign in with Google'), findsOneWidget);
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Turn on sync'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('passphrase')), 'correct horse');
    await tester.enterText(find.byKey(const Key('passphrase2')), 'correct horse');
    await tester.tap(find.text('Turn on sync'));
    await tester.pumpAndSettle();
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.textContaining('Last synced'), findsOneWidget);
    await db.close();
  });
```

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/sync/sync_controller_test.dart test/widget_test.dart`
Expected: compile errors — `sync_controller.dart`, `settings_screen.dart` not found.

- [ ] **Step 3: Controller**

Create `lib/sync/sync_controller.dart`:

```dart
import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/db.dart';
import 'crypto.dart';
import 'google_auth.dart';
import 'sync_keys.dart';
import 'sync_service.dart';
import 'sync_setup.dart';
import 'sync_store.dart';

enum SyncState {
  /// Not signed in to Google (or sign-in could not be restored).
  signedOut,

  /// Signed in, but this device has no key: create or enter the passphrase.
  needsPassphrase,

  /// Signed in with a key; syncing happens on the triggers of spec §4.5.
  ready,
}

/// Owns everything the UI needs to know about sync, and runs it. Triggers:
/// [start] (app start), [syncNow] (resume, pull to refresh, Sync now) and
/// [poke] (debounced, after any local change or SMS sync).
class SyncController extends ChangeNotifier {
  SyncController(
    this._db, {
    required SyncAuth auth,
    required SyncKeys keys,
    required SyncStore Function(http.Client client) storeFor,
    this.debounce = const Duration(seconds: 5),
    this.iterations = SyncCrypto.iterations,
  })  : _auth = auth,
        _keys = keys,
        _storeFor = storeFor;

  final AppDb _db;
  final SyncAuth _auth;
  final SyncKeys _keys;
  final SyncStore Function(http.Client) _storeFor;
  final Duration debounce;
  final int iterations;

  SyncState state = SyncState.signedOut;
  bool syncing = false;
  DateTime? lastOk;
  String? lastError;

  /// Whether another device already set sync up (so the passphrase screen
  /// asks to enter, not create). Valid in [SyncState.needsPassphrase].
  bool metaExists = false;

  SyncStore? _store;
  SecretKey? _key;
  Timer? _debounce;

  Future<void> start() async {
    final ms = int.tryParse(await _db.getMeta('drive_last_ok_ms') ?? '');
    if (ms != null) lastOk = DateTime.fromMillisecondsSinceEpoch(ms);
    final client = await _guard(_auth.restore);
    if (client == null) return _set(SyncState.signedOut);
    _store = _storeFor(client);
    _key = await _keys.read();
    if (_key == null) return _askPassphrase();
    _set(SyncState.ready);
    await syncNow();
  }

  Future<void> signIn() async {
    final client = await _guard(_auth.signIn);
    if (client == null) return _set(SyncState.signedOut);
    _store = _storeFor(client);
    _key = await _keys.read();
    if (_key != null) {
      _set(SyncState.ready);
      await syncNow();
    } else {
      await _askPassphrase();
    }
  }

  Future<void> _askPassphrase() async {
    final meta = await _guard(() => SyncSetup(_store!, iterations: iterations).readMeta());
    metaExists = meta != null;
    _set(SyncState.needsPassphrase);
  }

  /// Creates the folder's meta.json (first device) or checks the passphrase
  /// against it. False means it didn't match; the state is unchanged.
  Future<bool> setPassphrase(String passphrase) async {
    final setup = SyncSetup(_store!, iterations: iterations);
    final meta = await setup.readMeta();
    final key = meta == null ? await setup.create(passphrase) : await setup.join(passphrase, meta);
    if (key == null) return false;
    await _keys.write(key);
    _key = key;
    // Everything local must reach the folder once, whatever sync_dirty says.
    await _db.setMeta('sync_dirty', '1');
    _set(SyncState.ready);
    await syncNow();
    return true;
  }

  Future<void> syncNow() async {
    if (state != SyncState.ready || syncing) return;
    syncing = true;
    notifyListeners();
    try {
      await SyncService(_db, _store!, _key!).sync();
      lastOk = DateTime.now();
      lastError = null;
      await _db.setMeta('drive_last_ok_ms', lastOk!.millisecondsSinceEpoch.toString());
    } on SecretBoxAuthenticationError {
      // Spec §4.6: sync was reset on another device; our key no longer fits.
      await _keys.clear();
      _key = null;
      lastError = 'Sync was reset on another device. Enter the new passphrase.';
      await _askPassphrase();
    } catch (e) {
      lastError = '$e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Sync soon, once, however many times this is called in quick succession.
  void poke() {
    if (state != SyncState.ready) return;
    _debounce?.cancel();
    _debounce = Timer(debounce, syncNow);
  }

  /// Forgotten passphrase: wipe the folder; local data stays and is
  /// re-uploaded after a new passphrase.
  Future<void> reset() async {
    await _try(() => SyncSetup(_store!, iterations: iterations).reset());
    await _keys.clear();
    _key = null;
    await _askPassphrase();
  }

  Future<void> signOut() async {
    _debounce?.cancel();
    await _try(_auth.signOut);
    await _keys.clear();
    _key = null;
    _store = null;
    _set(SyncState.signedOut);
  }

  /// Runs [action]; on failure records the error and yields null.
  Future<T?> _guard<T extends Object>(Future<T?> Function() action) async {
    try {
      return await action();
    } catch (e) {
      lastError = '$e';
      notifyListeners();
      return null;
    }
  }

  /// [_guard] for actions with no result.
  Future<void> _try(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      lastError = '$e';
      notifyListeners();
    }
  }

  void _set(SyncState s) {
    state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Settings screen**

Create `lib/screens/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../sync/sync_controller.dart';

/// Settings → Sync with Google Drive (spec §4.7).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.sync});

  final SyncController sync;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: sync,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Sync with Google Drive', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            switch (sync.state) {
              SyncState.signedOut => _SignedOut(sync: sync),
              SyncState.needsPassphrase => _Passphrase(sync: sync),
              SyncState.ready => _Ready(sync: sync),
            },
            if (sync.lastError != null) ...[
              const SizedBox(height: 12),
              Text(sync.lastError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.sync});
  final SyncController sync;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Keep a second phone or the web app in step. Your data is '
              'encrypted on this device with a passphrase before it is stored '
              'in a hidden folder of your Google Drive; Google cannot read it.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: sync.signIn,
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
          ),
        ],
      );
}

class _Passphrase extends StatefulWidget {
  const _Passphrase({required this.sync});
  final SyncController sync;

  @override
  State<_Passphrase> createState() => _PassphraseState();
}

class _PassphraseState extends State<_Passphrase> {
  final _one = TextEditingController();
  final _two = TextEditingController();
  String? _problem;
  bool _busy = false;

  bool get _create => !widget.sync.metaExists;

  @override
  void dispose() {
    _one.dispose();
    _two.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p = _one.text;
    if (p.length < 8) return setState(() => _problem = 'Use at least 8 characters.');
    if (_create && p != _two.text) return setState(() => _problem = 'The two entries differ.');
    setState(() {
      _busy = true;
      _problem = null;
    });
    final ok = await widget.sync.setPassphrase(p);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _problem = "That passphrase doesn't match the one used on your other device.";
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_create
              ? 'Choose a passphrase. It protects your data in Drive and is never '
                  'sent to Google. Write it down: without it, sync has to be reset.'
              : 'Enter the passphrase you chose on your other device.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('passphrase'),
            controller: _one,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Passphrase', border: OutlineInputBorder()),
          ),
          if (_create) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('passphrase2'),
              controller: _two,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repeat passphrase', border: OutlineInputBorder()),
            ),
          ],
          if (_problem != null) ...[
            const SizedBox(height: 8),
            Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_create ? 'Turn on sync' : 'Continue'),
              ),
              const SizedBox(width: 12),
              if (!_create)
                TextButton(
                  onPressed: _busy ? null : () => _confirmReset(context, widget.sync),
                  child: const Text('Forgot it? Reset sync'),
                ),
              const SizedBox(width: 12),
              TextButton(onPressed: _busy ? null : widget.sync.signOut, child: const Text('Sign out')),
            ],
          ),
        ],
      );
}

/// Shared by the passphrase and ready states.
Future<void> _confirmReset(BuildContext context, SyncController sync) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Reset sync?'),
      content: const Text('Deletes the sync files in your Drive. Nothing on this '
          'phone is lost; you choose a new passphrase and everything is uploaded '
          'again. Other devices will ask for the new passphrase.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
      ],
    ),
  );
  if (yes == true) await sync.reset();
}

class _Ready extends StatelessWidget {
  const _Ready({required this.sync});
  final SyncController sync;

  @override
  Widget build(BuildContext context) {
    final last = sync.lastOk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(sync.syncing
            ? 'Syncing…'
            : last == null
                ? 'Not synced yet'
                : 'Last synced ${DateFormat('d MMM, HH:mm').format(last)}'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              onPressed: sync.syncing ? null : sync.syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
            OutlinedButton(onPressed: sync.signOut, child: const Text('Sign out')),
            TextButton(
              onPressed: () => _confirmReset(context, sync),
              child: const Text('Reset sync'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Sign out keeps your data on this phone and forgets the key. Reset '
          'deletes the Drive files so you can choose a new passphrase.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Home screen and app wiring**

`lib/screens/home_screen.dart`:

Imports: add `import '../sync/sync_controller.dart';` and `import 'settings_screen.dart';`.

Constructor: change to

```dart
  const HomeScreen({super.key, required this.repository, this.updateChecker, this.syncController});

  final TxnRepository repository;
  final UpdateChecker? updateChecker;
  final SyncController? syncController;
```

In `didChangeAppLifecycleState`, after `if (state == AppLifecycleState.resumed) _checkAccess();` add:

```dart
    if (state == AppLifecycleState.resumed) widget.syncController?.syncNow();
```

At the end of `_load()`'s body (after the `if (mounted) { setState(...) }` block) add:

```dart
    widget.syncController?.poke();
```

Add a method next to `_openHidden`:

```dart
  Future<void> _openSettings() async {
    final sync = widget.syncController;
    if (sync == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(sync: sync),
    ));
    await _load();
  }
```

In the `PopupMenuButton` `onSelected`, next to `if (v == 'hidden') _openHidden();` add `if (v == 'settings') _openSettings();`. In its `itemBuilder` list, after the `'hidden'` item add:

```dart
              if (widget.syncController != null)
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.cloud_sync_outlined),
                    title: Text('Sync'),
                  ),
                ),
```

In the `ListView` children, directly after `SummaryCard(summary: summary, showToday: _isCurrentMonth),` add:

```dart
            if (widget.syncController != null)
              ListenableBuilder(
                listenable: widget.syncController!,
                builder: (context, _) {
                  final s = widget.syncController!;
                  if (s.state != SyncState.ready) return const SizedBox.shrink();
                  final text = s.syncing
                      ? 'Syncing…'
                      : s.lastOk == null
                          ? 'Not synced yet'
                          : 'Last synced ${DateFormat('d MMM, HH:mm').format(s.lastOk!)}';
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(s.lastError == null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                            size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(text,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        if (s.lastError != null)
                          IconButton(
                            iconSize: 16,
                            tooltip: s.lastError,
                            icon: const Icon(Icons.info_outline),
                            onPressed: _openSettings,
                          ),
                      ],
                    ),
                  );
                },
              ),
```

(`DateFormat` is already imported in home_screen.dart via `package:intl/intl.dart`.)

`lib/main.dart`: add imports

```dart
import 'sync/drive_sync_store.dart';
import 'sync/google_auth.dart';
import 'sync/sync_controller.dart';
import 'sync/sync_keys.dart';
```

and replace `main()` with:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDb.open();
  final info = await PackageInfo.fromPlatform();
  final sync = SyncController(
    db,
    auth: GoogleAuth(),
    keys: SecureSyncKeys(),
    storeFor: DriveSyncStore.new,
  );
  runApp(UpiTrackApp(
    repository: TxnRepository(db, SmsSource(), ShortcutInbox()),
    updateChecker: UpdateChecker(db, currentVersion: info.version),
    syncController: sync,
  ));
  unawaited(sync.start());
}
```

(add `import 'dart:async';` for `unawaited`), and thread it through `UpiTrackApp`:

```dart
  const UpiTrackApp({super.key, required this.repository, this.updateChecker, this.syncController});

  final TxnRepository repository;
  final UpdateChecker? updateChecker;
  final SyncController? syncController;
  ...
      home: HomeScreen(
        repository: repository,
        updateChecker: updateChecker,
        syncController: syncController,
      ),
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/sync/sync_controller_test.dart test/widget_test.dart`
Expected: all pass (5 controller tests, 4 widget tests).

- [ ] **Step 7: Analyze, full suite, commit**

```bash
flutter analyze && flutter test
git add lib/sync/sync_controller.dart lib/screens/settings_screen.dart lib/screens/home_screen.dart lib/main.dart test/sync/fakes.dart test/sync/sync_controller_test.dart test/widget_test.dart
git commit -m "Add the sync controller, Settings screen and sync triggers" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JRLLy55rhHqrkMzo7AVgEa"
```

Expected suite: 113 tests.

---

### Task 9: README (spec §5, §6)

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Features**

Under `## Features`, after the `- **Self transfers:** …` bullet, add:

```markdown
- **Sync (optional):** sign in with Google and choose a passphrase; your payments, categories and hidden rows are encrypted on the phone and kept in a hidden folder of your own Google Drive, so a second phone shows the same data. Google cannot read it
```

- [ ] **Step 2: A new section**

Insert before `## How it works`:

```markdown
## Sync between devices

Menu → **Sync** → *Sign in with Google*. The first device chooses a passphrase; every other device enters the same one. Sync runs when the app opens or resumes, a few seconds after any change, and on pull-to-refresh; a "Last synced" line sits under the summary card.

- What is stored: an encrypted copy of every transaction (including the original SMS text and hidden rows) and your payee rules, in Drive's app-data folder, which only this app can see. `meta.json` there is plain and holds only the salt and a key check.
- Encryption: PBKDF2-HMAC-SHA256 (200 000 rounds) turns the passphrase into an AES-256-GCM key on the device. The key, not the passphrase, is kept in the Android Keystore / iOS Keychain. Google never sees either.
- Merging: payments are only ever added. For category changes and hiding, the most recent human change wins; an automatic import on another device never overwrites your correction.
- Forgot the passphrase: *Reset sync* deletes the Drive files, you choose a new passphrase and this phone re-uploads everything. Other devices then ask for the new passphrase. Nothing on any phone is deleted.
- *Sign out* forgets the key on this phone and keeps your data.

### Owner setup (once, by whoever publishes the app)

Google sign-in needs a Google Cloud project — no code, about ten minutes:

1. [console.cloud.google.com](https://console.cloud.google.com) → New project (e.g. "UPI Track").
2. APIs & Services → Library → enable **Google Drive API**.
3. APIs & Services → OAuth consent screen → External → fill the app name and your email → Scopes → add `https://www.googleapis.com/auth/drive.appdata` only → Audience → Publish app (the `drive.appdata` scope is non-sensitive and needs no verification).
4. APIs & Services → Credentials → Create credentials → OAuth client ID → **Android**: package name `com.piyush.upitrack`, SHA-1 of the release keystore (`keytool -list -v -keystore upload-keystore.jks`, or `openssl x509 -in cert.pem -noout -fingerprint -sha1` on the PEM saved next to it). Add a second Android client with the debug SHA-1 if you run debug builds. Phase 2b adds a Web client for the GitHub Pages origin.

Client IDs are not secrets; Android needs none in code.
```

- [ ] **Step 3: How it works table**

In the `## How it works` table, after the `lib/parser/merchant.dart` row, add:

```markdown
| `lib/sync/` | Snapshot + merge rules (`snapshot.dart`, `merge.dart`), encryption (`crypto.dart`), the sync round (`sync_service.dart`), the Drive adapter (`drive_sync_store.dart`) and the controller the UI talks to (`sync_controller.dart`). |
```

- [ ] **Step 4: Limitations**

Under `## Limitations`, add:

```markdown
- Sync needs the app to be opened: another device sees new payments only after the phone that received the SMS has run the app (no background upload).
- Google sign-in on a sideloaded APK works only when the APK is signed with the keystore whose SHA-1 is registered in the Google Cloud project; a build signed with another key gets a sign-in error.
- Clearing the app's data (or reinstalling without sync) loses local-only changes made since the last successful sync.
```

- [ ] **Step 5: Commit**

```bash
flutter analyze && flutter test
git add README.md
git commit -m "Document Google Drive sync and the owner's Google Cloud setup" -m "Co-Authored-By: <model> <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JRLLy55rhHqrkMzo7AVgEa"
```

---

## Self-review against the spec

| Spec | Task |
| --- | --- |
| §4.2 Drive layout: `appDataFolder`, `meta.json`, `dev-<id>.json.enc`, own file only, whole-file replace | 6 (`SyncSetup`, `SyncService.fileNameFor`), 7 (`DriveSyncStore.upload`) |
| §4.3 schema v3: `edit_ts`, `rules.ts`, meta keys, manual key with device id, dirty on every write | 1, 2 |
| §4.4 snapshot format incl. hidden + raw, no ids | 3, 4 |
| §4.5 merge algorithm, idempotent, rule application respects `edit_ts`, triggers | 3, 4, 6, 8 |
| §4.6 PBKDF2/AES-GCM parameters, key check, key in secure storage, reset flow, "reset on another device" detection | 5, 6, 7, 8 |
| §4.7 sign-in, scope, Settings flow (create / enter / reset / sign out), owner setup documented | 7, 8, 9 |
| §4.9 tests: pure merge, crypto round-trip + wrong key + nonce, apply against real SQLite, dirty bookkeeping, fake store | 3, 4, 5, 6, 8 |
| §3.3 "Phase 2's `edit_ts` makes this exact" — pairing on `edit_ts`, `unpaired_ids` migrated away | 1, 2 |
| §5 files and dependencies (minus `uuid`; gzip deferred — see Deviations) | 5, 7 |
| §6 risks in README | 9 |
| §4.8 web build | **Phase 2b plan** |

Name consistency: `Txn.editTs`/`hidden` (1 → 2, 4, 6); `AppDb.setCategory(id, category, {byUser})` (2 → 2's pairing); `AppDb.deviceId()`, `rulesRows()` (1–2 → 4, 6); `mergeTxn`/`ruleWins`/`TxnMerge` (3 → 4); `buildSnapshot`/`encodeSnapshot`/`decodeSnapshot` (3 → 4, 6); `SyncCrypto.{newSalt,deriveKey,encrypt,decrypt,makeCheck,verifyCheck}` (5 → 6, 8); `RemoteFile.version`, `SyncStore` four methods (6 → 7, 8); `SyncSetup(store, {iterations})` with `readMeta/create/join/reset` (6 → 8); `SyncService(db, store, key).sync()`, `fileNameFor` (6 → 8); `SyncAuth.{signIn,restore,signOut}`, `SyncKeys.{read,write,clear}` (7 → 8); `SyncController` API and `SyncState` (8 → 8's Settings, home, main).
