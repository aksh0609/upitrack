import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/txn.dart';

/// Local SQLite storage. Nothing ever leaves the phone.
class AppDb {
  AppDb._(this._db);

  final Database _db;

  static Future<AppDb> open() async {
    final path = p.join(await getDatabasesPath(), 'upitrack.db');
    final db = await openDatabase(
      path,
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
            hidden INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('CREATE INDEX idx_txns_ts ON txns(ts)');
        // Category the user picked for a payee, applied to future payments.
        await db.execute(
            'CREATE TABLE rules(counterparty TEXT PRIMARY KEY, category TEXT NOT NULL)');
        await db.execute(
            'CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT NOT NULL)');
      },
    );
    return AppDb._(db);
  }

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
}
