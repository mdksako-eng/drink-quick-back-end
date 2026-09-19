// utils/inventory_report_files.dart
// Professional PDF / Excel / CSV builders for the inventory report.
//
// The PDF is the presentation-ready one: company name, period, KPI boxes, two
// dependency-free bar charts (units sold per category + top movers) and the
// tables the user ticked in the export dialog. Everything is localized through
// the app's `t` function, so EN and FR both work.
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/drink_model.dart';
import '../models/inventory_model.dart';
import 'expiry_alert_helper.dart';

/// Which sections the user wants in the exported inventory report.
class InventoryExportOptions {
  /// KPI summary (stock total, items in/out, net change, low stock).
  final bool summary;

  /// The bar charts (units sold per category + top movers).
  final bool charts;

  /// Current stock table.
  final bool currentStock;

  /// Only the items at or below their minimum level.
  final bool lowStock;

  /// Batch expiry table (drinks with a production/expiry date).
  final bool expiry;

  /// Stock movement log for the period.
  final bool transactions;

  const InventoryExportOptions({
    this.summary = true,
    this.charts = true,
    this.currentStock = true,
    this.lowStock = true,
    this.expiry = true,
    this.transactions = true,
  });

  /// Everything included.
  static const InventoryExportOptions all = InventoryExportOptions();

  /// Nothing selected (the dialog refuses to export in that case).
  bool get isEmpty =>
      !summary && !charts && !currentStock && !lowStock && !expiry && !transactions;
}

/// One row of the expiry table (derived from the drinks' batch dates).
class InventoryExpiryRow {
  final String drinkName;
  final DateTime expiryDate;
  final int daysLeft;
  final bool isExpired;
  final int currentStock;

  const InventoryExpiryRow({
    required this.drinkName,
    required this.expiryDate,
    required this.daysLeft,
    required this.isExpired,
    required this.currentStock,
  });
}

class InventoryReportFiles {
  InventoryReportFiles._();

  /// Rows for the expiry section: every drink that carries an expiry date,
  /// soonest first (drinks without a date are skipped).
  static List<InventoryExpiryRow> expiryRows(List<Drink> drinks) {
    final rows = <InventoryExpiryRow>[];
    for (final alert in computeExpiryAlerts(drinks: drinks)) {
      rows.add(InventoryExpiryRow(
        drinkName: alert.drinkName,
        expiryDate: alert.expiryDate,
        daysLeft: alert.daysLeft,
        isExpired: alert.isExpired,
        currentStock: alert.currentStock,
      ));
    }
    return rows;
  }

