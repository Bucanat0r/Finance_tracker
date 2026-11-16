import 'package:finance_tracker/alerts/alert_parser.dart';
import 'package:finance_tracker/alerts/uba_parser.dart';
import 'package:finance_tracker/data/tables.dart';
import 'package:flutter_test/flutter_test.dart';

// Fake alerts in the exact layout UBA uses. The names and numbers are
// invented.
const debitWrapped =
    'Txn:DR\n'
    'Ac:2XX..91X\n'
    'Amt:NGN 30,026.88\n'
    'Des:LEO/SBW/UTO/ADA\n'
    'OKAFOR\n'
    'Date:16-11-2026 10:30\n'
    'Bal:NGN 61,020.91\n'
    'Loan? Dial *919*28#';

const creditTransfer =
    'Txn:CR\n'
    'Ac:2XX..91X\n'
    'Amt:NGN 120,000.00\n'
    'Des:Outward Transfer to\n'
    'ADA OKAFOR CHIDI 0000\n'
    'Date:12-11-2026 13:28\n'
    'Bal:NGN 120,246.67\n'
    'Loan? Dial *919*28#';

const topupWithReference =
    'Txn:DR\n'
    'Ac:2XX..91X\n'
    'Amt:NGN 11,000.00\n'
    'Des:LEO TOPUP 9139260851\n'
    'AATU1411260020060624479926\n'
    'Date:14-11-2026 00:20\n'
    'Bal:NGN 101,246.67\n'
    'Loan? Dial *919*28#';

void main() {
  const parser = UbaParser();

  group('UbaParser', () {
    test('reads a debit whose description wraps onto a second line', () {
      final a = parser.parse(debitWrapped)!;

      expect(a.kind, TxnKind.expense);
      expect(a.amountKobo, 3002688);
      expect(a.signedKobo, -3002688);
      expect(a.description, 'LEO/SBW/UTO/ADA OKAFOR');
      expect(a.occurredAt, DateTime(2026, 11, 16, 10, 30));
      expect(a.balanceKobo, 6102091);
      expect(a.accountHint, '2XX..91X');
      expect(a.reference, isNull);
    });

    test('reads a credit', () {
      final a = parser.parse(creditTransfer)!;

      expect(a.kind, TxnKind.income);
      expect(a.amountKobo, 12000000);
      expect(a.signedKobo, 12000000);
      expect(a.description, 'Outward Transfer to ADA OKAFOR CHIDI 0000');
      expect(a.balanceKobo, 12024667);
    });

    test('separates the reference code from the description', () {
      final a = parser.parse(topupWithReference)!;

      expect(a.description, 'LEO TOPUP 9139260851');
      expect(a.reference, 'AATU1411260020060624479926');
      expect(a.amountKobo, 1100000);
      expect(a.occurredAt, DateTime(2026, 11, 14, 0, 20));
    });

    test('reads an alert whose line breaks were flattened into spaces', () {
      const flat =
          'Txn:DR Ac:2XX..91X Amt:NGN 11,000.00 '
          'Des:LEO TOPUP 9139260851 AATU1411260020060624479926 '
          'Date:14-11-2026 00:20 Bal:NGN 101,246.67 Loan? Dial *919*28#';

      final a = parser.parse(flat)!;

      expect(a.description, 'LEO TOPUP 9139260851');
      expect(a.reference, 'AATU1411260020060624479926');
      expect(a.balanceKobo, 10124667);
    });

    test('works without a balance line', () {
      const noBalance =
          'Txn:CR\nAc:2XX..91X\nAmt:NGN 500.00\n'
          'Des:Refund\nDate:01-11-2026 09:05';

      final a = parser.parse(noBalance)!;

      expect(a.balanceKobo, isNull);
      expect(a.amountKobo, 50000);
    });

    test('rejects an impossible date', () {
      const badDate =
          'Txn:DR\nAc:2XX..91X\nAmt:NGN 500.00\n'
          'Des:Test\nDate:31-02-2026 09:05\nBal:NGN 1.00';

      expect(parser.canParse(badDate), isTrue); // It LOOKS like an alert...
      expect(parser.parse(badDate), isNull); // ...but cannot be read safely.
    });

    test('does not treat other messages as alerts', () {
      expect(parser.canParse('Your OTP is 482913. Do not share it.'), isFalse);
      expect(parser.canParse('Hi, are we still meeting at 5?'), isFalse);
    });
  });

  group('parseKobo', () {
    test('handles commas, decimals and signs', () {
      expect(parseKobo('30,026.88'), 3002688);
      expect(parseKobo('100'), 10000);
      expect(parseKobo('1,234.5'), 123450);
      expect(parseKobo('-50.25'), -5025);
      expect(parseKobo('0.05'), 5);
    });

    test('rejects things that are not amounts', () {
      expect(parseKobo('abc'), isNull);
      expect(parseKobo('1.234'), isNull);
      expect(parseKobo(''), isNull);
    });
  });

  group('matchesAnyName', () {
    test('matches when all words appear, in any order', () {
      expect(matchesAnyName('LEO/SBW/UTO/ADA OKAFOR', ['ADA OKAFOR']), isTrue);
      expect(
        matchesAnyName('Transfer to OKAFOR ADA CHIDI', ['ada okafor']),
        isTrue,
      );
    });

    test('does not match on a single shared word', () {
      expect(matchesAnyName('Transfer to ADA BELLO', ['ADA OKAFOR']), isFalse);
    });

    test('ignores one-word names', () {
      expect(matchesAnyName('Transfer to ADA', ['ADA']), isFalse);
    });

    test('does nothing when no name is set', () {
      expect(matchesAnyName('ADA OKAFOR', []), isFalse);
    });
  });

  group('suggestCategoryName', () {
    test('recognises airtime, charges and salary', () {
      expect(
        suggestCategoryName('LEO TOPUP 9139260851', TxnKind.expense),
        'Airtime & data',
      );
      expect(
        suggestCategoryName('SMS ALERT CHARGE', TxnKind.expense),
        'Bank charges',
      );
      expect(suggestCategoryName('SALARY NOV', TxnKind.income), 'Salary');
    });

    test('returns null when unsure', () {
      expect(suggestCategoryName('Transfer to Chidi', TxnKind.expense), isNull);
    });
  });
}
