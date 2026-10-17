import 'dart:async';

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
import '../util/apk_installer.dart';
import '../util/search.dart';
import '../util/update_check.dart';
import '../util/who.dart';
import '../theme.dart';
import '../widgets/appear.dart';
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

/// The web app opened on an iPhone: no Shortcuts action of its own, but the
/// automation can still log bank SMS to a file that the user imports.
bool get _isIphoneWeb => kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

class HomeScreen extends StatefulWidget {
  const HomeScreen(
      {super.key,
      required this.repository,
      this.updateChecker,
      this.syncController});

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
  Who _who = Who.all;

  /// 0 = Overview, 1 = Payments.
  int _tab = 0;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  int _shortcutCount = 0;
  int _unparsedCount = 0;
  List<AccountRef> _accounts = const [];
  AccountRef? _account;
  UpdateInfo? _update;

  /// 0..1 while an update APK downloads; null otherwise.
  double? _updateProgress;

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
  Future<void> _checkUpdate({bool force = false}) async {
    final checker = widget.updateChecker;
    if (checker == null ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final info = await checker.check(force: force);
    if (mounted) setState(() => _update = info);
  }

  /// Download the APK and let Android's installer take over; without an APK
  /// asset, open the release page instead.
  Future<void> _installUpdate() async {
    final apk = _update?.apkUrl;
    if (apk == null) {
      await launchUrl(Uri.parse(_update!.url),
          mode: LaunchMode.externalApplication);
      return;
    }
    setState(() => _updateProgress = 0);
    try {
      await downloadAndInstall(Uri.parse(apk), onProgress: (p) {
        if (mounted) setState(() => _updateProgress = p);
      });
    } catch (e) {
      _snack('Update failed: $e');
    } finally {
      if (mounted) setState(() => _updateProgress = null);
    }
  }

  Future<void> _dismissUpdate() async {
    await widget.updateChecker!.dismiss(_update!.tag);
    if (mounted) setState(() => _update = null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _searchFocus.dispose();
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
        _snack('Could not read messages: $e');
      } finally {
        if (mounted) setState(() => _syncing = false);
      }
    }
    await _refreshShortcutCount();
    await _load();
    unawaited(_checkUpdate(force: true));
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
        if (accounts.length < 2 || !accounts.contains(_account)) {
          _account = null;
        }
      });
    }
    widget.syncController?.poke();
  }

  void _snack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        action: action,
        // Flutter 3.47 keeps a snack bar with an action on screen until it is
        // tapped; "Hidden / Undo" should still go away on its own.
        persist: false,
        duration: const Duration(seconds: 5),
      ));
  }

  /// Search lives on the Payments tab; the app-bar button takes you there.
  void _openSearch() {
    setState(() => _tab = 1);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _who = Who.all;
      _account = null;
      _upiOnly = false;
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
    // A swiped-away row must leave the list in this frame.
    setState(() => _txns = _txns.where((x) => x.key != t.key).toList());
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
    if (added) {
      await _refreshShortcutCount();
      await _load();
    }
  }

  /// How many bank SMS the Shortcuts route has delivered; drives the iPhone
  /// set-up card and the guide's status line.
  Future<void> _refreshShortcutCount() async {
    if (_access != _Access.iphone && !_isIphoneWeb) return;
    final count = await widget.repository.shortcutMessageCount();
    if (mounted) setState(() => _shortcutCount = count);
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

  /// Shown when the month has nothing to list, with the ways to fix that.
  String get _emptyMessage {
    final hasSource = _access == _Access.granted ||
        ((_access == _Access.iphone || _isIphoneWeb) && _shortcutCount > 0);
    if (hasSource) {
      return _isCurrentMonth
          ? 'No payments yet this month.'
          : 'No payments in ${DateFormat('MMMM y').format(_month)}.';
    }
    if (kIsWeb) {
      return 'Sync with Google Drive to see your payments here, '
          'or import a statement.';
    }
    if (_isIOS) return 'Set up auto-tracking or import a statement.';
    return 'Allow SMS access to track payments, or import a statement.';
  }

  @override
  Widget build(BuildContext context) {
    // Filters shape both tabs; search narrows only the Payments list.
    final visible = _txns
        .where((t) => !_upiOnly || t.channel == 'UPI')
        .where((t) => matchesWho(t, _who))
        .where((t) =>
            _account == null ||
            (t.bank == _account!.bank && t.account == _account!.last4))
        .toList();
    final summary = MonthSummary.from(visible);

    return Scaffold(
      appBar: AppBar(
        title: const _Brand(),
        actions: [
          IconButton(
            tooltip: 'Search payments',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
          if (_syncing)
            const Padding(
              padding: EdgeInsets.all(14),
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
            tooltip: 'More',
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
                  title: Text('Import file'),
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
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (_access == _Access.iphone || _isIphoneWeb)
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
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(
          gradient: kBrandGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: kGlow.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _addManual,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Payments',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: Center(
          // Phones fill the width; the web app on a laptop stays readable.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            // Tabs cross-fade with a slight rise instead of snapping.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position:
                      Tween(begin: const Offset(0, 0.02), end: Offset.zero)
                          .animate(animation),
                  child: child,
                ),
              ),
              child: ListView(
                key: PageStorageKey<int>(_tab),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  if (_tab == 0) ..._notices(),
                  _MonthSwitcher(
                    month: _month,
                    canGoForward: !_isCurrentMonth,
                    onChanged: _changeMonth,
                  ),
                  _Filters(
                    who: _who,
                    onWho: (w) => setState(() => _who = w),
                    accounts: _accounts,
                    account: _account,
                    onAccount: (a) => setState(() => _account = a),
                    upiOnly: _upiOnly,
                    onUpiOnly: (v) => setState(() => _upiOnly = v),
                  ),
                  const SizedBox(height: 12),
                  if (_tab == 0)
                    ..._overview(context, summary, visible)
                  else
                    ..._payments(context, visible),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Cards that need the user: update, permission, set-up, unread SMS.
  List<Widget> _notices() => [
        if (_update != null)
          _UpdateCard(
            info: _update!,
            progress: _updateProgress,
            onInstall: _installUpdate,
            onDismiss: _dismissUpdate,
          ),
        if (_access == _Access.denied || _access == _Access.permanentlyDenied)
          _PermissionCard(
            permanentlyDenied: _access == _Access.permanentlyDenied,
            onPressed: _requestAccess,
          ),
        if ((_access == _Access.iphone || _isIphoneWeb) && _shortcutCount == 0)
          _IphoneCard(onSetup: _openIphoneSetup, onImport: _importStatement),
        if (_access == _Access.web &&
            widget.syncController != null &&
            widget.syncController!.state != SyncState.ready)
          _WebSyncCard(onSetup: _openSettings),
        if (_unparsedCount > 0)
          _UnparsedCard(count: _unparsedCount, onTap: _openUnparsed),
      ];

  bool get _filtering => _who != Who.all || _account != null || _upiOnly;

  Widget _noMatch() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Text('No payments match.', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton(
                onPressed: _clearFilters, child: const Text('Clear filters')),
          ],
        ),
      );

  List<Widget> _overview(
      BuildContext context, MonthSummary summary, List<Txn> visible) {
    return [
      Appear(
        child: SummaryCard(
            summary: summary, month: _month, showToday: _isCurrentMonth),
      ),
      if (widget.syncController != null)
        _SyncLine(sync: widget.syncController!, onOpen: _openSettings),
      const SizedBox(height: 12),
      if (visible.isEmpty)
        _filtering
            ? _noMatch()
            : _EmptyState(
                message: _emptyMessage,
                onImport: _importStatement,
                onAdd: _addManual,
              )
      else ...[
        if (summary.byCategory.isNotEmpty)
          _Section(
            index: 1,
            title: 'Where it went',
            child: CategoryBars(totals: summary.byCategory),
          ),
        if (summary.byMerchant.isNotEmpty)
          _Section(
            index: 2,
            title: 'Top merchants',
            action: summary.byMerchant.length > 5 ? 'See all' : null,
            onAction: () => _openMerchants(summary),
            child: MerchantBars(
              totals: summary.byMerchant,
              limit: 5,
              onTap: _openMerchant,
            ),
          ),
        _Section(
          index: 3,
          title: 'Recent payments',
          action: visible.length > 5 ? 'See all' : null,
          onAction: () => setState(() => _tab = 1),
          child: Column(
            children: txnsGroupedByDay(context, visible.take(5).toList(),
                onTap: _openTxn, onHide: _hideTxn),
          ),
        ),
      ],
    ];
  }

  List<Widget> _payments(BuildContext context, List<Txn> visible) {
    final listed =
        visible.where((t) => matchesSearch(t, _search.text)).toList();
    final searching = _search.text.trim().isNotEmpty;
    return [
      TextField(
        controller: _search,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search payee or merchant',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: searching
              ? IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: _search.clear,
                )
              : null,
        ),
      ),
      if (listed.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text(
            listed.length == 1 ? '1 payment' : '${listed.length} payments',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      if (listed.isEmpty && (searching || _filtering))
        _noMatch()
      else if (listed.isEmpty)
        _EmptyState(
          message: _emptyMessage,
          onImport: _importStatement,
          onAdd: _addManual,
        )
      else
        Card(
          margin: const EdgeInsets.only(top: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              children: txnsGroupedByDay(context, listed,
                  onTap: _openTxn, onHide: _hideTxn),
            ),
          ),
        ),
      if (listed.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text('Swipe a payment left to hide it.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
    ];
  }
}

/// "Last synced …" under the summary; tap it when sync needs attention.
class _SyncLine extends StatelessWidget {
  const _SyncLine({required this.sync, required this.onOpen});

  final SyncController sync;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final attention =
            sync.state == SyncState.needsPassphrase && sync.lastError != null;
        if (sync.state != SyncState.ready && !attention) {
          return const SizedBox.shrink();
        }
        final label = attention
            ? 'Sync needs attention'
            : sync.syncing
                ? 'Syncing…'
                : sync.lastOk == null
                    ? 'Not synced yet'
                    : 'Last synced ${DateFormat('d MMM, HH:mm').format(sync.lastOk!)}';
        final scheme = Theme.of(context).colorScheme;
        final ok = sync.lastError == null && !attention;
        final color = ok ? scheme.onSurfaceVariant : scheme.error;
        return InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                Icon(ok ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: color)),
                ),
                if (!ok) Icon(Icons.chevron_right, size: 18, color: color),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A titled card on the Overview tab.
class _Section extends StatelessWidget {
  const _Section({
    required this.index,
    required this.title,
    required this.child,
    this.action,
    this.onAction,
  });

  /// Position on the tab, so the cards arrive one after another.
  final int index;
  final String title;
  final Widget child;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Appear(
      index: index,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (action != null)
                      TextButton(onPressed: onAction, child: Text(action!)),
                  ],
                ),
              ),
              Padding(padding: const EdgeInsets.only(right: 8), child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who, which account and UPI-only, in one scrollable row of chips.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.who,
    required this.onWho,
    required this.accounts,
    required this.account,
    required this.onAccount,
    required this.upiOnly,
    required this.onUpiOnly,
  });

  final Who who;
  final ValueChanged<Who> onWho;
  final List<AccountRef> accounts;
  final AccountRef? account;
  final ValueChanged<AccountRef?> onAccount;
  final bool upiOnly;
  final ValueChanged<bool> onUpiOnly;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Chips slide under the list's side padding instead of being cut off.
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final w in Who.values) ...[
            ChoiceChip(
              label: Text(w.label),
              selected: who == w,
              onSelected: (_) => onWho(w),
            ),
            const SizedBox(width: 8),
          ],
          if (accounts.length >= 2) ...[
            // -1 = all accounts; PopupMenuButton treats a null pick as cancel.
            PopupMenuButton<int>(
              tooltip: 'Choose account',
              onSelected: (i) => onAccount(i < 0 ? null : accounts[i]),
              itemBuilder: (_) => [
                const PopupMenuItem(value: -1, child: Text('All accounts')),
                for (var i = 0; i < accounts.length; i++)
                  PopupMenuItem(
                      value: i, child: Text(accountLabel(accounts[i]))),
              ],
              child: Chip(
                backgroundColor:
                    account == null ? null : scheme.secondaryContainer,
                avatar: const Icon(Icons.account_balance_outlined, size: 18),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(account == null
                        ? 'All accounts'
                        : accountLabel(account!)),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          FilterChip(
            label: const Text('UPI only'),
            selected: upiOnly,
            onSelected: onUpiOnly,
          ),
        ],
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

  /// False on the current month: there is nothing ahead to show.
  final bool canGoForward;

  /// Months to move by; a big jump returns to the current month.
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final back = (now.year - month.year) * 12 + now.month - month.month;
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(-1),
        ),
        Expanded(
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                      scale: Tween(begin: 0.9, end: 1.0).animate(animation),
                      child: child),
                ),
                child: Text(
                  DateFormat('MMMM y').format(month),
                  key: ValueKey(month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (canGoForward)
                TextButton(
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () => onChanged(back),
                  child: const Text('Back to this month'),
                ),
            ],
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
                  child:
                      Text('Sync with Google Drive', style: text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'A browser can\'t read SMS. Sign in with the Google account you '
              'use on your phone to see the same payments here; the first '
              'time, enter your sync passphrase. Statements can be imported '
              'from the menu.',
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
              kIsWeb
                  ? 'iPhones don\'t let apps read SMS. Set up a one-time '
                      'Shortcuts automation (about a minute) and every bank '
                      'SMS is saved to a file in your iCloud Drive that you '
                      'import here. Import a statement to fill in older months.'
                  : 'iPhones don\'t let apps read SMS. Set up a one-time '
                      'Shortcuts automation (about a minute) and every bank '
                      'SMS will be passed to this app. Import a statement to '
                      'fill in older months.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(onPressed: onSetup, child: const Text('Set up')),
                OutlinedButton(
                    onPressed: onImport, child: const Text('Import file')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.message,
    required this.onImport,
    required this.onAdd,
  });

  final String message;
  final VoidCallback onImport;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: kBrandGradient,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.receipt_long_outlined,
                size: 34, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import file'),
              ),
              FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add payment'),
              ),
            ],
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
    required this.progress,
    required this.onInstall,
    required this.onDismiss,
  });

  final UpdateInfo info;

  /// Download progress 0..1, or null when idle.
  final double? progress;
  final VoidCallback onInstall;
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
            Text('${info.title} is available', style: text.titleMedium),
            const SizedBox(height: 4),
            if (progress != null) ...[
              Text('Downloading\u2026 ${(progress! * 100).round()}%',
                  style: text.bodyMedium),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress == 0 ? null : progress),
              const SizedBox(height: 8),
            ] else ...[
              Text(
                  info.apkUrl == null
                      ? 'Download the new APK and open it to update.'
                      : 'Tap Update; Android asks you to confirm. Your data '
                          'and sign-in stay.',
                  style: text.bodyMedium),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: onDismiss, child: const Text('Later')),
                  FilledButton(
                      onPressed: onInstall,
                      child: Text(info.apkUrl == null ? 'Download' : 'Update')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The logo mark and name in the app bar.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: kBrandGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              const Icon(Icons.currency_rupee, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        const Text('UPI Track'),
      ],
    );
  }
}
