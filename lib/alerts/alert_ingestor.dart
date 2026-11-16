import '../data/alert_queries.dart';
import '../data/database_instance.dart';
import '../data/tables.dart';
import '../utils/formatters.dart';
import 'alert_parser.dart';
import 'alert_settings.dart';
import 'uba_parser.dart';

/// What happened to a message we were given.
enum IngestStatus {
  /// A transaction was created.
  imported,

  /// We had already recorded this alert.
  duplicate,

  /// Not a bank alert (a one-time password, a chat...). Nothing was saved.
  notAnAlert,

  /// It looks like an alert but could not be read. Saved for review.
  failed,

  /// No account is linked to that bank yet. Saved to import later.
  needsAccount,
}

class IngestResult {
  const IngestResult(this.status, this.message);

  final IngestStatus status;

  /// A sentence for the screen.
  final String message;
}

/// Turns incoming bank alerts into transactions.
///
/// The same code handles an alert arriving from Android, one you paste, and
/// old alerts being retried, so they can never behave differently.
class AlertIngestor {
  // Only static methods, so nobody should create an instance.
  AlertIngestor._();

  /// Every bank we can read. To support a new bank, write a parser for it
  /// and add it to this list.
  static const List<AlertParser> parsers = [UbaParser()];

  static AlertParser? _parserFor(String body) {
    for (final p in parsers) {
      if (p.canParse(body)) return p;
    }
    return null;
  }

  /// Handles one message.
  static Future<IngestResult> ingest({
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    return _process(sender: sender, body: body, receivedAt: receivedAt);
  }

  /// Retries every saved alert that was waiting (for example after you link
  /// an account). Returns how many became transactions.
  static Future<int> reprocessPending() async {
    final waiting = await db.pendingRawMessages();
    var imported = 0;
    for (final raw in waiting) {
      final result = await _process(
        sender: raw.sender,
        body: raw.body,
        receivedAt: raw.receivedAt,
        rawId: raw.id,
      );
      if (result.status == IngestStatus.imported) imported++;
    }
    return imported;
  }

  // -------------------------------------------------------------------------
  // THE PIPELINE
  // -------------------------------------------------------------------------

  /// [rawId] is set only when retrying a message that is already saved in
  /// the inbox, so we update that row instead of adding a second copy.
  static Future<IngestResult> _process({
    required String sender,
    required String body,
    required DateTime receivedAt,
    int? rawId,
  }) async {
    // 1. Is this a bank alert at all? If not, we save NOTHING, so one-time
    //    passwords and private chats never end up in the app's database.
    final parser = _parserFor(body);
    if (parser == null) {
      if (rawId != null) await db.setRawStatus(rawId, RawStatus.ignored);
      return const IngestResult(
        IngestStatus.notAnAlert,
        'That does not look like a supported bank alert, so it was ignored.',
      );
    }

    // 2. Read it. If it looks like an alert but cannot be read, keep the
    //    original text, so the parser can be fixed and the alert retried.
    final alert = parser.parse(body);
    if (alert == null) {
      const note = 'Could not read this alert.';
      if (rawId != null) {
        await db.setRawStatus(rawId, RawStatus.failed, errorNote: note);
      } else if (!await db.openRawMessageExists(sender, body)) {
        await db.insertRawMessage(
          sender: sender,
          body: body,
          receivedAt: receivedAt,
          status: RawStatus.failed,
          errorNote: note,
        );
      }
      return IngestResult(
        IngestStatus.failed,
        'It looks like a ${parser.bankName} alert, but I could not read it. '
        'It was saved so the parser can be fixed.',
      );
    }

    // 3. Already recorded? (The same alert can arrive twice: once by SMS and
    //    again from an import, or you paste one you already have.)
    final key = _dedupeKey(alert);
    if (await db.dedupeKeyExists(key)) {
      if (rawId != null) {
        await db.setRawStatus(
          rawId,
          RawStatus.parsed,
          errorNote: 'Duplicate of a transaction already recorded.',
        );
      }
      return const IngestResult(
        IngestStatus.duplicate,
        'That alert was already recorded.',
      );
    }

    // 4. Which account does this bank feed? If none is linked, keep the
    //    alert and wait.
    final account = await db.accountForBank(alert.bankKey);
    if (account == null) {
      if (rawId == null && !await db.openRawMessageExists(sender, body)) {
        await db.insertRawMessage(
          sender: sender,
          body: body,
          receivedAt: receivedAt,
          status: RawStatus.pending,
          errorNote: 'No account is linked to ${parser.bankName} yet.',
        );
      }
      return IngestResult(
        IngestStatus.needsAccount,
        'Link an account to ${parser.bankName} first. The alert is saved and '
        'will be imported once you do.',
      );
    }

    // 5. Does it mention your own name? Then it is probably money moving
    //    between your own accounts: save it as a transfer, which income,
    //    expense, budget and report calculations all skip.
    final myNames = await AlertSettings.myNames();
    final isOwnTransfer = matchesAnyName(alert.description, myNames);
    final kind = isOwnTransfer ? TxnKind.transfer : alert.kind;

    // 6. A guessed category (never for transfers).
    int? categoryId;
    if (!isOwnTransfer) {
      final name = suggestCategoryName(alert.description, alert.kind);
      if (name != null)
        categoryId = await db.categoryIdByName(name, alert.kind);
    }

    // 7. Save the raw alert and the transaction TOGETHER: either both are
    //    written or neither, so they can never get out of step.
    await db.transaction(() async {
      final savedRawId =
          rawId ??
          await db.insertRawMessage(
            sender: sender,
            body: body,
            receivedAt: receivedAt,
            status: RawStatus.parsed,
          );
      if (rawId != null) await db.setRawStatus(rawId, RawStatus.parsed);

      await db.insertAlertTransaction(
        accountId: account.id,
        categoryId: categoryId,
        amountKobo: alert.signedKobo,
        kind: kind,
        occurredAt: alert.occurredAt,
        narration: alert.description,
        balanceAfterKobo: alert.balanceKobo,
        dedupeKey: key,
        rawMessageId: savedRawId,
      );
    });

    final label = isOwnTransfer
        ? 'a transfer between your own accounts'
        : (alert.kind == TxnKind.expense ? 'an expense' : 'income');
    return IngestResult(
      IngestStatus.imported,
      'Saved ${formatNaira(alert.amountKobo)} as $label: ${alert.description}',
    );
  }

  /// A fingerprint of one alert, used to spot the same alert arriving twice.
  ///
  /// With a bank reference code the key is the code plus the amount.
  /// Without one, it is built from the account, direction, amount, minute
  /// and printed balance. The balance matters: two identical payments in the
  /// same minute leave different balances, so they are not mistaken for one.
  static String _dedupeKey(ParsedAlert a) {
    final ref = a.reference;
    if (ref != null) return '${a.bankKey}:ref:$ref:${a.amountKobo}';

    String two(int n) => n.toString().padLeft(2, '0');
    final t = a.occurredAt;
    final stamp =
        '${t.year}${two(t.month)}${two(t.day)}${two(t.hour)}${two(t.minute)}';

    return '${a.bankKey}:${a.accountHint}:${a.kind.name}:${a.amountKobo}'
        ':$stamp:${a.balanceKobo ?? ''}';
  }
}
