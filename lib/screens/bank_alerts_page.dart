import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../alerts/alert_ingestor.dart';
import '../alerts/alert_settings.dart';
import '../data/alert_queries.dart';
import '../data/app_database.dart';
import '../data/database_instance.dart';
import '../data/tables.dart';
import '../utils/formatters.dart';

/// Set up bank alerts: choose which account each bank feeds, tell the app
/// your name, and test with alerts you paste in.
class BankAlertsPage extends StatefulWidget {
  const BankAlertsPage({super.key});

  @override
  State<BankAlertsPage> createState() => _BankAlertsPageState();
}

class _BankAlertsPageState extends State<BankAlertsPage> {
  final _pasteCtrl = TextEditingController();
  final _namesCtrl = TextEditingController();

  // Streams are created once, so they are not restarted on every rebuild.
  late final Stream<List<Account>> _accountsStream = db.watchAccounts();
  late final Stream<List<RawMessage>> _recentStream = db
      .watchRecentRawMessages();

  bool _busy = false;
  String? _result;
  bool _resultIsGood = false;

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  @override
  void dispose() {
    _pasteCtrl.dispose();
    _namesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNames() async {
    final names = await AlertSettings.myNames();
    if (!mounted) return;
    _namesCtrl.text = names.join(', ');
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // -------------------------------------------------------------------------
  // ACTIONS
  // -------------------------------------------------------------------------

  Future<void> _saveNames() async {
    final names = _namesCtrl.text.split(',');
    await AlertSettings.setMyNames(names);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _snack('Saved.');
  }

  Future<void> _link(String bankKey, int accountId, bool selected) async {
    if (selected) {
      await db.linkAccountToBank(accountId, bankKey);
      // Alerts that arrived before you linked an account can be imported now.
      final imported = await AlertIngestor.reprocessPending();
      if (!mounted) return;
      if (imported > 0) _snack('Imported $imported waiting alerts.');
    } else {
      await db.unlinkBank(bankKey);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      if (mounted) _snack('Nothing to paste. Copy the alert text first.');
      return;
    }
    _pasteCtrl.text = text;
  }

  Future<void> _importPasted() async {
    final text = _pasteCtrl.text.trim();
    if (text.isEmpty || _busy) return;

    setState(() => _busy = true);
    final result = await AlertIngestor.ingest(
      sender: 'pasted',
      body: text,
      receivedAt: DateTime.now(),
    );
    if (!mounted) return;

    setState(() {
      _busy = false;
      _result = result.message;
      _resultIsGood = result.status == IngestStatus.imported;
    });
    if (result.status == IngestStatus.imported) _pasteCtrl.clear();
  }

  Future<void> _retryWaiting() async {
    final imported = await AlertIngestor.reprocessPending();
    if (!mounted) return;
    _snack(
      imported == 0
          ? 'Nothing could be imported yet.'
          : 'Imported $imported alerts.',
    );
  }

  /// Compares the app's balance with the bank's and offers to fix the
  /// difference by adjusting the account's opening balance.
  Future<void> _syncBalance() async {
    // Uses the first linked bank (there is only one for now).
    final account = await db.accountForBank(
      AlertIngestor.parsers.first.bankKey,
    );
    if (!mounted) return;
    if (account == null) {
      _snack('Link an account first.');
      return;
    }

    final latest = await db.latestAlertBalance(account.id);
    final current = await db.currentBalanceKobo(account.id);
    if (!mounted) return;
    if (latest == null) {
      _snack('No alert with a balance has been imported yet.');
      return;
    }

    final diff = latest.balanceKobo - current;
    if (diff == 0) {
      _snack('Already matches: ${formatNaira(current)}.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Match the bank\'s balance?'),
        content: Text(
          'The newest alert (${formatDate(latest.at)}) says the balance is '
          '${formatNaira(latest.balanceKobo)}, but the app shows '
          '${formatNaira(current)}.\n\n'
          'This changes the opening balance of "${account.name}" by '
          '${formatNaira(diff)}; your transactions are not touched.\n\n'
          'Only do this if that alert is the latest thing that happened on '
          'the account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Adjust'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await db.adjustOpeningBalance(account.id, diff);
    if (mounted) _snack('Balance now matches the bank.');
  }

  // -------------------------------------------------------------------------
  // SCREEN
  // -------------------------------------------------------------------------

  IconData _statusIcon(RawStatus s) {
    switch (s) {
      case RawStatus.parsed:
        return Icons.check_circle;
      case RawStatus.pending:
        return Icons.schedule;
      case RawStatus.failed:
        return Icons.error_outline;
      case RawStatus.ignored:
        return Icons.block;
    }
  }

  Color? _statusColor(RawStatus s, ColorScheme scheme) {
    switch (s) {
      case RawStatus.parsed:
        return Colors.green.shade700;
      case RawStatus.pending:
        return Colors.orange.shade700;
      case RawStatus.failed:
        return scheme.error;
      case RawStatus.ignored:
        return null;
    }
  }

  String _statusLabel(RawStatus s) {
    switch (s) {
      case RawStatus.parsed:
        return 'Imported';
      case RawStatus.pending:
        return 'Waiting';
      case RawStatus.failed:
        return 'Could not read';
      case RawStatus.ignored:
        return 'Ignored';
    }
  }

  Widget _title(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Bank alerts')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Bank alerts are read on your phone and turned into '
              'transactions. Nothing is sent anywhere. Messages that are not '
              'bank alerts are ignored and never saved.',
              style: TextStyle(fontSize: 13),
            ),
          ),

          // ---- Which account each bank feeds ----
          StreamBuilder<List<Account>>(
            stream: _accountsStream,
            builder: (context, snapshot) {
              final accounts = snapshot.data;
              if (accounts == null) return const SizedBox.shrink();

              if (accounts.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Create an account on the Home screen first.'),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final parser in AlertIngestor.parsers) ...[
                    _title('${parser.bankName} alerts go to'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final a in accounts)
                            ChoiceChip(
                              label: Text(a.name),
                              selected: a.smsSenderId == parser.bankKey,
                              onSelected: (sel) =>
                                  _link(parser.bankKey, a.id, sel),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),

          // ---- Your name ----
          _title('Your name in alerts'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _namesCtrl,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveNames(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'e.g. ADA OKAFOR',
                helperText:
                    'At least two words, as the bank prints them. Separate '
                    'several names with commas. Alerts with your name are '
                    'saved as transfers between your own accounts, so they '
                    'do not count as spending or income.',
                helperMaxLines: 5,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: _saveNames,
                ),
              ),
            ),
          ),

          // ---- Paste an alert ----
          _title('Import an alert'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _pasteCtrl,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Paste the full alert text',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.content_paste),
                      label: const Text('Paste'),
                      onPressed: _paste,
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _busy ? null : _importPasted,
                      child: const Text('Import'),
                    ),
                  ],
                ),
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _result!,
                    style: TextStyle(
                      color: _resultIsGood
                          ? Colors.green.shade700
                          : scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ---- Balance check ----
          _title('Balance check'),
          ListTile(
            leading: const Icon(Icons.balance),
            title: const Text('Match balance to latest alert'),
            subtitle: const Text(
              'Alerts print your real balance. Use this once to line the '
              'app up with the bank.',
            ),
            onTap: _syncBalance,
          ),

          // ---- Recent alerts ----
          StreamBuilder<List<RawMessage>>(
            stream: _recentStream,
            builder: (context, snapshot) {
              final messages = snapshot.data ?? const <RawMessage>[];
              final hasWaiting = messages.any(
                (m) => m.status == RawStatus.pending,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Recent alerts',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (hasWaiting)
                          TextButton(
                            onPressed: _retryWaiting,
                            child: const Text('Retry waiting'),
                          ),
                      ],
                    ),
                  ),
                  if (messages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No alerts yet.'),
                    )
                  else
                    for (final m in messages)
                      ListTile(
                        leading: Icon(
                          _statusIcon(m.status),
                          color: _statusColor(m.status, scheme),
                        ),
                        title: Text(
                          // The alert on one line, for a quick look.
                          m.body.replaceAll(RegExp(r'\s+'), ' '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          [
                            _statusLabel(m.status),
                            formatDate(m.receivedAt),
                            if (m.errorNote != null) m.errorNote!,
                          ].join(' \u00B7 '),
                        ),
                      ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
