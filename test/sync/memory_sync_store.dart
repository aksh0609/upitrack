import 'dart:typed_data';

import 'package:upitrack/sync/sync_store.dart';

/// Drive stand-in: files by name, a version that changes with content.
class MemorySyncStore implements SyncStore {
  final Map<String, Uint8List> files = {};
  int downloads = 0;
  int uploads = 0;

  /// Runs before each upload is stored; tests use it to simulate a local
  /// write or a network failure mid-upload.
  Future<void> Function()? onUpload;

  @override
  Future<List<RemoteFile>> list() async => [
        for (final e in files.entries)
          RemoteFile(
              id: e.key,
              name: e.key,
              version: Object.hashAll(e.value).toRadixString(16)),
      ];

  @override
  Future<Uint8List> download(String id) async {
    downloads++;
    return files[id]!;
  }

  @override
  Future<void> upload(String name, Uint8List bytes) async {
    if (onUpload != null) await onUpload!();
    uploads++;
    files[name] = bytes;
  }

  @override
  Future<void> deleteAll() async => files.clear();
}
