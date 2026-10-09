import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/txn.dart';
import '../models/unparsed.dart';

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
        version: 2,
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
          await _createUnparsed(db);
        },
        onUpgrade: (db, from, to) async {
          if (from < 2) await _createUnparsed(db);
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

  /// A separate read-only connection for the background SMS path. Not a
  /// single instance, so closing it never touches the app's own connection,
  /// and no version/migration hooks run. Throws if the file doesn't exist.
  static Future<AppDb> openReadOnly({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'upitrack.db'),
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    return AppDb._(db);
  }

  Future<void> close() => _db.close();

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
    return await _count() - before;
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

  Future<void> setCategory(int id, String category) => _db.update(
      'txns', {'category': category},
      where: 'id = ?', whereArgs: [id]);

  /// Re-categorises every payment to/from [counterparty] and remembers it.
  Future<void> setCategoryForPayee(String counterparty, String category) async {
    await _db.transaction((txn) async {
      await txn.update('txns', {'category': category},
          where: 'counterparty = ? AND is_debit = 1',
          whereArgs: [counterparty]);
      await txn.insert(
          'rules', {'counterparty': counterparty, 'category': category},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Hidden rather than deleted, so the next SMS sync doesn't re-add it.
  Future<void> hide(int id) =>
      _db.update('txns', {'hidden': 1}, where: 'id = ?', whereArgs: [id]);

  /// Everything the user hid, newest first, across all months.
  Future<List<Txn>> hidden() async {
    final rows = await _db.query('txns', where: 'hidden = 1', orderBy: 'ts DESC');
    return rows.map(Txn.fromMap).toList();
  }

  Future<void> unhide(int id) =>
      _db.update('txns', {'hidden': 0}, where: 'id = ?', whereArgs: [id]);

  Future<Map<String, String>> rules() async {
    final rows = await _db.query('rules');
    return {
      for (final r in rows) r['counterparty'] as String: r['category'] as String
    };
  }

  Future<String?> getMeta(String k) async {
    final rows =
        await _db.query('meta', where: 'k = ?', whereArgs: [k], limit: 1);
    return rows.isEmpty ? null : rows.first['v'] as String;
  }

  Future<void> setMeta(String k, String v) => _db.insert(
      'meta', {'k': k, 'v': v},
      conflictAlgorithm: ConflictAlgorithm.replace);

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
}