  /// Total units moved per drink (in + out), biggest first — the "top movers"
  /// chart. Pure, so the chart and the spreadsheet always agree.
  static List<MapEntry<String, int>> topMovers(InventoryReport report,
      {int limit = 8}) {
    final totals = <String, int>{};
    for (final tx in report.transactions) {
      totals[tx.drinkName] = (totals[tx.drinkName] ?? 0) + tx.quantity;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// Units sold per category, biggest first.
  static List<MapEntry<String, int>> categorySales(InventoryReport report,
      {int limit = 8}) {
    final sorted = report.salesByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// Total units currently in stock.
  static int totalInStock(InventoryReport report) =>
      report.currentStock.fold(0, (sum, item) => sum + item.quantity);

  /// The low-stock items of the report, worst first.
  static List<InventoryItem> lowStockItems(InventoryReport report) {
    final items = report.currentStock.where((item) => item.isLowStock).toList()
      ..sort((a, b) => a.quantity.compareTo(b.quantity));
    return items;
  }
// ============================================================
  //  PDF — the presentation-ready report
  // ============================================================
  static Future<List<int>> buildPdf({
    required InventoryReport report,
    required String Function(String key) t,
    String? companyName,
    List<Drink> drinks = const [],
    InventoryExportOptions options = InventoryExportOptions.all,
    DateTime? generatedAt,
  }) async {
    final doc = pw.Document();
    final generated = generatedAt ?? DateTime.now();
    final expiry = expiryRows(drinks);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          _pdfHeader(t, companyName, report),
          if (options.summary) ...[
            pw.SizedBox(height: 12),
            _pdfSectionTitle(t('exp_summary')),
            _pdfKpiBoxes(report, expiry, t),
          ],
          if (options.charts) ...[
            pw.SizedBox(height: 14),
            _pdfSectionTitle(t('inv_unitsPerCategory')),
            _pdfBarChart(
              data: categorySales(report),
              color: PdfColor.fromInt(0xFF4361EE),
              emptyLabel: t('inv_noMovement'),
            ),
            pw.SizedBox(height: 14),
            _pdfSectionTitle(t('inv_topMovers')),
            _pdfBarChart(
              data: topMovers(report),
              color: PdfColor.fromInt(0xFF2A9D8F),
              emptyLabel: t('inv_noMovement'),
            ),
          ],
          if (options.currentStock && report.currentStock.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _pdfSectionTitle(t('exp_currentStockHeader')),
            _pdfTable(
              headers: [
                t('exp_drinkName'),
                t('exp_category'),
                t('exp_quantity'),
                t('exp_minLevel'),
                t('exp_status'),
              ],
              rows: report.currentStock
                  .map((i) => [
                        i.drinkName,
                        i.category,
                        '${i.quantity}',
                        '${i.minStockLevel}',
                        i.isLowStock ? t('exp_low') : t('exp_ok'),
                      ])
                  .toList(),
            ),
          ],
          if (options.lowStock && lowStockItems(report).isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _pdfSectionTitle(t('exp_lowStockItems')),
            _pdfTable(
              headers: [
                t('exp_drinkName'),
                t('exp_quantity'),
                t('exp_minLevel'),
                t('exp_suggestedOrder'),
              ],
              rows: lowStockItems(report)
                  .map((i) => [
                        i.drinkName,
                        '${i.quantity}',
                        '${i.minStockLevel}',
                        '${i.minStockLevel * 2 - i.quantity}',
                      ])
                  .toList(),
            ),
          ],
if (options.expiry && expiry.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _pdfSectionTitle(t('expiryAlertTitle')),
            _pdfTable(
              headers: [
                t('exp_drinkName'),
                t('dm_expiryDate'),
                t('exp_quantity'),
                t('exp_status'),
              ],
              rows: expiry
                  .map((r) => [
                        r.drinkName,
                        _date(r.expiryDate),
                        '${r.currentStock}',
                        r.isExpired
                            ? t('expiryAlreadyExpired')
                            : '${r.daysLeft} ${t('expiryDaysLeft')}',
                      ])
                  .toList(),
            ),
          ],
          if (options.transactions && report.transactions.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _pdfSectionTitle(t('exp_transactionsHeader')),
            _pdfTable(
              headers: [
                t('exp_date'),
                t('exp_drink'),
                t('exp_type'),
                t('exp_quantityLabel'),
                t('exp_reason'),
              ],
              rows: report.transactions
                  .take(120)
                  .map((tx) => [
                        _date(tx.date),
                        tx.drinkName,
                        tx.isIncoming ? t('exp_in') : t('exp_out'),
                        '${tx.quantity}',
                        tx.reason,
                      ])
                  .toList(),
            ),
          ],
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${t('exp_generated')} ${_dateTime(generated)}  •  '
            '${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );

    return doc.save();
  }
// ------------------------------------------------------------
  // PDF building blocks
  // ------------------------------------------------------------
  static pw.Widget _pdfHeader(
      String Function(String) t, String? companyName, InventoryReport report) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (companyName != null && companyName.trim().isNotEmpty)
          pw.Text(companyName.trim(),
              style:
                  pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.Text(t('exp_inventoryReport'),
            style: const pw.TextStyle(fontSize: 15)),
        pw.SizedBox(height: 4),
        pw.Text(
          '${t('exp_period')}: ${_date(report.startDate)} - ${_date(report.endDate)}',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 6),
        pw.Divider(color: PdfColors.grey400),
      ],
    );
  }

  static pw.Widget _pdfSectionTitle(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(title,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _pdfKpiBoxes(
      InventoryReport report, List<InventoryExpiryRow> expiry,
      String Function(String) t) {
    final expired = expiry.where((e) => e.isExpired).length;
    pw.Widget box(String label, String value) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(label,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700)),
              ],
            ),
          ),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(children: [
          box(t('exp_totalItemsInStock'), '${totalInStock(report)}'),
          box(t('exp_itemsIn'), '${report.totalItemsIn}'),
          box(t('exp_itemsOut'), '${report.totalItemsOut}'),
          box(t('exp_netChange'), '${report.netChange}'),
        ]),
        pw.SizedBox(height: 4),
        pw.Row(children: [
          box(t('exp_lowStockItems'), '${lowStockItems(report).length}'),
          box(t('expiryAlertTitle'), '${expiry.length}'),
          box(t('expiryAlreadyExpired'), '$expired'),
          box(t('exp_transactionsHeader'), '${report.transactions.length}'),
        ]),
      ],
    );
  }
