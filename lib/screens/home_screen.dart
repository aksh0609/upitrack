import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/repository.dart';
import '../models/account.dart';
import '../models/summary.dart';
import '../models/txn.dart';
import '../sync/sync_controller.dart';
import '../util/search.dart';
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
import 'settings_screen.dart';
import 'txn_sheet.dart';
import 'unparsed_screen.dart';

/// Android: SMS permission state. iPhone: SMS come in via Shortcuts instead.
/// Web: no SMS at all; data comes from sync and statement import.
enum _Access { checking, granted, denied, permanentlyDenied, iphone, web }

/// iPhone, not the web app. `Platform.isIOS` is unavailable on the web.
bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, this.updateChecker, this.syncController});

  final TxnRepository repository;
  final UpdateChecker? updateChecker;
  final SyncController? syncController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  _Access _access = _Access.checking;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Txn> _txns = const [];
  bool _syncing = false;
  bool _upiOnly = false;
  bool _searching = false;
  final TextEditingController _search = TextEditingController();
  int _shortcutCount = 0;
  int _unparsedCount = 0;
  List<AccountRef> _accounts = const [];
  AccountRef? _account;
  UpdateInfo? _update;

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.syncController?.addListener(_onSyncChanged);
    _search.addListener(() => setState(() {}));
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
    _search.dispose();
    widget.syncController?.removeListener(_onSyncChanged);
    super.dispose();
  }

  int _seenPulls = 0;

  void _onSyncChanged() {
    final c = widget.syncController;
    if (c != null && c.pulled != _seenPulls) {
      _seenPulls = c.pulled;
      _load();
    }
  }

  /// Picks up new SMS (and a permission granted in Settings) when the user
  /// comes back to the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAccess();
    if (state == AppLifecycleState.resumed) widget.syncController?.syncNow();
  }

  Future<void> _checkAccess() async {
    if (kIsWeb) {
      if (mounted) setState(() => _access = _Access.web);
      await _sync();
      return;
    }
    if (_isIOS) {
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
      } catch (e) {
        _snack('Could not read shortcut messages: $e');
      } finally {
        if (mounted) setState(() => _syncing = false);
      }
      if (_access == _Access.iphone) {
        final count = await widget.repository.shortcutMessageCount();
        if (mounted) setState(() => _shortcutCount = count);
      }
    }
    await _load();
    await widget.syncController?.syncNow();
  }

  Future<void> _load() async {
    final txns = await widget.repository
        .between(_month, DateTime(_month.year, _month.month + 1));
    final unparsed = await widget.repository.unparsed();
    final accounts = await widget.repository.accounts();
    if (mounted) {
      setState(() {
        _txns = txns;
        _unparsedCount = unparsed.length;
        _accounts = accounts;
        // Chips are hidden below two accounts, so a lingering pick would hide rows.
        if (accounts.length < 2 || !accounts.contains(_account)) _account = null;
      });
    }
    widget.syncController?.poke();
  }

  void _snack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _search.clear();
    });
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

  Future<void> _openSettings() async {
    final sync = widget.syncController;
    if (sync == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(sync: sync),
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
    final visible = _txns
        .where((t) => !_upiOnly || t.channel == 'UPI')
        .where((t) =>
            _account == null ||
            (t.bank == _account!.bank && t.account == _account!.last4))
        .where((t) => matchesSearch(t, _search.text))
        .toList();
    final summary = MonthSummary.from(visible);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search payee or merchant',
                  border: InputBorder.none,
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _search.clear,
                        ),
                ),
              )
            : const Text('UPI Track'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.search_off : Icons.search),
            onPressed: _toggleSearch,
          ),
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
              tooltip: kIsWeb ? 'Sync now' : 'Check for new SMS',
              icon: const Icon(Icons.refresh),
              onPressed: _sync,
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'import') _importStatement();
              if (v == 'iphone') _openIphoneSetup();
              if (v == 'hidden') _openHidden();
              if (v == 'settings') _openSettings();
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
              if (widget.syncController != null)
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.cloud_sync_outlined),
                    title: Text('Sync'),
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
            if (_access == _Access.web &&
                widget.syncController != null &&
                widget.syncController!.state != SyncState.ready)
              _WebSyncCard(onSetup: _openSettings),
            if (_unparsedCount > 0)
              _UnparsedCard(count: _unparsedCount, onTap: _openUnparsed),
            _MonthSwitcher(
              month: _month,
              canGoForward: !_isCurrentMonth,
              onChanged: _changeMonth,
            ),
            if (_accounts.length >= 2)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _account == null,
                      onSelected: (_) => setState(() => _account = null),
                    ),
                    for (final a in _accounts) ...[
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(accountLabel(a)),
                        selected: _account == a,
                        onSelected: (_) => setState(() => _account = a),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
            SummaryCard(summary: summary, showToday: _isCurrentMonth),
            if (widget.syncController != null)
              ListenableBuilder(
                listenable: widget.syncController!,
                builder: (context, _) {
                  final s = widget.syncController!;
                  final attention = s.state == SyncState.needsPassphrase && s.lastError != null;
                  if (s.state != SyncState.ready && !attention) return const SizedBox.shrink();
                  final text = attention
                      ? 'Sync needs attention'
                      : s.syncing
                      ? 'Syncing…'
                      : s.lastOk == null
                          ? 'Not synced yet'
                          : 'Last synced ${DateFormat('d MMM, HH:mm').format(s.lastOk!)}';
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(s.lastError == null && !attention ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                            size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(text,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        if (s.lastError != null)
                          IconButton(
                            iconSize: 16,
                            tooltip: s.lastError,
                            icon: const Icon(Icons.info_outline),
                            onPressed: _openSettings,
                          ),
                      ],
                    ),
                  );
                },
              ),
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
            if (visible.isEmpty && _search.text.trim().isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text('No payments match.', textAlign: TextAlign.center),
              )
            else if (visible.isEmpty)
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

class _WebSyncCard extends StatelessWidget {
  const _WebSyncCard({required this.onSetup});

  final VoidCallback onSetup;

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
                const Icon(Icons.cloud_sync_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Sync with Google Drive', style: text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'A browser can\'t read SMS. Sign in with the Google account you '
              'use on your phone and enter your sync passphrase to see the '
              'same payments here. Statements can be imported from the menu.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onSetup,
              icon: const Icon(Icons.login),
              label: const Text('Set up sync'),
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
                ? (kIsWeb
                    ? 'Sync with Google Drive to see your payments here, import a statement, or tap Add.'
                    : _isIOS
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
