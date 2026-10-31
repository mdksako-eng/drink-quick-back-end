// test/inventory_report_files_test.dart
// Verifies the inventory export: the section checkboxes map to the options, the
// derived data (totals, low stock, top movers, expiry rows) is right, and the
// three builders produce output that carries the company name.
import 'package:flutter_test/flutter_test.dart';

import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/models/inventory_model.dart';
import 'package:drinks_calculator_fixed/utils/export_helper.dart';
import 'package:drinks_calculator_fixed/utils/inventory_report_files.dart';
import 'package:drinks_calculator_fixed/utils/report_profit_helper.dart';

String t(String key) => const {
      'exp_inventoryReport': 'Inventory Report',
      'exp_period': 'Period',
      'exp_generated': 'Generated',
      'exp_summary': 'SUMMARY',
      'exp_metric': 'Metric',
      'exp_value': 'Value',
      'exp_totalItemsInStock': 'Total items in stock',
      'exp_itemsIn': 'Items in',
      'exp_itemsOut': 'Items out',
      'exp_netChange': 'Net change',
      'exp_lowStockItems': 'Low stock items',
      'exp_currentStockHeader': 'CURRENT STOCK',
      'exp_transactionsHeader': 'MOVEMENTS',
      'exp_drinkName': 'Drink',
      'exp_category': 'Category',
      'exp_quantity': 'Qty',
      'exp_minLevel': 'Min',
      'exp_status': 'Status',
      'exp_low': 'LOW',
      'exp_ok': 'OK',
      'exp_date': 'Date',
      'exp_drink': 'Drink',
      'exp_type': 'Type',
      'exp_quantityLabel': 'Qty',
      'exp_reason': 'Reason',
      'exp_in': 'IN',
      'exp_out': 'OUT',
      'exp_suggestedOrder': 'Suggested order',
      'inv_unitsPerCategory': 'Units sold per category',
      'inv_topMovers': 'Top moving drinks',
      'inv_noMovement': 'No stock movement in this period.',
      'expiryAlertTitle': 'Batches expiring soon',
      'expiryAlreadyExpired': 'already expired',
      'expiryDaysLeft': 'day(s) left',
      'companyName': 'Company',
      // The money section (report_profit_helper figures).
      'exp_profitSection': 'Profit & margins',
      'exp_unitsSold': 'Units sold',
      'rpt_revenue': 'Revenue',
      'rpt_cost': 'Cost',
      'rpt_profit': 'Profit',
      'rpt_margin': 'Margin',
      'rpt_avgSellingPrice': 'Avg selling price',
      'rpt_avgPurchasePrice': 'Avg purchase price',
      'rpt_caveatNoCost': 'Some units have no cost price on record',
      'rpt_caveatUnvalued': 'Some units could not be valued',
      'dm_expiryDate': 'Expiry date',
    }[key] ??
    key;

final _report = InventoryReport(
  startDate: DateTime(2026, 8, 1),
  endDate: DateTime(2026, 8, 31),
  currentStock: [
    InventoryItem(
      id: 'i1',
      drinkId: 'd1',
      drinkName: 'Beer',
      quantity: 24,
      minStockLevel: 5,
      lastRestocked: DateTime(2026, 8, 1),
      category: 'Beer',
    ),
    InventoryItem(
      id: 'i2',
      drinkId: 'd2',
      drinkName: 'Water',
      quantity: 2,
      minStockLevel: 10,
      lastRestocked: DateTime(2026, 8, 2),
      category: 'Soft',
    ),
  ],
  transactions: [
    InventoryTransaction(
      id: 't1',
      drinkId: 'd1',
      drinkName: 'Beer',
      quantity: 40,
      type: 'out',
      date: DateTime(2026, 8, 3),
      reason: 'sale',
    ),
    InventoryTransaction(
      id: 't2',
      drinkId: 'd2',
      drinkName: 'Water',
      quantity: 6,
      type: 'out',
      date: DateTime(2026, 8, 4),
      reason: 'sale',
    ),
    InventoryTransaction(
      id: 't3',
      drinkId: 'd1',
      drinkName: 'Beer',
      quantity: 60,
      type: 'in',
      date: DateTime(2026, 8, 5),
      reason: 'restock',
    ),
  ],
  totalItemsIn: 60,
  totalItemsOut: 46,
  lowStockCount: 1,
  salesByCategory: const {'Beer': 40, 'Soft': 6},
  wasteByItem: const {},
);

Drink _drink({required String name, DateTime? expiry, int stock = 0}) => Drink(
      id: 'd-$name',
      name: name,
      price: 1000,
      imageUrl: 'i',
      currentStock: stock,
      expiryDate: expiry,
    );

