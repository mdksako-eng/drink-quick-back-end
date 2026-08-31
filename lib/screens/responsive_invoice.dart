// screens/responsive_invoice.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:provider/provider.dart';
import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';
class ResponsiveInvoice extends StatefulWidget {
  final List<Drink> drinks;
  final double totalAmount;
  final double amountPaid;
  final double balance;
  final String? orderId;
  final String? customerName;
  final bool isPreview;

  const ResponsiveInvoice({
    Key? key,
    required this.drinks,
    required this.totalAmount,
    required this.amountPaid,
    required this.balance,
    this.orderId,
    this.customerName,
    this.isPreview = false,
  }) : super(key: key);

  @override
  State<ResponsiveInvoice> createState() => _ResponsiveInvoiceState();
}

class _ResponsiveInvoiceState extends State<ResponsiveInvoice> {
  String _consumerName = '';
  String _companyName = 'Drink Quick Cal';
  String _companyEmail = '';
  String _companyPhone = '';
  String _companyAddress = '';
  bool _isGeneratingPDF = false;
  final TextEditingController _companyNameController = TextEditingController();

  static const Color primaryColor = Color(0xFF4361EE);
  static const Color secondaryColor = Color(0xFF4CC9F0);
  static const Color successColor = Color(0xFF4CAF50);
  static const Color warningColor = Color(0xFFFF9800);
  static const Color errorColor = Color(0xFFF44336);
  static const Color backgroundColor = Color(0xFFF8F9FA);
  static const Color textPrimary = Color(0xFF2C3E50);
  static const Color textSecondary = Color(0xFF7B8A8B);
  static const Color lightBlueBg = Color(0xFFE8F4FD);
  static const Color purpleButtonColor = Color(0xFF764BA2);

  String get _invoiceId => widget.orderId?.isNotEmpty == true ? widget.orderId! : DateTime.now().millisecondsSinceEpoch.toString();
  String get _displayInvoiceId => _invoiceId.length > 12 ? _invoiceId.substring(_invoiceId.length - 12) : _invoiceId;

  @override
  void initState() {
    super.initState();
    _loadCompanyInfo();
    if (widget.customerName != null && widget.customerName!.isNotEmpty) _consumerName = widget.customerName!;
  }

  @override
  void dispose() { _companyNameController.dispose(); super.dispose(); }

