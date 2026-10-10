import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:upitrack/util/apk_installer_io.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('apk'));
  tearDown(() => tmp.delete(recursive: true));

  test('downloadApk streams the bytes to the file and reports progress',
      () async {
    final bytes = List<int>.generate(10000, (i) => i % 251);
    final progress = <double>[];
    final file = File('${tmp.path}/update.apk');
    await downloadApk(
      Uri.parse('https://x/u.apk'),
      file,
      onProgress: progress.add,
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    expect(await file.readAsBytes(), bytes);
    expect(progress.last, 1.0);
  });

  test('a non-200 answer throws and leaves no file', () async {
    final file = File('${tmp.path}/update.apk');
    await expectLater(
      downloadApk(Uri.parse('https://x/u.apk'), file,
          client: MockClient((_) async => http.Response('nope', 404))),
      throwsA(isA<HttpException>()),
    );
    expect(file.existsSync(), isFalse);
  });
}
