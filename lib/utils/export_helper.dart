// utils/export_helper.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/inventory_model.dart';
import 'i18n.dart';

class ExportHelper {
  // Export as PDF
  static Future<void> exportInventoryReport(InventoryReport report, BuildContext context) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('exportReport')),
        content: Text(t('chooseFormat')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'pdf'),
            child: Text(t('exportPdf')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'excel'),
            child: Text(t('exportExcel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'csv'),
            child: Text(t('exportCsv')),
          ),
        ],
      ),
    );

    if (action == null) return;

    try {
      switch (action) {
        case 'pdf':
          await _exportAsPdf(report, context);
          break;
        case 'excel':
          await _exportAsExcel(report, context);
          break;
        case 'csv':
          await _exportAsCsv(report, context);
          break;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('refreshFailed') + ': $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // PDF Export
  static Future<void> _exportAsPdf(InventoryReport report, BuildContext context) async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('MMM dd, yyyy');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            pw.Header(
              level: 0,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Drinks Quick Cal', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text(t('exp_inventoryReport'), style: pw.TextStyle(fontSize: 18)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '${dateFormat.format(report.startDate)} - ${dateFormat.format(report.endDate)}',
                    style: pw.TextStyle(fontSize: 14, color: PdfColors.grey600),
                  ),
                  pw.Divider(),
                ],
              ),
            ),

            // Summary
            pw.Header(level: 1, text: t('exp_summary')),
            pw.Table(
              border: pw.TableBorder.all(),
              children: [
                _pdfTableRow([t('exp_metric'), t('exp_value')], isHeader: true),
                _pdfTableRow([t('exp_totalItemsInStock'), '${report.currentStock.fold(0, (s, i) => s + i.quantity)}']),
                _pdfTableRow([t('exp_itemsIn'), '${report.totalItemsIn}']),
                _pdfTableRow([t('exp_itemsOut'), '${report.totalItemsOut}']),
                _pdfTableRow([t('exp_netChange'), '${report.netChange}']),
                _pdfTableRow([t('exp_lowStockItems'), '${report.lowStockCount}']),
              ],
            ),
            pw.SizedBox(height: 20),

            // Current Stock
            pw.Header(level: 1, text: t('exp_currentStockLevels')),
            pw.Table(
              border: pw.TableBorder.all(),
              children: [
                _pdfTableRow([t('exp_drinkName'), t('exp_quantity'), t('exp_minLevel'), t('exp_status')], isHeader: true),
                ...report.currentStock.map((item) => _pdfTableRow([
                  item.drinkName,
                  '${item.quantity}',
                  '${item.minStockLevel}',
                  item.isLowStock ? t('exp_lowStock') : t('exp_ok'),
                ])),
              ],
            ),
            pw.SizedBox(height: 20),

            // Sales by Category
            if (report.salesByCategory.isNotEmpty) ...[
              pw.Header(level: 1, text: t('exp_salesByCategory')),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  _pdfTableRow([t('exp_category'), t('exp_itemsSold')], isHeader: true),
                  ...report.salesByCategory.entries.map((e) => _pdfTableRow([e.key, '${e.value}'])),
                ],
              ),
              pw.SizedBox(height: 20),
            ],

            // Recent Transactions
            pw.Header(level: 1, text: t('exp_recentTransactions')),
            pw.Table(
              border: pw.TableBorder.all(),
              children: [
                _pdfTableRow([t('exp_date'), t('exp_drink'), t('exp_type'), t('exp_quantityLabel'), t('exp_reason')], isHeader: true),
                ...report.transactions.take(20).map((tx) => _pdfTableRow([
                  dateFormat.format(tx.date),
                  tx.drinkName,
                  tx.isIncoming ? t('exp_in') : t('exp_out'),
                  '${tx.quantity}',
                  tx.reason,
                ])),
              ],
            ),

            // Footer
            pw.SizedBox(height: 40),
            pw.Divider(),
            pw.Text(
              t('exp_generatedOn').replaceAll('@date', dateFormat.format(DateTime.now())),
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey400),
              textAlign: pw.TextAlign.center,
            ),
          ];
        },
      ),
    );

    // Save and share
 Directory output;
  try {
    if (Platform.isAndroid) {
      final downloadsDir = Directory('/storage/emulated/0/Download/Drink_Quick/Inventory_Reports');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      output = downloadsDir;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      output = Directory('${appDir.path}/Inventory_Reports');
      if (!await output.exists()) {
        await output.create(recursive: true);
      }
    }
  } catch (e) {
    final appDir = await getApplicationDocumentsDirectory();
    output = Directory('${appDir.path}/Inventory_Reports');
    if (!await output.exists()) {
      await output.create(recursive: true);
    }
  }
    final fileName = 'Inventory_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('exportPdf') + ' ' + t('exportSaved') + ': $fileName'), backgroundColor: Colors.green),
      );
    }

    await SharePlus.instance.share(ShareParams(
  files: [XFile(file.path)],
  subject: t('exp_inventoryReport'),
));
  }

  static pw.TableRow _pdfTableRow(List<String> cells, {bool isHeader = false}) {
    return pw.TableRow(
      decoration: isHeader ? const pw.BoxDecoration(color: PdfColors.grey200) : null,
      children: cells.map((cell) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(
          cell,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      )).toList(),
    );
  }

  // Excel Export
  static Future<void> _exportAsExcel(InventoryReport report, BuildContext context) async {
    final excel = Excel.createExcel();
    final dateFormat = DateFormat('MMM dd, yyyy');
    final sheet = excel[t('exp_inventoryReport')];

    // Summary sheet
    sheet.appendRow([t('exp_headerTitle')]);
    sheet.appendRow(['${t('exp_period')}: ${dateFormat.format(report.startDate)} - ${dateFormat.format(report.endDate)}']);
    sheet.appendRow(['${t('exp_generated')}: ${dateFormat.format(DateTime.now())}']);
    sheet.appendRow([]);
    sheet.appendRow([t('exp_summary').toUpperCase()]);
    sheet.appendRow([t('exp_metric'), t('exp_value')]);
    sheet.appendRow([t('exp_totalItemsInStock'), report.currentStock.fold(0, (s, i) => s + i.quantity)]);
    sheet.appendRow([t('exp_itemsIn'), report.totalItemsIn]);
    sheet.appendRow([t('exp_itemsOut'), report.totalItemsOut]);
    sheet.appendRow([t('exp_netChange'), report.netChange]);
    sheet.appendRow([t('exp_lowStockItems'), report.lowStockCount]);
    sheet.appendRow([]);
    sheet.appendRow([t('exp_currentStockHeader')]);
    sheet.appendRow([t('exp_drinkName'), t('exp_quantity'), t('exp_minLevel'), t('exp_status')]);
    for (final item in report.currentStock) {
      sheet.appendRow([item.drinkName, item.quantity, item.minStockLevel, item.isLowStock ? t('exp_low') : t('exp_ok')]);
    }
    sheet.appendRow([]);
    sheet.appendRow([t('exp_transactionsHeader')]);
    sheet.appendRow([t('exp_date'), t('exp_drink'), t('exp_type'), t('exp_quantityLabel'), t('exp_reason')]);
    for (final tx in report.transactions) {
      sheet.appendRow([dateFormat.format(tx.date), tx.drinkName, tx.isIncoming ? t('exp_in') : t('exp_out'), tx.quantity, tx.reason]);
    }

    // Save and share
     Directory output;
  try {
    if (Platform.isAndroid) {
      final downloadsDir = Directory('/storage/emulated/0/Download/Drink_Quick/Inventory_Reports');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      output = downloadsDir;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      output = Directory('${appDir.path}/Inventory_Reports');
      if (!await output.exists()) {
        await output.create(recursive: true);
      }
    }
  } catch (e) {
    final appDir = await getApplicationDocumentsDirectory();
    output = Directory('${appDir.path}/Inventory_Reports');
    if (!await output.exists()) {
      await output.create(recursive: true);
    }
  }
    final fileName = 'Inventory_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(excel.encode()!);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('exportExcel') + ' ' + t('exportSaved') + ': $fileName'), backgroundColor: Colors.green),
      );
    }

    await SharePlus.instance.share(ShareParams(
  files: [XFile(file.path)],
  subject: t('exp_inventoryReport'),
));
  }

  // CSV Export
  static Future<void> _exportAsCsv(InventoryReport report, BuildContext context) async {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final buffer = StringBuffer();

    buffer.writeln(t('exp_headerTitle'));
    buffer.writeln('${t('exp_period')}:,${dateFormat.format(report.startDate)} - ${dateFormat.format(report.endDate)}');
    buffer.writeln('${t('exp_generated')}:,${dateFormat.format(DateTime.now())}');
    buffer.writeln();
    buffer.writeln(t('exp_summary').toUpperCase());
    buffer.writeln('${t('exp_metric')},${t('exp_value')}');
    buffer.writeln('${t('exp_totalItemsInStock')},${report.currentStock.fold(0, (s, i) => s + i.quantity)}');
    buffer.writeln('${t('exp_itemsIn')},${report.totalItemsIn}');
    buffer.writeln('${t('exp_itemsOut')},${report.totalItemsOut}');
    buffer.writeln('${t('exp_netChange')},${report.netChange}');
    buffer.writeln('${t('exp_lowStockItems')},${report.lowStockCount}');
    buffer.writeln();
    buffer.writeln(t('exp_currentStockHeader'));
    buffer.writeln('${t('exp_drinkName')},${t('exp_quantity')},${t('exp_minLevel')},${t('exp_status')}');
    for (final item in report.currentStock) {
      buffer.writeln('${item.drinkName},${item.quantity},${item.minStockLevel},${item.isLowStock ? t('exp_low') : t('exp_ok')}');
    }
    buffer.writeln();
    buffer.writeln(t('exp_transactionsHeader'));
    buffer.writeln('${t('exp_date')},${t('exp_drink')},${t('exp_type')},${t('exp_quantityLabel')},${t('exp_reason')}');
    for (final tx in report.transactions) {
      buffer.writeln('${dateFormat.format(tx.date)},${tx.drinkName},${tx.isIncoming ? t('exp_in') : t('exp_out')},${tx.quantity},${tx.reason}');
    }

    // Save and share
     Directory output;
  try {
    if (Platform.isAndroid) {
      final downloadsDir = Directory('/storage/emulated/0/Download/Drink_Quick/Inventory_Reports');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      output = downloadsDir;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      output = Directory('${appDir.path}/Inventory_Reports');
      if (!await output.exists()) {
        await output.create(recursive: true);
      }
    }
  } catch (e) {
    final appDir = await getApplicationDocumentsDirectory();
    output = Directory('${appDir.path}/Inventory_Reports');
    if (!await output.exists()) {
      await output.create(recursive: true);
    }
  }
    final fileName = 'Inventory_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File('${output.path}/$fileName');
    await file.writeAsString(buffer.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('exportCsv') + ' ' + t('exportSaved') + ': $fileName'), backgroundColor: Colors.green),
      );
    }

    await SharePlus.instance.share(ShareParams(
  files: [XFile(file.path)],
  subject: t('exp_inventoryReport'),
));
  }
}