  Future<void> _loadCompanyInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      _companyName = prefs.getString('company_name') ?? 'Drink Quick Cal';
      _companyEmail = prefs.getString('company_email') ?? '';
      _companyPhone = prefs.getString('company_phone') ?? '';
      _companyAddress = prefs.getString('company_address') ?? '';
    });
  }

  Future<void> _saveCompanyName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_name', name);
  }

  String _formatCurrency(double amount) => CurrencyHelper.format(amount);

  Map<String, Map<String, dynamic>> _groupDrinks() {
    final map = <String, Map<String, dynamic>>{};
    for (final d in widget.drinks) {
      if (map.containsKey(d.name)) {
        map[d.name]!['quantity'] += 1;
        map[d.name]!['total'] += d.price;
      } else {
        map[d.name] = {'drink': d, 'quantity': 1, 'total': d.price};
      }
    }
    return map;
  }

  // ========== PDF GENERATION ==========

  Future<pw.Document> _createPDFDocument() async {
    final grouped = _groupDrinks();
    final name = _consumerName.isNotEmpty ? _consumerName : (widget.customerName ?? 'Customer');
    final items = grouped.entries.toList();
    final margin = items.length > 15 ? 25.0 : 40.0;
    final pdf = pw.Document();
    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.all(margin), build: (ctx) => _buildPDFPage(ctx, items, name)));
    return pdf;
  }

  pw.Widget _buildPDFPage(pw.Context ctx, List<MapEntry<String, Map<String, dynamic>>> items, String consumerName) {
    final count = items.length;
    final titleSize = count > 15 ? 24.0 : 28.0;
    final tableSize = count > 15 ? 9.0 : 11.0;
    final half = (items.length / 2).ceil();
    final left = items.sublist(0, half).cast<MapEntry<String, Map<String, dynamic>>>();
    final right = half < items.length ? items.sublist(half).cast<MapEntry<String, Map<String, dynamic>>>() : <MapEntry<String, Map<String, dynamic>>>[];

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Center(child: pw.Column(children: [
        pw.Text('DRINK INVOICE', style: pw.TextStyle(fontSize: titleSize, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
        pw.SizedBox(height: 4),
        pw.Text(DateFormat('dd MMMM yyyy, hh:mm a').format(DateTime.now()), style: pw.TextStyle(fontSize: 12, color: PdfColors.grey)),
      ])),
      pw.SizedBox(height: 20), pw.Divider(thickness: 1.5), pw.SizedBox(height: 16),

      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: _pdfCard('COMPANY INFO', [
          pw.Text(_companyName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          if (_companyPhone.isNotEmpty) pw.SizedBox(height: 4),
          if (_companyPhone.isNotEmpty) pw.Text('Phone: $_companyPhone', style: const pw.TextStyle(fontSize: 10)),
          if (_companyEmail.isNotEmpty) pw.SizedBox(height: 4),
          if (_companyEmail.isNotEmpty) pw.Text('Email: $_companyEmail', style: const pw.TextStyle(fontSize: 10)),
          if (_companyAddress.isNotEmpty) pw.SizedBox(height: 4),
          if (_companyAddress.isNotEmpty) pw.Text('Address: $_companyAddress', style: const pw.TextStyle(fontSize: 10)),
        ])),
        pw.SizedBox(width: 20),
        pw.Expanded(child: _pdfCard('INVOICE INFO', [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Invoice #:', style: const pw.TextStyle(fontSize: 10)), pw.Text(_displayInvoiceId, style: const pw.TextStyle(fontSize: 10))]),
          pw.SizedBox(height: 4),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Date:', style: const pw.TextStyle(fontSize: 10)), pw.Text(DateFormat('dd/MM/yyyy').format(DateTime.now()), style: const pw.TextStyle(fontSize: 10))]),
          pw.SizedBox(height: 4),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Customer:', style: const pw.TextStyle(fontSize: 10)), pw.Text(consumerName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue))]),
        ])),
      ]),

      pw.SizedBox(height: 20),
      pw.Text('ORDER ITEMS', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 10),

      if (items.isNotEmpty)
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: _buildItemsColumn(left, tableSize)),
          pw.SizedBox(width: 20),
          pw.Expanded(child: _buildItemsColumn(right, tableSize)),
        ])
      else
        pw.Text('No items', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey)),

      pw.SizedBox(height: 20),

      pw.Container(padding: const pw.EdgeInsets.all(16), decoration: pw.BoxDecoration(color: PdfColor.fromHex('E8F4FD'), borderRadius: pw.BorderRadius.circular(8), border: pw.Border.all(color: PdfColors.blue, width: 0.5)), child: pw.Column(children: [
        _pdfSummaryRow('Total Amount:', _formatCurrency(widget.totalAmount), true),
        pw.SizedBox(height: 8),
        _pdfSummaryRow('Amount Received:', _formatCurrency(widget.amountPaid), false),
        pw.SizedBox(height: 8), pw.Divider(thickness: 0.5), pw.SizedBox(height: 8),
        _pdfSummaryRow(widget.balance >= 0 ? 'Change Due:' : 'Balance Due:', _formatCurrency(widget.balance.abs()), true, widget.balance >= 0 ? PdfColors.green : PdfColors.red),
      ])),

      pw.SizedBox(height: 20),
      pw.Center(child: pw.Column(children: [
        pw.Text('Thank you for your purchase!', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Terms & Conditions Apply', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
      ])),
    ]);
  }

  pw.Widget _pdfCard(String title, List<pw.Widget> children) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(6), border: pw.Border.all(color: PdfColors.grey300, width: 0.5)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
        pw.SizedBox(height: 8),
        ...children,
      ]),
    );
  }

  pw.Widget _pdfSummaryRow(String label, String value, bool isBold, [PdfColor? color]) {
    return pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text(label, style: pw.TextStyle(fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      pw.Text(value, style: pw.TextStyle(fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? PdfColors.blue)),
    ]);
  }

  pw.Widget _buildItemsColumn(List<MapEntry<String, Map<String, dynamic>>> items, double fontSize) {
    final children = <pw.Widget>[];
    children.add(pw.Container(
      decoration: pw.BoxDecoration(color: PdfColors.grey200, border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5))),
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: pw.Row(children: [
        pw.Expanded(flex: 3, child: pw.Text('ITEM', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSize))),
        pw.Expanded(flex: 1, child: pw.Center(child: pw.Text('QTY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSize)))),
        pw.Expanded(flex: 1, child: pw.Center(child: pw.Text('PRICE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSize)))),
        pw.Expanded(flex: 1, child: pw.Center(child: pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSize)))),
      ]),
    ));
    for (final e in items) {
      children.add(pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: pw.Row(children: [
          pw.Expanded(flex: 3, child: pw.Text(e.key, style: pw.TextStyle(fontSize: fontSize), softWrap: true, overflow: pw.TextOverflow.clip)),
          pw.Expanded(flex: 1, child: pw.Center(child: pw.Text('${e.value['quantity']}', style: pw.TextStyle(fontSize: fontSize)))),
          pw.Expanded(flex: 1, child: pw.Center(child: pw.Text('${(e.value['drink'] as Drink).price.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: fontSize)))),
          pw.Expanded(flex: 1, child: pw.Center(child: pw.Text('${e.value['total'].toStringAsFixed(0)}', style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold)))),
        ]),
      ));
    }
    return pw.Column(children: children);
  }

  // ========== ACTIONS ==========

  Future<void> _generateAndPrintPDF(BuildContext ctx) async {
    if (widget.isPreview) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Finalize purchase first'), backgroundColor: warningColor)); return; }
    setState(() => _isGeneratingPDF = true);
    try {
      final pdf = await _createPDFDocument();
      await Printing.layoutPdf(onLayout: (_) async => await pdf.save());
    } catch (e) { if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: errorColor)); }
    finally { if (mounted) setState(() => _isGeneratingPDF = false); }
  }

  Future<void> _savePDF(BuildContext ctx) async {
  if (widget.isPreview) { 
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Finalize purchase first'), backgroundColor: warningColor)); 
    return; 
  }
  if (_consumerName.isEmpty) { 
    await _showConsumerNameDialog(ctx, forPrint: false); 
    if (_consumerName.isEmpty) return; 
  }
  setState(() => _isGeneratingPDF = true);
  try {
    final pdf = await _createPDFDocument();
    final bytes = await pdf.save();
    
    // Create Drink_Invoices folder in Downloads/App Documents
    Directory invoicesDir;
    
        if (Platform.isAndroid) {
      // Save to Downloads folder for visibility
      invoicesDir = Directory('/storage/emulated/0/Download/Drink_Quick/Drink_Invoices');
      if (!await Directory('/storage/emulated/0/Download').exists()) {
        final directory = await getApplicationDocumentsDirectory();
        invoicesDir = Directory('${directory.path}/Drink_Invoices');
      }
    } else {
      final directory = await getApplicationDocumentsDirectory();
      invoicesDir = Directory('${directory.path}/Drink_Invoices');
    }
    
    if (!await invoicesDir.exists()) {
      await invoicesDir.create(recursive: true);
    }

    final fileName = 'Invoice_${_consumerName.replaceAll(RegExp(r'[^\w]'), '_')}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final file = File('${invoicesDir.path}/$fileName');
    await file.writeAsBytes(bytes);

    if (mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('✅ Saved: $fileName'), backgroundColor: successColor, duration: const Duration(seconds: 3)),
      );
      
      // Offer to share the file
      await showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          title: const Text('PDF Saved'),
          content: const Text('Would you like to share or open the PDF?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Close')),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(c, true);
                Share.shareXFiles([XFile(file.path)], text: 'Invoice - $_companyName');
              },
              icon: const Icon(Icons.share),
              label: const Text('Share'),
            ),
          ],
        ),
      );
    }
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: errorColor));
  } finally {
    if (mounted) setState(() => _isGeneratingPDF = false);
  }
}
  Future<void> _sharePDF(BuildContext ctx) async {
    if (widget.isPreview) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Finalize purchase first'), backgroundColor: warningColor)); return; }
    if (_consumerName.isEmpty) { await _showConsumerNameDialog(ctx, forPrint: false); if (_consumerName.isEmpty) return; }
    setState(() => _isGeneratingPDF = true);
    try {
      final pdf = await _createPDFDocument();
      final bytes = await pdf.save();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/Invoice_${_consumerName.replaceAll(RegExp(r'[^\w]'), '_')}.pdf');
      await file.writeAsBytes(bytes);
      // ignore: deprecated_member_use
      await SharePlus.instance.share(ShareParams(
  files: [XFile(file.path)],
  text: 'Invoice - $_companyName\nTotal: ${_formatCurrency(widget.totalAmount)}',
));
    } catch (e) { if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: errorColor)); }
    finally { if (mounted) setState(() => _isGeneratingPDF = false); }
  }

  // ========== DIALOGS ==========

  Future<void> _showCompanyNameDialog(BuildContext ctx) async {
    _companyNameController.text = _companyName;
    await showDialog(context: ctx, builder: (c) => AlertDialog(title: const Text('Edit Company Name'), content: TextField(controller: _companyNameController, decoration: const InputDecoration(labelText: 'Company Name')), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), ElevatedButton(onPressed: () { final n = _companyNameController.text.trim(); if (n.isNotEmpty) { setState(() => _companyName = n); _saveCompanyName(n); } Navigator.pop(c); }, child: const Text('Save'))]));
  }

  Future<void> _showConsumerNameDialog(BuildContext ctx, {bool forPrint = true}) async {
    final ctrl = TextEditingController(text: _consumerName);
    await showDialog(context: ctx, builder: (c) => AlertDialog(title: const Text('Customer Name'), content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Enter customer name'), autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), ElevatedButton(onPressed: () { final n = ctrl.text.trim(); if (n.isNotEmpty) { setState(() => _consumerName = n); Navigator.pop(c); if (forPrint) _generateAndPrintPDF(ctx); } }, child: const Text('Continue'))]));
  }

  // ========== UI BUILD ==========

  Widget _buildInvoiceContent() {
    final authProvider = Provider.of<AuthProvider>(context);
  final isStaff = (authProvider.user!.role.toLowerCase()) == 'staff';
    final entries = _groupDrinks().entries.toList();
    return Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20)]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_companyName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor)),
          if (_companyPhone.isNotEmpty) Row(children: [const Icon(Icons.phone, size: 14, color: textSecondary), const SizedBox(width: 4), Text(_companyPhone, style: const TextStyle(fontSize: 12, color: textSecondary))]),
          if (_companyEmail.isNotEmpty) Row(children: [const Icon(Icons.email, size: 14, color: textSecondary), const SizedBox(width: 4), Text(_companyEmail, style: const TextStyle(fontSize: 12, color: textSecondary))]),
          if (_companyAddress.isNotEmpty) Row(children: [const Icon(Icons.location_on, size: 14, color: textSecondary), const SizedBox(width: 4), Expanded(child: Text(_companyAddress, style: const TextStyle(fontSize: 12, color: textSecondary)))]),
        ])),
        if (!widget.isPreview && !isStaff ) GestureDetector(onTap: () => _showCompanyNameDialog(context), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: primaryColor)), child: const Row(children: [Icon(Icons.edit, size: 16, color: primaryColor), SizedBox(width: 4), Text('Edit', style: TextStyle(fontSize: 12, color: primaryColor))]))),
      ]),
      const SizedBox(height: 20),
      Center(child: Column(children: [const Text('DRINK INVOICE', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: primaryColor)), const SizedBox(height: 8), Text(DateFormat('dd MMMM yyyy, hh:mm a').format(DateTime.now()), style: const TextStyle(fontSize: 13, color: textSecondary))])),
      const SizedBox(height: 24), Divider(color: primaryColor.withValues(alpha: 0.3)), const SizedBox(height: 24),
      LayoutBuilder(builder: (_, cons) => cons.maxWidth < 600 ? Column(children: [_infoCard(Icons.business, 'COMPANY INFO', _companyName, _companyPhone, _companyEmail, _companyAddress), const SizedBox(height: 16), _invoiceInfoCard()]) : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _infoCard(Icons.business, 'COMPANY INFO', _companyName, _companyPhone, _companyEmail, _companyAddress)), const SizedBox(width: 20), Expanded(child: _invoiceInfoCard())])),
      const SizedBox(height: 24), Divider(color: primaryColor.withValues(alpha: 0.3)), const SizedBox(height: 24),
      const Text('ORDER ITEMS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary)), const SizedBox(height: 16),
      Container(decoration: BoxDecoration(border: Border.all(color: primaryColor.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(8)), child: Column(children: [
        Container(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16), decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.1), border: Border(bottom: BorderSide(color: primaryColor.withValues(alpha: 0.2)))), child: const Row(children: [Expanded(flex: 3, child: Text('ITEM', style: TextStyle(fontWeight: FontWeight.bold))), Expanded(child: Center(child: Text('QTY', style: TextStyle(fontWeight: FontWeight.bold)))), Expanded(child: Align(alignment: Alignment.centerRight, child: Text('PRICE', style: TextStyle(fontWeight: FontWeight.bold)))), Expanded(child: Align(alignment: Alignment.centerRight, child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))))])),
        ...entries.map((e) { final d = e.value['drink'] as Drink; final q = e.value['quantity'] as int; final t = e.value['total'] as double; return Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), child: Row(children: [Expanded(flex: 3, child: Text(e.key, style: const TextStyle(fontSize: 14))), Expanded(child: Center(child: Text('$q', style: const TextStyle(fontSize: 14)))), Expanded(child: Align(alignment: Alignment.centerRight, child: Text(_formatCurrency(d.price), style: const TextStyle(fontSize: 14)))), Expanded(child: Align(alignment: Alignment.centerRight, child: Text(_formatCurrency(t), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryColor))))])); }).toList(),
      ])),
      const SizedBox(height: 24),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: lightBlueBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryColor.withValues(alpha: 0.3))), child: Column(children: [
        _summaryRow('Total Amount', _formatCurrency(widget.totalAmount), true), const SizedBox(height: 12),
        _summaryRow('Amount Received', _formatCurrency(widget.amountPaid)), const SizedBox(height: 12),
        Divider(color: primaryColor.withValues(alpha: 0.3)), const SizedBox(height: 12),
        _summaryRow(widget.balance >= 0 ? 'Change Due' : 'Balance Due', _formatCurrency(widget.balance.abs()), true, widget.balance >= 0 ? successColor : errorColor),
      ])),
      if (_consumerName.isNotEmpty) ...[const SizedBox(height: 20), Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: secondaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: secondaryColor)), child: Row(children: [Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: secondaryColor, shape: BoxShape.circle), child: const Icon(Icons.person, color: Colors.white, size: 20)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('CUSTOMER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryColor)), Text(_consumerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: secondaryColor))])), if (!widget.isPreview) IconButton(icon: const Icon(Icons.edit, color: secondaryColor), onPressed: () => _showConsumerNameDialog(context, forPrint: false))]))],
      const SizedBox(height: 24),
      Center(child: Column(children: [const Text('Thank you for your purchase!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)), const SizedBox(height: 8), Text(_companyPhone.isNotEmpty ? 'For inquiries: $_companyPhone' : 'Contact: $_companyName', style: const TextStyle(fontSize: 13, color: textSecondary)), const SizedBox(height: 4), const Text('Terms & Conditions Apply', style: TextStyle(fontSize: 11, color: textSecondary))])),
    ]));
  }

  Widget _infoCard(IconData icon, String title, String name, String phone, String email, String address) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryColor.withValues(alpha: 0.2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 18, color: primaryColor), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryColor))]),
      const SizedBox(height: 12), Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
      if (phone.isNotEmpty) ...[const SizedBox(height: 8), Row(children: [const Icon(Icons.phone, size: 14, color: textSecondary), const SizedBox(width: 8), Text(phone, style: const TextStyle(fontSize: 13, color: textSecondary))])],
      if (email.isNotEmpty) ...[const SizedBox(height: 4), Row(children: [const Icon(Icons.email, size: 14, color: textSecondary), const SizedBox(width: 8), Text(email, style: const TextStyle(fontSize: 13, color: textSecondary))])],
      if (address.isNotEmpty) ...[const SizedBox(height: 4), Row(children: [const Icon(Icons.location_on, size: 14, color: textSecondary), const SizedBox(width: 8), Expanded(child: Text(address, style: const TextStyle(fontSize: 13, color: textSecondary)))])],
    ]));
  }

  Widget _invoiceInfoCard() {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryColor.withValues(alpha: 0.2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.receipt, size: 18, color: primaryColor), const SizedBox(width: 8), const Text('INVOICE INFO', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryColor))]),
      const SizedBox(height: 12),
      _infoRow('Invoice #:', _displayInvoiceId), const SizedBox(height: 8),
      _infoRow('Date:', DateFormat('dd/MM/yyyy').format(DateTime.now())), const SizedBox(height: 8),
      _infoRow('Time:', DateFormat('hh:mm a').format(DateTime.now())), const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Status:', style: TextStyle(fontSize: 13, color: textSecondary)), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: widget.balance >= 0 ? successColor.withValues(alpha: 0.1) : errorColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Text(widget.balance >= 0 ? 'PAID' : 'PENDING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: widget.balance >= 0 ? successColor : errorColor)))]),
    ]));
  }

  Widget _infoRow(String label, String value) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 13, color: textSecondary)), Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary))]);
  Widget _summaryRow(String label, String value, [bool bold = false, Color? color]) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.bold : FontWeight.normal)), Text(value, style: TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color ?? primaryColor))]);

  @override
  Widget build(BuildContext context) {
     final authProvider = Provider.of<AuthProvider>(context);
    final isStaff = (authProvider.user!.role.toLowerCase()) == 'staff';
    
    return GestureDetector(
    onTap: () => LockService().resetTimer(),
    onPanDown: (_) => LockService().resetTimer(),
    onScaleStart: (_) => LockService().resetTimer(),
    onLongPress: () => LockService().resetTimer(),
    behavior: HitTestBehavior.translucent,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.isPreview ? 'Invoice Preview' : 'Invoice - $_companyName'), backgroundColor: primaryColor, centerTitle: true, actions: [
        if (!widget.isPreview && !isStaff) IconButton(icon: const Icon(Icons.business), onPressed: () => _showCompanyNameDialog(context)),
        if (_isGeneratingPDF) const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
      ]),
      body: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [backgroundColor, Colors.white])), child: SingleChildScrollView(padding: const EdgeInsets.all(20), child:
      
       _buildInvoiceContent())),
      bottomNavigationBar: widget.isPreview ? null : Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]), child: SafeArea(child: Row(children: [
        Expanded(child: ElevatedButton.icon(onPressed: _isGeneratingPDF ? null : () => _generateAndPrintPDF(context), icon: const Icon(Icons.print), label: const Text('Print'), style: ElevatedButton.styleFrom(backgroundColor: primaryColor, padding: const EdgeInsets.symmetric(vertical: 14)))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton.icon(onPressed: _isGeneratingPDF ? null : () => _savePDF(context), icon: const Icon(Icons.save), label: const Text('Save'), style: ElevatedButton.styleFrom(backgroundColor: successColor, padding: const EdgeInsets.symmetric(vertical: 14)))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton.icon(onPressed: _isGeneratingPDF ? null : () => _sharePDF(context), icon: const Icon(Icons.share), label: const Text('Share'), style: ElevatedButton.styleFrom(backgroundColor: purpleButtonColor, padding: const EdgeInsets.symmetric(vertical: 14)))),
      ]))),
    ),
    );
  }
}