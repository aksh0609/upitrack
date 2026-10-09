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
