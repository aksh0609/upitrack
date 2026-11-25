import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../background/reminders.dart';
import '../data/repository.dart';
import '../sync/google_button.dart';
import '../sync/oauth_ids.dart';
import '../sync/sync_controller.dart';
import '../util/native_bridge.dart';
import '../widgets/app_lock.dart';

/// Settings: App lock (phones) and Sync with Google Drive (spec §4.7).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.repository, this.sync});

  final TxnRepository repository;
  final SyncController? sync;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _lock;
  bool? _reminders;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lock = await widget.repository.flag(kAppLockFlag);
    final off = await widget.repository.flag(kRemindersOff);
    if (mounted) {
      setState(() {
        _lock = lock;
        _reminders = !off;
      });
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// Turning it on asks once, so nobody locks themselves out.
  Future<void> _setLock(bool on) async {
    if (on) {
      if (!await deviceCanLock()) {
        _snack('Set a screen lock (PIN, pattern, fingerprint or face) in '
            "your phone's settings first.");
        return;
      }
      if (!await unlockWithDevice()) return;
    }
    await widget.repository.setFlag(kAppLockFlag, on);
    if (mounted) setState(() => _lock = on);
  }

  @override
  Widget build(BuildContext context) {
    final sync = widget.sync;
    final title = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (appLockAvailable && _lock != null) ...[
            Text('Privacy', style: title),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _lock!,
              onChanged: _setLock,
              title: const Text('App lock'),
              subtitle: const Text('Ask for your fingerprint, face or phone '
                  'PIN when the app opens'),
            ),
            const SizedBox(height: 24),
          ],
          if (NativeBridge.available && _reminders != null) ...[
            Text('Notifications', style: title),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _reminders!,
              onChanged: (on) async {
                await widget.repository.setFlag(kRemindersOff, !on);
                if (mounted) setState(() => _reminders = on);
              },
              title: const Text('Weekly summary and bill reminders'),
              subtitle: const Text('Last week\'s spending each Monday, and a '
                  'note a day or two before a monthly payment is due'),
            ),
            const SizedBox(height: 24),
          ],
          if (sync != null) _SyncSection(sync: sync),
        ],
      ),
    );
  }
}

class _SyncSection extends StatelessWidget {
  const _SyncSection({required this.sync});

  final SyncController sync;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sync with Google Drive',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          switch (sync.state) {
            SyncState.signedOut => _SignedOut(sync: sync),
            SyncState.needsPassphrase => _Passphrase(sync: sync),
            SyncState.ready => _Ready(sync: sync),
          },
          if (sync.lastError != null) ...[
            const SizedBox(height: 12),
            Text(sync.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.sync});
  final SyncController sync;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Keep a second phone or the web app in step. Your data is '
              'encrypted on this device with a passphrase before it is stored '
              'in a hidden folder of your Google Drive; Google cannot read it.'),
          const SizedBox(height: 12),
          if (kIsWeb && !sync.hasAccount && kGoogleServerClientId != null)
            // The web plugin signs in only through Google's own button; the
            // Drive consent follows with the tap below once the account is known.
            googleSignInButton()
          else
            FilledButton.icon(
              onPressed: sync.signIn,
              icon: const Icon(Icons.login),
              label: Text(kIsWeb && sync.hasAccount
                  ? 'Allow Drive access'
                  : 'Sign in with Google'),
            ),
        ],
      );
}

class _Passphrase extends StatefulWidget {
  const _Passphrase({required this.sync});
  final SyncController sync;

  @override
  State<_Passphrase> createState() => _PassphraseState();
}

class _PassphraseState extends State<_Passphrase> {
  final _one = TextEditingController();
  final _two = TextEditingController();
  String? _problem;
  bool _busy = false;

  bool get _create => !widget.sync.metaExists;

  @override
  void dispose() {
    _one.dispose();
    _two.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p = _one.text;
    if (p.length < 8) {
      return setState(() => _problem = 'Use at least 8 characters.');
    }
    if (_create && p != _two.text) {
      return setState(() => _problem = 'The two entries differ.');
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final ok = await widget.sync.setPassphrase(p);
      if (!mounted) return;
      setState(() {
        if (!ok) {
          _problem = widget.sync.lastError ??
              "That passphrase doesn't match the one used on your other device.";
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_create
              ? 'Choose a passphrase. It protects your data in Drive and is never '
                  'sent to Google. Write it down: without it, sync has to be reset.'
              : 'Enter the passphrase you chose on your other device.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('passphrase'),
            controller: _one,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Passphrase', border: OutlineInputBorder()),
          ),
          if (_create) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('passphrase2'),
              controller: _two,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Repeat passphrase', border: OutlineInputBorder()),
            ),
          ],
          if (_problem != null) ...[
            const SizedBox(height: 8),
            Text(_problem!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_create ? 'Turn on sync' : 'Continue'),
              ),
              const SizedBox(width: 12),
              if (!_create)
                TextButton(
                  onPressed:
                      _busy ? null : () => _confirmReset(context, widget.sync),
                  child: const Text('Forgot it? Reset sync'),
                ),
              const SizedBox(width: 12),
              TextButton(
                  onPressed: _busy ? null : widget.sync.signOut,
                  child: const Text('Sign out')),
            ],
          ),
        ],
      );
}

/// Shared by the passphrase and ready states.
Future<void> _confirmReset(BuildContext context, SyncController sync) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Reset sync?'),
      content: const Text(
          'Deletes the sync files in your Drive. Nothing on this '
          'phone is lost; you choose a new passphrase and everything is uploaded '
          'again. Other devices will ask for the new passphrase.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset')),
      ],
    ),
  );
  if (yes == true) await sync.reset();
}

class _Ready extends StatelessWidget {
  const _Ready({required this.sync});
  final SyncController sync;

  @override
  Widget build(BuildContext context) {
    final last = sync.lastOk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(sync.syncing
            ? 'Syncing…'
            : last == null
                ? 'Not synced yet'
                : 'Last synced ${DateFormat('d MMM, HH:mm').format(last)}'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              onPressed: sync.syncing ? null : sync.syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
            OutlinedButton(
                onPressed: sync.signOut, child: const Text('Sign out')),
            TextButton(
              onPressed: () => _confirmReset(context, sync),
              child: const Text('Reset sync'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Sign out keeps your data on this phone and forgets the key. Reset '
          'deletes the Drive files so you can choose a new passphrase.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
