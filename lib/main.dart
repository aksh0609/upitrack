import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'background/sms_background.dart';
import 'data/db.dart';
import 'data/repository.dart';
import 'data/shortcut_inbox.dart';
import 'data/sms_source.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';
import 'sync/drive_sync_store.dart';
import 'sync/google_auth.dart';
import 'sync/oauth_ids.dart';
import 'sync/sync_controller.dart';
import 'sync/sync_keys.dart';
import 'theme.dart';
import 'util/update_check.dart';
import 'widgets/app_lock.dart';

/// Commit time of this build, stamped by CI with
/// `--dart-define=BUILD_TIME=$(git log -1 --format=%ct)`; null when built by hand.
final DateTime? kBuildTime = const int.fromEnvironment('BUILD_TIME') == 0
    ? null
    : DateTime.fromMillisecondsSinceEpoch(
        const int.fromEnvironment('BUILD_TIME') * 1000,
        isUtc: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Plus Jakarta Sans'],
        await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  // Browser: SQLite compiled to WebAssembly, persisted in IndexedDB (spec §4.8).
  if (kIsWeb) databaseFactory = databaseFactoryFfiWeb;
  final db = await AppDb.open();
  themeMode.value = themeModeNamed(await db.getMeta(kThemeSetting));
  palette.value = paletteNamed(await db.getMeta(kPaletteSetting));
  final auth = GoogleAuth();
  final sync = SyncController(
    db,
    auth: auth,
    keys: SecureSyncKeys(),
    storeFor: DriveSyncStore.new,
  );
  // Web: Google's button signs in outside our code; re-check when it does.
  auth.onAccountChanged = () => unawaited(sync.start());
  runApp(UpiTrackApp(
    repository: TxnRepository(db, SmsSource(), ShortcutInbox()),
    updateChecker: UpdateChecker(db, buildTime: kBuildTime),
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
  const UpiTrackApp(
      {super.key,
      required this.repository,
      this.updateChecker,
      this.syncController});

  final TxnRepository repository;
  final UpdateChecker? updateChecker;
  final SyncController? syncController;

  @override
  Widget build(BuildContext context) {
    final home = HomeScreen(
      repository: repository,
      updateChecker: updateChecker,
      syncController: syncController,
    );
    final sync = syncController;
    return ListenableBuilder(
      listenable: Listenable.merge([themeMode, palette]),
      builder: (context, _) => MaterialApp(
        title: 'UPI Track',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, palette.value),
        darkTheme: buildTheme(Brightness.dark, palette.value),
        themeMode: themeMode.value,
        // Above the Navigator, so the lock covers every screen.
        builder: (context, child) => appLockAvailable
            ? AppLockGate(
                enabled: () => repository.flag(kAppLockFlag), child: child!)
            : child!,
        // Inside the Navigator (unlike the lock), so the welcome screen's
        // text fields and dialogs work.
        home: sync != null && kSignInConfigured
            ? SignInGate(sync: sync, child: home)
            : home,
      ),
    );
  }
}
