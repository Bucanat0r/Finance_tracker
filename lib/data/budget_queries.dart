import 'package:drift/drift.dart';

import 'app_database.dart';
import 'tables.dart';

// ---------------------------------------------------------------------------
// BUDGET QUERIES
//
// These live in their own file as an "extension" on AppDatabase. An extension
// adds methods to a class from outside it, so we get db.watchBudgetRows(...)
// without touching app_database.dart or regenerating any code.
// ---------------------------------------------------------------------------

/// One line of the budgets screen: an expense category, how much you set
/// aside for it this month (if anything), and how much you have spent.
class BudgetRow {
  const BudgetRow({
    required this.categoryId,
    required this.categoryName,
    required this.spentKobo,
    this.limitKobo,
  });

  final int categoryId;
  final String categoryName;

  /// Spent this month as a POSITIVE number (expenses are stored negative).
  final int spentKobo;

  /// The monthly limit, or null when no budget is set for this category.
  final int? limitKobo;

  bool get hasBudget => limitKobo != null;

  /// Money left. Negative means you are over budget.
  int get remainingKobo => (limitKobo ?? 0) - spentKobo;

  /// 0.0 to 1.0+ for the progress bar. A double is fine here because it is
  /// only used to draw a bar, never for money maths.
  double get progress {
    final limit = limitKobo;
    if (limit == null || limit == 0) return 0;
    return spentKobo / limit;
  }
}

extension BudgetQueries on AppDatabase {
  /// A live list of every EXPENSE category for one month, each with its
  /// budget (if any) and what you have spent in it that month.
  ///
  /// It is a raw SQL query because it combines three tables and adds up
  /// spending per category in one pass, which is clearer in SQL than in
  /// Dart. "readsFrom" tells Drift which tables this query depends on, so
  /// the stream re-runs by itself whenever any of them changes. That is why
  /// the screen updates the moment you add a transaction.
  Stream<List<BudgetRow>> watchBudgetRows(int year, int month) {
    final start = DateTime(year, month);
    // DateTime rolls month 13 over into January of next year for us.
    final end = DateTime(year, month + 1);

    return customSelect(
      '''
      SELECT
        c.id   AS category_id,
        c.name AS category_name,
        b.limit_kobo AS limit_kobo,
        -- Expenses are stored negative, so we flip the sign with the minus.
        -- COALESCE turns "no transactions" (NULL) into 0.
        COALESCE((
          SELECT -SUM(t.amount_kobo)
          FROM transactions t
          WHERE t.category_id = c.id
            AND t.kind = ?
            AND t.occurred_at >= ?
            AND t.occurred_at < ?
        ), 0) AS spent_kobo
      FROM categories c
      -- LEFT JOIN keeps categories that have no budget yet.
      LEFT JOIN budgets b
        ON b.category_id = c.id AND b.year = ? AND b.month = ?
      WHERE c.kind = ?
      ORDER BY c.name
      ''',
      // The order here must match the order of the ? marks above.
      // Drift stores dates as whole seconds since 1970, so we convert.
      variables: [
        Variable.withInt(TxnKind.expense.index),
        Variable.withInt(start.millisecondsSinceEpoch ~/ 1000),
        Variable.withInt(end.millisecondsSinceEpoch ~/ 1000),
        Variable.withInt(year),
        Variable.withInt(month),
        Variable.withInt(TxnKind.expense.index),
      ],
      readsFrom: {categories, budgets, transactions},
    ).watch().map((rows) {
      return rows.map((r) {
        return BudgetRow(
          categoryId: r.read<int>('category_id'),
          categoryName: r.read<String>('category_name'),
          // readNullable because a category with no budget has no limit.
          limitKobo: r.readNullable<int>('limit_kobo'),
          spentKobo: r.read<int>('spent_kobo'),
        );
      }).toList();
    });
  }

  /// Sets (or changes) the budget for one category in one month.
  ///
  /// "Upsert" = insert, or update if it already exists. The budgets table has
  /// a unique rule on (category, year, month), so a second insert for the
  /// same trio would normally fail. DoUpdate says: when that happens,
  /// update the limit instead.
  Future<void> setBudget({
    required int categoryId,
    required int year,
    required int month,
    required int limitKobo,
  }) async {
    await into(budgets).insert(
      BudgetsCompanion.insert(
        categoryId: categoryId,
        year: year,
        month: month,
        limitKobo: limitKobo,
      ),
      onConflict: DoUpdate(
        (old) => BudgetsCompanion(limitKobo: Value(limitKobo)),
        target: [budgets.categoryId, budgets.year, budgets.month],
      ),
    );
  }

  /// Removes the budget for one category in one month (spending history is
  /// untouched).
  Future<void> clearBudget({
    required int categoryId,
    required int year,
    required int month,
  }) async {
    await (delete(budgets)..where(
          (b) =>
              b.categoryId.equals(categoryId) &
              b.year.equals(year) &
              b.month.equals(month),
        ))
        .go();
  }

  /// Copies every budget from one month to another, so you do not have to
  /// retype them each month. Budgets that already exist in the target month
  /// are left alone (insertOrIgnore skips rows that would break the unique
  /// rule). Returns how many budgets the source month had.
  Future<int> copyBudgets({
    required int fromYear,
    required int fromMonth,
    required int toYear,
    required int toMonth,
  }) async {
    final source = await (select(
      budgets,
    )..where((b) => b.year.equals(fromYear) & b.month.equals(fromMonth))).get();

    await batch((batch) {
      batch.insertAll(
        budgets,
        source
            .map(
              (b) => BudgetsCompanion.insert(
                categoryId: b.categoryId,
                year: toYear,
                month: toMonth,
                limitKobo: b.limitKobo,
              ),
            )
            .toList(),
        mode: InsertMode.insertOrIgnore,
      );
    });

    return source.length;
  }
}
