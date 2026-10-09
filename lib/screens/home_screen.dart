import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/repository.dart';
import '../models/summary.dart';
import '../models/txn.dart';
import '../util/update_check.dart';
import '../widgets/category_bars.dart';
import '../widgets/merchant_bars.dart';
import '../widgets/summary_card.dart';
import '../widgets/txn_day_list.dart';
import 'add_txn_sheet.dart';
import 'hidden_screen.dart';
import 'import_flow.dart';
import 'iphone_setup_screen.dart';
import 'merchant_screen.dart';
import 'merchants_screen.dart';
import 'txn_sheet.dart';
import 'unparsed_screen.dart';

/// Android: SMS permission state. iPhone: SMS come in via Shortcuts instead.
enum _Access { checking, granted, denied, permanentlyDenied, iphone }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, this.updateChecker});

  final TxnRepository repository;
  final UpdateChecker? updateChecker;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  _Access _access = _Access.checking;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Txn> _txns = const [];
  bool _syncing = false;
  bool _upiOnly = false;
  int _shortcutCount = 0;
  int _unparsedCount = 0;
  UpdateInfo? _update;

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
    _checkUpdate();
  }

  /// Android only: the APK is installed by hand, so tell people about new
  /// releases. Web is always current; iPhone updates through TestFlight.
  Future<void> _checkUpdate() async {
    final checker = widget.updateChecker;
    if (checker == null || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final info = await checker.check();
    if (mounted) setState(() => _update = info);
  }

  Future<void> _dismissUpdate() async {
    await widget.updateChecker!.dismiss(_update!.tag);
    if (mounted) setState(() => _update = null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Picks up new SMS (and a permission granted in Settings) when the user
  /// comes back to the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAccess();
  }

  Future<void> _checkAccess() async {
    if (Platform.isIOS) {
      if (mounted) setState(() => _access = _Access.iphone);
      await _sync();
      return;
    }
    final status = await Permission.sms.status;
    if (!mounted) return;
    setState(() => _access = _accessFrom(status));
    await _sync();
  }

  _Access _accessFrom(PermissionStatus s) {
    if (s.isGranted) return _Access.granted;
    if (s.isPermanentlyDenied) return _Access.permanentlyDenied;
    return _Access.denied;
  }

  Future<void> _requestAccess() async {
    if (_access == _Access.permanentlyDenied) {
      await openAppSettings();
      return;
    }
    final status = await Permission.sms.request();
    // Android 13+: notifications need their own permission. Older versions
    // return granted at once.
    if (status.isGranted) await Permission.notification.request();
    if (!mounted) return;
    setState(() => _access = _accessFrom(status));
    await _sync();
  }

  Future<void> _sync() async {
    final canSync = _access == _Access.granted || _access == _Access.iphone;
    if (canSync && !_syncing) {
      setState(() => _syncing = true);
      try {
        final added = _access == _Access.iphone
            ? await widget.repository.syncShortcutInbox()
            : await widget.repository.syncSms();
        if (mounted && added > 0) {
          _snack(added == 1 ? '1 new transaction' : '$added new transactions');
        }
      } on PlatformException catch (e) {
        _snack('Could not read SMS: ${e.message ?? e.code}');
      } on FileSystemException catch (e) {
        _snack('Could not read shortcut messages: ${e.message}');
      } finally {
        if (mounted) setState(() => _syncing = false);
      }
      if (_access == _Access.iphone) {
        final count = await widget.repository.shortcutMessageCount();
        if (mounted) setState(() => _shortcutCount = count);
      }
    }
    await _load();
  }

  Future<void> _load() async {
    final txns = await widget.repository
        .between(_month, DateTime(_month.year, _month.month + 1));
    final unparsed = await widget.repository.unparsed();
    if (mounted) {
      setState(() {
        _txns = txns;
        _unparsedCount = unparsed.length;
      });
    }
  }

  void _snack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  Future<void> _openTxn(Txn t) async {
    final changed = await showTxnSheet(context, t, widget.repository);
    if (changed == true) await _load();
  }

  Future<void> _hideTxn(Txn t) async {
    await widget.repository.hide(t);
    await _load();
    _snack(
      'Hidden',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await widget.repository.unhide(t);
          await _load();
        },
      ),
    );
  }

  Future<void> _importStatement() async {
    final added = await importStatement(context, widget.repository);
    if (added) await _load();
  }

  Future<void> _openIphoneSetup() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => IphoneSetupScreen(messagesReceived: _shortcutCount),
    ));
  }

  Future<void> _openUnparsed() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => UnparsedScreen(repository: widget.repository),
    ));
    await _load();
  }

  Future<void> _openHidden() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HiddenScreen(repository: widget.repository),
    ));
    await _load();
  }

  Future<void> _openMerchant(String merchant) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MerchantScreen(
        repository: widget.repository,
        merchant: merchant,
        month: _month,
      ),
    ));
    await _load();
  }

  Future<void> _openMerchants(MonthSummary summary) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MerchantsScreen(
        repository: widget.repository,
        month: _month,
        totals: summary.byMerchant,
      ),
    ));
    await _load();
  }

  Future<void> _addManual() async {
    final added = await showAddTxnSheet(context, widget.repository);
    if (added == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _upiOnly ? _txns.where((t) => t.channel == 'UPI').toList() : _txns;
    final summary = MonthSummary.from(visible);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('UPI Track'),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              tooltip: 'Check for new SMS',
              icon: const Icon(Icons.refresh),
              onPressed: _sync,
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'import') _importStatement();
              if (v == 'iphone') _openIphoneSetup();
              if (v == 'hidden') _openHidden();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.upload_file),
                  title: Text('Import statement'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'hidden',
                child: ListTile(
                  leading: Icon(Icons.visibility_off_outlined),
                  title: Text('Hidden'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_access == _Access.iphone)
                const PopupMenuItem(
                  value: 'iphone',
                  child: ListTile(
                    leading: Icon(Icons.phone_iphone),
                    title: Text('iPhone auto-tracking'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addManual,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (_update != null)
              _UpdateCard(
                info: _update!,
                onDownload: () => launchUrl(Uri.parse(_update!.url),
                    mode: LaunchMode.externalApplication),
                onDismiss: _dismissUpdate,
              ),
            if (_access == _Access.denied ||
                _access == _Access.permanentlyDenied)
              _PermissionCard(
                permanentlyDenied: _access == _Access.permanentlyDenied,
                onPressed: _requestAccess,
              ),
            if (_access == _Access.iphone && _shortcutCount == 0)
              _IphoneCard(onSetup: _openIphoneSetup, onImport: _importStatement),
            if (_unparsedCount > 0)
              _UnparsedCard(count: _unparsedCount, onTap: _openUnparsed),
            _MonthSwitcher(
              month: _month,
              canGoForward: !_isCurrentMonth,
              onChanged: _changeMonth,
            ),
            const SizedBox(height: 8),
            SummaryCard(summary: summary, showToday: _isCurrentMonth),
            if (summary.byCategory.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Where it went', style: text.titleMedium),
              const SizedBox(height: 8),
              CategoryBars(totals: summary.byCategory),
            ],
            if (summary.byMerchant.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Text('Top merchants', style: text.titleMedium)),
                  if (summary.byMerchant.length > 5)
                    TextButton(
                      onPressed: () => _openMerchants(summary),
                      child: const Text('See all'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              MerchantBars(
                totals: summary.byMerchant,
                limit: 5,
                onTap: _openMerchant,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: Text('Transactions', style: text.titleMedium)),
                FilterChip(
                  label: const Text('UPI only'),
                  selected: _upiOnly,
                  onSelected: (v) => setState(() => _upiOnly = v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (visible.isEmpty)
              _EmptyState(
                  waitingForAccess: _access != _Access.granted &&
                      !(_access == _Access.iphone && _shortcutCount > 0))
            else
              ...txnsGroupedByDay(context, visible,
                  onTap: _openTxn, onHide: _hideTxn),
          ],
        ),
      ),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.canGoForward,
    required this.onChanged,
  });

  final DateTime month;
  final bool canGoForward;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(-1),
        ),
        Expanded(
          child: Text(
            DateFormat('MMMM y').format(month),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right),
          onPressed: canGoForward ? () => onChanged(1) : null,
        ),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.permanentlyDenied,
    required this.onPressed,
  });

  final bool permanentlyDenied;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sms_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Track UPI payments automatically',
                      style: text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Every UPI payment makes your bank send an SMS. Allow SMS access '
              'and the app will read those bank messages to list your '
              'payments. Everything stays on this phone and is never uploaded.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onPressed,
              child: Text(permanentlyDenied
                  ? 'Open settings to allow SMS'
                  : 'Allow SMS access'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IphoneCard extends StatelessWidget {
  const _IphoneCard({required this.onSetup, required this.onImport});

  final VoidCallback onSetup;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.phone_iphone),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Track UPI payments automatically',
                      style: text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'iPhones don\'t let apps read SMS. Set up a one-time Shortcuts '
              'automation (about a minute) and every bank SMS will be passed '
              'to this app. Import a statement to fill in older months.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(onPressed: onSetup, child: const Text('Set up')),
                OutlinedButton(
                    onPressed: onImport, child: const Text('Import statement')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.waitingForAccess});

  final bool waitingForAccess;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            waitingForAccess
                ? (Platform.isIOS
                    ? 'Set up auto-tracking or import a statement, or tap Add.'
                    : 'Allow SMS access, import a statement, or tap Add.')
                : 'No transactions this month.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _UnparsedCard extends StatelessWidget {
  const _UnparsedCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.help_outline),
        title: Text(count == 1
            ? '1 bank SMS could not be read'
            : '$count bank SMS could not be read'),
        subtitle: const Text('Add them by hand or report them'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.info,
    required this.onDownload,
    required this.onDismiss,
  });

  final UpdateInfo info;
  final VoidCallback onDownload;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${info.tag.replaceFirst('v', '')} is available',
                style: text.titleMedium),
            const SizedBox(height: 4),
            Text('Download the new APK and open it to update.',
                style: text.bodyMedium),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDismiss, child: const Text('Later')),
                FilledButton(onPressed: onDownload, child: const Text('Download')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
