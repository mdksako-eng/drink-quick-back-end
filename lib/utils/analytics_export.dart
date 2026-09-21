// utils/analytics_export.dart
// Builds presentation-ready analytics reports (CSV + shareable summary) for the
// manager dashboard. Pure functions — no Flutter/plugin dependencies — so the
// report layout can be unit-tested.
import '../models/analytics_model.dart';
import 'currency_helper.dart';

/// Decimal places used for percentages in reports.
const int _percentDecimals = 1;

/// Which sections the user wants in the exported report.
class AnalyticsExportOptions {
  final bool summary;
  final bool profit;
  final bool staff;
  final bool popularItems;
  final bool categories;
  final bool revenueChart;

  const AnalyticsExportOptions({
    this.summary = true,
    this.profit = true,
    this.staff = true,
    this.popularItems = true,
    this.categories = true,
    this.revenueChart = true,
  });

  /// Everything included.
  static const AnalyticsExportOptions all = AnalyticsExportOptions();

  bool get isEmpty =>
      !summary && !profit && !staff && !popularItems && !categories && !revenueChart;
}

/// Profit figures for the reporting period (needs purchase prices).
class ProfitSummary {
  final double revenue;
  final double cost;
  final double profit;

  const ProfitSummary({
    required this.revenue,
    required this.cost,
    required this.profit,
  });

  /// Profit margin as a percentage of revenue.
  double get marginPercent => revenue == 0 ? 0 : (profit / revenue) * 100;

  static const ProfitSummary empty =
      ProfitSummary(revenue: 0, cost: 0, profit: 0);
}

class AnalyticsExport {
  /// Fully formatted CSV report including the requested period, a KPI summary,
  /// the **Sales by Staff** breakdown, popular items and the category mix.
  ///
  /// [t] resolves a localized label (usually the app's `t()` from i18n.dart).
  /// [options] lets the caller include/exclude sections.
  static String csvReport({
    required AnalyticsSnapshot snapshot,
    required DateTime startDate,
    required DateTime endDate,
    required String Function(String key) t,
    String? companyName,
    String? logoUrl,
    DateTime? generatedAt,
    AnalyticsExportOptions options = AnalyticsExportOptions.all,
    ProfitSummary? profit,
  }) {
    final buf = StringBuffer();

    // ---------- Header ----------
    buf.writeln(_csv(t('dashTitle')));
    if (companyName != null && companyName.trim().isNotEmpty) {
      buf.writeln('${_csv(t('companyName'))},${_csv(companyName.trim())}');
    }
    if (logoUrl != null && logoUrl.trim().isNotEmpty) {
      buf.writeln('${_csv(t('branding_title'))},${_csv(logoUrl.trim())}');
    }
    buf.writeln('${_csv(t('exp_period'))},'
        '${_csv('${dateStamp(startDate)} - ${dateStamp(endDate)}')}');
    buf.writeln('${_csv(t('exp_generated'))},'
        '${_csv(dateTimeStamp(generatedAt ?? DateTime.now()))}');
    buf.writeln('${_csv(t('currency'))},${_csv(CurrencyHelper.getSymbol())}');

    // ---------- KPIs ----------
    if (options.summary) {
      buf.writeln();
      buf.writeln(_csv(t('dashSummary')));
      buf.writeln('${_csv(t('dashMetric'))},${_csv(t('dashValue'))}');
      buf.writeln(
          '${_csv(t('dashTotalRevenue'))},${_csv(_money(snapshot.totalRevenue))}');
      buf.writeln('${_csv(t('dashOrders'))},${snapshot.totalOrders}');
      buf.writeln('${_csv(t('dashItemsSold'))},${snapshot.totalItemsSold}');
      buf.writeln(
          '${_csv(t('dashAvgOrder'))},${_csv(_money(snapshot.averageOrderValue))}');
    }

    // ---------- Profit ----------
    if (options.profit && profit != null) {
      buf.writeln();
      buf.writeln(_csv(t('dashProfit')));
      buf.writeln('${_csv(t('dashMetric'))},${_csv(t('dashValue'))}');
      buf.writeln('${_csv(t('dashRevenue'))},${_csv(_money(profit.revenue))}');
      buf.writeln('${_csv(t('dashCostOfGoods'))},${_csv(_money(profit.cost))}');
      buf.writeln('${_csv(t('dashGrossProfit'))},${_csv(_money(profit.profit))}');
      buf.writeln(
          '${_csv(t('dashMargin'))},${_csv(_percent(profit.marginPercent))}');
    }

    // ---------- Revenue trend (chart data) ----------
    if (options.revenueChart && snapshot.revenueValues.isNotEmpty) {
      buf.writeln();
      buf.writeln(_csv(t('dashRevenueTrend')));
      buf.writeln('${_csv(t('dashDay'))},${_csv(t('dashRevenue'))}');
      for (var i = 0; i < snapshot.revenueValues.length; i++) {
        final label = i < snapshot.revenueLabels.length
            ? snapshot.revenueLabels[i]
            : '${i + 1}';
        buf.writeln(
            '${_csv(label)},${_csv(_money(snapshot.revenueValues[i]))}');
      }
    }

    // ---------- Sales by staff ----------
    if (options.staff) {
    buf.writeln();
    buf.writeln(_csv(t('dashSalesByStaff')));
    buf.writeln([
      _csv(t('username')),
      _csv(t('dashOrders')),
      _csv(t('dashItemsSold')),
      _csv(t('dashTotalRevenue')),
      _csv(t('dashAvgOrder')),
      _csv(t('dashShareOfRevenue')),
    ].join(','));
    for (final staff in snapshot.staffSales) {
      final share = _share(staff.revenue, snapshot.totalRevenue);
      final avg = staff.orders == 0 ? 0.0 : staff.revenue / staff.orders;
      buf.writeln([
        _csv(staff.name),
        '${staff.orders}',
        '${staff.itemsSold}',
        _csv(_money(staff.revenue)),
        _csv(_money(avg)),
        _csv(_percent(share)),
      ].join(','));
    }
    if (snapshot.staffSales.isNotEmpty) {
      final staffRevenue =
          snapshot.staffSales.fold<double>(0, (sum, s) => sum + s.revenue);
      buf.writeln([
        _csv(t('dashTotal')),
        '${snapshot.staffSales.fold<int>(0, (sum, s) => sum + s.orders)}',
        '${snapshot.staffSales.fold<int>(0, (sum, s) => sum + s.itemsSold)}',
        _csv(_money(staffRevenue)),
        '',
        '',
      ].join(','));
      final unattributed = snapshot.totalRevenue - staffRevenue;
      if (unattributed > 0.5) {
        buf.writeln([
          _csv(t('dashUnattributed')),
          '',
          '',
          _csv(_money(unattributed)),
          '',
          _csv(_percent(_share(unattributed, snapshot.totalRevenue))),
        ].join(','));
      }
    }
    } // end options.staff

    // ---------- Popular items ----------
    if (options.popularItems) {
      buf.writeln();
      buf.writeln(_csv(t('dashPopularItems')));
      buf.writeln([
        _csv(t('exp_drinkName')),
        _csv(t('quantity')),
        _csv(t('dashTotalRevenue')),
      ].join(','));
      for (final item in snapshot.popularItems) {
        buf.writeln([
          _csv(item.name),
          '${item.quantity}',
          _csv(_money(item.revenue)),
        ].join(','));
      }
    }

    // ---------- Category mix ----------
    if (options.categories) {
      buf.writeln();
      buf.writeln(_csv(t('dashCategoryMix')));
      buf.writeln([
        _csv(t('exp_category')),
        _csv(t('dashItemsSold')),
        _csv(t('dashShare')),
      ].join(','));
      for (final slice in snapshot.categoryMix) {
        buf.writeln([
          _csv(slice.category),
          '${slice.count}',
          _csv(_percent(_share(slice.count.toDouble(),
              snapshot.totalItemsSold.toDouble()))),
        ].join(','));
      }
    }

    return buf.toString();
  }

