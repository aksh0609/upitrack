import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:upitrack/sync/google_auth.dart';
import 'package:upitrack/sync/sync_keys.dart';

/// Signs in instantly; `restore` succeeds only after a sign-in.
class FakeAuth implements SyncAuth {
  bool signedIn = false;
  bool cancelNext = false;

  @override
  Future<http.Client?> signIn() async {
    if (cancelNext) {
      cancelNext = false;
      return null;
    }
    signedIn = true;
    return http.Client();
  }

  @override
  Future<http.Client?> restore() async => signedIn ? http.Client() : null;

  @override
  Future<http.Client?> client() async => signedIn ? http.Client() : null;

  @override
  Future<void> signOut() async => signedIn = false;
}

class MemorySyncKeys implements SyncKeys {
  SecretKey? key;

  @override
  Future<SecretKey?> read() async => key;

  @override
  Future<void> write(SecretKey k) async => key = k;

  @override
  Future<void> clear() async => key = null;
}

/// Polls [condition] every 10 ms until true or [timeout]; fails the test on timeout.
Future<void> waitFor(bool Function() condition,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('waitFor timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
