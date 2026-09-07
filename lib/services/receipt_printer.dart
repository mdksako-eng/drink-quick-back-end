// services/receipt_printer.dart
// Thermal receipt generation + Bluetooth printing (ESC/POS).
// The ESC/POS byte stream is built locally (no external generator dependency),
// keeping it compatible with the app's other packages.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../utils/currency_helper.dart';

class ReceiptLineItem {
  final String name;
  final int quantity;
  final double price;
  const ReceiptLineItem({
    required this.name,
    required this.quantity,
    required this.price,
  });
  double get total => quantity * price;
}

class ReceiptData {
  final String companyName;
  final String companyAddress;
  final String companyPhone;
  final String companyEmail;
  final String orderId;
  final String customerName;
  final DateTime date;
  final List<ReceiptLineItem> items;
  final double totalAmount;
  final double amountPaid;
  final double balance;

  const ReceiptData({
    required this.companyName,
    this.companyAddress = '',
    this.companyPhone = '',
    this.companyEmail = '',
    required this.orderId,
    this.customerName = '',
    required this.date,
    required this.items,
    required this.totalAmount,
    required this.amountPaid,
    required this.balance,
  });
}

class ReceiptPrinter {
  ReceiptPrinter._();

  /// Plain monospace receipt text (used for preview, share and save).
  static String buildPlainText(ReceiptData d, {int width = 32}) {
    final lines = <String>[];
    String center(String s) {
      if (s.length >= width) return s.substring(0, width);
      final left = (width - s.length) ~/ 2;
      return s.padLeft(s.length + left).padRight(width);
    }

    lines.add(center(d.companyName));
    if (d.companyAddress.isNotEmpty) lines.add(center(d.companyAddress));
    final contact = [d.companyPhone, d.companyEmail]
        .where((s) => s.isNotEmpty)
        .join('  ');
    if (contact.isNotEmpty) lines.add(center(contact));
    lines.add('-'.padRight(width, '-'));
    lines.add('Order: ${d.orderId}');
    lines.add('Date: ${DateFormat('yyyy-MM-dd HH:mm').format(d.date)}');
    if (d.customerName.isNotEmpty) lines.add('Customer: ${d.customerName}');
    lines.add('-'.padRight(width, '-'));
    for (final it in d.items) {
      lines.add(_formatItem(it, width));
    }
    lines.add('-'.padRight(width, '-'));
    lines.add(_row('Subtotal', CurrencyHelper.format(d.totalAmount), width));
    lines.add(_row('Paid', CurrencyHelper.format(d.amountPaid), width));
    lines.add(_row('Balance', CurrencyHelper.format(d.balance), width));
    lines.add('-'.padRight(width, '-'));
    lines.add(center('Thank you!'));
    lines.add('');
    return lines.join('\n');
  }

  static String _formatItem(ReceiptLineItem it, int width) {
    final left = '${it.name} x${it.quantity}';
    final right = CurrencyHelper.format(it.total);
    final maxLeft = width - right.length;
    final l = left.length > maxLeft ? left.substring(0, maxLeft) : left;
    return l.padRight(width - right.length) + right;
  }

  static String _row(String label, String value, int width) {
    return label.padRight(width - value.length) + value;
  }

  /// ESC/POS byte stream for a 58mm (width=32) or 80mm (width=48) printer.
  static List<int> buildEscPosBytes(ReceiptData d, {int width = 32}) {
    final b = <int>[];
    void esc(List<int> c) => b.addAll(c);
    void txt(String s, {int align = 0, bool doubleSize = false}) {
      esc([0x1B, 0x61, align]); // alignment: 0 left, 1 center, 2 right
      esc([0x1B, 0x21, doubleSize ? 0x30 : 0x00]); // double width + height
      b.addAll(_encode(s));
      esc([0x0A]);
    }

    esc([0x1B, 0x40]); // initialize
    txt(d.companyName, align: 1, doubleSize: true);
    if (d.companyAddress.isNotEmpty) txt(d.companyAddress, align: 1);
    final contact = [d.companyPhone, d.companyEmail]
        .where((s) => s.isNotEmpty)
        .join('  ');
    if (contact.isNotEmpty) txt(contact, align: 1);
    txt('-'.padRight(width, '-'));
    txt('Order: ${d.orderId}');
    txt('Date: ${DateFormat('yyyy-MM-dd HH:mm').format(d.date)}');
    if (d.customerName.isNotEmpty) txt('Customer: ${d.customerName}');
    txt('-'.padRight(width, '-'));
    for (final it in d.items) {
      txt(_formatItem(it, width));
    }
    txt('-'.padRight(width, '-'));
    txt(_row('Subtotal', CurrencyHelper.format(d.totalAmount), width));
    txt(_row('Paid', CurrencyHelper.format(d.amountPaid), width));
    txt(_row('Balance', CurrencyHelper.format(d.balance), width));
    txt('-'.padRight(width, '-'));
    txt('Thank you!', align: 1);
    esc([0x1B, 0x64, 3]); // feed 3 lines
    esc([0x1D, 0x56, 1]); // partial cut
    return b;
  }

  /// Encode to a single-byte codepage (Latin-1 range), '?' otherwise.
  static List<int> _encode(String s) {
    return s.codeUnits.map((c) => c > 255 ? 0x3F : c).toList();
  }

  // ---------- Bluetooth printing (Android + Windows) ----------

  static Future<bool> isBluetoothEnabled() async {
    if (kIsWeb) return false;
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  static Future<List<BluetoothInfo>> pairedPrinters() async {
    if (kIsWeb) return [];
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return [];
    }
  }

  static Future<bool> printViaBluetooth(
      List<int> bytes, String macAddress) async {
    try {
      final connected =
          await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
      if (!connected) return false;
      final wrote = await PrintBluetoothThermal.writeBytes(bytes);
      await PrintBluetoothThermal.disconnect;
      return wrote;
    } catch (_) {
      return false;
    }
  }
}
