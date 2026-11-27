import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../theme.dart';

/// Setting key (TxnRepository.flag) for App lock.
const String kAppLockFlag = 'app_lock';

/// Phones have a device lock to ask for; a browser doesn't.
bool get appLockAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Asks for the fingerprint, face or the phone's own PIN, pattern or
/// passcode. False when cancelled or when the phone has no screen lock.
Future<bool> unlockWithDevice() async {
  try {
    return await LocalAuthentication().authenticate(
      localizedReason: 'Unlock UPI Track',
      persistAcrossBackgrounding: true,
    );
  } catch (_) {
    return false;
  }
}

/// Whether the phone has a screen lock that [unlockWithDevice] can use.
Future<bool> deviceCanLock() async {
  try {
    return await LocalAuthentication().isDeviceSupported();
  } catch (_) {
    return false;
  }
}

/// Covers the whole app (it sits above the Navigator, via MaterialApp's
/// builder) until the user unlocks: at launch, and on return after more than
/// [grace] away. The app underneath keeps its state.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.enabled,
    required this.child,
    this.unlock = unlockWithDevice,
    this.grace = const Duration(seconds: 30),
  });

  /// Reads the setting; asked again on each return to the app.
  final Future<bool> Function() enabled;
  final Future<bool> Function() unlock;
  final Duration grace;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  /// Until the setting is read, show nothing rather than flash the data.
  bool _checking = true;
  bool _locked = false;

  /// The system prompt (and Android's PIN screen) pauses the app; those
  /// lifecycle changes are not the user leaving.
  bool _asking = false;
  DateTime? _left;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final on = await widget.enabled();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _locked = on;
    });
    if (on) await _unlock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_asking || _locked) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _left ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _left;
      _left = null;
      if (left != null && DateTime.now().difference(left) > widget.grace) {
        _relock();
      }
    }
  }

  Future<void> _relock() async {
    if (!await widget.enabled() || !mounted) return;
    setState(() => _locked = true);
    await _unlock();
  }

  Future<void> _unlock() async {
    if (_asking) return;
    _asking = true;
    final ok = await widget.unlock();
    _asking = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    final hide = _checking || _locked;
    return Stack(
      children: [
        ExcludeSemantics(
          excluding: hide,
          child: TickerMode(enabled: !hide, child: widget.child),
        ),
        if (hide)
          Positioned.fill(
            child: _LockScreen(onUnlock: _checking ? null : _unlock),
          ),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});

  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Center(
          child: onUnlock == null
              ? const SizedBox.shrink()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: context.brand.hero,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.lock_outline,
                          size: 34, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    Text('UPI Track is locked', style: text.titleLarge),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onUnlock,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Unlock'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
