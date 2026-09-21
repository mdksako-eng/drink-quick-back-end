// utils/analytics_report_files.dart
// Professional PDF / Excel builders for the manager dashboard report.
// Reuses AnalyticsExport for labels/formatting so EN + FR both work.
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/analytics_model.dart';
import 'analytics_export.dart';
import 'currency_helper.dart';

class AnalyticsReportFiles {
  /// Visual PDF report: header with company name, KPI boxes, profit, a revenue
  /// bar chart and the data tables the user selected.
  static Future<List<int>> buildPdf({
    required AnalyticsSnapshot snapshot,
    required DateTime startDate,
    required DateTime endDate,
    required String Function(String key) t,
    String? companyName,
    Uint8List? logoBytes,
    AnalyticsExportOptions options = AnalyticsExportOptions.all,
    ProfitSummary? profit,
    DateTime? generatedAt,
  }) async {
    final doc = pw.Document();
    final generated = generatedAt ?? DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          _pdfHeader(t, companyName, startDate, endDate, logoBytes),
          if (options.summary) ...[
            pw.SizedBox(height: 12),
            _pdfSectionTitle(t('dashSummary')),
            _pdfKpiBoxes(snapshot, t),
          ],
          if (options.profit && profit != null) ...[
            pw.SizedBox(height: 12),
            _pdfSectionTitle(t('dashProfit')),
            _pdfTable(
              headers: [t('dashMetric'), t('dashValue')],
              rows: [
                [t('dashRevenue'), _money(profit.revenue)],
                [t('dashCostOfGoods'), _money(profit.cost)],
                [t('dashGrossProfit'), _money(profit.profit)],
                [t('dashMargin'), '${profit.marginPercent.toStringAsFixed(1)}%'],
              ],
            ),
          ],
          if (options.revenueChart && snapshot.revenueValues.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _pdfSectionTitle(t('dashRevenueTrend')),
            _pdfBarChart(snapshot),
          ],
          if (options.staff && snapshot.staffSales.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _pdfSectionTitle(t('dashSalesByStaff')),
            _pdfTable(
              headers: [
                t('username'),
                t('dashOrders'),
                t('dashItemsSold'),
                t('dashTotalRevenue'),
                t('dashShareOfRevenue'),
              ],
              rows: snapshot.staffSales
                  .map((s) => [
                        s.name,
                        '${s.orders}',
                        '${s.itemsSold}',
                        _money(s.revenue),
                        '${_share(s.revenue, snapshot.totalRevenue).toStringAsFixed(1)}%',
                      ])
                  .toList(),
            ),
          ],
          if (options.popularItems && snapshot.popularItems.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _pdfSectionTitle(t('dashPopularItems')),
            _pdfTable(
              headers: [
                t('exp_drinkName'),
                t('quantity'),
                t('dashTotalRevenue'),
              ],
              rows: snapshot.popularItems
                  .take(15)
                  .map((i) => [i.name, '${i.quantity}', _money(i.revenue)])
                  .toList(),
            ),
          ],
          if (options.categories && snapshot.categoryMix.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _pdfSectionTitle(t('dashCategoryMix')),
            _pdfTable(
              headers: [t('exp_category'), t('dashItemsSold'), t('dashShare')],
              rows: snapshot.categoryMix
                  .map((c) => [
                        c.category,
                        '${c.count}',
                        '${_share(c.count.toDouble(), snapshot.totalItemsSold.toDouble()).toStringAsFixed(1)}%',
                      ])
                  .toList(),
            ),
          ],
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('${t('exp_generated')} ${_date(generated)}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ),
      ),
    );

