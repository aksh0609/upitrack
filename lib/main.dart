import 'package:flutter/material.dart';

import 'data/db.dart';
import 'data/repository.dart';
import 'data/shortcut_inbox.dart';
import 'data/sms_source.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDb.open();
  runApp(UpiTrackApp(
    repository: TxnRepository(db, SmsSource(), ShortcutInbox()),
  ));
}

class UpiTrackApp extends StatelessWidget {
  const UpiTrackApp({super.key, required this.repository});

  final TxnRepository repository;

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
      home: HomeScreen(repository: repository),
    );
  }
}
