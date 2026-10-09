import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
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

  /// A Google account is known, whether or not Drive access is current.
  /// On the web the Settings screen then offers "Allow Drive access"
  /// instead of Google's sign-in button.
  bool get hasAccount;
}

/// google_sign_in 7.x. The Android OAuth client is matched by package name +
/// signing SHA-1 in the Google Cloud console; Credential Manager also needs
/// the Web client id as `serverClientId` (spec §4.7, README "Owner setup").
/// On the web the same Web client id is the `clientId`, the user signs in
/// through Google's rendered button, and the hour-long access token is never
/// refreshed, so `client()` turns null until the next "Allow Drive access".
class GoogleAuth implements SyncAuth {
  static const String scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const List<String> _scopes = [scope];

  /// Web only: Google's button (or its sign-out) changed the account outside
  /// our code; the controller re-checks sign-in when this fires.
  VoidCallback? onAccountChanged;

  Future<void>? _initializing;
  GoogleSignInAccount? _account;

  @override
  bool get hasAccount => _account != null;

  /// Runs the plugin's initialize() once, however many callers overlap.
  Future<void> _init() async {
    try {
      await (_initializing ??= _doInit());
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  Future<void> _doInit() async {
    final id = kGoogleServerClientId;
    if (id == null) {
      throw StateError(
          'Google sign-in is not configured: set kGoogleServerClientId in '
          'lib/sync/oauth_ids.dart (README → Owner setup).');
    }
    if (kIsWeb) {
      // The web plugin rejects serverClientId and takes the Web client as
      // clientId. Sign-in happens through renderButton() and lands here.
      await GoogleSignIn.instance.initialize(clientId: id);
      GoogleSignIn.instance.authenticationEvents.listen((event) {
        _account = switch (event) {
          GoogleSignInAuthenticationEventSignIn(:final user) => user,
          GoogleSignInAuthenticationEventSignOut() => null,
        };
        onAccountChanged?.call();
      });
    } else {
      await GoogleSignIn.instance.initialize(serverClientId: id);
    }
  }

  @override
  Future<http.Client?> signIn() async {
    await _init();
    try {
      // Web: authenticate() is unsupported; the account came from Google's
      // button, and this call (made from a tap) only asks for Drive access.
      final account = kIsWeb
          ? _account
          : await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
      if (account == null) return null;
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
    // Web: attemptLightweightAuthentication shows Google One Tap on every
    // page load and returns null at once; reuse a known account instead.
    if (kIsWeb) return client();
    final account =
        await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) return null;
    _account = account;
    return client();
  }

  /// The access token inside lasts about an hour, so callers ask for a new
  /// client per operation; authorizationForScopes refreshes it silently
  /// (on the web it returns null once the token has expired).
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
