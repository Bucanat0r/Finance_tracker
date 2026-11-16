import 'package:drift/drift.dart';

import 'app_database.dart';
import 'tables.dart';

// ---------------------------------------------------------------------------
// DATABASE QUERIES FOR BANK ALERTS
//
// Like the other *_queries.dart files, this is an extension on AppDatabase.
//
// NOTE: "smsSenderId" on an account now holds the BANK KEY of the parser
// that feeds it (for example "uba"), not the phone's sender name. We match
// alerts by the layout of the message, which is more reliable than a sender
// name that banks sometimes change.
// ---------------------------------------------------------------------------

extension AlertQueries on AppDatabase {
  // -------------------------------------------------------------------------
  // LINKING A BANK TO AN ACCOUNT
  // -------------------------------------------------------------------------

  /// The account that receives this bank's alerts, or null if none yet.
  Future<Account?> accountForBank(String bankKey) {
    return (select(accounts)
          ..where(
            (a) => a.smsSenderId.equals(bankKey) & a.archived.equals(false),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// Makes [accountId] the account for this bank. Only one account can hold
  /// a bank at a time, so any other is cleared first, all in one step.
  Future<void> linkAccountToBank(int accountId, String bankKey) async {
    await transaction(() async {
      await (update(accounts)..where((a) => a.smsSenderId.equals(bankKey)))
          .write(const AccountsCompanion(smsSenderId: Value<String?>(null)));
      await (update(accounts)..where((a) => a.id.equals(accountId))).write(
        AccountsCompanion(smsSenderId: Value(bankKey)),
      );
    });
  }

  Future<void> unlinkBank(String bankKey) async {
    await (update(accounts)..where((a) => a.smsSenderId.equals(bankKey))).write(
      const AccountsCompanion(smsSenderId: Value<String?>(null)),
    );
  }

  // -------------------------------------------------------------------------
  // THE RAW INBOX
  // -------------------------------------------------------------------------

  /// True if the same text is already waiting or has already failed. Stops
  /// the same unreadable or unlinked alert from piling up in the inbox.
  Future<bool> openRawMessageExists(String sender, String body) async {
    final found =
        await (select(rawMessages)
              ..where(
                (r) =>
                    r.sender.equals(sender) &
                    r.body.equals(body) &
                    (r.status.equalsValue(RawStatus.pending) |
                        r.status.equalsValue(RawStatus.failed)),
              )
              ..limit(1))
            .get();
    return found.isNotEmpty;
  }

  Future<int> insertRawMessage({
    required String sender,
    required String body,
    required DateTime receivedAt,
    required RawStatus status,
    String? errorNote,
  }) {
    return into(rawMessages).insert(
      RawMessagesCompanion.insert(
        sender: sender,
        body: body,
        receivedAt: receivedAt,
        status: Value(status),
        errorNote: Value(errorNote),
      ),
    );
  }

  Future<void> setRawStatus(int id, RawStatus status, {String? errorNote}) {
    return (update(rawMessages)..where((r) => r.id.equals(id))).write(
      RawMessagesCompanion(status: Value(status), errorNote: Value(errorNote)),
    );
  }

  /// Alerts that were saved but could not be turned into transactions yet
  /// (for example because no account was linked at the time).
  Future<List<RawMessage>> pendingRawMessages() {
    return (select(rawMessages)
          ..where((r) => r.status.equalsValue(RawStatus.pending))
          ..orderBy([(r) => OrderingTerm.asc(r.receivedAt)]))
        .get();
  }

  /// A live list of the most recent saved alerts, newest first.
  Stream<List<RawMessage>> watchRecentRawMessages({int limit = 30}) {
    return (select(rawMessages)
          ..orderBy([
            (r) => OrderingTerm.desc(r.receivedAt),
            (r) => OrderingTerm.desc(r.id),
          ])
          ..limit(limit))
        .watch();
  }

  // -------------------------------------------------------------------------
  // CREATING TRANSACTIONS FROM ALERTS
  // -------------------------------------------------------------------------

  /// True if a transaction with this duplicate-detection key already exists.
  Future<bool> dedupeKeyExists(String key) async {
    final found =
        await (select(transactions)
              ..where((t) => t.dedupeKey.equals(key))
              ..limit(1))
            .get();
    return found.isNotEmpty;
  }

  /// The id of the category with this name and kind, or null if none.
  Future<int?> categoryIdByName(String name, TxnKind kind) async {
    final found =
        await (select(categories)
              ..where(
                (c) =>
                    c.kind.equalsValue(kind) &
                    c.name.lower().equals(name.toLowerCase()),
              )
              ..limit(1))
            .getSingleOrNull();
    return found?.id;
  }

  /// Saves a transaction that came from a bank alert.
  /// [amountKobo] is SIGNED here (debits negative), exactly as stored.
  Future<int> insertAlertTransaction({
    required int accountId,
    int? categoryId,
    required int amountKobo,
    required TxnKind kind,
    required DateTime occurredAt,
    required String narration,
    int? balanceAfterKobo,
    required String dedupeKey,
    int? rawMessageId,
  }) {
    return into(transactions).insert(
      TransactionsCompanion.insert(
        accountId: accountId,
        categoryId: Value(categoryId),
        amountKobo: amountKobo,
        kind: kind,
        occurredAt: occurredAt,
        narration: Value(narration),
        source: const Value(TxnSource.sms),
        balanceAfterKobo: Value(balanceAfterKobo),
        dedupeKey: Value(dedupeKey),
        rawMessageId: Value(rawMessageId),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // CHECKING THE BALANCE AGAINST THE BANK'S
  // -------------------------------------------------------------------------

  /// The balance printed in the NEWEST alert for this account, with the time
  /// of that alert. Null if no alert with a balance exists.
  Future<({int balanceKobo, DateTime at})?> latestAlertBalance(
    int accountId,
  ) async {
    final row =
        await (select(transactions)
              ..where(
                (t) =>
                    t.accountId.equals(accountId) &
                    t.source.equalsValue(TxnSource.sms) &
                    t.balanceAfterKobo.isNotNull(),
              )
              ..orderBy([
                (t) => OrderingTerm.desc(t.occurredAt),
                (t) => OrderingTerm.desc(t.id),
              ])
              ..limit(1))
            .getSingleOrNull();

    if (row == null) return null;
    return (balanceKobo: row.balanceAfterKobo!, at: row.occurredAt);
  }

  /// Moves an account's opening balance up or down by [deltaKobo].
  Future<void> adjustOpeningBalance(int accountId, int deltaKobo) async {
    final account = await (select(
      accounts,
    )..where((a) => a.id.equals(accountId))).getSingle();

    await (update(accounts)..where((a) => a.id.equals(accountId))).write(
      AccountsCompanion(
        openingBalanceKobo: Value(account.openingBalanceKobo + deltaKobo),
      ),
    );
  }
}
