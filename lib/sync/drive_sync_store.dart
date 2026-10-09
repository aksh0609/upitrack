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
    final media = await _api.files.get(id,
        downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
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
      await _api.files
          .update(drive.File(), existing.first.id, uploadMedia: media);
    }
  }

  @override
  Future<void> deleteAll() async {
    for (final f in await list()) {
      await _api.files.delete(f.id);
    }
  }
}
