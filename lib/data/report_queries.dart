import 'package:drift/drift.dart';

import 'app_database.dart';
import 'tables.dart';

// ---------------------------------------------------------------------------
// QUERY FOR THE REPORTS SCREEN
//
// Like the other *_queries.dart files, this is an extension on AppDatabase.
// ---------------------------------------------------------------------------

/// A stripped-down transaction: just what the reports need.
class ReportTxn {
  const ReportTxn({
    required this.amountKobo,
    required this.kind,
    required this.occurredAt,
    this.categoryName,
  });

  /// Signed: income positive, expenses negative (as stored).
  final int amountKobo;
  final TxnKind kind;
  final DateTime occurredAt;

  /// Null when the transaction has no category.
  final String? categoryName;
}

extension ReportQueries on AppDatabase {
  /// A live list of every income and expense, with its category name.
  ///
  /// Transfers are left out in the database itself: moving your own money
  /// between accounts is neither income nor spending, so it must never show
  /// up in a profit and loss report.
  ///
  /// The screen then adds the numbers up per month and per category in Dart.
  /// Why not do the grouping in SQL: month boundaries depend on the phone's
  /// time zone, and doing the calendar maths in Dart (with the same DateTime
  /// rules the rest of the app uses) keeps every screen consistent. For a
  /// personal app, a few thousand rows is trivial.
  Stream<List<ReportTxn>> watchReportTransactions() {
    final query = select(transactions).join([
      // LEFT join so transactions without a category are kept.
      leftOuterJoin(
        categories,
        categories.id.equalsExp(transactions.categoryId),
      ),
    ])..where(transactions.kind.equalsValue(TxnKind.transfer).not());

    return query.watch().map((rows) {
      return rows.map((row) {
        final t = row.readTable(transactions);
        // readTableOrNull because the category side may be missing.
        final c = row.readTableOrNull(categories);
        return ReportTxn(
          amountKobo: t.amountKobo,
          kind: t.kind,
          occurredAt: t.occurredAt,
          categoryName: c?.name,
        );
      }).toList();
    });
  }
}
