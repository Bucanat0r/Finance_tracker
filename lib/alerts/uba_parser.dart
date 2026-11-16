import '../data/tables.dart';
import 'alert_parser.dart';

/// Reads UBA debit/credit SMS alerts, which look like this (fake data):
///
///   Txn:DR
///   Ac:2XX..91X
///   Amt:NGN 30,026.88
///   Des:LEO/SBW/UTO/ADA
///   OKAFOR
///   Date:16-11-2026 10:30
///   Bal:NGN 61,020.91
///   Loan? Dial *919*28#
///
/// Things the layout taught us:
///  - The description can wrap onto extra lines, until the "Date:" line.
///  - Some alerts put a long reference code on its own extra line.
///  - Some phones flatten the line breaks into spaces, so none of the
///    patterns below depend on a line break being present.
class UbaParser extends AlertParser {
  const UbaParser();

  @override
  String get bankKey => 'uba';

  @override
  String get bankName => 'UBA';

  // Each pattern finds one field. caseSensitive: false so "AMT:" works too.
  static final _txn = RegExp(r'Txn:\s*(DR|CR)\b', caseSensitive: false);
  static final _account = RegExp(r'Ac:\s*(\S+)', caseSensitive: false);
  static final _amount = RegExp(
    r'Amt:\s*NGN\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );
  static final _balance = RegExp(
    r'Bal:\s*NGN\s*(-?[\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );
  static final _date = RegExp(
    r'Date:\s*(\d{1,2})-(\d{1,2})-(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?',
    caseSensitive: false,
  );

  // Everything after "Des:" up to (but not including) the "Date:" part.
  // dotAll lets "." match line breaks; the "?" makes it stop at the FIRST
  // "Date:" instead of running to the end.
  static final _description = RegExp(
    r'Des:(.*?)(?=\s+Date:)',
    caseSensitive: false,
    dotAll: true,
  );

  @override
  bool canParse(String body) {
    // The signature of a UBA alert: a DR/CR marker and an NGN amount.
    return _txn.hasMatch(body) && _amount.hasMatch(body);
  }

  @override
  ParsedAlert? parse(String body) {
    final text = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final txn = _txn.firstMatch(text);
    final amount = _amount.firstMatch(text);
    final date = _date.firstMatch(text);
    if (txn == null || amount == null || date == null) return null;

    final amountKobo = parseKobo(amount.group(1)!);
    if (amountKobo == null || amountKobo <= 0) return null;

    final occurredAt = _parseDate(date);
    if (occurredAt == null) return null;

    // The balance is a bonus: an alert without one is still usable.
    final balanceMatch = _balance.firstMatch(text);
    final balanceKobo = balanceMatch == null
        ? null
        : parseKobo(balanceMatch.group(1)!);

    // Split the description into words. A long mix of letters AND digits is
    // the bank's reference code; everything else is the description.
    String? reference;
    final descriptionWords = <String>[];
    final rawDescription = _description.firstMatch(text)?.group(1) ?? '';
    for (final word in rawDescription.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      if (reference == null && _looksLikeReference(word)) {
        reference = word;
      } else {
        descriptionWords.add(word);
      }
    }
    var description = descriptionWords.join(' ');
    if (description.isEmpty) description = 'UBA transaction';

    final isDebit = txn.group(1)!.toUpperCase() == 'DR';

    return ParsedAlert(
      bankKey: bankKey,
      kind: isDebit ? TxnKind.expense : TxnKind.income,
      amountKobo: amountKobo,
      description: description,
      occurredAt: occurredAt,
      accountHint: _account.firstMatch(text)?.group(1) ?? '',
      balanceKobo: balanceKobo,
      reference: reference,
    );
  }

  /// 16+ letters and digits, containing BOTH. Phone numbers (digits only)
  /// and names (letters only) are not references.
  static bool _looksLikeReference(String word) {
    return RegExp(r'^[A-Za-z0-9]{16,}$').hasMatch(word) &&
        word.contains(RegExp(r'[A-Za-z]')) &&
        word.contains(RegExp(r'\d'));
  }

  /// Builds the date, or returns null if it is impossible (like 31-02).
  static DateTime? _parseDate(RegExpMatch m) {
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final year = int.parse(m.group(3)!);
    final hour = int.parse(m.group(4)!);
    final minute = int.parse(m.group(5)!);
    final second = m.group(6) == null ? 0 : int.parse(m.group(6)!);

    final when = DateTime(year, month, day, hour, minute, second);

    // DateTime silently rolls impossible dates over (31 Feb becomes 3 Mar).
    // If any part changed, the original was invalid, so reject it.
    if (when.year != year ||
        when.month != month ||
        when.day != day ||
        when.hour != hour ||
        when.minute != minute) {
      return null;
    }
    return when;
  }
}
