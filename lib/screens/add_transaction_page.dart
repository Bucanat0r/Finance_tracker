import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/database_instance.dart';
import '../data/tables.dart';
import '../utils/formatters.dart';

/// The form for adding one income or expense by hand.
class AddTransactionPage extends StatefulWidget {
  const AddTransactionPage({super.key});

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  // Text controllers hold what is typed. They must be disposed (below) to
  // free their memory when the page closes.
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  TxnKind _kind = TxnKind.expense;
  int? _accountId;
  int? _categoryId; // Optional: a transaction may have no category.
  DateTime _date = DateTime.now();
  String? _error;
  bool _loading = true;

  List<Account> _accounts = [];
  List<Category> _categories = [];

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

  /// Loads the accounts and categories the form needs to offer.
  Future<void> _loadData() async {
    final accounts = await db.getAccounts();
    final categories = await db.getCategories(_kind);

    // The page may have been closed while we waited.
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _categories = categories;
      // Pre-select the first account so the common case needs no extra tap.
      _accountId = accounts.isNotEmpty ? accounts.first.id : null;
      _loading = false;
    });
  }

  /// Switches between Expense and Income. The category list changes with it,
  /// and the old choice is cleared (a "Food" category makes no sense for
  /// income).
  Future<void> _setKind(TxnKind kind) async {
    final categories = await db.getCategories(kind);
    if (!mounted) return;
    setState(() {
      _kind = kind;
      _categories = categories;
      _categoryId = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(), // No future dates: money has not moved yet.
    );
    if (picked == null || !mounted) return;
    setState(() {
      // Keep the time of day, change only the date.
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
      setState(() => _error = 'Enter a valid amount, like 2500 or 2,500.50');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Choose an account.');
      return;
    }

    // Pass the amount as a positive number. addTransaction() makes expenses
    // negative itself, so the sign can never be wrong here.
    await db.addTransaction(
      accountId: _accountId!,
      categoryId: _categoryId,
      amountKobo: kobo,
      kind: _kind,
      occurredAt: _date,
      narration: _noteCtrl.text.trim(),
    );

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add transaction')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Expense / Income switch.
                SegmentedButton<TxnKind>(
                  segments: const [
                    ButtonSegment(
                      value: TxnKind.expense,
                      label: Text('Expense'),
                      icon: Icon(Icons.arrow_upward),
                    ),
                    ButtonSegment(
                      value: TxnKind.income,
                      label: Text('Income'),
                      icon: Icon(Icons.arrow_downward),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => _setKind(s.first),
                ),
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
                const SizedBox(height: 20),

                Text('Account', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _accounts
                      .map(
                        (a) => ChoiceChip(
                          label: Text(a.name),
                          selected: _accountId == a.id,
                          onSelected: (_) => setState(() => _accountId = a.id),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),

                Text(
                  'Category (optional)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _categories
                      .map(
                        (c) => ChoiceChip(
                          label: Text(c.name),
                          selected: _categoryId == c.id,
                          // Tapping the chosen chip again clears it.
                          onSelected: (sel) =>
                              setState(() => _categoryId = sel ? c.id : null),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),

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

                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
    );
  }
}
