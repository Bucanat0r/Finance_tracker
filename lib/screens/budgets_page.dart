import 'package:flutter/material.dart';

import '../data/budget_queries.dart';
import '../data/database_instance.dart';
import '../utils/formatters.dart';

/// Shows a monthly budget for each expense category, with progress bars.
/// Tap a category to set or change its limit.
class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  late int _year;
  late int _month;

  // The stream is stored in a field and only replaced when the month
  // changes. Creating it inside build() would restart the query on every
  // rebuild.
  late Stream<List<BudgetRow>> _stream;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _stream = db.watchBudgetRows(_year, _month);
  }

  /// Moves to the previous (-1) or next (+1) month.
  void _changeMonth(int delta) {
    // DateTime fixes overflow for us: month 0 becomes December of last year.
    final d = DateTime(_year, _month + delta);
    setState(() {
      _year = d.year;
      _month = d.month;
      _stream = db.watchBudgetRows(_year, _month);
    });
  }

  /// Copies last month's budgets into the month on screen.
  Future<void> _copyFromLastMonth() async {
    final prev = DateTime(_year, _month - 1);
    final count = await db.copyBudgets(
      fromYear: prev.year,
      fromMonth: prev.month,
      toYear: _year,
      toMonth: _month,
    );

    if (!mounted) return;
    final prevName = _monthNames[prev.month - 1];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 0
              ? 'No budgets found in $prevName.'
              : 'Copied $count budgets from $prevName. Existing ones were kept.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            tooltip: 'Copy budgets from last month',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _copyFromLastMonth,
          ),
        ],
      ),
      body: Column(
        children: [
          // Month picker.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _changeMonth(-1),
              ),
              SizedBox(
                width: 180,
                child: Text(
                  '${_monthNames[_month - 1]} $_year',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _changeMonth(1),
              ),
            ],
          ),
          Expanded(
            child: StreamBuilder<List<BudgetRow>>(
              stream: _stream,
              builder: (context, snapshot) {
                final rows = snapshot.data;
                if (rows == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Totals for the summary card, added up in whole kobo.
                var budgeted = 0;
                var spentInBudgeted = 0;
                var spentUnbudgeted = 0;
                for (final r in rows) {
                  if (r.hasBudget) {
                    budgeted += r.limitKobo!;
                    spentInBudgeted += r.spentKobo;
                  } else {
                    spentUnbudgeted += r.spentKobo;
                  }
                }

                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _BudgetSummary(
                      budgeted: budgeted,
                      spent: spentInBudgeted,
                      unbudgetedSpent: spentUnbudgeted,
                    ),
                    for (final r in rows)
                      _BudgetTile(
                        row: r,
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => _SetBudgetDialog(
                            row: r,
                            year: _year,
                            month: _month,
                          ),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Text(
                        'Only transactions that have a category count '
                        'towards a budget.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetSummary extends StatelessWidget {
  const _BudgetSummary({
    required this.budgeted,
    required this.spent,
    required this.unbudgetedSpent,
  });

  final int budgeted;
  final int spent;
  final int unbudgetedSpent;

  @override
  Widget build(BuildContext context) {
    final remaining = budgeted - spent;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _line('Total budgeted', formatNaira(budgeted)),
            _line('Spent (budgeted categories)', formatNaira(spent)),
            const Divider(),
            _line(
              remaining >= 0 ? 'Left to spend' : 'Over budget by',
              formatNaira(remaining.abs()),
              color: remaining >= 0 ? Colors.green.shade700 : scheme.error,
              bold: true,
            ),
            if (unbudgetedSpent > 0) ...[
              const SizedBox(height: 8),
              _line('Spent with no budget set', formatNaira(unbudgetedSpent)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.row, required this.onTap});

  final BudgetRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // No budget yet: show what was spent and an invitation to set one.
    if (!row.hasBudget) {
      return ListTile(
        title: Text(row.categoryName),
        subtitle: Text(
          row.spentKobo > 0
              ? 'Spent ${formatNaira(row.spentKobo)} \u00B7 no budget set'
              : 'No budget set',
        ),
        trailing: const Icon(Icons.add_circle_outline),
        onTap: onTap,
      );
    }

    // Colour tells you how you are doing at a glance:
    // green = fine, orange = past 80%, red = over the limit.
    final ratio = row.progress;
    final Color barColor = ratio >= 1.0
        ? scheme.error
        : ratio >= 0.8
        ? Colors.orange.shade700
        : Colors.green.shade600;

    final over = row.remainingKobo < 0;

    return ListTile(
      onTap: onTap,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(row.categoryName)),
          Text(
            '${formatNaira(row.spentKobo)} / ${formatNaira(row.limitKobo!)}',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                // Clamped so the bar never draws past its end when you are
                // over budget.
                value: ratio.clamp(0.0, 1.0),
                minHeight: 8,
                color: barColor,
                backgroundColor: barColor.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              over
                  ? '${formatNaira(row.remainingKobo.abs())} over'
                  : '${formatNaira(row.remainingKobo)} left',
              style: TextStyle(fontSize: 12, color: over ? scheme.error : null),
            ),
          ],
        ),
      ),
    );
  }
}

/// The popup for typing a limit. It is its own StatefulWidget so the text
/// controller is disposed at the right moment (after the dialog has fully
/// closed), which avoids a crash during the closing animation.
class _SetBudgetDialog extends StatefulWidget {
  const _SetBudgetDialog({
    required this.row,
    required this.year,
    required this.month,
  });

  final BudgetRow row;
  final int year;
  final int month;

  @override
  State<_SetBudgetDialog> createState() => _SetBudgetDialogState();
}

class _SetBudgetDialogState extends State<_SetBudgetDialog> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    // If a budget already exists, start with its value in the box.
    final limit = widget.row.limitKobo;
    _ctrl = TextEditingController(text: limit == null ? '' : _plain(limit));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Kobo to a plain editable number: 5000000 -> "50000", 5050 -> "50.50".
  String _plain(int kobo) {
    final whole = kobo ~/ 100;
    final cents = kobo % 100;
    return cents == 0 ? '$whole' : '$whole.${cents.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final kobo = parseNairaToKobo(_ctrl.text);
    if (kobo == null || kobo == 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }

    await db.setBudget(
      categoryId: widget.row.categoryId,
      year: widget.year,
      month: widget.month,
      limitKobo: kobo,
    );

    // The dialog may have closed while we waited for the database.
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _remove() async {
    await db.clearBudget(
      categoryId: widget.row.categoryId,
      year: widget.year,
      month: widget.month,
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.row.categoryName} budget'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Monthly limit',
              prefixText: '\u20A6 ',
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
      actions: [
        // Only offer "Remove" when there is a budget to remove.
        if (widget.row.hasBudget)
          TextButton(onPressed: _remove, child: const Text('Remove')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
