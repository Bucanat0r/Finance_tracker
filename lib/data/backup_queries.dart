import 'package:drift/drift.dart';

import 'app_database.dart';
import 'tables.dart';

// ---------------------------------------------------------------------------
// BACKUP AND RESTORE (the database side)
//
// A backup is one JSON file holding every table. Like the other
// *_queries.dart files, the database methods are an extension on AppDatabase.
//
// Two design choices worth knowing:
//  1. Enums (account type, transaction kind...) are saved by NAME, such as
//     "expense", not by position (1). If we ever reorder or add enum values,
//     old backups still restore correctly.
//  2. The "version" number lets a future version of the app change the
//     format and still read old backups.
// ---------------------------------------------------------------------------

/// Written into every backup so we can tell it is ours.
const String backupFormat = 'finance_tracker_backup';

/// The backup layout version. Bump it if the layout changes.
const int backupVersion = 1;

/// A problem with a backup file that we can explain to the user in words.
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What is inside a backup file, shown before you confirm a restore.
class BackupSummary {
  const BackupSummary({
    required this.exportedAt,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.budgets,
  });

  final DateTime? exportedAt;
  final int accounts;
  final int categories;
  final int transactions;
  final int budgets;
}

/// Checks that decoded JSON really is one of our backups. Returns it as a
/// map, or throws a [BackupException] saying what is wrong.
Map<String, dynamic> validateBackup(Object? decoded) {
  if (decoded is! Map<String, dynamic> || decoded['format'] != backupFormat) {
    throw const BackupException('That file is not a Finance Tracker backup.');
  }

  final version = decoded['version'];
  if (version is! int) {
    throw const BackupException('That backup file is damaged.');
  }
  if (version > backupVersion) {
    throw const BackupException(
      'That backup was made by a newer version of the app. Update the app first.',
    );
  }

  // Every table must be present, even if empty.
  for (final key in [
    'accounts',
    'categories',
    'rawMessages',
    'transactions',
    'budgets',
  ]) {
    if (decoded[key] is! List) {
      throw const BackupException('That backup file is incomplete.');
    }
  }
  return decoded;
}

/// Counts what is inside a validated backup.
BackupSummary summarizeBackup(Map<String, dynamic> data) {
  return BackupSummary(
    exportedAt: DateTime.tryParse((data['exportedAt'] as String?) ?? '')
        ?.toLocal(),
    accounts: (data['accounts'] as List).length,
    categories: (data['categories'] as List).length,
    transactions: (data['transactions'] as List).length,
    budgets: (data['budgets'] as List).length,
  );
}

extension BackupQueries on AppDatabase {
  /// Reads every table and returns it as a JSON-friendly map.
  Future<Map<String, dynamic>> exportBackup() async {
    final accountRows = await select(accounts).get();
    final categoryRows = await select(categories).get();
    final rawRows = await select(rawMessages).get();
    final txnRows = await select(transactions).get();
    final budgetRows = await select(budgets).get();

    // Dates are saved as UTC text (ISO 8601), which is unambiguous and
    // survives a change of phone or time zone.
    String iso(DateTime d) => d.toUtc().toIso8601String();

    return {
      'format': backupFormat,
      'version': backupVersion,
      'exportedAt': iso(DateTime.now()),
      'accounts': [
        for (final a in accountRows)
          {
            'id': a.id,
            'name': a.name,
            'type': a.type.name,
            'openingBalanceKobo': a.openingBalanceKobo,
            'creditLimitKobo': a.creditLimitKobo,
            'smsSenderId': a.smsSenderId,
            'archived': a.archived,
            'createdAt': iso(a.createdAt),
          },
      ],
      'categories': [
        for (final c in categoryRows)
          {
            'id': c.id,
            'name': c.name,
            'kind': c.kind.name,
            'colorValue': c.colorValue,
          },
      ],
      'rawMessages': [
        for (final r in rawRows)
          {
            'id': r.id,
            'sender': r.sender,
            'body': r.body,
            'receivedAt': iso(r.receivedAt),
            'status': r.status.name,
            'errorNote': r.errorNote,
          },
      ],
      'transactions': [
        for (final t in txnRows)
          {
            'id': t.id,
            'accountId': t.accountId,
            'categoryId': t.categoryId,
            'amountKobo': t.amountKobo,
            'kind': t.kind.name,
            'narration': t.narration,
            'occurredAt': iso(t.occurredAt),
            'source': t.source.name,
            'balanceAfterKobo': t.balanceAfterKobo,
            'dedupeKey': t.dedupeKey,
            'rawMessageId': t.rawMessageId,
            'needsReview': t.needsReview,
            'transferGroupId': t.transferGroupId,
            'createdAt': iso(t.createdAt),
          },
      ],
      'budgets': [
        for (final b in budgetRows)
          {
            'id': b.id,
            'categoryId': b.categoryId,
            'year': b.year,
            'month': b.month,
            'limitKobo': b.limitKobo,
          },
      ],
    };
  }

