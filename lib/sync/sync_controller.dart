import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/db.dart';
import 'crypto.dart';
import 'google_auth.dart';
import 'sync_keys.dart';
import 'sync_service.dart';
import 'sync_setup.dart';
import 'sync_store.dart';

enum SyncState {
  /// Not signed in to Google (or sign-in could not be restored).
  signedOut,

  /// Signed in, but this device has no key: create or enter the passphrase.
  needsPassphrase,

  /// Signed in with a key; syncing happens on the triggers of spec §4.5.
  ready,
}

/// Owns everything the UI needs to know about sync, and runs it. Triggers:
/// [start] (app start), [syncNow] (resume, pull to refresh, Sync now) and
/// [poke] (debounced, after any local change or SMS sync).
class SyncController extends ChangeNotifier {
  SyncController(
    this._db, {
    required SyncAuth auth,
    required SyncKeys keys,
    required SyncStore Function(http.Client client) storeFor,
    this.debounce = const Duration(seconds: 5),
    this.iterations = SyncCrypto.iterations,
  })  : _auth = auth,
        _keys = keys,
        _storeFor = storeFor;

  final AppDb _db;
  final SyncAuth _auth;
  final SyncKeys _keys;
  final SyncStore Function(http.Client) _storeFor;
  final Duration debounce;
  final int iterations;

  SyncState state = SyncState.signedOut;
  bool syncing = false;
  DateTime? lastOk;
  String? lastError;

  /// Whether another device already set sync up (so the passphrase screen
  /// asks to enter, not create). Valid in [SyncState.needsPassphrase].
  bool metaExists = false;

  /// Counts syncs that pulled something new, so the home screen knows to reload.
  int pulled = 0;

  SyncStore? _store;
  SecretKey? _key;
  Timer? _debounce;

  Future<void> start() async {
    final ms = int.tryParse(await _db.getMeta('drive_last_ok_ms') ?? '');
    if (ms != null) lastOk = DateTime.fromMillisecondsSinceEpoch(ms);
    final client = await _guard(_auth.restore);
    if (client == null) return _set(SyncState.signedOut);
    _store = _storeFor(client);
    _key = await _keys.read();
    if (_key == null) return _askPassphrase();
    _set(SyncState.ready);
    await syncNow();
  }

  Future<void> signIn() async {
    final client = await _guard(_auth.signIn);
    if (client == null) return _set(SyncState.signedOut);
    _store = _storeFor(client);
    _key = await _keys.read();
    if (_key != null) {
      _set(SyncState.ready);
      await syncNow();
    } else {
      await _askPassphrase();
    }
  }

  Future<void> _askPassphrase() async {
    final meta = await _guard(() => SyncSetup(_store!, iterations: iterations).readMeta());
    metaExists = meta != null;
    _set(SyncState.needsPassphrase);
  }

  /// Creates the folder's meta.json (first device) or checks the passphrase
  /// against it. False means it didn't match; the state is unchanged.
  Future<bool> setPassphrase(String passphrase) async {
    try {
      final setup = SyncSetup(_store!, iterations: iterations);
      final meta = await setup.readMeta();
      final key = meta == null ? await setup.create(passphrase) : await setup.join(passphrase, meta);
      if (key == null) return false;
      await _keys.write(key);
      _key = key;
      // Everything local must reach the folder once, whatever sync_dirty says.
      await _db.setMeta('sync_dirty', '1');
      _set(SyncState.ready);
      await syncNow();
      return true;
    } catch (e) {
      lastError = '$e';
      notifyListeners();
      return false;
    }
  }

  Future<void> syncNow() async {
    if (state != SyncState.ready || syncing) return;
    syncing = true;
    notifyListeners();
    try {
      final result = await SyncService(_db, _store!, _key!).sync();
      if (result.applied > 0) pulled++;
      lastOk = DateTime.now();
      lastError = null;
      await _db.setMeta('drive_last_ok_ms', lastOk!.millisecondsSinceEpoch.toString());
    } on SecretBoxAuthenticationError {
      // Spec §4.6: sync was reset on another device; our key no longer fits.
      await _keys.clear();
      _key = null;
      lastError = 'Sync was reset on another device. Enter the new passphrase.';
      await _askPassphrase();
    } catch (e) {
      lastError = '$e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Sync soon, once, however many times this is called in quick succession.
  void poke() {
    if (state != SyncState.ready) return;
    _debounce?.cancel();
    _debounce = Timer(debounce, syncNow);
  }

  /// Forgotten passphrase: wipe the folder; local data stays and is
  /// re-uploaded after a new passphrase.
  Future<void> reset() async {
    await _try(() => SyncSetup(_store!, iterations: iterations).reset());
    await _keys.clear();
    _key = null;
    await _askPassphrase();
  }

  Future<void> signOut() async {
    _debounce?.cancel();
    await _try(_auth.signOut);
    await _keys.clear();
    _key = null;
    _store = null;
    _set(SyncState.signedOut);
  }

  /// Runs [action]; on failure records the error and yields null.
  Future<T?> _guard<T extends Object>(Future<T?> Function() action) async {
    try {
      return await action();
    } catch (e) {
      lastError = '$e';
      notifyListeners();
      return null;
    }
  }

  /// [_guard] for actions with no result.
  Future<void> _try(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      lastError = '$e';
      notifyListeners();
    }
  }

  void _set(SyncState s) {
    state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
