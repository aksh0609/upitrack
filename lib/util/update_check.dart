import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/db.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.tag,
    required this.url,
    required this.createdAt,
    this.apkUrl,
  });

  /// Git tag of the release, e.g. 'v0.3.0' or 'test-build-7'.
  final String tag;

  /// The release page, where the APK is attached.
  final String url;

  /// Direct download of the APK asset, when the release has one.
  final String? apkUrl;

  /// GitHub sets this to the date of the commit the release was built from.
  final DateTime createdAt;

  /// 'Version 0.3.0' for a tagged version, else the tag itself.
  String get title => tag.startsWith('v') ? 'Version ${tag.substring(1)}' : tag;
}

/// Asks GitHub for the newest release (pre-releases included) at most every
/// [interval] and remembers the answer in `meta`. A release counts as an
/// update when its commit is newer than the one this build came from
/// ([buildTime], stamped by CI). Only shown on Android: the web app is always
/// current and iPhones update through TestFlight.
class UpdateChecker {
  UpdateChecker(
    this._db, {
    this.buildTime,
    http.Client? client,
    this.repo = 'aksh0609/upitrack',
  }) : _client = client ?? http.Client();

  final AppDb _db;

  /// Commit time of this build; null for local builds, which then treat
  /// every release as newer.
  final DateTime? buildTime;
  final http.Client _client;
  final String repo;

  static const Duration interval = Duration(minutes: 15);

  /// A newer release the user hasn't dismissed, or null. [force] asks GitHub
  /// again even inside [interval].
  Future<UpdateInfo?> check({DateTime? now, bool force = false}) async {
    final t = now ?? DateTime.now();
    final last =
        int.tryParse(await _db.getMeta('update_checked_ms') ?? '') ?? 0;
    if (force || t.millisecondsSinceEpoch - last >= interval.inMilliseconds) {
      await _fetch(t);
    }
    final tag = await _db.getMeta('update_tag');
    final url = await _db.getMeta('update_url');
    final created =
        DateTime.tryParse(await _db.getMeta('update_created') ?? '');
    if (tag == null || url == null || created == null) return null;
    if (tag == await _db.getMeta('update_dismissed')) return null;
    final built = buildTime;
    if (built != null && !created.isAfter(built)) return null;
    return UpdateInfo(
      tag: tag,
      url: url,
      createdAt: created,
      apkUrl: switch (await _db.getMeta('update_apk')) {
        null || '' => null,
        final u => u,
      },
    );
  }

  Future<void> _fetch(DateTime now) async {
    try {
      final r = await _client.get(
        Uri.https('api.github.com', '/repos/$repo/releases', {'per_page': '1'}),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final list = jsonDecode(r.body) as List<dynamic>;
      if (list.isEmpty) return;
      final json = list.first as Map<String, dynamic>;
      final assets = (json['assets'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      final apk = assets
          .map((a) => a['browser_download_url'] as String?)
          .firstWhere((u) => u != null && u.endsWith('.apk'),
              orElse: () => null);
      await _db.setMeta('update_tag', json['tag_name'] as String);
      await _db.setMeta('update_url', json['html_url'] as String);
      await _db.setMeta('update_created', json['created_at'] as String);
      await _db.setMeta('update_apk', apk ?? '');
      await _db.setMeta(
          'update_checked_ms', now.millisecondsSinceEpoch.toString());
    } catch (_) {
      // Offline, rate-limited or GitHub down: try again on the next open.
    }
  }

  /// Hide this tag's banner. A later release shows a banner again.
  Future<void> dismiss(String tag) => _db.setMeta('update_dismissed', tag);
}
