import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/repository.dart';
import '../models/summary.dart';
import '../models/txn.dart';
import '../util/format.dart';
import '../widgets/category_bars.dart';
import '../widgets/summary_card.dart';
import '../widgets/txn_tile.dart';
import 'add_txn_sheet.dart';
import 'txn_sheet.dart';

enum _Access { checking, granted, denied, permanentlyDenied }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});

  final TxnRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  _Access _access = _Access.checking;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Txn> _txns = const [];
  bool _syncing = false;
  bool _upiOnly = false;

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
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
    if (!mounted) return;
    setState(() => _access = _accessFrom(status));
    await _sync();
  }

  Future<void> _sync() async {
    if (_access == _Access.granted && !_syncing) {
      setState(() => _syncing = true);
      try {
        final added = await widget.repository.sync();
        if (mounted && added > 0) {
          _snack(added == 1 ? '1 new transaction' : '$added new transactions');
        }
      } on PlatformException catch (e) {
        _snack('Could not read SMS: ${e.message ?? e.code}');
      } finally {
        if (mounted) setState(() => _syncing = false);
      }
    }
    await _load();
  }

  Future<void> _load() async {
    final txns = await widget.repository
        .between(_month, DateTime(_month.year, _month.month + 1));
    if (mounted) setState(() => _txns = txns);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  Future<void> _openTxn(Txn t) async {
    final changed = await showTxnSheet(context, t, widget.repository);
    if (changed == true) await _load();
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
            if (_access == _Access.denied ||
                _access == _Access.permanentlyDenied)
              _PermissionCard(
                permanentlyDenied: _access == _Access.permanentlyDenied,
                onPressed: _requestAccess,
              ),
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
              _EmptyState(waitingForAccess: _access != _Access.granted)
            else
              ..._groupedByDay(visible, text),
          ],
        ),
      ),
    );
  }

  List<Widget> _groupedByDay(List<Txn> txns, TextTheme text) {
    final widgets = <Widget>[];
    DateTime? currentDay;
    for (final t in txns) {
      final day = DateTime(t.time.year, t.time.month, t.time.day);
      if (day != currentDay) {
        currentDay = day;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 2),
          child: Text(dayLabel(day),
              style: text.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ));
      }
      widgets.add(TxnTile(txn: t, onTap: () => _openTxn(t)));
    }
    return widgets;
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
                ? 'Allow SMS access, or tap Add to log a payment yourself.'
                : 'No transactions this month.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
