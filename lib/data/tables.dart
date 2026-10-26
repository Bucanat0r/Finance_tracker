import 'package:drift/drift.dart';

// ---------------------------------------------------------------------------
// ENUMS
// Drift stores these as integers in the database. We use enums in code so the
// compiler stops us from typing a wrong value like "expnse".
// IMPORTANT: never reorder or delete existing values later, because the
// database stores their position (0, 1, 2...). Only add new ones at the end.
// ---------------------------------------------------------------------------

/// What kind of account this is. A credit card behaves differently from the
/// others: its balance is money you OWE, not money you have.
enum AccountType { bank, wallet, creditCard, cash }

/// What a transaction represents. "transfer" is money moved between two of
/// your own accounts. It must NOT count as income or expense, otherwise your
/// spending would look doubled.
enum TxnKind { income, expense, transfer }

/// Where a transaction came from, so we can trust or review it differently.
enum TxnSource { manual, sms, notification, statementImport }

/// Life cycle of a raw bank alert in the inbox table.
enum RawStatus { pending, parsed, ignored, failed }

// ---------------------------------------------------------------------------
// ACCOUNTS
// ---------------------------------------------------------------------------
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 60)();

  IntColumn get type => intEnum<AccountType>()();

  // MONEY RULE: all amounts are whole numbers of KOBO (1 naira = 100 kobo).
  // Never use double for money: 0.1 + 0.2 != 0.3 in floating point, so totals
  // would slowly drift. Integers are exact.
  //
  // Balance is NEVER stored. It is always computed as:
  //   openingBalanceKobo + sum(all transactions for this account)
  // Why: if we stored the balance too, it could disagree with the transactions
  // after an edit or a deleted row. With a ledger there is only one truth.
  IntColumn get openingBalanceKobo =>
      integer().withDefault(const Constant(0))();

  // Only meaningful for credit cards. Null for everything else.
  IntColumn get creditLimitKobo => integer().nullable()();

  // The sender ID bank SMS arrive from (e.g. the name shown in your messages
  // app). Later, the parser uses this to know which bank an alert belongs to.
  TextColumn get smsSenderId => text().nullable()();

  // "Archived" hides an account without deleting its history.
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ---------------------------------------------------------------------------
// CATEGORIES
// ---------------------------------------------------------------------------
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 40)();

  // Income categories (Salary) and expense categories (Food) are kept apart
  // so the budget and profit/loss screens can group them correctly.
  IntColumn get kind => intEnum<TxnKind>()();

  // Colour stored as an ARGB int, e.g. 0xFF4CAF50. Used for charts later.
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF9E9E9E))();

  @override
  List<Set<Column>> get uniqueKeys => [
    // Prevent two categories with the same name and kind.
    {name, kind},
  ];
}

// ---------------------------------------------------------------------------
// RAW MESSAGES (the "inbox")
// Every bank alert is saved here FIRST, exactly as received, before we try to
// parse it. Why: if the parser has a bug or sees a new alert format, we never
// lose the original text and can re-run the parser after fixing it.
// ---------------------------------------------------------------------------
class RawMessages extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get sender => text()();

  TextColumn get body => text()();

  DateTimeColumn get receivedAt => dateTime()();

  IntColumn get status =>
      intEnum<RawStatus>().withDefault(Constant(RawStatus.pending.index))();

  // Why parsing failed, so the "needs review" screen can explain it.
  TextColumn get errorNote => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    // Importing your old SMS history twice must not create duplicates.
    {sender, body, receivedAt},
  ];
}

// ---------------------------------------------------------------------------
// TRANSACTIONS (the ledger)
// ---------------------------------------------------------------------------
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  // If an account is deleted, its transactions go too (cascade). Normally we
  // archive accounts instead, so this is a safety net.
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();

  // Nullable: a freshly parsed alert has no category until a rule or you
  // assign one. If a category is deleted, transactions keep existing
  // (set null), because losing financial history would be worse.
  IntColumn get categoryId => integer().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();

  // SIGNED amount in kobo: credits are positive, debits are negative.
  // Why signed: balance = opening + SUM(amount) becomes one simple query, and
  // there is no separate "direction" column that could disagree with the sign.
  IntColumn get amountKobo => integer()();

  IntColumn get kind => intEnum<TxnKind>()();

  // The bank's description of the transaction (the "narration").
  TextColumn get narration => text().withDefault(const Constant(''))();

  // When the money actually moved (not when we saved the row).
  DateTimeColumn get occurredAt => dateTime()();

  IntColumn get source =>
      intEnum<TxnSource>().withDefault(Constant(TxnSource.manual.index))();

  // The balance printed in the bank alert, if it had one. Used as a
  // checkpoint: if it disagrees with our computed balance, we missed a
  // transaction. Null when the alert has no balance.
  IntColumn get balanceAfterKobo => integer().nullable()();

  // Used to detect the same transaction arriving twice (e.g. SMS and a
  // statement import). Unique, but null is allowed for manual entries.
  TextColumn get dedupeKey => text().nullable().unique()();

  // Link back to the raw alert this came from, for traceability.
  IntColumn get rawMessageId => integer().nullable().references(
    RawMessages,
    #id,
    onDelete: KeyAction.setNull,
  )();

  // True when the parser was unsure and wants you to check it.
  BoolColumn get needsReview => boolean().withDefault(const Constant(false))();

  // For transfers: both sides of one transfer share the same group id, so we
  // can show them as one item and exclude them from spending totals.
  TextColumn get transferGroupId => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ---------------------------------------------------------------------------
// BUDGETS
// One row = "I want to spend at most X on this category in this month".
// ---------------------------------------------------------------------------
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();

  IntColumn get year => integer()();

  // 1 = January ... 12 = December.
  IntColumn get month => integer()();

  IntColumn get limitKobo => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
    // Only one budget per category per month.
    {categoryId, year, month},
  ];
}
