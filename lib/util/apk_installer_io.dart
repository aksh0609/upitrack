import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const _channel = MethodChannel('upitrack/update');

/// Downloads [apk] into the app's cache and opens Android's package
/// installer, which asks the user to confirm the update. Same package name
/// and signing key as the running app, so data and sign-in survive.
Future<void> downloadAndInstall(Uri apk,
    {void Function(double)? onProgress}) async {
  final dir =
      Directory('${(await getApplicationCacheDirectory()).path}/updates');
  await dir.create(recursive: true);
  final file = File('${dir.path}/update.apk');
  await downloadApk(apk, file, onProgress: onProgress);
  // Android 8+: the user allows "install unknown apps" once for this app.
  if (!await Permission.requestInstallPackages.isGranted) {
    await Permission.requestInstallPackages.request();
  }
  await _channel.invokeMethod<void>('install', {'path': file.path});
}

/// Streams [apk] into [into], reporting progress 0..1 when the server says
/// how big the file is. Throws on a non-200 response.
Future<void> downloadApk(Uri apk, File into,
    {void Function(double)? onProgress, http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c.send(http.Request('GET', apk));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: apk);
    }
    final total = res.contentLength;
    final sink = into.openWrite();
    var got = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total != null && total > 0) onProgress?.call(got / total);
      }
    } finally {
      await sink.close();
    }
  } finally {
    c.close();
  }
}
