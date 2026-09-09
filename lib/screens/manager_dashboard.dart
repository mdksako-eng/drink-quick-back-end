// screens/manager_dashboard.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/analytics_model.dart';
import '../providers/order_provider.dart';
import '../utils/analytics_helper.dart';
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
  bool _loading = true;
  late AnalyticsSnapshot _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _compute();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  AnalyticsSnapshot _compute() {
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    return computeAnalytics(
      orders: orderProvider.orderHistory,
      startDate: DateTime.now().subtract(Duration(days: _rangeDays)),
      endDate: DateTime.now(),
    );
  }

  void _setRange(int days) {
    setState(() {
      _rangeDays = days;
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
    final s = _snapshot;
    final primary = Theme.of(context).primaryColor;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('dashTitle')),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _exportCsv,
              tooltip: t('dashExport')),
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
    return Row(
      children: [7, 30, 90].map((d) {
        final selected = _rangeDays == d;
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
  }

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

  Future<void> _exportCsv() async {
    final s = _snapshot;
    final buf = StringBuffer();
    buf.writeln(t('dashTitle'));
    buf.writeln('${t('dashTotalRevenue')},${s.totalRevenue}');
    buf.writeln('${t('dashOrders')},${s.totalOrders}');
    buf.writeln('${t('dashItemsSold')},${s.totalItemsSold}');
    buf.writeln('${t('dashAvgOrder')},${s.averageOrderValue}');
    buf.writeln();
    buf.writeln(t('dashSalesByStaff'));
    buf.writeln(
        '${t('username')},${t('dashOrders')},${t('dashItemsSold')},${t('dashTotalRevenue')}');
    for (final st in s.staffSales) {
      buf.writeln('${st.name},${st.orders},${st.itemsSold},${st.revenue}');
    }
    buf.writeln();
    buf.writeln(t('dashPopularItems'));
    buf.writeln('${t('exp_drinkName')},${t('quantity')}');
    for (final p in s.popularItems) {
      buf.writeln('${p.name},${p.quantity}');
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/analytics_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(buf.toString());
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        text: t('dashTitle'),
        files: [XFile(file.path)],
      ));
    } catch (e) {
      if (mounted) Helpers.showToast('$e');
    }
  }
}
