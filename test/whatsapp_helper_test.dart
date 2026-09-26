// test/whatsapp_helper_test.dart
// The WhatsApp sharing helper: links, number normalisation, message layout and
// the length clamp. No widgets, no network.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/whatsapp_helper.dart';

void main() {
  group('phone numbers', () {
    test('a local number gets the country code', () {
      expect(WhatsAppHelper.normalizeNumber('6 99 12 34 56'), '237699123456');
      expect(WhatsAppHelper.normalizeNumber('699123456'), '237699123456');
    });

    test('a trunk zero is dropped', () {
      expect(WhatsAppHelper.normalizeNumber('0699123456'), '237699123456');
    });

    test('a number that already has the code is left alone', () {
      expect(WhatsAppHelper.normalizeNumber('+237 699 123 456'), '237699123456');
      expect(WhatsAppHelper.normalizeNumber('237699123456'), '237699123456');
    });

    test('a foreign number is kept as it is', () {
      expect(WhatsAppHelper.normalizeNumber('+234 801 234 5678'), '2348012345678');
    });

    test('an empty number stays empty', () {
      expect(WhatsAppHelper.normalizeNumber(null), '');
      expect(WhatsAppHelper.normalizeNumber('  '), '');
    });
  });

  group('wa.me links', () {
    test('builds a link with the encoded message', () {
      final link = WhatsAppHelper.link('699123456', 'Hello world');
      expect(link, startsWith('https://wa.me/237699123456?text='));
      expect(link, contains('Hello%20world'));
    });

    test('encodes newlines and spaces (stars stay, they are the bold mark)', () {
      final link = WhatsAppHelper.link('699123456', '*Total*\n2 000 Frs');
      expect(link, contains('%0A'));
      // Dart leaves the sub-delimiters alone, and WhatsApp reads * as bold.
      expect(link, contains('*Total*'));
      expect(link, isNot(contains(' ')));
    });

    test('no number means no link', () {
      expect(WhatsAppHelper.link('', 'hello'), '');
      expect(WhatsAppHelper.link(null, 'hello'), '');
    });

    test('the contact-picker link carries the message but no recipient', () {
      final link = WhatsAppHelper.shareLink('*Z-report*\nSales: 20 000 Frs');
      expect(link, startsWith('https://wa.me/?text='));
      expect(link, contains('*Z-report*'));
      expect(link, isNot(contains('wa.me/237')));
    });
  });

  group('message layout', () {
    test('title, rows, total, notes and footer', () {
      final text = WhatsAppHelper.message(
        title: 'Z-report',
        subtitle: 'Bih · 08:00 - 16:00',
        rows: const [WaRow('Sales', '20 000 Frs')],
        totalLabel: 'Expected cash',
        totalValue: '25 000 Frs',
        notes: const ['Counted 23 000 Frs'],
        footer: 'Sent by Chez Nous',
      );
      expect(text, startsWith('*Z-report*'));
      expect(text, contains('\nBih · 08:00 - 16:00'));
      expect(text, contains('\nSales: 20 000 Frs'));
      expect(text, contains('\n\n*Expected cash: 25 000 Frs*'));
      expect(text, contains('\n- Counted 23 000 Frs'));
      expect(text, endsWith('_Sent by Chez Nous_'));
    });

    test('an empty optional part never leaves a dangling label', () {
      final text = WhatsAppHelper.message(title: 'Statement');
      expect(text, '*Statement*');
      expect(text, isNot(contains(':')));
    });

    test('blank notes and footer are skipped', () {
      final text = WhatsAppHelper.message(
        title: 'Statement',
        notes: const ['', '   '],
        footer: '  ',
      );
      expect(text, '*Statement*');
    });

    test('optional rows drop out when the value is empty', () {
      final rows = WhatsAppHelper.rows([
        WhatsAppHelper.row('Phone', '699123456'),
        WhatsAppHelper.row('Note', ''),
        WhatsAppHelper.row('Reason', null),
      ]);
      expect(rows.length, 1);
      expect(rows.first.value, '699123456');
    });
  });

  group('length clamp', () {
    test('a long message is cut on a line boundary', () {
      final long = WhatsAppHelper.message(
        title: 'Statement',
        rows: List.generate(200, (i) => WaRow('Item $i', 'value $i')),
      );
      final clamped = WhatsAppHelper.clamp(long, max: 300);
      expect(clamped.length, lessThanOrEqualTo(301));
      expect(clamped.endsWith('…'), isTrue);
      // Nothing half-written: the cut line was dropped entirely.
      expect(clamped.contains('value 199'), isFalse);
    });

    test('a short message is untouched', () {
      expect(WhatsAppHelper.clamp('short', max: 100), 'short');
    });

    test('a receipt is sent as a code block so its columns hold', () {
      final block = WhatsAppHelper.receiptBlock(
        'ORDER 123\nTotal 2 000',
        footer: 'Chez Nous',
      );
      expect(block, startsWith('```\nORDER 123'));
      expect(block, contains('\n```'));
      expect(block, endsWith('_Chez Nous_'));
    });
  });
}
