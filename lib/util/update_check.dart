import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/db.dart';

/// 'v0.2.0' is newer than '0.1.5'. Compares major.minor.patch; ignores a
/// leading 'v', build numbers ('+5') and pre-release tags ('-beta').
bool isNewerVersion(String tag, String current) {
  List<int> parse(String v) => RegExp(r'\d+')
      .allMatches(v.split(RegExp(r'[-+]')).first)
      .map((m) => int.parse(m.group(0)!))
      .toList();
  final a = parse(tag);
  final b = parse(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

class UpdateInfo {
  const UpdateInfo({required this.tag, required this.url});

  /// Git tag of the release, e.g. 'v0.2.0'.
  final String tag;

  /// The release page, where the APK is attached.
  final String url;
}

/// Asks GitHub for the latest release at most once a day and remembers the
/// answer in `meta`. Only shown on Android: the web app is always current
/// and iPhones update through TestFlight.
class UpdateChecker {
  UpdateChecker(
    this._db, {
    required this.currentVersion,
    http.Client? client,
    this.repo = 'aksh0609/upitrack',
  }) : _client = client ?? http.Client();

  final AppDb _db;
  final String currentVersion;
  final http.Client _client;
  final String repo;

  static const Duration interval = Duration(hours: 24);

  /// A newer release the user hasn't dismissed, or null.
  Future<UpdateInfo?> check({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final last = int.tryParse(await _db.getMeta('update_checked_ms') ?? '') ?? 0;
    if (t.millisecondsSinceEpoch - last >= interval.inMilliseconds) {
      await _fetch(t);
    }
    final tag = await _db.getMeta('update_tag');
    final url = await _db.getMeta('update_url');
    if (tag == null || url == null) return null;
    if (tag == await _db.getMeta('update_dismissed')) return null;
    return isNewerVersion(tag, currentVersion) ? UpdateInfo(tag: tag, url: url) : null;
  }

  Future<void> _fetch(DateTime now) async {
    try {
      final r = await _client
          .get(
            Uri.https('api.github.com', '/repos/$repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      await _db.setMeta('update_tag', json['tag_name'] as String);
      await _db.setMeta('update_url', json['html_url'] as String);
      await _db.setMeta('update_checked_ms', now.millisecondsSinceEpoch.toString());
    } catch (_) {
      // Offline, rate-limited or GitHub down: try again on the next open.
    }
  }

  /// Hide this tag's banner. A later release shows a banner again.
  Future<void> dismiss(String tag) => _db.setMeta('update_dismissed', tag);
}
