// screens/receipt_print_screen.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:share_plus/share_plus.dart';
import '../models/drink_model.dart';
import '../services/receipt_printer.dart';
import '../utils/helpers.dart';
import '../utils/i18n.dart';

class ReceiptPrintScreen extends StatefulWidget {
  final List<Drink> drinks;
  final double totalAmount;
  final double amountPaid;
  final double balance;
  final String? orderId;
  final String? customerName;
  final String companyName;
  final String companyAddress;
  final String companyPhone;
  final String companyEmail;

  const ReceiptPrintScreen({
    Key? key,
    required this.drinks,
    required this.totalAmount,
    required this.amountPaid,
    required this.balance,
    this.orderId,
    this.customerName,
    this.companyName = 'Drink Quick Cal',
    this.companyAddress = '',
    this.companyPhone = '',
    this.companyEmail = '',
  }) : super(key: key);

  @override
  State<ReceiptPrintScreen> createState() => _ReceiptPrintScreenState();
}

class _ReceiptPrintScreenState extends State<ReceiptPrintScreen> {
  int _paperWidth = 32; // 58mm ~ 32 chars; 80mm ~ 48 chars
  bool _busy = false;

  ReceiptData get _data {
    final counts = <String, int>{};
    final prices = <String, double>{};
    for (final d in widget.drinks) {
      counts[d.name] = (counts[d.name] ?? 0) + 1;
      prices[d.name] = d.price;
    }
    final items = <ReceiptLineItem>[];
    counts.forEach((name, qty) {
      items.add(ReceiptLineItem(
          name: name, quantity: qty, price: prices[name] ?? 0));
    });
    return ReceiptData(
      companyName: widget.companyName,
      companyAddress: widget.companyAddress,
      companyPhone: widget.companyPhone,
      companyEmail: widget.companyEmail,
      orderId:
          widget.orderId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      customerName: widget.customerName ?? '',
      date: DateTime.now(),
      items: items,
      totalAmount: widget.totalAmount,
      amountPaid: widget.amountPaid,
      balance: widget.balance,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final text = ReceiptPrinter.buildPlainText(_data, width: _paperWidth);
    return Scaffold(
      appBar: AppBar(
        title: Text(t('receiptTitle')),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildPaperSelector(primary),
          Expanded(child: _buildPreview(text)),
          _buildActions(primary),
        ],
      ),
    );
  }

  Widget _buildPaperSelector(Color primary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(t('receiptPaper'),
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(width: 12),
          ChoiceChip(
            label: const Text('58mm'),
            selected: _paperWidth == 32,
            onSelected: (_) => setState(() => _paperWidth = 32),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('80mm'),
            selected: _paperWidth == 48,
            onSelected: (_) => setState(() => _paperWidth = 48),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.08), blurRadius: 8),
          ],
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: Colors.black,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(Color primary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06), blurRadius: 10),
        ],
      ),
      child: SafeArea(
        child: Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _print,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.print),
              label: Text(t('receiptPrint')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share),
              label: Text(t('receiptShare')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(t('receiptSave')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _print() async {
    if (kIsWeb) {
      Helpers.showToast(t('receiptBtNote'));
      return;
    }
    setState(() => _busy = true);
    try {
      final enabled = await ReceiptPrinter.isBluetoothEnabled();
      if (!enabled) {
        Helpers.showToast(t('receiptBtOff'));
        return;
      }
      final printers = await ReceiptPrinter.pairedPrinters();
      if (printers.isEmpty) {
        Helpers.showToast(t('receiptNoPrinter'));
        return;
      }
      final mac = await _showPrinterPicker(printers);
      if (mac == null) return;
      final bytes = ReceiptPrinter.buildEscPosBytes(_data, width: _paperWidth);
      final ok = await ReceiptPrinter.printViaBluetooth(bytes, mac);
      if (!mounted) return;
      Helpers.showToast(ok ? t('receiptPrinted') : t('receiptPrintFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final text = ReceiptPrinter.buildPlainText(_data, width: _paperWidth);
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _save() async {
    final text = ReceiptPrinter.buildPlainText(_data, width: _paperWidth);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.txt');
      await file.writeAsString(text);
      if (!mounted) return;
      Helpers.showToast(t('receiptSaved'));
    } catch (e) {
      if (mounted) Helpers.showToast('$e');
    }
  }

  Future<String?> _showPrinterPicker(List<BluetoothInfo> printers) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t('receiptSelectPrinter')),
        children: printers.map((p) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, p.macAdress),
            child: ListTile(
              leading: const Icon(Icons.print),
              title: Text(p.name),
              subtitle: Text(p.macAdress),
            ),
          );
        }).toList(),
      ),
    );
  }
}