  /// Replaces ALL data in the app with the contents of a backup.
  ///
  /// Everything happens inside one database "transaction": if anything goes
  /// wrong halfway (a damaged file, a missing field), the database rolls
  /// back and your current data is left exactly as it was. You can never
  /// end up half-restored.
  ///
  /// The original ids are kept, because rows point at each other by id
  /// (a transaction points at its account and category). Tables are filled
  /// in an order where every row's targets already exist.
  Future<void> restoreBackup(Map<String, dynamic> data) async {
    // Small helper: read a list of rows out of the backup.
    List<Map<String, dynamic>> rows(String key) =>
        (data[key] as List).cast<Map<String, dynamic>>();

    DateTime date(Object? v) => DateTime.parse(v as String);

    await transaction(() async {
      // 1. Wipe, in an order that never leaves a row pointing at nothing:
      //    rows that POINT at others go first.
      await delete(transactions).go();
      await delete(budgets).go();
      await delete(rawMessages).go();
      await delete(categories).go();
      await delete(accounts).go();

      // 2. Refill, in the opposite order: rows that are POINTED AT go first.
      await batch((b) {
        b.insertAll(accounts, [
          for (final m in rows('accounts'))
            AccountsCompanion.insert(
              id: Value(m['id'] as int),
              name: m['name'] as String,
              type: AccountType.values.byName(m['type'] as String),
              openingBalanceKobo: Value(m['openingBalanceKobo'] as int),
              creditLimitKobo: Value(m['creditLimitKobo'] as int?),
              smsSenderId: Value(m['smsSenderId'] as String?),
              archived: Value(m['archived'] as bool),
              createdAt: Value(date(m['createdAt'])),
            ),
        ]);

        b.insertAll(categories, [
          for (final m in rows('categories'))
            CategoriesCompanion.insert(
              id: Value(m['id'] as int),
              name: m['name'] as String,
              kind: TxnKind.values.byName(m['kind'] as String),
              colorValue: Value(m['colorValue'] as int),
            ),
        ]);

        b.insertAll(rawMessages, [
          for (final m in rows('rawMessages'))
            RawMessagesCompanion.insert(
              id: Value(m['id'] as int),
              sender: m['sender'] as String,
              body: m['body'] as String,
              receivedAt: date(m['receivedAt']),
              status: Value(RawStatus.values.byName(m['status'] as String)),
              errorNote: Value(m['errorNote'] as String?),
            ),
        ]);

        b.insertAll(transactions, [
          for (final m in rows('transactions'))
            TransactionsCompanion.insert(
              id: Value(m['id'] as int),
              accountId: m['accountId'] as int,
              categoryId: Value(m['categoryId'] as int?),
              amountKobo: m['amountKobo'] as int,
              kind: TxnKind.values.byName(m['kind'] as String),
              narration: Value(m['narration'] as String),
              occurredAt: date(m['occurredAt']),
              source: Value(TxnSource.values.byName(m['source'] as String)),
              balanceAfterKobo: Value(m['balanceAfterKobo'] as int?),
              dedupeKey: Value(m['dedupeKey'] as String?),
              rawMessageId: Value(m['rawMessageId'] as int?),
              needsReview: Value(m['needsReview'] as bool),
              transferGroupId: Value(m['transferGroupId'] as String?),
              createdAt: Value(date(m['createdAt'])),
            ),
        ]);

        b.insertAll(budgets, [
          for (final m in rows('budgets'))
            BudgetsCompanion.insert(
              id: Value(m['id'] as int),
              categoryId: m['categoryId'] as int,
              year: m['year'] as int,
              month: m['month'] as int,
              limitKobo: m['limitKobo'] as int,
            ),
        ]);
      });
    });
  }
}
