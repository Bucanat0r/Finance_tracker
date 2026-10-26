// ---------------------------------------------------------------------------
// Small helpers for showing and reading money and dates.
// Money is always stored as whole kobo (1 naira = 100 kobo). These helpers
// are the ONLY place where we convert between kobo and text.
// ---------------------------------------------------------------------------

/// Turns kobo into text for the screen, e.g. 123450 -> "₦1,234.50".
/// Negative amounts get a minus sign in front: -50000 -> "-₦500.00".
String formatNaira(int kobo) {
  final sign = kobo < 0 ? '-' : '';
  final abs = kobo.abs();

  // Whole naira part, with a comma inserted every three digits.
  // The regex finds each position that has a multiple of 3 digits after it.
  final whole = (abs ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );

  // Kobo part, always two digits ("5" becomes "05").
  final cents = (abs % 100).toString().padLeft(2, '0');

  // \u20A6 is the naira sign.
  return '$sign\u20A6$whole.$cents';
}

/// Reads what the user typed ("2500", "2,500.50", "₦2500.5") and returns kobo.
/// Returns null if the text is not a valid amount.
///
/// Why this does not use double.parse: doubles cannot represent values like
/// 0.1 exactly, which would put tiny errors into money. Here we split the
/// text on the dot and work only with whole numbers.
int? parseNairaToKobo(String input) {
  // Remove commas, spaces and the naira sign so "₦ 2,500" still works.
  final cleaned = input.replaceAll(RegExp(r'[,\s\u20A6]'), '');

  // Accept digits with an optional dot and at most two decimal places.
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(cleaned)) return null;

  final parts = cleaned.split('.');
  final whole = int.parse(parts[0]);

  // "2500.5" means 50 kobo, not 5, so pad the decimals to two digits.
  final cents = parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0;

  return whole * 100 + cents;
}

/// Formats a date like "26 Oct 2026". Written by hand so we do not need an
/// extra package yet.
String formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