/// Horizontal bar chart of `label: value` pairs (dependency-free).
  static pw.Widget _pdfBarChart({
    required List<MapEntry<String, int>> data,
    required PdfColor color,
    required String emptyLabel,
  }) {
    if (data.isEmpty) {
      return pw.Text(emptyLabel,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600));
    }
    final maxValue = data.first.value == 0 ? 1 : data.first.value;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: data.map((entry) {
        final ratio = maxValue == 0 ? 0.0 : entry.value / maxValue;
        final filled = (ratio * 1000).round().clamp(1, 1000);
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(
                width: 110,
                child: pw.Text(entry.key,
                    style: const pw.TextStyle(fontSize: 9),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip),
              ),
              pw.Expanded(
                child: pw.SizedBox(
                  height: 10,
                  // A filled segment over a light track: the ratio is expressed
                  // with layout, so no graphics layer is required.
                  child: pw.Row(children: [
                    pw.Expanded(
                        flex: filled, child: pw.Container(color: color)),
                    pw.Expanded(
                        flex: 1000 - filled + 1,
                        child:
                            pw.Container(color: PdfColor.fromInt(0xFFEDEFF5))),
                  ]),
                ),
              ),
              pw.SizedBox(
                width: 40,
                child: pw.Text(' ${entry.value}',
                    style: const pw.TextStyle(fontSize: 9)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static pw.Widget _pdfTable(
      {required List<String> headers, required List<List<String>> rows}) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: headers
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(h,
                        style: pw.TextStyle(
                            fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  ))
              .toList(),
        ),
        ...rows.map((row) => pw.TableRow(
              children: row
                  .map((cell) => pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(cell,
                            style: const pw.TextStyle(fontSize: 9.5)),
                      ))
                  .toList(),
            )),
      ],
    );
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _dateTime(DateTime d) =>
      '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

