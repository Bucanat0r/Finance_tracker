import 'package:drift/drift.dart';

import 'app_database.dart';
import 'tables.dart';

// ---------------------------------------------------------------------------
// QUERIES FOR EDITING TRANSACTIONS AND MAKING TRANSFERS
//
// Like the other *_queries.dart files, this is an extension on AppDatabase,
// so we add methods without touching app_database.dart or regenerating code.
// ---------------------------------------------------------------------------

/// Everything the edit form needs to know about one transaction.
///
/// Why our own small class: the list screen only carries names for display,
/// but the form needs the raw ids (account, category) to pre-select them.
class TxnDetails {
  const TxnDetails({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.amountKobo,
    required this.kind,
    required this.occurredAt,
    required this.narration,
  });

  final int id;
  final int accountId;
  final int? categoryId;

  /// Signed: credits positive, debits negative (as stored).
  final int amountKobo;
  final TxnKind kind;
  final DateTime occurredAt;
  final String narration;
}

extension TransactionQueries on AppDatabase {
  /// Loads one transaction for editing, or null if it no longer exists.
  Future<TxnDetails?> getTransactionDetails(int id) async {
    final row = await (select(
      transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;

    return TxnDetails(
      id: row.id,
      accountId: row.accountId,
      categoryId: row.categoryId,
      amountKobo: row.amountKobo,
      kind: row.kind,
      occurredAt: row.occurredAt,
      narration: row.narration,
    );
  }

  /// Saves changes to an existing income or expense.
  ///
  /// Pass [amountKobo] as a POSITIVE number. This method applies the sign
  /// (expenses are stored negative), exactly like addTransaction does, so the
  /// form can never save a wrong sign.
  Future<void> updateTransaction({
    required int id,
    required int accountId,
    int? categoryId,
    required int amountKobo,
    required TxnKind kind,
    required DateTime occurredAt,
    String narration = '',
  }) async {
    final signed = kind == TxnKind.expense
        ? -amountKobo.abs()
        : amountKobo.abs();

    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        accountId: Value(accountId),
        categoryId: Value(categoryId),
        amountKobo: Value(signed),
        kind: Value(kind),
        occurredAt: Value(occurredAt),
        narration: Value(narration),
        // Once you have looked at a transaction and saved it, it no longer
        // needs review. Later, the SMS parser will flag uncertain ones, and
        // this is how you clear the flag.
        needsReview: const Value(false),
      ),
    );
  }

  /// Moves money between two of your own accounts.
  ///
  /// A transfer is stored as TWO rows: money leaves one account (negative)
  /// and arrives in the other (positive). Both rows get the same
  /// transferGroupId so we can find them as a pair. The kind is "transfer",
  /// which every income, expense, budget and profit/loss calculation skips,
  /// so the move does not look like spending.
  ///
  /// [amountKobo] is positive. Both rows are saved inside one database
  /// "transaction": either both are written or neither is, so you can never
  /// end up with money that left one account and never arrived.
  Future<void> addTransfer({
    required int fromAccountId,
    required int toAccountId,
    required String fromName,
    required String toName,
    required int amountKobo,
    required DateTime occurredAt,
    String note = '',
  }) async {
    // One shared id for the pair. The current time in microseconds is unique
    // enough for a personal app.
    final group = '${DateTime.now().microsecondsSinceEpoch}';

    // If the user wrote a note, add it after the automatic description.
    String describe(String base) => note.isEmpty ? base : '$base - $note';

    await transaction(() async {
      await into(transactions).insert(
        TransactionsCompanion.insert(
          accountId: fromAccountId,
          amountKobo: -amountKobo.abs(),
          kind: TxnKind.transfer,
          occurredAt: occurredAt,
          narration: Value(describe('Transfer to $toName')),
          source: const Value(TxnSource.manual),
          transferGroupId: Value(group),
        ),
      );
      await into(transactions).insert(
        TransactionsCompanion.insert(
          accountId: toAccountId,
          amountKobo: amountKobo.abs(),
          kind: TxnKind.transfer,
          occurredAt: occurredAt,
          narration: Value(describe('Transfer from $fromName')),
          source: const Value(TxnSource.manual),
          transferGroupId: Value(group),
        ),
      );
    });
  }

  /// Deletes a transaction. If it is half of a transfer, BOTH halves are
  /// deleted. Removing only one would leave the other account's balance
  /// permanently wrong.
  Future<void> deleteTransactionSmart(int id) async {
    final row = await (select(
      transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;

    final group = row.transferGroupId;
    if (group == null) {
      await (delete(transactions)..where((t) => t.id.equals(id))).go();
    } else {
      await (delete(
        transactions,
      )..where((t) => t.transferGroupId.equals(group))).go();
    }
  }
}
