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
      db = await AppDb.open(
          factory: databaseFactoryFfi, path: inMemoryDatabasePath);
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
        client: MockClient((_) async =>
            http.Response('{"tag_name":"v0.2.0","html_url":"u"}', 200)),
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
