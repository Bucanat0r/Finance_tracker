import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

// This line tells the code generator where to write its output. The file
// app_database.g.dart is created by build_runner. It contains the base class
// _$AppDatabase and the table accessors (accounts, transactions, ...).
// If that file is missing or stale, every table name below shows as
// "undefined" in the editor.
part 'app_database.g.dart';

@DriftDatabase(
  tables: [Accounts, Categories, RawMessages, Transactions, Budgets],
)
class AppDatabase extends _$AppDatabase {
  // driftDatabase() picks the right place to store the SQLite file on each
  // platform, so we do not have to write that ourselves.
  AppDatabase() : super(driftDatabase(name: 'finance_tracker'));

  // Bump this number whenever you change a table, and add a migration step
  // below. It is how the app upgrades old databases without losing data.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      // Runs once, on first launch: create all the tables.
      await m.createAll();

      // Give the user sensible starting categories so budgets and
      // reports have something to attach to. They can add, rename or
      // delete them later. A batch sends all the inserts in one go,
      // which is faster than inserting one by one.
      await batch((b) {
        b.insertAll(categories, [
          // Income
          CategoriesCompanion.insert(name: 'Salary', kind: TxnKind.income),
          CategoriesCompanion.insert(name: 'Business', kind: TxnKind.income),
          CategoriesCompanion.insert(name: 'Gifts', kind: TxnKind.income),
          CategoriesCompanion.insert(
            name: 'Other income',
            kind: TxnKind.income,
          ),
          // Expenses
          CategoriesCompanion.insert(name: 'Food', kind: TxnKind.expense),
          CategoriesCompanion.insert(name: 'Transport', kind: TxnKind.expense),
          CategoriesCompanion.insert(
            name: 'Airtime & data',
            kind: TxnKind.expense,
          ),
          CategoriesCompanion.insert(
            name: 'Bills & utilities',
            kind: TxnKind.expense,
          ),
          CategoriesCompanion.insert(name: 'Shopping', kind: TxnKind.expense),
          CategoriesCompanion.insert(
            name: 'Entertainment',
            kind: TxnKind.expense,
          ),
          CategoriesCompanion.insert(
            name: 'Bank charges',
            kind: TxnKind.expense,
          ),
          CategoriesCompanion.insert(
            name: 'Other expenses',
            kind: TxnKind.expense,
          ),
        ]);
      });
    },
    beforeOpen: (details) async {
      // SQLite ignores foreign keys unless you switch them on. Without
      // this, the "cascade" and "set null" rules in tables.dart do
      // nothing.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // -------------------------------------------------------------------------
  // BALANCE
  // -------------------------------------------------------------------------

  /// Current balance of one account in kobo:
  /// opening balance + the sum of all its transactions.
  Future<int> currentBalanceKobo(int accountId) async {
    final account = await (select(
      accounts,
    )..where((a) => a.id.equals(accountId))).getSingle();

    // Ask SQLite to add everything up itself. This is much faster than
    // loading every row into Dart and summing there.
    final total = transactions.amountKobo.sum();
    final row =
        await (selectOnly(transactions)
              ..addColumns([total])
              ..where(transactions.accountId.equals(accountId)))
            .getSingle();

    // SUM over zero rows returns null, so treat that as 0.
    return account.openingBalanceKobo + (row.read(total) ?? 0);
  }

  // -------------------------------------------------------------------------
  // MONTHLY SUMMARY (the basis of the profit and loss screen)
  // -------------------------------------------------------------------------

  /// Total income and total expenses for a month, in kobo.
  /// Transfers are excluded on purpose (see TxnKind.transfer).
  /// Expenses come back as a positive number, since they are stored negative.
  Future<({int income, int expense})> monthlyTotals(int year, int month) async {
    final start = DateTime(year, month);
    // DateTime rolls month 13 over into January of next year for us.
    final end = DateTime(year, month + 1);

    // Adds up all transactions of one kind inside the month.
    Future<int> sumFor(TxnKind kind) async {
      final total = transactions.amountKobo.sum();
      final row =
          await (selectOnly(transactions)
                ..addColumns([total])
                ..where(
                  transactions.kind.equalsValue(kind) &
                      transactions.occurredAt.isBiggerOrEqualValue(start) &
                      transactions.occurredAt.isSmallerThanValue(end),
                ))
              .getSingle();
      return row.read(total) ?? 0;
    }

    final income = await sumFor(TxnKind.income);
    final expense = await sumFor(TxnKind.expense);

    // Net profit/loss for the month is income - expense.
    // Expenses are stored negative, so we flip the sign for display.
    return (income: income, expense: -expense);
  }
}
