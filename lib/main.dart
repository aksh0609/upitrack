import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'data/db.dart';
import 'data/repository.dart';
import 'data/shortcut_inbox.dart';
import 'data/sms_source.dart';
import 'screens/home_screen.dart';
import 'util/update_check.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDb.open();
  final info = await PackageInfo.fromPlatform();
  runApp(UpiTrackApp(
    repository: TxnRepository(db, SmsSource(), ShortcutInbox()),
    updateChecker: UpdateChecker(db, currentVersion: info.version),
  ));
}

class UpiTrackApp extends StatelessWidget {
  const UpiTrackApp({super.key, required this.repository, this.updateChecker});

  final TxnRepository repository;
  final UpdateChecker? updateChecker;

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
      home: HomeScreen(repository: repository, updateChecker: updateChecker),
    );
  }
}