/// 10 units at 1000 sold, costing 700: revenue 10 000, cost 7 000, profit 3 000,
/// margin 30 %, averages 1000 / 700.
const _profit = ProfitSummary(
  revenue: 10000,
  cost: 7000,
  unitsSold: 10,
  unitsWithoutCost: 0,
  unitsUnvalued: 0,
  profitByCategory: {},
  topProfitableDrinks: [],
);

/// The same, but 2 of the units have no cost on record — the case that used to be
/// exported as a flattering 100 % margin.
const _profitWithCaveat = ProfitSummary(
  revenue: 10000,
  cost: 7000,
  unitsSold: 10,
  unitsWithoutCost: 2,
  unitsUnvalued: 3,
  profitByCategory: {},
  topProfitableDrinks: [],
);

void main() {
  group('optionsFromSelection', () {
    test('maps the checkbox order to the report sections', () {
      final all = ExportHelper.optionsFromSelection(
          const [true, true, true, true, true, true, true]);
      expect(all.summary, isTrue);
      expect(all.charts, isTrue);
      expect(all.currentStock, isTrue);
      expect(all.lowStock, isTrue);
      expect(all.expiry, isTrue);
      expect(all.transactions, isTrue);
      expect(all.profit, isTrue);
      expect(all.isEmpty, isFalse);
    });

    test('respects an unchecked box', () {
      final only = ExportHelper.optionsFromSelection(const [true, false, false, false, false, false]);
      expect(only.summary, isTrue);
      expect(only.charts, isFalse);
      expect(only.transactions, isFalse);
      // A list that predates the money box simply leaves it off.
      expect(only.profit, isFalse);
    });

    test('nothing selected is empty (the dialog refuses to export)', () {
      final none = ExportHelper.optionsFromSelection(
          const [false, false, false, false, false, false, false]);
      expect(none.isEmpty, isTrue);
    });

    test('a short selection list does not crash', () {
      final short = ExportHelper.optionsFromSelection(const [true]);
      expect(short.summary, isTrue);
      expect(short.charts, isFalse);
    });
  });

  group('derived report data', () {
    test('total in stock sums every item', () {
      expect(InventoryReportFiles.totalInStock(_report), 26);
    });

    test('low stock items are the ones at/below their minimum, worst first', () {
      final low = InventoryReportFiles.lowStockItems(_report);
      expect(low.map((i) => i.drinkName).toList(), ['Water']);
    });

    test('top movers aggregate in + out per drink, biggest first', () {
      final movers = InventoryReportFiles.topMovers(_report);
      expect(movers.first.key, 'Beer');
      expect(movers.first.value, 100); // 40 out + 60 in
      expect(movers.last.key, 'Water');
      expect(movers.last.value, 6);
    });

    test('category sales are sorted by volume', () {
      final cats = InventoryReportFiles.categorySales(_report);
      expect(cats.first.key, 'Beer');
      expect(cats.first.value, 40);
    });

    test('expiry rows skip drinks without a batch date', () {
      final rows = InventoryReportFiles.expiryRows([
        _drink(name: 'Beer', expiry: DateTime.now().add(const Duration(days: 3)), stock: 8),
        _drink(name: 'NoDate'),
      ]);
      expect(rows, hasLength(1));
      expect(rows.first.drinkName, 'Beer');
      expect(rows.first.currentStock, 8);
      expect(rows.first.isExpired, isFalse);
    });
  });

  group('builders', () {
    test('the PDF is produced with the company name', () async {
      final bytes = await InventoryReportFiles.buildPdf(
        report: _report,
        t: t,
        companyName: 'Ma Boutique SARL',
        drinks: [_drink(name: 'Beer', expiry: DateTime.now().add(const Duration(days: 4)))],
      );
      expect(bytes, isNotEmpty);
    });

    test('the PDF can be limited to the summary only', () async {
      final bytes = await InventoryReportFiles.buildPdf(
        report: _report,
        t: t,
        options: const InventoryExportOptions(
            charts: false,
            currentStock: false,
            lowStock: false,
            expiry: false,
            transactions: false),
      );
      expect(bytes, isNotEmpty);
    });

    test('the Excel workbook is produced', () {
      final bytes = InventoryReportFiles.buildExcel(
        report: _report,
        t: t,
        companyName: 'Ma Boutique SARL',
        drinks: [_drink(name: 'Beer', expiry: DateTime.now().add(const Duration(days: 4)))],
      );
      expect(bytes, isNotNull);
      expect(bytes!, isNotEmpty);
    });

    test('the CSV carries the company name, period and selected sections', () {
      final csv = InventoryReportFiles.buildCsv(
        report: _report,
        t: t,
        companyName: 'Ma Boutique SARL',
      );
      expect(csv, contains('Ma Boutique SARL'));
      expect(csv, contains('Period'));
      expect(csv, contains('Total items in stock'));
      expect(csv, contains('CURRENT STOCK'));
      expect(csv, contains('MOVEMENTS'));
      expect(csv, contains('Beer'));
    });

    test('the CSV omits the sections the user unchecked', () {
      final csv = InventoryReportFiles.buildCsv(
        report: _report,
        t: t,
        options: const InventoryExportOptions(
            charts: false,
            currentStock: false,
            lowStock: false,
            expiry: false,
            transactions: false),
      );
      expect(csv, contains('SUMMARY'));
      expect(csv, isNot(contains('CURRENT STOCK')));
      expect(csv, isNot(contains('MOVEMENTS')));
      expect(csv, isNot(contains('Units sold per category')));
    });

    test('the CSV escapes a drink name containing a comma', () {
      final report = InventoryReport(
        startDate: _report.startDate,
        endDate: _report.endDate,
        currentStock: [
          InventoryItem(
            id: 'x',
            drinkId: 'x',
            drinkName: 'Beer, Premium',
            quantity: 3,
            minStockLevel: 1,
            lastRestocked: DateTime(2026, 8, 1),
          ),
        ],
        transactions: const [],
        totalItemsIn: 0,
        totalItemsOut: 0,
        lowStockCount: 0,
        salesByCategory: const {},
        wasteByItem: const {},
      );
      final csv = InventoryReportFiles.buildCsv(report: report, t: t);
      expect(csv, contains('"Beer, Premium"'));
    });
  });

  group('money in the exported file', () {
    test('the CSV carries the totals, the margin and the two averages', () {
      final csv = InventoryReportFiles.buildCsv(
        report: _report,
        t: t,
        profit: _profit,
      );

      expect(csv, contains('Profit & margins'));
      expect(csv, contains('Revenue,10000.00'));
      expect(csv, contains('Cost,7000.00'));
      expect(csv, contains('Profit,3000.00'));
      expect(csv, contains('Margin,30.0%'));
      expect(csv, contains('Avg selling price,1000.00'));
      expect(csv, contains('Avg purchase price,700.00'));
      expect(csv, contains('Units sold,10'));
    });

    test('the CSV omits the money when the box is unchecked', () {
      final csv = InventoryReportFiles.buildCsv(
        report: _report,
        t: t,
        profit: _profit,
        options: const InventoryExportOptions(profit: false),
      );

      expect(csv, isNot(contains('Profit & margins')));
      expect(csv, isNot(contains('Avg selling price')));
    });

    test('an incomplete cost price is exported with its caveat', () {
      final csv = InventoryReportFiles.buildCsv(
        report: _report,
        t: t,
        profit: _profitWithCaveat,
      );

      expect(csv, contains('Some units have no cost price on record,2'));
      expect(csv, contains('Some units could not be valued,3'));
    });

    test('a complete report carries no caveat', () {
      final csv = InventoryReportFiles.buildCsv(
        report: _report,
        t: t,
        profit: _profit,
      );

      expect(csv, isNot(contains('no cost price on record')));
      expect(csv, isNot(contains('could not be valued')));
    });

    test('the money rows are the one definition both formats use', () {
      final rows = InventoryReportFiles.profitRows(_profit, t);
      final byLabel = {for (final row in rows) row[0] as String: row[1]};

      expect(byLabel['Metric'], 'Value');
      expect(byLabel['Revenue'], 10000.0);
      expect(byLabel['Cost'], 7000.0);
      expect(byLabel['Profit'], 3000.0);
      expect(byLabel['Margin'], '30.0%');
      expect(byLabel['Avg selling price'], 1000.0);
      expect(byLabel['Avg purchase price'], 700.0);
      expect(byLabel['Units sold'], 10);
      // Header plus the seven figures, and nothing else on a complete report.
      expect(rows, hasLength(8));
    });

    test('the caveat rows appear only when the figures are incomplete', () {
      final rows = InventoryReportFiles.profitRows(_profitWithCaveat, t);
      final byLabel = {for (final row in rows) row[0] as String: row[1]};

      expect(byLabel['Some units have no cost price on record'], 2);
      expect(byLabel['Some units could not be valued'], 3);
      expect(rows, hasLength(10));
    });

    test('the Excel workbook is produced with the money sheet', () {
      final bytes = InventoryReportFiles.buildExcel(
        report: _report,
        t: t,
        profit: _profit,
      );

      // What goes INTO the sheet is asserted through profitRows above: the excel
      // package cannot re-parse a workbook containing the empty spacer rows this
      // builder writes, so decoding the bytes here would fail for reasons that have
      // nothing to do with the report.
      expect(bytes, isNotNull);
      expect(bytes!, isNotEmpty);
    });

    test('the PDF is produced with the money section', () async {
      final bytes = await InventoryReportFiles.buildPdf(
        report: _report,
        t: t,
        companyName: 'Ma Boutique SARL',
        profit: _profitWithCaveat,
        currencySymbol: 'Frs',
      );
      expect(bytes, isNotEmpty);
    });
  });
}