  /// Short, human-readable version of the same report — handy for sharing in
  /// chat apps where a CSV attachment is not convenient.
  static String summaryReport({
    required AnalyticsSnapshot snapshot,
    required DateTime startDate,
    required DateTime endDate,
    required String Function(String key) t,
    String? companyName,
  }) {
    final buf = StringBuffer();
    if (companyName != null && companyName.trim().isNotEmpty) {
      buf.writeln(companyName.trim());
    }
    buf.writeln(t('dashTitle'));
    buf.writeln(
        '${t('exp_period')}: ${dateStamp(startDate)} - ${dateStamp(endDate)}');
    buf.writeln();
    buf.writeln('${t('dashTotalRevenue')}: ${_money(snapshot.totalRevenue)}');
    buf.writeln('${t('dashOrders')}: ${snapshot.totalOrders}');
    buf.writeln('${t('dashItemsSold')}: ${snapshot.totalItemsSold}');
    buf.writeln('${t('dashAvgOrder')}: ${_money(snapshot.averageOrderValue)}');

    if (snapshot.staffSales.isNotEmpty) {
      buf.writeln();
      buf.writeln('${t('dashSalesByStaff')}:');
      for (final staff in snapshot.staffSales) {
        final share = _share(staff.revenue, snapshot.totalRevenue);
        buf.writeln('• ${staff.name}: ${_money(staff.revenue)} '
            '(${staff.orders} ${t('dashOrders')}, ${_percent(share)})');
      }
    }
    return buf.toString();
  }

  /// `analytics_2026-08-16_2026-09-15.csv` — sortable, self-describing name.
  static String fileName(
      {required DateTime startDate, required DateTime endDate}) {
    return 'analytics_${dateStamp(startDate)}_${dateStamp(endDate)}.csv';
  }

  // ------------------------------------------------------------
  // formatting helpers
  // ------------------------------------------------------------

  /// RFC-4180 style escaping: quote when the value contains a separator, quote
  /// or line break (staff names are arbitrary text).
  static String _csv(String value) {
    final needsQuotes = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  static String dateStamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String dateTimeStamp(DateTime d) =>
      '${dateStamp(d)} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  static String _money(double value) => CurrencyHelper.format(value);

  static String _percent(double value) =>
      '${value.toStringAsFixed(_percentDecimals)}%';

  /// `part / whole` as a percentage (0 when the whole is zero).
  static double _share(double part, double whole) =>
      whole == 0 ? 0.0 : (part / whole) * 100;
}
