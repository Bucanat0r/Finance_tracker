import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/database_instance.dart';
import '../data/report_queries.dart';
import '../data/tables.dart';
import '../utils/formatters.dart';

const _monthNames = [
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

/// One month's totals, used for the chart.
class _MonthPoint {
  const _MonthPoint({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
  });

  final int year;
  final int month;
  final int income; // Positive kobo.
  final int expense; // Positive kobo.
}

/// Profit and loss for a month, a 6-month comparison, and a breakdown of
/// where the money went (or came from) by category.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  // Created once so the stream is not restarted on every rebuild.
  late final Stream<List<ReportTxn>> _stream = db.watchReportTransactions();

  late int _year;
  late int _month;

  // The breakdown shows either expenses or income.
  bool _showExpenses = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  /// Moves to the previous (-1) or next (+1) month.
  void _changeMonth(int delta) {
    // DateTime fixes overflow for us: month 0 becomes December of last year.
    final d = DateTime(_year, _month + delta);
    setState(() {
      _year = d.year;
      _month = d.month;
    });
  }

  /// A single number that identifies a month, so months can be used as map
  /// keys: January 2026 -> 2026*12 + 0.
  int _key(int year, int month) => year * 12 + (month - 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: StreamBuilder<List<ReportTxn>>(
        stream: _stream,
        builder: (context, snapshot) {
          final txns = snapshot.data;
          if (txns == null) {
            return const Center(child: CircularProgressIndicator());
          }

          // ------------------------------------------------------------
          // One pass over every transaction, adding up per month.
          // ------------------------------------------------------------
          final incomeByMonth = <int, int>{};
          final expenseByMonth = <int, int>{};
          for (final t in txns) {
            final k = _key(t.occurredAt.year, t.occurredAt.month);
            if (t.kind == TxnKind.income) {
              incomeByMonth[k] = (incomeByMonth[k] ?? 0) + t.amountKobo;
            } else if (t.kind == TxnKind.expense) {
              // Expenses are stored negative; flip to positive for reports.
              expenseByMonth[k] = (expenseByMonth[k] ?? 0) - t.amountKobo;
            }
          }

          final selectedKey = _key(_year, _month);
          final income = incomeByMonth[selectedKey] ?? 0;
          final expense = expenseByMonth[selectedKey] ?? 0;

          final prev = DateTime(_year, _month - 1);
          final prevKey = _key(prev.year, prev.month);
          final prevExpense = expenseByMonth[prevKey] ?? 0;

          // The six months ending at the selected month, oldest first.
          final series = <_MonthPoint>[];
          for (var i = 5; i >= 0; i--) {
            final d = DateTime(_year, _month - i);
            final k = _key(d.year, d.month);
            series.add(
              _MonthPoint(
                year: d.year,
                month: d.month,
                income: incomeByMonth[k] ?? 0,
                expense: expenseByMonth[k] ?? 0,
              ),
            );
          }

          // ------------------------------------------------------------
          // Breakdown by category for the selected month.
          // ------------------------------------------------------------
          final wantedKind = _showExpenses ? TxnKind.expense : TxnKind.income;
          final byCategory = <String, int>{};
          for (final t in txns) {
            if (t.kind != wantedKind) continue;
            if (t.occurredAt.year != _year || t.occurredAt.month != _month) {
              continue;
            }
            final name = t.categoryName ?? 'Uncategorised';
            // abs() so income (positive) and expenses (negative) both add up
            // as positive amounts.
            byCategory[name] = (byCategory[name] ?? 0) + t.amountKobo.abs();
          }
          // Biggest first.
          final entries = byCategory.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final breakdownTotal = entries.fold<int>(
            0,
            (sum, e) => sum + e.value,
          );

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _MonthPicker(
                label: '${_monthNames[_month - 1]} $_year',
                onPrevious: () => _changeMonth(-1),
                onNext: () => _changeMonth(1),
              ),
              _ProfitLossCard(
                income: income,
                expense: expense,
                prevExpense: prevExpense,
                prevMonthName: _monthNames[prev.month - 1],
              ),
              _SectionTitle('Last 6 months'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _MonthBars(data: series),
              ),
              const SizedBox(height: 8),
              _SectionTitle('Breakdown'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Expenses')),
                    ButtonSegment(value: false, label: Text('Income')),
                  ],
                  selected: {_showExpenses},
                  onSelectionChanged: (s) =>
                      setState(() => _showExpenses = s.first),
                ),
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Nothing recorded this month.')),
                )
              else
                for (final e in entries)
                  _CategoryBar(
                    name: e.key,
                    amount: e.value,
                    total: breakdownTotal,
                    color: _showExpenses
                        ? Theme.of(context).colorScheme.error
                        : Colors.green.shade600,
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthPicker extends StatelessWidget {
  const _MonthPicker({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrevious),
        SizedBox(
          width: 180,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

/// Income, expenses and the profit or loss for the month.
class _ProfitLossCard extends StatelessWidget {
  const _ProfitLossCard({
    required this.income,
    required this.expense,
    required this.prevExpense,
    required this.prevMonthName,
  });

  final int income;
  final int expense;
  final int prevExpense;
  final String prevMonthName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final net = income - expense;
    final profit = net >= 0;
    final netColor = profit ? Colors.green.shade700 : scheme.error;

    // Savings rate: how much of your income you kept. Whole numbers only,
    // since it is just a label. Skipped when there was no income to compare
    // against (dividing by zero).
    final rate = income > 0 ? (net * 100 ~/ income) : null;

    // How spending compares with last month.
    String? comparison;
    if (expense > 0 || prevExpense > 0) {
      final diff = expense - prevExpense;
      if (diff == 0) {
        comparison = 'Same spending as $prevMonthName.';
      } else if (diff > 0) {
        comparison = '${formatNaira(diff)} more than $prevMonthName.';
      } else {
        comparison = '${formatNaira(-diff)} less than $prevMonthName.';
      }
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profit ? 'Profit' : 'Loss'),
            Text(
              formatNaira(net.abs()),
              style: Theme.of(context).textTheme.displaySmall
                  ?.copyWith(color: netColor),
            ),
            const SizedBox(height: 16),
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
            if (rate != null) ...[
              const Divider(),
              Text(
                rate >= 0
                    ? 'You kept $rate% of your income.'
                    : 'You spent ${-rate}% more than you earned.',
              ),
            ],
            if (comparison != null) ...[
              const SizedBox(height: 4),
              Text(comparison, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A simple bar chart: for each month, a green bar (income) next to a red bar
/// (expenses). Drawn with plain widgets, so it needs no chart package.
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.data});

  final List<_MonthPoint> data;

  // Height of the tallest bar, in pixels.
  static const double _chartHeight = 110;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Every bar is scaled against the biggest value shown, so months can be
    // compared fairly. At least 1, to avoid dividing by zero when all months
    // are empty.
    var maxValue = 1;
    for (final p in data) {
      maxValue = math.max(maxValue, math.max(p.income, p.expense));
    }

    // Turns an amount into a bar height. Real money maths stays in integers;
    // this double is only used to draw pixels.
    double heightFor(int value) {
      if (value == 0) return 0;
      // A tiny amount still gets a visible sliver (minimum 2 pixels).
      return math.max(2, value / maxValue * _chartHeight);
    }

    Widget bar(int value, Color color) {
      return Container(
        width: 10,
        height: heightFor(value),
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
      );
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < data.length; i++)
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: _chartHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          bar(data[i].income, Colors.green.shade600),
                          const SizedBox(width: 3),
                          bar(data[i].expense, scheme.error),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      // First three letters of the month: "Oct".
                      _monthNames[data[i].month - 1].substring(0, 3),
                      style: TextStyle(
                        fontSize: 12,
                        // The last bar group is the month you selected.
                        fontWeight: i == data.length - 1
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Legend.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 10, height: 10, color: Colors.green.shade600),
            const SizedBox(width: 4),
            const Text('Income', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 16),
            Container(width: 10, height: 10, color: scheme.error),
            const SizedBox(width: 4),
            const Text('Expenses', style: TextStyle(fontSize: 12)),
          ],
        ),
      ],
    );
  }
}

/// One row of the breakdown: category name, amount, share, and a bar.
class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.name,
    required this.amount,
    required this.total,
    required this.color,
  });

  final String name;
  final int amount;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Share of the total, used only for the bar and the percentage label.
    final fraction = total == 0 ? 0.0 : amount / total;
    final percent = (fraction * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(name)),
              Text('${formatNaira(amount)}  \u00B7  $percent%'),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}