// ============================================================
  //  EXCEL — one sheet per selected section
  // ============================================================
  static List<int>? buildExcel({
    required InventoryReport report,
    required String Function(String key) t,
    String? companyName,
    List<Drink> drinks = const [],
    InventoryExportOptions options = InventoryExportOptions.all,
    DateTime? generatedAt,
  }) {
    try {
      final excel = Excel.createExcel();
      final generated = generatedAt ?? DateTime.now();
      final expiry = expiryRows(drinks);

      void header(Sheet sheet, String title) {
        sheet.appendRow([title]);
        if (companyName != null && companyName.trim().isNotEmpty) {
          sheet.appendRow([
            '${t('companyName')}: ${companyName.trim()}',
          ]);
        }
        sheet.appendRow([
          
              '${t('exp_period')}: ${_date(report.startDate)} - ${_date(report.endDate)}',
        ]);
        sheet.appendRow([
          '${t('exp_generated')}: ${_dateTime(generated)}',
        ]);
        sheet.appendRow([]);
      }

      if (options.summary) {
        final sheet = excel['Summary'];
        header(sheet, t('exp_inventoryReport'));
        sheet.appendRow(
            [t('exp_metric'), t('exp_value')]);
        sheet.appendRow([
          t('exp_totalItemsInStock'),
          totalInStock(report),
        ]);
        sheet.appendRow(
            [t('exp_itemsIn'), report.totalItemsIn]);
        sheet.appendRow([
          t('exp_itemsOut'),
          report.totalItemsOut,
        ]);
        sheet.appendRow([
          t('exp_netChange'),
          report.netChange,
        ]);
        sheet.appendRow([
          t('exp_lowStockItems'),
          lowStockItems(report).length,
        ]);
        sheet.appendRow([
          t('expiryAlertTitle'),
          expiry.length,
        ]);
      }

      if (options.charts) {
        final sheet = excel['Charts'];
        header(sheet, t('inv_unitsPerCategory'));
        sheet.appendRow(
            [t('exp_category'), t('exp_quantity')]);
        for (final entry in categorySales(report)) {
          sheet.appendRow([entry.key, entry.value]);
        }
        sheet.appendRow([]);
        sheet.appendRow([t('inv_topMovers')]);
        sheet.appendRow([
          t('exp_drinkName'),
          t('exp_quantity'),
        ]);
        for (final entry in topMovers(report)) {
          sheet.appendRow([entry.key, entry.value]);
        }
      }
if (options.currentStock && report.currentStock.isNotEmpty) {
        final sheet = excel['CurrentStock'];
        header(sheet, t('exp_currentStockHeader'));
        sheet.appendRow([
          t('exp_drinkName'),
          t('exp_category'),
          t('exp_quantity'),
          t('exp_minLevel'),
          t('exp_status'),
        ]);
        for (final item in report.currentStock) {
          sheet.appendRow([
            item.drinkName,
            item.category,
            item.quantity,
            item.minStockLevel,
            item.isLowStock ? t('exp_low') : t('exp_ok'),
          ]);
        }
      }

      if (options.lowStock && lowStockItems(report).isNotEmpty) {
        final sheet = excel['LowStock'];
        header(sheet, t('exp_lowStockItems'));
        sheet.appendRow([
          t('exp_drinkName'),
          t('exp_quantity'),
          t('exp_minLevel'),
          t('exp_suggestedOrder'),
        ]);
        for (final item in lowStockItems(report)) {
          sheet.appendRow([
            item.drinkName,
            item.quantity,
            item.minStockLevel,
            item.minStockLevel * 2 - item.quantity,
          ]);
        }
      }

      if (options.expiry && expiry.isNotEmpty) {
        final sheet = excel['Expiry'];
        header(sheet, t('expiryAlertTitle'));
        sheet.appendRow([
          t('exp_drinkName'),
          t('dm_expiryDate'),
          t('exp_quantity'),
          t('exp_status'),
        ]);
        for (final row in expiry) {
          sheet.appendRow([
            row.drinkName,
            _date(row.expiryDate),
            row.currentStock,
            row.isExpired
                ? t('expiryAlreadyExpired')
                : '${row.daysLeft} ${t('expiryDaysLeft')}',
          ]);
        }
      }

      if (options.transactions && report.transactions.isNotEmpty) {
        final sheet = excel['Movements'];
        header(sheet, t('exp_transactionsHeader'));
        sheet.appendRow([
          t('exp_date'),
          t('exp_drink'),
          t('exp_type'),
          t('exp_quantityLabel'),
          t('exp_reason'),
        ]);
        for (final tx in report.transactions) {
          sheet.appendRow([
            _date(tx.date),
            tx.drinkName,
            tx.isIncoming ? t('exp_in') : t('exp_out'),
            tx.quantity,
            tx.reason,
          ]);
        }
      }

      // Drop the empty default sheet when at least one real sheet exists.
      try {
        if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
          excel.delete('Sheet1');
        }
      } catch (_) {}

      return excel.encode();
    } catch (e) {
      return null;
    }
  }
