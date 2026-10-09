import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'background/sms_background.dart';
import 'data/db.dart';
import 'data/repository.dart';
import 'data/shortcut_inbox.dart';
import 'data/sms_source.dart';
import 'screens/home_screen.dart';
import 'sync/drive_sync_store.dart';
import 'sync/google_auth.dart';
import 'sync/sync_controller.dart';
import 'sync/sync_keys.dart';
import 'util/update_check.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDb.open();
  final info = await PackageInfo.fromPlatform();
  final sync = SyncController(
    db,
    auth: GoogleAuth(),
    keys: SecureSyncKeys(),
    storeFor: DriveSyncStore.new,
  );
  runApp(UpiTrackApp(
    repository: TxnRepository(db, SmsSource(), ShortcutInbox()),
    updateChecker: UpdateChecker(db, currentVersion: info.version),
    syncController: sync,
  ));
  unawaited(sync.start());
}

/// Started by android/.../SmsReceiver.kt when a bank SMS arrives. It must be
/// a top-level function in a library the app imports, or the compiler
/// tree-shakes it away.
@pragma('vm:entry-point')
Future<void> smsBackground() => runSmsBackground();

class UpiTrackApp extends StatelessWidget {
  const UpiTrackApp({super.key, required this.repository, this.updateChecker, this.syncController});

  final TxnRepository repository;
  final UpdateChecker? updateChecker;
  final SyncController? syncController;

  static const Color _seed = Color(0xFF0F766E);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UPI Track',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomeScreen(
        repository: repository,
        updateChecker: updateChecker,
        syncController: syncController,
      ),
    );
  }
}
