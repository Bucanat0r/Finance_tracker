import 'package:flutter/material.dart';

import '../data/database_instance.dart';
import '../data/manage_queries.dart';
import '../data/tables.dart';
import '../utils/formatters.dart';
import 'add_account_dialog.dart';

/// Lists your accounts with their balances. Tap one to edit it.
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  // Created once so the stream is not restarted on every rebuild.
  late final Stream<List<AccountBalance>> _stream = db.watchAccountBalances();

  IconData _iconFor(AccountType t) {
    switch (t) {
      case AccountType.bank:
        return Icons.account_balance;
      case AccountType.wallet:
        return Icons.account_balance_wallet;
      case AccountType.creditCard:
        return Icons.credit_card;
      case AccountType.cash:
        return Icons.payments;
    }
  }

  String _labelFor(AccountType t) {
    switch (t) {
      case AccountType.bank:
        return 'Bank';
      case AccountType.wallet:
        return 'Wallet';
      case AccountType.creditCard:
        return 'Credit card';
      case AccountType.cash:
        return 'Cash';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            tooltip: 'Add account',
            icon: const Icon(Icons.add),
            onPressed: () => showAddAccountDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<List<AccountBalance>>(
        stream: _stream,
        builder: (context, snapshot) {
          final accounts = snapshot.data;
          if (accounts == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (accounts.isEmpty) {
            return const Center(child: Text('No accounts yet.'));
          }

          final total = accounts.fold<int>(0, (sum, a) => sum + a.balanceKobo);

          return ListView(
            children: [
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total across accounts'),
                      Text(
                        formatNaira(total),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              for (final a in accounts)
                ListTile(
                  leading: CircleAvatar(child: Icon(_iconFor(a.type))),
                  title: Text(a.name),
                  subtitle: Text(_labelFor(a.type)),
                  trailing: Text(
                    formatNaira(a.balanceKobo),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _EditAccountDialog(account: a),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Popup to change an account's name, type and opening balance.
class _EditAccountDialog extends StatefulWidget {
  const _EditAccountDialog({required this.account});

  final AccountBalance account;

  @override
  State<_EditAccountDialog> createState() => _EditAccountDialogState();
}

class _EditAccountDialogState extends State<_EditAccountDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _balanceCtrl;
  late AccountType _type;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.account.name);
    _balanceCtrl = TextEditingController(
      text: _plain(widget.account.openingBalanceKobo),
    );
    _type = widget.account.type;
  }

  // The controllers are disposed here, after the dialog has fully closed.
  // Disposing them earlier can crash during the closing animation.
  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  /// Kobo to an editable number: 5000000 -> "50000", 5050 -> "50.50".
  String _plain(int kobo) {
    final whole = kobo ~/ 100;
    final cents = kobo % 100;
    return cents == 0 ? '$whole' : '$whole.${cents.toString().padLeft(2, '0')}';
  }

  String _labelFor(AccountType t) {
    switch (t) {
      case AccountType.bank:
        return 'Bank';
      case AccountType.wallet:
        return 'Wallet';
      case AccountType.creditCard:
        return 'Credit card';
      case AccountType.cash:
        return 'Cash';
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the account a name.');
      return;
    }

    // An empty balance box means the account started at zero.
    final text = _balanceCtrl.text.trim();
    final kobo = text.isEmpty ? 0 : parseNairaToKobo(text);
    if (kobo == null) {
      setState(() => _error = 'Enter the balance as a number, like 50000.');
      return;
    }

    await db.updateAccount(
      id: widget.account.id,
      name: name,
      type: _type,
      openingBalanceKobo: kobo,
    );

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: AccountType.values
                  .map(
                    (t) => ChoiceChip(
                      label: Text(_labelFor(t)),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = t),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _balanceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Opening balance',
                prefixText: '\u20A6 ',
                helperText:
                    'What it held when you started tracking. Changing it '
                    'changes the balance; your transactions stay the same.',
                helperMaxLines: 3,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
