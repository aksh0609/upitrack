import 'package:cryptography/cryptography.dart';
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
