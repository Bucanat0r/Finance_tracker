import '../data/tables.dart';

// ---------------------------------------------------------------------------
// THE COMMON PART OF EVERY BANK PARSER
//
// Each bank words its alerts differently, so each gets its own small parser
// (uba_parser.dart is the first). They all produce the same result type
// below, so everything after parsing (saving, dedupe, categories) is shared.
// ---------------------------------------------------------------------------

/// What we managed to read out of one bank alert.
class ParsedAlert {
  const ParsedAlert({
    required this.bankKey,
    required this.kind,
    required this.amountKobo,
    required this.description,
    required this.occurredAt,
    required this.accountHint,
    this.balanceKobo,
    this.reference,
  });

  /// Which bank this came from, e.g. "uba".
  final String bankKey;

  /// Income (credit) or expense (debit). Never "transfer": deciding that
  /// needs your own name, which is done later in the ingestor.
  final TxnKind kind;

  /// Always POSITIVE kobo, as printed in the alert.
  final int amountKobo;

  final String description;
  final DateTime occurredAt;

  /// The masked account text from the alert, kept only for building a
  /// duplicate-detection key.
  final String accountHint;

  /// The balance printed in the alert, when it has one.
  final int? balanceKobo;

  /// The bank's reference code, when the alert has one.
  final String? reference;

  /// The amount as stored in the ledger: debits negative, credits positive.
  int get signedKobo => kind == TxnKind.expense ? -amountKobo : amountKobo;
}

/// Reads one bank's alerts.
abstract class AlertParser {
  const AlertParser();

  /// Short key saved on the linked account, e.g. "uba".
  String get bankKey;

  /// Name shown to the user, e.g. "UBA".
  String get bankName;

  /// A quick check: does this text LOOK like one of this bank's alerts?
  /// Messages that do not (one-time passwords, promotions, chats) are
  /// ignored and never saved, so the app does not hoard private messages.
  bool canParse(String body);

  /// Reads the alert, or returns null if a needed part is missing.
  ParsedAlert? parse(String body);
}

// ---------------------------------------------------------------------------
// SHARED HELPERS
// ---------------------------------------------------------------------------

/// Reads an amount like "30,026.88" or "-50.5" and returns whole kobo.
/// Returns null if it is not a valid amount.
///
/// Why not double.parse: doubles cannot hold values like 0.1 exactly, which
/// would put tiny errors into money. This uses only whole-number maths.
int? parseKobo(String input) {
  // Remove commas and spaces: "30,026.88" -> "30026.88".
  var text = input.replaceAll(RegExp(r'[,\s]'), '');

  var negative = false;
  if (text.startsWith('-')) {
    negative = true;
    text = text.substring(1);
  }

  // Digits, optionally followed by a dot and one or two decimals.
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) return null;

  final parts = text.split('.');
  final whole = int.parse(parts[0]);
  // "50.5" means 50 kobo, not 5, so pad the decimals to two digits.
  final cents = parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0;

  final value = whole * 100 + cents;
  return negative ? -value : value;
}

/// Guesses a category NAME from the description, or null if unsure.
///
/// This is deliberately small and cautious: a wrong guess is worse than no
/// guess, because you can always set a category yourself. The names must
/// match your category names exactly; if you have renamed one, the guess
/// simply finds nothing and the transaction stays uncategorised.
String? suggestCategoryName(String description, TxnKind kind) {
  final d = description.toUpperCase();
  bool has(List<String> words) => words.any(d.contains);

  if (kind == TxnKind.expense) {
    if (has([
      'TOPUP',
      'TOP-UP',
      'TOP UP',
      'AIRTIME',
      'DATA PLAN',
      'DATA BUNDLE',
    ])) {
      return 'Airtime & data';
    }
    if (has([
      'CHARGE',
      'COMMISSION',
      'STAMP DUTY',
      'SMS ALERT',
      'MAINTENANCE FEE',
    ])) {
      return 'Bank charges';
    }
    if (has(['UBER', 'BOLT', 'INDRIVE'])) return 'Transport';
    if (has(['DSTV', 'GOTV', 'STARTIMES', 'ELECTRICITY', 'IKEDC', 'EKEDC'])) {
      return 'Bills & utilities';
    }
  }

  if (kind == TxnKind.income) {
    if (has(['SALARY', 'PAYROLL'])) return 'Salary';
  }

  return null;
}

/// True if the description contains one of YOUR names, which usually means
/// the money moved between your own accounts.
///
/// A name only counts if it has at least TWO words, and every word appears
/// (in any order, as a whole word). A one-word name like "JOHN" would match
/// far too many unrelated people.
bool matchesAnyName(String description, List<String> names) {
  List<String> words(String text) =>
      RegExp(r'[A-Z0-9]+')
          .allMatches(text.toUpperCase())
          .map((m) => m.group(0)!)
          .toList();

  final inDescription = words(description).toSet();

  for (final name in names) {
    final nameWords = words(name);
    if (nameWords.length >= 2 && nameWords.every(inDescription.contains)) {
      return true;
    }
  }
  return false;
}
