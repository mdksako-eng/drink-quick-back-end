// test/analytics_export_test.dart
// Regression tests for the manager dashboard's exportable sales report
// (lib/utils/analytics_export.dart) — the CSV must stay presentable and must
// include the Sales-by-Staff breakdown.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drinks_calculator_fixed/models/analytics_model.dart';
import 'package:drinks_calculator_fixed/utils/analytics_export.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';

/// Minimal English labels so the assertions read like the real report.
String t(String key) => const {
      'dashTitle': 'Sales Analytics',
      'exp_period': 'Period',
      'exp_generated': 'Generated',
      'currency': 'Currency',
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
    PopularItem(name: 'Beer, cold', quantity: 4, revenue: 60),
    PopularItem(name: 'Soda', quantity: 2, revenue: 30),
  ],
  hourlySales: List<int>.filled(24, 0),
  revenueValues: const [40, 60],
  revenueLabels: const ['1/9', '2/9'],
  categoryMix: const [
    CategorySlice(category: 'Beer', count: 4),
    CategorySlice(category: 'Soft', count: 2),
  ],
  staffSales: const [
    StaffSale(name: 'Alice', revenue: 80, orders: 2, itemsSold: 5),
    StaffSale(name: 'Bob', revenue: 20, orders: 1, itemsSold: 1),
  ],
  topHour: 18,
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await CurrencyHelper.initialize();
  });

  test('CSV report has a header, KPI summary and totals', () {
    final csv = AnalyticsExport.csvReport(
      snapshot: _snapshot,
      startDate: DateTime(2026, 8, 16),
      endDate: DateTime(2026, 9, 15),
      t: t,
      companyName: 'Quick Sip Bar',
      generatedAt: DateTime(2026, 9, 15, 10, 30),
    );

    expect(csv, contains('Sales Analytics'));
    expect(csv, contains('Company,Quick Sip Bar'));
    expect(csv, contains('Period,2026-08-16 - 2026-09-15'));
    expect(csv, contains('Generated,2026-09-15 10:30'));
    expect(csv, contains('SUMMARY'));
    expect(csv, contains('Total Revenue,100'));
    expect(csv, contains('Orders,3'));
    expect(csv, contains('Items Sold,6'));
    expect(csv, contains('Avg Order,33'));
  });

  test('CSV report contains sales by staff with share of revenue', () {
    final csv = AnalyticsExport.csvReport(
      snapshot: _snapshot,
      startDate: DateTime(2026, 8, 16),
      endDate: DateTime(2026, 9, 15),
      t: t,
    );

    expect(csv, contains('Sales by Staff'));
    expect(
        csv,
        contains(
            'Username,Orders,Items Sold,Total Revenue,Avg Order,Share of revenue'));
    // Alice: 80 of 100 = 80.0%, average order 40
    expect(csv, contains('Alice,2,5,80Frs,40Frs,80.0%'));
    expect(csv, contains('Bob,1,1,20Frs,20Frs,20.0%'));
    expect(csv, contains('TOTAL,3,6,100Frs,,'));
    expect(csv, isNot(contains('Unattributed')));
  });

  test('CSV report flags unattributed revenue when staff is missing', () {
    final snapshot = AnalyticsSnapshot(
      totalRevenue: 100,
      totalOrders: 4,
      totalItemsSold: 6,
      averageOrderValue: 25,
      popularItems: const [],
      hourlySales: List<int>.filled(24, 0),
      revenueValues: const [],
      revenueLabels: const [],
      categoryMix: const [],
      staffSales: const [
        StaffSale(name: 'Alice', revenue: 60, orders: 2, itemsSold: 5),
      ],
      topHour: 0,
    );

    final csv = AnalyticsExport.csvReport(
      snapshot: snapshot,
      startDate: DateTime(2026, 8, 16),
      endDate: DateTime(2026, 9, 15),
      t: t,
    );

    expect(csv, contains('TOTAL,2,5,60Frs,,'));
    expect(csv, contains('Unattributed,,,40Frs,,40.0%'));
  });

  test('CSV report escapes separators and quotes in names', () {
    final csv = AnalyticsExport.csvReport(
      snapshot: _snapshot,
      startDate: DateTime(2026, 8, 16),
      endDate: DateTime(2026, 9, 15),
      t: t,
    );

    // "Beer, cold" must not break the column layout.
    expect(csv, contains('"Beer, cold",4,60'));
  });

  test('CSV report lists the category mix with shares', () {
    final csv = AnalyticsExport.csvReport(
      snapshot: _snapshot,
      startDate: DateTime(2026, 8, 16),
      endDate: DateTime(2026, 9, 15),
      t: t,
    );

    expect(csv, contains('Sales by Category'));
    expect(csv, contains('Beer,4,66.7%'));
    expect(csv, contains('Soft,2,33.3%'));
  });

  test('text summary is shareable and includes staff line items', () {
    final summary = AnalyticsExport.summaryReport(
      snapshot: _snapshot,
      startDate: DateTime(2026, 8, 16),
      endDate: DateTime(2026, 9, 15),
      t: t,
      companyName: 'Quick Sip Bar',
    );

    expect(summary, contains('Quick Sip Bar'));
    expect(summary, contains('Period: 2026-08-16 - 2026-09-15'));
    expect(summary, contains('Sales by Staff:'));
    expect(summary, contains('• Alice: 80Frs (2 Orders, 80.0%)'));
    expect(summary, contains('• Bob: 20Frs (1 Orders, 20.0%)'));
  });

  test('exported file name is self-describing', () {
    expect(
      AnalyticsExport.fileName(
        startDate: DateTime(2026, 8, 6),
        endDate: DateTime(2026, 9, 15),
      ),
      'analytics_2026-08-06_2026-09-15.csv',
    );
  });
}