// utils/whatsapp_helper.dart
// Share a receipt, a customer statement or a Z-report on WhatsApp.
//
// Your buyers live in WhatsApp, so the reports go where they are instead of into
// an email nobody opens. Everything here is pure string work: the caller passes
// already-translated labels (t('…')) so the helper carries no UI strings, and
// the layout can be unit tested.
//
// WhatsApp markdown: *bold*, _italic_. Rows are "Label: value" rather than
// padded columns, because WhatsApp renders with a proportional font.

class WaRow {
  final String label;
  final String value;

  const WaRow(this.label, this.value);
}

class WhatsAppHelper {
  WhatsAppHelper._();

  /// WhatsApp refuses very long links; past this the message is cut on a line
  /// boundary and marked with an ellipsis (the full report is always available
  /// in the app / PDF).
  static const int maxMessageLength = 1500;

  /// Country code used when the customer typed a local number (the shop's
  /// market: Cameroon, +237).
  static const String defaultDial = '237';

  /// Digits with a country code, which is what wa.me expects:
  /// "6 99 12 34 56" or "+237 699123456" both become "237699123456".
  static String normalizeNumber(String? phone, {String dial = defaultDial}) {
    var digits = (phone ?? '').replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return '';
    // Drop a national trunk zero ("0699123456" -> "699123456").
    while (digits.length > 1 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.startsWith(dial)) return digits;
    // A number that already carries another country code (11+ digits) is kept
    // as it is: the shop sells to neighbours too.
    if (digits.length >= 11) return digits;
    return '$dial$digits';
  }

  /// The wa.me link that opens the chat with [phone] and the message ready to
  /// send. Returns '' when there is no usable number.
  static String link(
    String? phone,
    String message, {
    String dial = defaultDial,
  }) {
    final number = normalizeNumber(phone, dial: dial);
    if (number.isEmpty) return '';
    return 'https://wa.me/$number?text=${Uri.encodeComponent(message)}';
  }

  /// A link with **no recipient**: WhatsApp asks which chat to send it to.
  /// Used for the Z-report, which usually goes to the owner's own number.
  static String shareLink(String message) =>
      'https://wa.me/?text=${Uri.encodeComponent(clamp(message))}';

  /// The message itself: a bold title, optional subtitle, label/value rows, a
  /// total block, free notes and a footer.
  static String message({
    required String title,
    String? subtitle,
    List<WaRow> rows = const [],
    String? totalLabel,
    String? totalValue,
    List<String> notes = const [],
    String? footer,
  }) {
    final buffer = StringBuffer('*$title*');
    if (subtitle != null && subtitle.trim().isNotEmpty) {
      buffer.write('\n${subtitle.trim()}');
    }
    if (rows.isNotEmpty) {
      buffer.write('\n');
      for (final row in rows) {
        buffer.write('\n${row.label}: ${row.value}');
      }
    }
    if (totalLabel != null && totalValue != null) {
      buffer.write('\n\n*$totalLabel: $totalValue*');
    }
    final usableNotes = notes.where((n) => n.trim().isNotEmpty).toList();
    if (usableNotes.isNotEmpty) {
      buffer.write('\n');
      for (final note in usableNotes) {
        buffer.write('\n- ${note.trim()}');
      }
    }
    if (footer != null && footer.trim().isNotEmpty) {
      buffer.write('\n\n_${footer.trim()}_');
    }
    return clamp(buffer.toString());
  }

  /// Keeps a message inside [max] characters, cutting on a line boundary so a
  /// half sentence never looks like a real line item.
  static String clamp(String message, {int max = maxMessageLength}) {
    if (message.length <= max) return message;
    final cut = message.substring(0, max);
    final lastBreak = cut.lastIndexOf('\n');
    final body = lastBreak > max ~/ 2 ? cut.substring(0, lastBreak) : cut;
    return '$body…';
  }

  /// A receipt is already plain monospace text (see ReceiptPrinter): it is sent
  /// inside a code block so WhatsApp keeps the columns aligned.
  static String receiptBlock(String receiptText, {String? footer}) {
    final body = '```\n${receiptText.trim()}\n```';
    if (footer == null || footer.trim().isEmpty) return clamp(body);
    return clamp('$body\n\n_${footer.trim()}_');
  }

  /// One "label: value" row, or null when the value is empty (so a report never
  /// shows a dangling label).
  static WaRow? row(String label, String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    return WaRow(label, text);
  }

  /// Drops the nulls from a list of optional rows.
  static List<WaRow> rows(List<WaRow?> candidates) =>
      candidates.whereType<WaRow>().toList();
}
