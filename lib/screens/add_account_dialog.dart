import 'package:flutter/material.dart';

import '../data/database_instance.dart';
import '../data/tables.dart';
import '../utils/formatters.dart';

/// Opens the "New account" dialog.
Future<void> showAddAccountDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const AddAccountDialog(),
  );
}

/// A small form: account name, type, and the balance it holds right now.
///
/// It is its own StatefulWidget so the text controllers are cleaned up in
/// dispose() at the right moment. Disposing them too early (right after the
/// dialog closes) can crash while the closing animation is still running.
class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({super.key});

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  AccountType _type = AccountType.bank;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  String _typeLabel(AccountType t) {
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

    // Empty balance field means the account starts at zero.
    final balanceText = _balanceCtrl.text.trim();
    final balanceKobo = balanceText.isEmpty ? 0 : parseNairaToKobo(balanceText);
    if (balanceKobo == null) {
      setState(() => _error = 'Enter the balance as a number, like 50000.');
      return;
    }

    await db.addAccount(
      name: name,
      type: _type,
      openingBalanceKobo: balanceKobo,
    );

    // The dialog may have been closed while we waited for the database.
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name (e.g. GTBank, Opay)',
              ),
            ),
            const SizedBox(height: 16),
            // Chips instead of a dropdown: one tap, and they stay stable
            // across Flutter versions.
            Wrap(
              spacing: 8,
              children: AccountType.values
                  .map(
                    (t) => ChoiceChip(
                      label: Text(_typeLabel(t)),
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
                labelText: 'Current balance',
                prefixText: '\u20A6 ',
                helperText: 'What the account holds right now',
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
