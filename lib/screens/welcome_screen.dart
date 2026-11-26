import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../sync/sync_controller.dart';
import '../theme.dart';
import 'settings_screen.dart';

/// Required sign-in: shows [WelcomeScreen] in place of [child] until this
/// device has signed up (chosen a passphrase) or signed in (entered it).
/// After that the app opens offline too; only Sign out, or a reset on
/// another device, brings the welcome screen back.
class SignInGate extends StatelessWidget {
  const SignInGate({super.key, required this.sync, required this.child});

  final SyncController sync;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sync,
        builder: (context, _) => !sync.loaded
            ? const Scaffold()
            : sync.signedIn
                ? child
                : WelcomeScreen(sync: sync),
      );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.sync});

  final SyncController sync;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final (title, line) = switch (sync.state) {
      SyncState.needsPassphrase when !sync.metaExists => (
          'Create your account',
          'Signed in as ${sync.email ?? 'your Google account'}. One more step.'
        ),
      SyncState.needsPassphrase => (
          'Welcome back',
          'Enter your passphrase and your payments come back to this phone.'
        ),
      _ => (
          'Welcome to UPI Track',
          'Every UPI payment from your bank SMS, sorted. Sign in with Google '
              'to create your account, or to get back into it.'
        ),
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: kBrandGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.currency_rupee,
                        size: 32, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  Text(title,
                      style: text.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(line, style: text.bodyLarge?.copyWith(color: muted)),
                  const SizedBox(height: 24),
                  AccountPanel(sync: sync),
                  if (!kIsWeb) ...[
                    const SizedBox(height: 16),
                    // A sign-in bug must not also block its fix: the update
                    // card lives behind this screen.
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => launchUrl(
                          Uri.parse(
                              'https://github.com/aksh0609/upitrack/releases'),
                          mode: LaunchMode.externalApplication),
                      child: const Text('Trouble signing in? Get the newest '
                          'version'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