    return doc.save();
  }
  static pw.Widget _pdfHeader(
      String Function(String) t,
      String? companyName,
      DateTime startDate,
      DateTime endDate,
      [Uint8List? logoBytes]) {
    final hasName = companyName != null && companyName.trim().isNotEmpty;
    final nameBlock = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (hasName)
          pw.Text(companyName.trim(),
              style:
                  pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.Text(t('dashTitle'), style: const pw.TextStyle(fontSize: 16)),
        pw.SizedBox(height: 4),
        pw.Text(
          '${t('exp_period')}: ${_date(startDate)} - ${_date(endDate)}',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
      ],
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoBytes != null)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 52,
                height: 52,
                padding: const pw.EdgeInsets.all(2),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child:
                    pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(child: nameBlock),
            ],
          )
        else
          nameBlock,
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
      AnalyticsSnapshot s, String Function(String) t) {
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

    return pw.Row(children: [
      box(t('dashTotalRevenue'), _money(s.totalRevenue)),
      box(t('dashOrders'), '${s.totalOrders}'),
      box(t('dashItemsSold'), '${s.totalItemsSold}'),
      box(t('dashAvgOrder'), _money(s.averageOrderValue)),
    ]);
  }

  /// Simple, dependency-free bar chart of the daily revenue trend.
  static pw.Widget _pdfBarChart(AnalyticsSnapshot s) {
    final values = s.revenueValues;
    final maxValue =
        values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final step = values.length > 16 ? (values.length / 16).ceil() : 1;
    final bars = <pw.Widget>[];
    for (var i = 0; i < values.length; i += step) {
      final ratio = maxValue == 0 ? 0.0 : values[i] / maxValue;
      bars.add(pw.Container(
        width: 12,
        height: 4 + (ratio * 80),
        margin: const pw.EdgeInsets.symmetric(horizontal: 1.5),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFF4361EE),
          borderRadius: pw.BorderRadius.circular(2),
        ),
      ));
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          height: 90,
          alignment: pw.Alignment.bottomLeft,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: bars,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${s.revenueLabels.isNotEmpty ? s.revenueLabels.first : ''} - '
          '${s.revenueLabels.isNotEmpty ? s.revenueLabels.last : ''}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
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
                            fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ))
              .toList(),
        ),
        ...rows.map((row) => pw.TableRow(
              children: row
                  .map((cell) => pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(cell,
                            style: const pw.TextStyle(fontSize: 10)),
                      ))
                  .toList(),
            )),
      ],
    );
  }

  static String _money(double v) => CurrencyHelper.format(v);

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static double _share(double part, double whole) =>
      whole == 0 ? 0.0 : (part / whole) * 100;

  // ============================================================
  // 📊 EXCEL (one sheet per section, company name in the header row)
  // ============================================================
  static List<int>? buildExcel({
    required AnalyticsSnapshot snapshot,
    required DateTime startDate,
    required DateTime endDate,
    required String Function(String key) t,
    String? companyName,
    String? logoUrl,
    AnalyticsExportOptions options = AnalyticsExportOptions.all,
    ProfitSummary? profit,
    DateTime? generatedAt,
  }) {
    final excel = Excel.createExcel();
    final generated = generatedAt ?? DateTime.now();

    void header(Sheet sheet, String title) {
      sheet.appendRow([title]);
      if (companyName != null && companyName.trim().isNotEmpty) {
        sheet.appendRow([companyName.trim()]);
      }
      if (logoUrl != null && logoUrl.trim().isNotEmpty) {
        sheet.appendRow(['${t('branding_title')}: ${logoUrl.trim()}']);
      }
      sheet.appendRow([
        t('exp_period'),
        '${_date(startDate)} - ${_date(endDate)}',
      ]);
      sheet.appendRow([t('exp_generated'), _date(generated)]);
      sheet.appendRow([]);
    }

    // ---------- Summary ----------
    final summary = excel['Summary'];
    header(summary, t('dashSummary'));
    if (options.summary) {
      summary.appendRow([t('dashMetric'), t('dashValue')]);
      summary.appendRow([t('dashTotalRevenue'), snapshot.totalRevenue]);
      summary.appendRow([t('dashOrders'), snapshot.totalOrders]);
      summary.appendRow([t('dashItemsSold'), snapshot.totalItemsSold]);
      summary.appendRow([t('dashAvgOrder'), snapshot.averageOrderValue]);
    }
    if (options.profit && profit != null) {
      summary.appendRow([]);
      summary.appendRow([t('dashProfit')]);
      summary.appendRow([t('dashRevenue'), profit.revenue]);
      summary.appendRow([t('dashCostOfGoods'), profit.cost]);
      summary.appendRow([t('dashGrossProfit'), profit.profit]);
      summary.appendRow([
        t('dashMargin'),
        double.parse(profit.marginPercent.toStringAsFixed(2)),
      ]);
    }

    // ---------- Sales by staff ----------
    if (options.staff) {
      final sheet = excel['SalesByStaff'];
      header(sheet, t('dashSalesByStaff'));
      sheet.appendRow([
        t('username'),
        t('dashOrders'),
        t('dashItemsSold'),
        t('dashTotalRevenue'),
        t('dashShareOfRevenue'),
      ]);
      for (final s in snapshot.staffSales) {
        sheet.appendRow([
          s.name,
          s.orders,
          s.itemsSold,
          s.revenue,
          double.parse(
              _share(s.revenue, snapshot.totalRevenue).toStringAsFixed(2)),
        ]);
      }
    }

    // ---------- Popular items ----------
    if (options.popularItems) {
      final sheet = excel['PopularItems'];
      header(sheet, t('dashPopularItems'));
      sheet.appendRow([t('exp_drinkName'), t('quantity'), t('dashTotalRevenue')]);
      for (final i in snapshot.popularItems) {
        sheet.appendRow([i.name, i.quantity, i.revenue]);
      }
    }

    // ---------- Category mix ----------
    if (options.categories) {
      final sheet = excel['Categories'];
      header(sheet, t('dashCategoryMix'));
      sheet.appendRow([t('exp_category'), t('dashItemsSold'), t('dashShare')]);
      for (final c in snapshot.categoryMix) {
        sheet.appendRow([
          c.category,
          c.count,
          double.parse(_share(c.count.toDouble(),
                  snapshot.totalItemsSold.toDouble())
              .toStringAsFixed(2)),
        ]);
      }
    }

    // ---------- Revenue trend ----------
    if (options.revenueChart && snapshot.revenueValues.isNotEmpty) {
      final sheet = excel['RevenueTrend'];
      header(sheet, t('dashRevenueTrend'));
      sheet.appendRow([t('dashDay'), t('dashRevenue')]);
      for (var i = 0; i < snapshot.revenueValues.length; i++) {
        final label = i < snapshot.revenueLabels.length
            ? snapshot.revenueLabels[i]
            : '${i + 1}';
        sheet.appendRow([label, snapshot.revenueValues[i]]);
      }
    }

    // Remove the default empty sheet the package creates (some versions refuse —
    // an empty sheet is harmless, so never fail the export over it).
    try {
      if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
        excel.delete('Sheet1');
      }
    } catch (_) {}

    return excel.encode();
  }
}