// ============================================================
  //  CSV — same sections, RFC-4180 escaped
  // ============================================================
  static String buildCsv({
    required InventoryReport report,
    required String Function(String key) t,
    String? companyName,
    List<Drink> drinks = const [],
    InventoryExportOptions options = InventoryExportOptions.all,
    DateTime? generatedAt,
  }) {
    final buffer = StringBuffer();
    final generated = generatedAt ?? DateTime.now();
    final expiry = expiryRows(drinks);

    buffer.writeln(_csv(companyName == null || companyName.trim().isEmpty
        ? t('exp_inventoryReport')
        : companyName.trim()));
    buffer.writeln(_csv(t('exp_inventoryReport')));
    buffer.writeln('${_csv(t('exp_period'))},'
        '${_csv('${_date(report.startDate)} - ${_date(report.endDate)}')}');
    buffer.writeln('${_csv(t('exp_generated'))},'
        '${_csv(_dateTime(generated))}');

    if (options.summary) {
      buffer.writeln();
      buffer.writeln(_csv(t('exp_summary')));
      buffer.writeln('${_csv(t('exp_metric'))},${_csv(t('exp_value'))}');
      buffer.writeln('${_csv(t('exp_totalItemsInStock'))},'
          '${totalInStock(report)}');
      buffer.writeln('${_csv(t('exp_itemsIn'))},${report.totalItemsIn}');
      buffer.writeln('${_csv(t('exp_itemsOut'))},${report.totalItemsOut}');
      buffer.writeln('${_csv(t('exp_netChange'))},${report.netChange}');
      buffer.writeln(
          '${_csv(t('exp_lowStockItems'))},${lowStockItems(report).length}');
      buffer.writeln('${_csv(t('expiryAlertTitle'))},${expiry.length}');
    }

    if (options.charts) {
      buffer.writeln();
      buffer.writeln(_csv(t('inv_unitsPerCategory')));
      buffer.writeln('${_csv(t('exp_category'))},${_csv(t('exp_quantity'))}');
      for (final entry in categorySales(report)) {
        buffer.writeln('${_csv(entry.key)},${entry.value}');
      }
      buffer.writeln();
      buffer.writeln(_csv(t('inv_topMovers')));
      for (final entry in topMovers(report)) {
        buffer.writeln('${_csv(entry.key)},${entry.value}');
      }
    }

    if (options.currentStock && report.currentStock.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(_csv(t('exp_currentStockHeader')));
      buffer.writeln([
        _csv(t('exp_drinkName')),
        _csv(t('exp_category')),
        _csv(t('exp_quantity')),
        _csv(t('exp_minLevel')),
        _csv(t('exp_status')),
      ].join(','));
      for (final item in report.currentStock) {
        buffer.writeln([
          _csv(item.drinkName),
          _csv(item.category),
          '${item.quantity}',
          '${item.minStockLevel}',
          _csv(item.isLowStock ? t('exp_low') : t('exp_ok')),
        ].join(','));
      }
    }

    if (options.lowStock && lowStockItems(report).isNotEmpty) {
      buffer.writeln();
      buffer.writeln(_csv(t('exp_lowStockItems')));
      for (final item in lowStockItems(report)) {
        buffer.writeln([
          _csv(item.drinkName),
          '${item.quantity}',
          '${item.minStockLevel}',
          '${item.minStockLevel * 2 - item.quantity}',
        ].join(','));
      }
    }

    if (options.expiry && expiry.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(_csv(t('expiryAlertTitle')));
      buffer.writeln([
        _csv(t('exp_drinkName')),
        _csv(t('dm_expiryDate')),
        _csv(t('exp_quantity')),
        _csv(t('exp_status')),
      ].join(','));
      for (final row in expiry) {
        buffer.writeln([
          _csv(row.drinkName),
          _csv(_date(row.expiryDate)),
          '${row.currentStock}',
          _csv(row.isExpired
              ? t('expiryAlreadyExpired')
              : '${row.daysLeft} ${t('expiryDaysLeft')}'),
        ].join(','));
      }
    }

    if (options.transactions && report.transactions.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(_csv(t('exp_transactionsHeader')));
      buffer.writeln([
        _csv(t('exp_date')),
        _csv(t('exp_drink')),
        _csv(t('exp_type')),
        _csv(t('exp_quantityLabel')),
        _csv(t('exp_reason')),
      ].join(','));
      for (final tx in report.transactions) {
        buffer.writeln([
          _csv(_date(tx.date)),
          _csv(tx.drinkName),
          _csv(tx.isIncoming ? t('exp_in') : t('exp_out')),
          '${tx.quantity}',
          _csv(tx.reason),
        ].join(','));
      }
    }

    return buffer.toString();
  }

  /// RFC-4180 style escaping: quote when the value contains a separator, quote
  /// or line break (drink names and reasons are arbitrary text).
  static String _csv(String value) {
    if (!value.contains(',') &&
        !value.contains('"') &&
        !value.contains('\n') &&
        !value.contains('\r')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }
}