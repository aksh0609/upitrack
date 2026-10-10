import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upitrack/data/db.dart';
import 'package:upitrack/util/update_check.dart';

void main() {
  sqfliteFfiInit();

  const release = '''[{"tag_name":"test-build-7",
    "html_url":"https://github.com/aksh0609/upitrack/releases/tag/test-build-7",
    "created_at":"2026-10-10T12:00:00Z","prerelease":true,
    "assets":[{"name":"notes.txt","browser_download_url":"https://x/notes.txt"},
              {"name":"upitrack-test-build-7.apk",
               "browser_download_url":"https://x/upitrack-test-build-7.apk"}]}]''';
  final builtBefore = DateTime.utc(2026, 10, 10, 11);

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
        buildTime: builtBefore,
        client: MockClient((req) async {
          calls++;
          expect(req.url.path, '/repos/aksh0609/upitrack/releases');
          expect(req.url.queryParameters['per_page'], '1');
          return http.Response(release, 200);
        }),
      );
    });
    tearDown(() => db.close());

    test('reports the newest release, pre-release or not, with its APK',
        () async {
      final t0 = DateTime(2026, 10, 10, 18);
      final info = await checker.check(now: t0);
      expect(info?.tag, 'test-build-7');
      expect(info?.title, 'test-build-7');
      expect(info?.url, endsWith('/tag/test-build-7'));
      expect(info?.apkUrl, 'https://x/upitrack-test-build-7.apk');
      expect(calls, 1);

      await checker.check(now: t0.add(const Duration(minutes: 14)));
      expect(calls, 1, reason: 'within 15 min the stored answer is reused');
      await checker.check(now: t0.add(const Duration(minutes: 16)));
      expect(calls, 2);
      await checker.check(
          now: t0.add(const Duration(minutes: 16)), force: true);
      expect(calls, 3, reason: 'force asks again');
    });

    test('a dismissed tag is not shown again', () async {
      await checker.dismiss('test-build-7');
      expect(await checker.check(now: DateTime(2026, 10, 10)), isNull);
    });

    test('the build the release was made from is not an update', () async {
      final same = UpdateChecker(
        db,
        buildTime: DateTime.utc(2026, 10, 10, 12),
        client: MockClient((_) async => http.Response(release, 200)),
      );
      expect(await same.check(now: DateTime(2026, 10, 10)), isNull);
      final newer = UpdateChecker(
        db,
        buildTime: DateTime.utc(2026, 10, 10, 13),
        client: MockClient((_) async => http.Response(release, 200)),
      );
      expect(await newer.check(now: DateTime(2026, 10, 10)), isNull);
    });

    test('a hand-built app (no build time) treats every release as newer',
        () async {
      final local = UpdateChecker(
        db,
        client: MockClient((_) async => http.Response(release, 200)),
      );
      expect((await local.check(now: DateTime(2026, 10, 10)))?.tag,
          'test-build-7');
    });

    test('a version tag reads as "Version x.y.z"', () {
      final v = UpdateInfo(tag: 'v0.3.0', url: 'u', createdAt: DateTime(2026));
      expect(v.title, 'Version 0.3.0');
    });

    test('network failure is silent and retried next time', () async {
      final failing = UpdateChecker(
        db,
        buildTime: builtBefore,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await failing.check(now: DateTime(2026, 10, 10)), isNull);
      expect(await db.getMeta('update_checked_ms'), isNull);
    });
  });
}
