// screens/manager_dashboard.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:drinks_calculator_fixed/providers/plan_provider.dart';
import '../widgets/upgrade_required.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/analytics_model.dart';
import '../providers/drink_provider.dart';
import '../providers/order_provider.dart';
import '../services/company_branding_service.dart';
import '../services/supabase_service.dart';
import '../utils/analytics_export.dart';
import '../utils/analytics_helper.dart';
import '../utils/analytics_report_files.dart';
import '../utils/company_logo_bytes.dart';
import '../utils/currency_helper.dart';
import '../utils/helpers.dart';
import '../utils/i18n.dart';
import '../widgets/charts.dart';
import '../widgets/skeleton.dart';

class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({Key? key}) : super(key: key);

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  int _rangeDays = 30;
  DateTimeRange? _customRange;
  bool _loading = true;
  late AnalyticsSnapshot _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _compute();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  /// Effective start of the reporting period (custom range wins when set).
  DateTime get _startDate =>
      _customRange?.start ?? DateTime.now().subtract(Duration(days: _rangeDays));

  /// Effective end of the reporting period.
  DateTime get _endDate => _customRange?.end ?? DateTime.now();

  AnalyticsSnapshot _compute() {
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    return computeAnalytics(
      orders: orderProvider.orderHistory,
      startDate: _startDate,
      endDate: _endDate,
    );
  }

  void _setRange(int days) {
    setState(() {
      _rangeDays = days;
      _customRange = null;
      _snapshot = _compute();
    });
  }

  /// Opens the platform date-range picker so any period can be analysed.
  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
      helpText: t('dashRangeCustom'),
      saveText: t('dashApply'),
    );
    if (picked == null) return;
    setState(() {
      _customRange = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day),
      );
      _snapshot = _compute();
    });
  }

  void _clearCustomRange() {
    setState(() {
      _customRange = null;
      _snapshot = _compute();
    });
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    await orderProvider.reloadOrders();
    if (mounted) {
      setState(() {
        _snapshot = _compute();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!context.read<PlanProvider>().canAccess('analytics')) {
      return const UpgradeRequiredView();
    }
    final s = _snapshot;
    final primary = Theme.of(context).primaryColor;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('dashTitle')),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share),
            tooltip: t('dashExport'),
            onSelected: (value) {
              if (value == 'summary') {
                _exportCsv(asText: true);
              } else {
                _showExportDialog();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                  value: 'report',
                  child: Row(children: [
                    const Icon(Icons.summarize_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(t('dashExport')),
                  ])),
              PopupMenuItem(
                  value: 'summary',
                  child: Row(children: [
                    const Icon(Icons.text_snippet_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(t('dashExportSummary')),
                  ])),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: _loading
          ? const SkeletonList()
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildRangeSelector(),
          const SizedBox(height: 16),
          if (s.totalOrders == 0)
            _emptyState()
          else ...[
            _buildKpis(s, primary),
            const SizedBox(height: 16),
            _sectionCard(
              title: t('dashPopularItems'),
              child: _buildPopularItems(s.popularItems, primary),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: t('dashSalesByStaff'),
              child: _buildStaffSales(s.staffSales, primary),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: t('dashPeakHours'),
              subtitle: _peakSubtitle(s),
              child: HourlyBarChart(values: s.hourlySales, color: primary),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: t('dashRevenueTrend'),
              child: RevenueLineChart(values: s.revenueValues, color: primary),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: t('dashCategoryMix'),
              child: DonutChart(data: _categoryData(s.categoryMix)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRangeSelector() {
    final chips = Row(
      children: [7, 30, 90].map((d) {
        final selected = _customRange == null && _rangeDays == d;
        final label = d == 7
            ? t('dashRange7')
            : d == 30
                ? t('dashRange30')
                : t('dashRange90');
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => _setRange(d),
            ),
          ),
        );
      }).toList(),
    );

    // 📅 Custom period — lets the manager analyse any date range, not just the
    // preset 7/30/90-day windows.
    final customActive = _customRange != null;
    final customButton = Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickCustomRange,
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(
              customActive
                  ? '${_formatShortDate(_customRange!.start)} – '
                      '${_formatShortDate(_customRange!.end)}'
                  : t('dashRangeCustom'),
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: customActive ? Colors.white : null,
              backgroundColor: customActive ? Theme.of(context).primaryColor : null,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
          ),
        ),
        if (customActive)
          IconButton(
            tooltip: t('dashClearRange'),
            icon: const Icon(Icons.close, size: 18),
            onPressed: _clearCustomRange,
          ),
      ],
    );

    return Column(
      children: [
        chips,
        const SizedBox(height: 8),
        customButton,
      ],
    );
  }

  String _formatShortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _buildKpis(AnalyticsSnapshot s, Color primary) {
    return Column(children: [
      Row(children: [
        _kpiCard(t('dashTotalRevenue'), CurrencyHelper.format(s.totalRevenue),
            Icons.attach_money, Colors.green),
        const SizedBox(width: 10),
        _kpiCard(
            t('dashOrders'), '${s.totalOrders}', Icons.receipt_long, Colors.blue),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _kpiCard(
            t('dashItemsSold'), '${s.totalItemsSold}', Icons.local_drink, primary),
        const SizedBox(width: 10),
        _kpiCard(t('dashAvgOrder'), CurrencyHelper.format(s.averageOrderValue),
            Icons.trending_up, Colors.orange),
      ]),
    ]);
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(value,
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(title,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(
      {required String title, String? subtitle, required Widget child}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (subtitle != null)
              Text(subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildPopularItems(List<PopularItem> items, Color primary) {
    final top = items.take(5).toList();
    final maxQty = top.isEmpty ? 1 : top.first.quantity;
    return Column(
      children: top.map((item) {
        final ratio = maxQty == 0 ? 0.0 : item.quantity / maxQty;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                  width: 110,
                  child: Text(item.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 12,
                    backgroundColor: Colors.grey.withValues(alpha: 0.15),
                    color: primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                  width: 44,
                  child: Text('${item.quantity}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold))),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _peakSubtitle(AnalyticsSnapshot s) {
    final h = s.topHour.toString().padLeft(2, '0');
    return '${t('dashPeak')}: ${h}h';
  }

  List<ChartDatum> _categoryData(List<CategorySlice> slices) {
    const palette = [
      Color(0xFF4361EE),
      Color(0xFF4CC9F0),
      Color(0xFFF72585),
      Color(0xFFFFB703),
      Color(0xFF06D6A0),
      Color(0xFF9D4EDD),
    ];
    return slices
        .asMap()
        .entries
        .map((e) => ChartDatum(
              label: e.value.category,
              value: e.value.count.toDouble(),
              color: palette[e.key % palette.length],
            ))
        .toList();
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(children: [
        Icon(Icons.bar_chart, size: 60, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text(t('dashNoData'),
            style: TextStyle(color: Colors.grey[600], fontSize: 14)),
      ]),
    );
  }

  Widget _buildStaffSales(List<StaffSale> staff, Color primary) {
    if (staff.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(t('dashNoData'),
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      );
    }
    return Column(
      children: staff.map((s) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(s.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  Text(
                      '${s.orders} ${t('dashOrders')} · ${s.itemsSold} ${t('dashItemsSold')}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ])),
            Text(CurrencyHelper.format(s.revenue),
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: primary)),
          ]),
        );
      }).toList(),
    );
  }

  /// Export dialog: icon, section checkboxes and the three formats.
  Future<void> _showExportDialog() async {
    var options = const AnalyticsExportOptions();

    final format = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          scrollable: true,
          title: Row(children: [
            Icon(Icons.summarize_outlined,
                color: Theme.of(context).primaryColor),
            const SizedBox(width: 10),
            Expanded(child: Text(t('dashExport'))),
          ]),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t('dashChooseSections'),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 6),
                _exportCheck(
                  setDialogState,
                  title: t('dashSummary'),
                  value: options.summary,
                  onChanged: (v) => options = _withOptions(options, summary: v),
                ),
                _exportCheck(
                  setDialogState,
                  title: t('dashProfit'),
                  subtitle: t('dashProfitHint'),
                  value: options.profit,
                  onChanged: (v) => options = _withOptions(options, profit: v),
                ),
                _exportCheck(
                  setDialogState,
                  title: t('dashSalesByStaff'),
                  value: options.staff,
                  onChanged: (v) => options = _withOptions(options, staff: v),
                ),
                _exportCheck(
                  setDialogState,
                  title: t('dashPopularItems'),
                  value: options.popularItems,
                  onChanged: (v) =>
                      options = _withOptions(options, popularItems: v),
                ),
                _exportCheck(
                  setDialogState,
                  title: t('dashCategoryMix'),
                  value: options.categories,
                  onChanged: (v) =>
                      options = _withOptions(options, categories: v),
                ),
                _exportCheck(
                  setDialogState,
                  title: t('dashRevenueTrend'),
                  value: options.revenueChart,
                  onChanged: (v) =>
                      options = _withOptions(options, revenueChart: v),
                ),
              ],
            ),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'csv'),
              child: Text(t('exportCsv')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'excel'),
              child: Text(t('exportExcel')),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: Text(t('exportPdf')),
              onPressed: () => Navigator.pop(ctx, 'pdf'),
            ),
          ],
        ),
      ),
    );

    if (format == null) return;
    if (options.isEmpty) {
      Helpers.showToast(t('dashSelectAtLeastOne'), isError: true);
      return;
    }
    await _runExport(format, options);
  }

  Widget _exportCheck(
    StateSetter setDialogState, {
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle:
          subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 11)),
      value: value,
      onChanged: (v) => setDialogState(() => onChanged(v ?? false)),
    );
  }

  AnalyticsExportOptions _withOptions(
    AnalyticsExportOptions base, {
    bool? summary,
    bool? profit,
    bool? staff,
    bool? popularItems,
    bool? categories,
    bool? revenueChart,
  }) {
    return AnalyticsExportOptions(
      summary: summary ?? base.summary,
      profit: profit ?? base.profit,
      staff: staff ?? base.staff,
      popularItems: popularItems ?? base.popularItems,
      categories: categories ?? base.categories,
      revenueChart: revenueChart ?? base.revenueChart,
    );
  }

  /// Generates the chosen format and shares it.
  Future<void> _runExport(String format, AnalyticsExportOptions options) async {
    final s = _snapshot;
    final companyName = await _companyName();
    final start = _startDate;
    final end = _endDate;
    final profit = _profitSummary(s);
    final baseName = AnalyticsExport.fileName(startDate: start, endDate: end);
    // Company branding travels with every export (PDF embeds the image; Excel
    // and CSV record the link). Missing/offline logo simply omits it.
    final logoUrl = await CompanyBrandingService.load();
    final logoBytes = await CompanyLogoBytes.fromUrl(logoUrl);

    try {
      switch (format) {
        case 'csv':
          final csv = AnalyticsExport.csvReport(
            snapshot: s,
            startDate: start,
            endDate: end,
            t: t,
            companyName: companyName,
            logoUrl: logoUrl,
            options: options,
            profit: profit,
          );
          await _shareBytes(utf8.encode(csv), baseName);
          break;
        case 'excel':
          final bytes = AnalyticsReportFiles.buildExcel(
            snapshot: s,
            startDate: start,
            endDate: end,
            t: t,
            companyName: companyName,
            logoUrl: logoUrl,
            options: options,
            profit: profit,
          );
          if (bytes == null) throw Exception('Excel export failed');
          await _shareBytes(bytes, baseName.replaceAll('.csv', '.xlsx'));
          break;
        case 'pdf':
          final bytes = await AnalyticsReportFiles.buildPdf(
            snapshot: s,
            startDate: start,
            endDate: end,
            t: t,
            companyName: companyName,
            logoBytes: logoBytes,
            options: options,
            profit: profit,
          );
          await _shareBytes(bytes, baseName.replaceAll('.csv', '.pdf'));
          break;
      }
    } catch (e) {
      if (mounted) Helpers.showToast('$e', isError: true);
    }
  }

  Future<void> _shareBytes(List<int> bytes, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    if (!mounted) return;
    await SharePlus.instance.share(ShareParams(
      text: t('dashTitle'),
      files: [XFile(file.path)],
    ));
  }

  /// 💰 Revenue vs cost for the period, using each drink's purchase price.
  ProfitSummary _profitSummary(AnalyticsSnapshot s) {
    final drinks =
        Provider.of<DrinkProvider>(context, listen: false).customDrinks;
    final costByDrink = <String, double>{
      for (final d in drinks) d.name.toLowerCase(): d.purchasePrice,
    };

    var cost = 0.0;
    for (final order
        in Provider.of<OrderProvider>(context, listen: false).orderHistory) {
      if (!order.isActive) continue;
      if (order.date.isBefore(_startDate) ||
          order.date.isAfter(_endDate.add(const Duration(days: 1)))) {
        continue;
      }
      for (final item in order.items) {
        cost += costByDrink[item.name.toLowerCase()] ?? 0;
      }
    }

    return ProfitSummary(
      revenue: s.totalRevenue,
      cost: cost,
      profit: s.totalRevenue - cost,
    );
  }

  /// Exports the current analytics view as a presentation-ready CSV report
  /// (period header, KPIs, **sales by staff**, popular items, category mix).
  Future<void> _exportCsv({bool asText = false}) async {
    final s = _snapshot;
    final companyName = await _companyName();
    final start = _startDate;
    final end = _endDate;

    try {
      if (asText) {
        final summary = AnalyticsExport.summaryReport(
          snapshot: s,
          startDate: start,
          endDate: end,
          t: t,
          companyName: companyName,
        );
        await SharePlus.instance.share(ShareParams(
          text: summary,
          subject: '${t('dashTitle')} '
              '${AnalyticsExport.dateStamp(start)} - '
              '${AnalyticsExport.dateStamp(end)}',
        ));
        return;
      }

      final csv = AnalyticsExport.csvReport(
        snapshot: s,
        startDate: start,
        endDate: end,
        t: t,
        companyName: companyName,
      );

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${AnalyticsExport.fileName(
        startDate: start,
        endDate: end,
      )}');
      await file.writeAsString(csv);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        text: '${t('dashTitle')} ('
            '${AnalyticsExport.dateStamp(start)} - '
            '${AnalyticsExport.dateStamp(end)})',
        files: [XFile(file.path)],
      ));
    } catch (e) {
      if (mounted) Helpers.showToast('$e');
    }
  }

  /// Company name for reports: cached setting first, then the live company
  /// record so exports always carry the real business name.
  Future<String?> _companyName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('company_name');
      if (cached != null && cached.trim().isNotEmpty && cached.trim() != 'Drink Quick Cal') {
        return cached.trim();
      }

      // Fall back to the company record on the server (and cache it).
      final companyId = SupabaseService.currentCompanyId;
      if (companyId != null) {
        final company = await SupabaseService.getCompany(companyId);
        final name = company?['name']?.toString().trim();
        if (name != null && name.isNotEmpty) {
          await prefs.setString('company_name', name);
          return name;
        }
      }

      final trimmed = cached?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    } catch (_) {
      return null;
    }
  }
}
