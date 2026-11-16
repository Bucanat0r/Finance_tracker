import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_database.dart';
import 'backup_queries.dart';
import 'database_instance.dart';
import 'tables.dart';

/// Creates the backup and CSV files and hands them to Android's share sheet.
///
/// Files are written to the app's private temporary folder first, then shared
/// from there. We do not delete them straight after sharing, because the app
/// you shared to (Google Drive, say) may still be reading the file.
class BackupService {
  // Only static methods, so nobody should create an instance.
  BackupService._();

  static const _storage = FlutterSecureStorage();
  static const _kLastBackup = 'last_backup_at';

  // -------------------------------------------------------------------------
  // LAST BACKUP TIME
  // -------------------------------------------------------------------------

  /// When you last shared a backup, or null if never.
  static Future<DateTime?> lastBackupAt() async {
    final text = await _storage.read(key: _kLastBackup);
    return text == null ? null : DateTime.tryParse(text)?.toLocal();
  }

  static Future<void> _markBackedUp() async {
    await _storage.write(
      key: _kLastBackup,
      value: DateTime.now().toUtc().toIso8601String(),
    );
  }

  // -------------------------------------------------------------------------
  // BACKUP FILE
  // -------------------------------------------------------------------------

  /// Builds the backup, writes it to a file, and opens the share sheet.
  /// Returns true if the share sheet was used (false if you backed out).
  static Future<bool> shareBackup() async {
    final data = await db.exportBackup();

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/finance_backup_${_today()}.json');
    await file.writeAsString(jsonEncode(data));

    final shared = await _share(file, 'Finance Tracker backup');
    if (shared) await _markBackedUp();
    return shared;
  }

  // -------------------------------------------------------------------------
  // CSV EXPORT (for Excel / Google Sheets)
  // -------------------------------------------------------------------------

  /// Writes every transaction to a CSV file and opens the share sheet.
  /// A CSV export is for LOOKING at your data elsewhere. It cannot be
  /// restored into the app; use the backup file for that.
  static Future<bool> shareCsv() async {
    // watchTransactions() is a live stream; .first takes a single snapshot.
    final rows = await db.watchTransactions().first;

    final buffer = StringBuffer();

    // A "byte order mark" at the very start tells Excel the file is UTF-8, so
    // accented letters and symbols display correctly.
    buffer.write('\uFEFF');
    buffer.writeln('Date,Account,Type,Category,Amount (NGN),Description');

    for (final r in rows) {
      final type = switch (r.kind) {
        TxnKind.income => 'Income',
        TxnKind.expense => 'Expense',
        TxnKind.transfer => 'Transfer',
      };

      buffer.writeln(
        [
          _csvDate(r.occurredAt),
          _csvText(r.accountName),
          type,
          _csvText(r.categoryName ?? ''),
          _csvNaira(r.amountKobo),
          _csvText(r.narration),
        ].join(','),
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/finance_transactions_${_today()}.csv');
    await file.writeAsString(buffer.toString());

    return _share(file, 'Finance Tracker transactions');
  }

  // -------------------------------------------------------------------------
  // INTERNAL HELPERS
  // -------------------------------------------------------------------------

  /// Opens the share sheet for one file. Returns false if you closed it
  /// without choosing anything.
  static Future<bool> _share(File file, String subject) async {
    final result = await SharePlus.instance.share(
      // API
      ShareParams(files: [XFile(file.path)], subject: subject),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  /// Today's date as 2026-11-14, for file names.
  static String _today() {
    final d = DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static String _csvDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// Kobo to a plain decimal for spreadsheets: -50000 -> "-500.00".
  /// Done with whole-number maths, never a double, so nothing is rounded.
  static String _csvNaira(int kobo) {
    final sign = kobo < 0 ? '-' : '';
    final abs = kobo.abs();
    final cents = (abs % 100).toString().padLeft(2, '0');
    return '$sign${abs ~/ 100}.$cents';
  }

  /// Makes text safe for one CSV cell.
  ///  - Cells with a comma, quote or line break are wrapped in quotes, and
  ///    quotes inside are doubled (the CSV rule).
  ///  - Text starting with = + - @ gets a leading apostrophe. Spreadsheets
  ///    treat such text as a formula, which could run something nasty if a
  ///    bank message ever contained one.
  static String _csvText(String value) {
    var text = value;
    if (text.isNotEmpty && '=+-@'.contains(text[0])) text = "'$text";

    final needsQuotes =
        text.contains(',') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r');
    if (!needsQuotes) return text;

    return '"${text.replaceAll('"', '""')}"';
  }
}
