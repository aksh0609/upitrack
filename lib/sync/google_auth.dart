import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'oauth_ids.dart';

/// What the sync controller needs from Google: an authenticated HTTP client
/// for Drive, or null when the user isn't signed in. The interface exists
/// so tests can fake sign-in.
abstract class SyncAuth {
  /// Interactive sign-in plus Drive consent. Null when the user cancels.
  Future<http.Client?> signIn();

  /// Silent re-authentication on app start. Null when nobody is signed in
  /// or consent is missing.
  Future<http.Client?> restore();

  /// A client with a fresh token, without UI. Null when not signed in.
  Future<http.Client?> client();

  Future<void> signOut();
}

/// google_sign_in 7.x. The Android OAuth client is matched by package name +
/// signing SHA-1 in the Google Cloud console; Credential Manager also needs
/// the Web client id as `serverClientId` (spec §4.7, README "Owner setup").
class GoogleAuth implements SyncAuth {
  static const String scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const List<String> _scopes = [scope];

  bool _initialized = false;
  GoogleSignInAccount? _account;

  Future<void> _init() async {
    if (_initialized) return;
    if (kGoogleServerClientId == null) {
      throw StateError(
          'Google sign-in is not configured: set kGoogleServerClientId in '
          'lib/sync/oauth_ids.dart (README → Owner setup).');
    }
    await GoogleSignIn.instance
        .initialize(serverClientId: kGoogleServerClientId);
    _initialized = true;
  }

  @override
  Future<http.Client?> signIn() async {
    await _init();
    try {
      final account =
          await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
      final auth = await account.authorizationClient.authorizeScopes(_scopes);
      _account = account;
      return auth.authClient(scopes: _scopes);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  @override
  Future<http.Client?> restore() async {
    await _init();
    final account =
        await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) return null;
    _account = account;
    return client();
  }

  /// The access token inside lasts about an hour, so callers ask for a new
  /// client per operation; authorizationForScopes refreshes it silently.
  @override
  Future<http.Client?> client() async {
    final account = _account;
    if (account == null) return null;
    final auth =
        await account.authorizationClient.authorizationForScopes(_scopes);
    return auth?.authClient(scopes: _scopes);
  }

  @override
  Future<void> signOut() async {
    _account = null;
    await _init();
    await GoogleSignIn.instance.signOut();
  }
}
