import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/database_instance.dart';
import '../data/transaction_queries.dart';
import '../utils/formatters.dart';

/// Move money from one of your accounts to another.
class TransferPage extends StatefulWidget {
  const TransferPage({super.key});

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  List<Account> _accounts = [];
  int? _fromId;
  int? _toId;
  DateTime _date = DateTime.now();
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final accounts = await db.getAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      // Pre-select the first two accounts so the common case needs few taps.
      if (accounts.length >= 2) {
        _fromId = accounts[0].id;
        _toId = accounts[1].id;
      }
      _loading = false;
    });
  }

  /// Swaps "from" and "to" with one tap.
  void _swap() {
    setState(() {
      final tmp = _fromId;
      _fromId = _toId;
      _toId = tmp;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      // One day ahead of now, to avoid timezone edge cases around midnight.
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
      );
    });
  }

  Future<void> _save() async {
    final kobo = parseNairaToKobo(_amountCtrl.text);
    if (kobo == null || kobo == 0) {
      setState(() => _error = 'Enter a valid amount, like 5000');
      return;
    }
    if (_fromId == null || _toId == null || _fromId == _toId) {
      setState(() => _error = 'Choose two different accounts.');
      return;
    }

    // We need the names for the automatic description ("Transfer to GTBank").
    final from = _accounts.firstWhere((a) => a.id == _fromId);
    final to = _accounts.firstWhere((a) => a.id == _toId);

    await db.addTransfer(
      fromAccountId: from.id,
      toAccountId: to.id,
      fromName: from.name,
      toName: to.name,
      amountKobo: kobo,
      occurredAt: _date,
      note: _noteCtrl.text.trim(),
    );

    if (!mounted) return;
    Navigator.pop(context);
  }

  /// A row of account chips for choosing either side of the transfer.
  Widget _accountChips(int? selectedId, ValueChanged<int> onPick) {
    return Wrap(
      spacing: 8,
      children: _accounts
          .map(
            (a) => ChoiceChip(
              label: Text(a.name),
              selected: selectedId == a.id,
              onSelected: (_) => onPick(a.id),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.length < 2
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('You need at least two accounts to transfer.'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('From', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                _accountChips(_fromId, (id) => setState(() => _fromId = id)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Swap',
                    icon: const Icon(Icons.swap_vert),
                    onPressed: _swap,
                  ),
                ),
                Text('To', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                _accountChips(_toId, (id) => setState(() => _toId = id)),
                const SizedBox(height: 20),
                TextField(
                  controller: _amountCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '\u20A6 ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(formatDate(_date)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(onPressed: _save, child: const Text('Transfer')),
              ],
            ),
    );
  }
}
