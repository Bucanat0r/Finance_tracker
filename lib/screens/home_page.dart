import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/database_instance.dart';
import '../data/tables.dart';
import '../utils/formatters.dart';
import 'add_account_dialog.dart';
import 'add_transaction_page.dart';

/// The main screen. It first checks that at least one account exists. If not,
/// it asks you to create one. Otherwise it shows the dashboard.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // The stream is created ONCE here. If we called db.watchAccounts() inside
  // build(), every rebuild would create a brand new stream, and the
  // StreamBuilder would restart each time (flicker and wasted queries).
  late final Stream<List<Account>> _accountsStream = db.watchAccounts();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Account>>(
      stream: _accountsStream,
      builder: (context, snapshot) {
        final accounts = snapshot.data;

        // Still loading the first result.
        if (accounts == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Finance Tracker'),
            actions: [
              IconButton(
                tooltip: 'Add account',
                icon: const Icon(Icons.account_balance_wallet_outlined),
                onPressed: () => showAddAccountDialog(context),
              ),
            ],
          ),
          body: accounts.isEmpty
              ? _EmptyState(onCreate: () => showAddAccountDialog(context))
              : _Dashboard(accounts: accounts),
          // You cannot add a transaction until there is an account to put it in.
          floatingActionButton: accounts.isEmpty
              ? null
              : FloatingActionButton.extended(
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddTransactionPage(),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Shown on first launch, before any account exists.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Start by adding an account, like your bank or wallet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onCreate,
              child: const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Balance, this month's totals, and the list of transactions.
class _Dashboard extends StatefulWidget {
  const _Dashboard({required this.accounts});

  final List<Account> accounts;

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  // Created once, for the same reason as the accounts stream above.
  late final Stream<List<TxnRow>> _rowsStream = db.watchTransactions();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TxnRow>>(
      stream: _rowsStream,
      builder: (context, snapshot) {
        final rows = snapshot.data;
        if (rows == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // BALANCE = all opening balances + every transaction in the ledger.
        // Nothing is stored: it is recalculated each time, so it can never
        // disagree with the transactions.
        final opening = widget.accounts.fold<int>(
          0,
          (sum, a) => sum + a.openingBalanceKobo,
        );
        final ledger = rows.fold<int>(0, (sum, r) => sum + r.amountKobo);
        final balance = opening + ledger;

        // THIS MONTH's totals. We add them up here in Dart (not in SQL)
        // because the list is already loaded and we want the numbers to
        // update the instant the list changes. For a personal app this is
        // fast enough. If the list ever gets very large we can move this to
        // a database query.
        final now = DateTime.now();
        var income = 0;
        var expense = 0;
        for (final r in rows) {
          final sameMonth =
              r.occurredAt.year == now.year && r.occurredAt.month == now.month;
          if (!sameMonth) continue;
          // Transfers are skipped on purpose: moving your own money between
          // accounts is neither income nor spending.
          if (r.kind == TxnKind.income) income += r.amountKobo;
          if (r.kind == TxnKind.expense)
            expense += -r.amountKobo; // Flip to positive.
        }
        final net = income - expense;

        return Column(
          children: [
            _SummaryCard(
              balance: balance,
              income: income,
              expense: expense,
              net: net,
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text('No transactions yet. Tap Add to start.'),
                    )
                  : ListView.builder(
                      // Extra space at the bottom so the Add button never
                      // covers the last transaction.
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: rows.length,
                      itemBuilder: (context, i) => _TxnTile(row: rows[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.balance,
    required this.income,
    required this.expense,
    required this.net,
  });

  final int balance;
  final int income;
  final int expense;
  final int net;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Total balance'),
            Text(
              formatNaira(balance),
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 16),
            const Text('This month'),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Income'),
                Text(
                  formatNaira(income),
                  style: TextStyle(color: Colors.green.shade700),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Expenses'),
                Text(
                  formatNaira(expense),
                  style: TextStyle(color: scheme.error),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Net (profit / loss)'),
                Text(
                  formatNaira(net),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: net >= 0 ? Colors.green.shade700 : scheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One transaction in the list. Swipe it to the left to delete it.
class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.row});

  final TxnRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = row.amountKobo > 0;
    final color = isIncome ? Colors.green.shade700 : scheme.error;

    // Title: the bank's description if there is one, otherwise the category.
    final title = row.narration.isNotEmpty
        ? row.narration
        : (row.categoryName ?? (isIncome ? 'Income' : 'Expense'));

    // Subtitle: "Category - Account - Date", skipping the category if none.
    final subtitle = [
      if (row.categoryName != null) row.categoryName!,
      row.accountName,
      formatDate(row.occurredAt),
    ].join(' \u00B7 ');

    return Dismissible(
      // The key tells Flutter which row this is, so the right one disappears.
      key: ValueKey(row.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      // Ask first. Deleting financial records by an accidental swipe would
      // be painful, so we make the user confirm.
      confirmDismiss: (_) async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete transaction?'),
            content: Text(
              'This removes ${formatNaira(row.amountKobo)} from your records.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        return ok ?? false;
      },
      onDismissed: (_) => db.deleteTransaction(row.id),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: color,
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(
          formatNaira(row.amountKobo),
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
