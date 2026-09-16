// test/analytics_report_files_test.dart
// Verifies the export options (incl. profit) and the PDF/Excel builders.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drinks_calculator_fixed/models/analytics_model.dart';
import 'package:drinks_calculator_fixed/utils/analytics_export.dart';
import 'package:drinks_calculator_fixed/utils/analytics_report_files.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';

String t(String key) => const {
      'dashTitle': 'Sales Analytics',
      'exp_period': 'Period',
      'exp_generated': 'Generated',
      'companyName': 'Company',
      'dashSummary': 'SUMMARY',
      'dashMetric': 'Metric',
      'dashValue': 'Value',
      'dashTotalRevenue': 'Total Revenue',
      'dashOrders': 'Orders',
      'dashItemsSold': 'Items Sold',
      'dashAvgOrder': 'Avg Order',
      'dashSalesByStaff': 'Sales by Staff',
      'dashShareOfRevenue': 'Share of revenue',
      'dashShare': 'Share',
      'dashTotal': 'TOTAL',
      'dashUnattributed': 'Unattributed',
      'dashPopularItems': 'Popular Items',
      'dashCategoryMix': 'Sales by Category',
      'dashRevenueTrend': 'Revenue Trend',
      'dashProfit': 'Profit',
      'dashRevenue': 'Revenue',
      'dashCostOfGoods': 'Cost of goods',
      'dashGrossProfit': 'Gross profit',
      'dashMargin': 'Margin',
      'dashDay': 'Day',
      'username': 'Username',
      'quantity': 'Quantity',
      'exp_drinkName': 'Drink',
      'exp_category': 'Category',
    }[key] ??
    key;

final _snapshot = AnalyticsSnapshot(
  totalRevenue: 100,
  totalOrders: 3,
  totalItemsSold: 6,
  averageOrderValue: 33.33,
  popularItems: const [
    PopularItem(name: 'Beer', quantity: 4, revenue: 60),
  ],
  hourlySales: List<int>.filled(24, 0),
  revenueValues: const [40, 60],
  revenueLabels: const ['1/9', '2/9'],
  categoryMix: const [CategorySlice(category: 'Beer', count: 6)],
  staffSales: const [
    StaffSale(name: 'Alice', revenue: 80, orders: 2, itemsSold: 5),
  ],
  topHour: 18,
);

const _profit = ProfitSummary(revenue: 100, cost: 40, profit: 60);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await CurrencyHelper.initialize();
  });

  group('CSV honours the chosen sections', () {
    test('includes profit when selected', () {
      final csv = AnalyticsExport.csvReport(
        snapshot: _snapshot,
        startDate: DateTime(2026, 8, 16),
        endDate: DateTime(2026, 9, 15),
        t: t,
        options: const AnalyticsExportOptions(),
        profit: _profit,
      );

      expect(csv, contains('Profit'));
      expect(csv, contains('Gross profit,60Frs'));
      expect(csv, contains('Margin,60.0%'));
    });

    test('omits sections the user unchecked', () {
      final csv = AnalyticsExport.csvReport(
        snapshot: _snapshot,
        startDate: DateTime(2026, 8, 16),
        endDate: DateTime(2026, 9, 15),
        t: t,
        options: const AnalyticsExportOptions(
          staff: false,
          popularItems: false,
          categories: false,
          revenueChart: false,
          profit: false,
        ),
        profit: _profit,
      );

      expect(csv, contains('SUMMARY'));
      expect(csv, isNot(contains('Sales by Staff')));
      expect(csv, isNot(contains('Popular Items')));
      expect(csv, isNot(contains('Sales by Category')));
      expect(csv, isNot(contains('Gross profit')));
    });
  });

  group('PDF / Excel builders', () {
    test('PDF is produced with the company name and profit', () async {
      final bytes = await AnalyticsReportFiles.buildPdf(
        snapshot: _snapshot,
        startDate: DateTime(2026, 8, 16),
        endDate: DateTime(2026, 9, 15),
        t: t,
        companyName: 'Quick Sip Bar',
        options: const AnalyticsExportOptions(),
        profit: _profit,
      );

      expect(bytes, isNotEmpty);
      // PDF files start with the %PDF signature.
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('Excel workbook is produced', () {
      final bytes = AnalyticsReportFiles.buildExcel(
        snapshot: _snapshot,
        startDate: DateTime(2026, 8, 16),
        endDate: DateTime(2026, 9, 15),
        t: t,
        companyName: 'Quick Sip Bar',
        options: const AnalyticsExportOptions(),
        profit: _profit,
      );

      expect(bytes, isNotNull);
      expect(bytes!, isNotEmpty);
      // .xlsx files are ZIP archives ("PK").
      expect(String.fromCharCodes(bytes.take(2)), 'PK');
    });

    test('options can be emptied to warn the user', () {
      const none = AnalyticsExportOptions(
        summary: false,
        profit: false,
        staff: false,
        popularItems: false,
        categories: false,
        revenueChart: false,
      );
      expect(none.isEmpty, isTrue);
      expect(AnalyticsExportOptions.all.isEmpty, isFalse);
    });
  });
}