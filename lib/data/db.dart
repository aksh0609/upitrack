import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/account.dart';
import '../models/txn.dart';
import '../models/unparsed.dart';
import '../parser/categorizer.dart';
import '../sync/merge.dart';
import '../sync/snapshot.dart';

/// Local SQLite storage. Nothing ever leaves the phone.
class AppDb {
  AppDb._(this._db);

  final Database _db;

  /// Opens the on-device database. Tests pass [factory] (sqflite_common_ffi)
  /// and [path] (`inMemoryDatabasePath`) to get a throwaway in-memory copy.
  static Future<AppDb> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'upitrack.db'),
      options: OpenDatabaseOptions(
        version: 3,
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
            hidden INTEGER NOT NULL DEFAULT 0,
            edit_ts INTEGER NOT NULL DEFAULT 0
          )''');
          await db.execute('CREATE INDEX idx_txns_ts ON txns(ts)');
          // Category the user picked for a payee, applied to future payments.
          await db.execute(
              'CREATE TABLE rules(counterparty TEXT PRIMARY KEY, category TEXT NOT NULL, ts INTEGER NOT NULL DEFAULT 0)');
          await db.execute(
              'CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT NOT NULL)');
          await _createUnparsed(db);
        },
        onUpgrade: (db, from, to) async {
          if (from < 2) await _createUnparsed(db);
          if (from < 3) await _upgradeToV3(db);
        },
      ),
    );
    return AppDb._(db);
  }

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

  /// v3 (spec §4.3): `edit_ts` on txns and `ts` on rules. Existing rows
  /// whose category differs from the automatic guess were set by hand, so
  /// they are stamped as edits; so are the ids Phase 1b kept in
  /// `unpaired_ids`. Self-transfer rows stay automatic.
  static Future<void> _upgradeToV3(Database db) async {
    await db.execute(
        'ALTER TABLE txns ADD COLUMN edit_ts INTEGER NOT NULL DEFAULT 0');
    await db
        .execute('ALTER TABLE rules ADD COLUMN ts INTEGER NOT NULL DEFAULT 0');
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
      final guess = Categorizer.categorizeWith(
          rules, r['counterparty'] as String,
          isDebit: (r['is_debit'] as int) == 1);
      if (category != guess) {
        batch.update('txns', {'edit_ts': now},
            where: 'id = ?', whereArgs: [r['id']]);
      }
    }
    final unpaired = await db.query('meta', where: "k = 'unpaired_ids'");
    if (unpaired.isNotEmpty) {
      for (final s in (unpaired.first['v'] as String).split(',')) {
        if (s.isEmpty) continue;
        final id = int.tryParse(s);
        if (id == null) continue;
        batch.update('txns', {'edit_ts': now},
            where: 'id = ?', whereArgs: [id]);
      }
      batch.delete('meta', where: "k = 'unpaired_ids'");
    }
    batch.insert('meta', {'k': 'sync_dirty', 'v': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }

  /// A separate read-only connection for the background SMS path. Not a
  /// single instance, so closing it never touches the app's own connection,
  /// and no version/migration hooks run. Throws if the file doesn't exist.
  static Future<AppDb> openReadOnly(
      {DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'upitrack.db'),
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    return AppDb._(db);
  }

  Future<void> close() => _db.close();

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Spec §4.3: every write that changes txns or rules flags the device for
  /// upload. [e] is the connection or the transaction doing the write.
  static Future<void> _markDirty(DatabaseExecutor e) =>
      e.insert('meta', {'k': 'sync_dirty', 'v': '1'},
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<int> _count() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM txns')) ??
      0;

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

  Future<List<Txn>> between(DateTime from, DateTime to) async {
    final rows = await _db.query(
      'txns',
      where: 'hidden = 0 AND ts >= ? AND ts < ?',
      whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
      orderBy: 'ts DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  /// Like [between] but including hidden rows: duplicate matching must see
  /// a payment the user hid, or a statement import would add it back.
  Future<List<Txn>> betweenIncludingHidden(DateTime from, DateTime to) async {
    final rows = await _db.query(
      'txns',
      where: 'ts >= ? AND ts < ?',
      whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
      orderBy: 'ts DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  /// Accounts seen in the SMS, most-used first.
  Future<List<AccountRef>> accounts() async {
    final rows =
        await _db.rawQuery('SELECT bank, account, COUNT(*) AS n FROM txns '
            'WHERE account IS NOT NULL AND hidden = 0 '
            'GROUP BY bank, account ORDER BY n DESC');
    return [
      for (final r in rows)
        (bank: r['bank'] as String?, last4: r['account'] as String),
    ];
  }

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
      await txn.insert('rules',
          {'counterparty': counterparty, 'category': category, 'ts': now},
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

  /// Everything the user hid, newest first, across all months.
  Future<List<Txn>> hidden() async {
    final rows =
        await _db.query('txns', where: 'hidden = 1', orderBy: 'ts DESC');
    return rows.map(Txn.fromMap).toList();
  }

  Future<Map<String, String>> rules() async {
    final rows = await _db.query('rules');
    return {
      for (final r in rows) r['counterparty'] as String: r['category'] as String
    };
  }

  /// Every rule row with its timestamp, for snapshots.
  Future<List<Map<String, Object?>>> rulesRows() async =>
      [for (final r in await _db.query('rules')) Map<String, Object?>.from(r)];

  Future<String?> getMeta(String k) async {
    final rows =
        await _db.query('meta', where: 'k = ?', whereArgs: [k], limit: 1);
    return rows.isEmpty ? null : rows.first['v'] as String;
  }

  /// This install's id, generated once: 32 hex chars from a secure RNG.
  /// Names this device's snapshot file and keys its manual entries.
  Future<String> deviceId() async {
    final existing = await getMeta('device_id');
    if (existing != null) return existing;
    final rng = Random.secure();
    final id = List.generate(
        16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await setMeta('device_id', id);
    return id;
  }

  Future<void> setMeta(String k, String v) =>
      _db.insert('meta', {'k': k, 'v': v},
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteMeta(String k) =>
      _db.delete('meta', where: 'k = ?', whereArgs: [k]);

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
  /// outranks, then every local rule is re-applied to rows it outranks.
  /// Idempotent. Returns true (and flags dirty) when anything
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
          await txn.insert('txns', t,
              conflictAlgorithm: ConflictAlgorithm.ignore);
          changed = true;
        } else if (action == TxnMerge.update) {
          await txn.update(
            'txns',
            {
              'category': t['category'],
              'hidden': t['hidden'] ?? 0,
              'edit_ts': t['edit_ts'] ?? 0
            },
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
        await txn.insert('rules', r,
            conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.update('txns', {'category': r['category']},
            where: 'counterparty = ? AND is_debit = 1 AND edit_ts < ?',
            whereArgs: [r['counterparty'], r['ts']]);
        changed = true;
      }
      // A row that arrived after a local rule was set still follows it.
      for (final r in await txn.query('rules')) {
        final n = await txn.update('txns', {'category': r['category']},
            where:
                'counterparty = ? AND is_debit = 1 AND edit_ts < ? AND category != ? AND category != ?',
            whereArgs: [
              r['counterparty'],
              r['ts'],
              r['category'],
              Categorizer.selfTransfer
            ]);
        if (n > 0) changed = true;
      }
      if (changed) await _markDirty(txn);
    });
    return changed;
  }

  // ---------------------------------------------------------------- unparsed

  /// Inserts rows, skipping keys already stored.
  Future<void> insertUnparsed(List<UnparsedSms> rows) async {
    if (rows.isEmpty) return;
    final batch = _db.batch();
    for (final u in rows) {
      batch.insert('unparsed', u.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<List<UnparsedSms>> openUnparsed() async {
    final rows = await _db.query('unparsed',
        where: "state = 'open'", orderBy: 'ts DESC');
    return rows.map(UnparsedSms.fromMap).toList();
  }

  Future<void> setUnparsedState(int id, String state) => _db
      .update('unparsed', {'state': state}, where: 'id = ?', whereArgs: [id]);

  /// Deletes handled rows older than [before]. Open rows are kept.
  Future<void> purgeUnparsed({required DateTime before}) =>
      _db.delete('unparsed',
          where: "state != 'open' AND ts < ?",
          whereArgs: [before.millisecondsSinceEpoch]);
}
