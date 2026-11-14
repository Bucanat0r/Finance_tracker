import 'package:drift/drift.dart';

import 'app_database.dart';
import 'tables.dart';

// ---------------------------------------------------------------------------
// QUERIES FOR MANAGING ACCOUNTS AND CATEGORIES
//
// Like budget_queries.dart, this is an "extension" on AppDatabase, so we can
// add methods without touching app_database.dart or regenerating any code.
// ---------------------------------------------------------------------------

/// One account together with its current balance, for the accounts screen.
class AccountBalance {
  const AccountBalance({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalanceKobo,
    required this.balanceKobo,
  });

  final int id;
  final String name;
  final AccountType type;
  final int openingBalanceKobo;

  /// Opening balance + every transaction in this account.
  final int balanceKobo;
}

extension ManageQueries on AppDatabase {
  // -------------------------------------------------------------------------
  // ACCOUNTS
  // -------------------------------------------------------------------------

  /// A live list of accounts with their current balances.
  ///
  /// The balance is worked out by the database in one query: opening balance
  /// plus the sum of the account's transactions. LEFT JOIN keeps accounts
  /// that have no transactions yet, and COALESCE turns their "no sum" (NULL)
  /// into 0. "readsFrom" makes the stream refresh whenever either table
  /// changes.
  Stream<List<AccountBalance>> watchAccountBalances() {
    return customSelect(
      '''
      SELECT
        a.id AS id,
        a.name AS name,
        a.type AS account_type,
        a.opening_balance_kobo AS opening_kobo,
        a.opening_balance_kobo + COALESCE(SUM(t.amount_kobo), 0) AS balance_kobo
      FROM accounts a
      LEFT JOIN transactions t ON t.account_id = a.id
      WHERE a.archived = 0
      GROUP BY a.id
      ORDER BY a.id
      ''',
      readsFrom: {accounts, transactions},
    ).watch().map((rows) {
      return rows.map((r) {
        return AccountBalance(
          id: r.read<int>('id'),
          name: r.read<String>('name'),
          // The type is stored as the enum's position (0, 1, 2, 3).
          type: AccountType.values[r.read<int>('account_type')],
          openingBalanceKobo: r.read<int>('opening_kobo'),
          balanceKobo: r.read<int>('balance_kobo'),
        );
      }).toList();
    });
  }

  /// Changes an account's name, type and opening balance.
  /// Its transactions are not touched, so changing the opening balance
  /// changes the balance by the same amount.
  Future<void> updateAccount({
    required int id,
    required String name,
    required AccountType type,
    required int openingBalanceKobo,
  }) async {
    await (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        name: Value(name),
        type: Value(type),
        openingBalanceKobo: Value(openingBalanceKobo),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // CATEGORIES
  // -------------------------------------------------------------------------

  /// A live list of every category, income and expense, sorted by name.
  Stream<List<Category>> watchAllCategories() {
    return (select(
      categories,
    )..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();
  }

  /// True if another category of the same kind already has this name
  /// (ignoring upper/lower case). The database also forbids duplicates, but
  /// checking first lets us show a friendly message instead of crashing.
  /// [exceptId] excludes the category being renamed from the check.
  Future<bool> categoryNameTaken(
    String name,
    TxnKind kind, {
    int? exceptId,
  }) async {
    final matches =
        await (select(categories)..where(
              (c) =>
                  c.kind.equalsValue(kind) &
                  c.name.lower().equals(name.toLowerCase()),
            ))
            .get();
    return matches.any((c) => c.id != exceptId);
  }

  Future<void> addCategory(String name, TxnKind kind) async {
    await into(categories)
        .insert(CategoriesCompanion.insert(name: name, kind: kind));
  }

  Future<void> renameCategory(int id, String name) async {
    await (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(name: Value(name)),
    );
  }

  /// How many transactions use this category. Used to warn before deleting.
  Future<int> transactionCountForCategory(int id) async {
    final count = transactions.id.count();
    final row =
        await (selectOnly(transactions)
              ..addColumns([count])
              ..where(transactions.categoryId.equals(id)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Deletes a category. What happens to related data comes from the rules in
  /// tables.dart: transactions in it are KEPT and simply lose their category
  /// ("set null"), and budgets for it are removed ("cascade"). These rules
  /// only work because we switch on foreign keys in app_database.dart.
  Future<void> deleteCategory(int id) async {
    await (delete(categories)..where((c) => c.id.equals(id))).go();
  }
}
