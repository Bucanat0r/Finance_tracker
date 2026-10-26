import 'package:flutter/material.dart';
// We import only "Value" from drift. Importing all of drift would clash with
// Flutter, because both define a class called "Column".
import 'package:drift/drift.dart' show Value;

import 'data/app_database.dart';
import 'data/tables.dart';

// One shared database for the whole app. Opening it twice would create two
// separate connections to the same file, which causes bugs, so we keep a
// single instance. (Later we will hand it out with Riverpod instead.)
final db = AppDatabase();

void main() {
  // Required before using plugins (like the one that finds the database
  // folder) at startup.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finance Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int? _accountId;
  int _balanceKobo = 0;
  int _incomeKobo = 0;
  int _expenseKobo = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Finds (or creates) a test account, then reads the numbers from the
  /// database. Every number on screen comes from the ledger, never from
  /// variables we keep up to date by hand.
  Future<void> _load() async {
    var accounts = await db.select(db.accounts).get();

    if (accounts.isEmpty) {
      // First launch: make a test account with a N50,000.00 opening balance.
      // 50,000 naira * 100 = 5,000,000 kobo.
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'Test Bank',
              type: AccountType.bank,
              openingBalanceKobo: const Value(5000000),
            ),
          );
      accounts = await db.select(db.accounts).get();
    }

    final id = accounts.first.id;
    final balance = await db.currentBalanceKobo(id);
    final now = DateTime.now();
    final totals = await db.monthlyTotals(now.year, now.month);

    // Always check mounted after an await: the screen may have been closed
    // while we waited, and calling setState then would throw.
    if (!mounted) return;
    setState(() {
      _accountId = id;
      _balanceKobo = balance;
      _incomeKobo = totals.income;
      _expenseKobo = totals.expense;
    });
  }

  /// Adds a transaction and reloads. Debits are stored NEGATIVE, credits
  /// POSITIVE (see the comment on Transactions.amountKobo).
  Future<void> _add(int amountKobo, TxnKind kind, String narration) async {
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: _accountId!,
            amountKobo: amountKobo,
            kind: kind,
            occurredAt: DateTime.now(),
            narration: Value(narration),
          ),
        );
    await _load();
  }

  /// Display only: kobo -> "N1,234.50". This uses a double just to print, which
  /// is safe. All money MATHS stays in integer kobo.
  String _naira(int kobo) {
    final sign = kobo < 0 ? '-' : '';
    final abs = kobo.abs();
    final whole = (abs ~/ 100).toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );
    final cents = (abs % 100).toString().padLeft(2, '0');
    return '$sign\u20A6$whole.$cents';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finance Tracker')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Balance'),
            Text(
              _naira(_balanceKobo),
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 24),
            Text('This month income:   ${_naira(_incomeKobo)}'),
            Text('This month expenses: ${_naira(_expenseKobo)}'),
            Text('Net:                 ${_naira(_incomeKobo - _expenseKobo)}'),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: _accountId == null
                      ? null
                      : () => _add(-50000, TxnKind.expense, 'Test expense'),
                  child: const Text('Spend \u20A6500'),
                ),
                FilledButton(
                  onPressed: _accountId == null
                      ? null
                      : () => _add(200000, TxnKind.income, 'Test income'),
                  child: const Text('Receive \u20A62,000'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
