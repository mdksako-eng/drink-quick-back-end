// utils/analytics_helper.dart
// Pure aggregation over order history for the manager dashboard.
import '../models/analytics_model.dart';
import '../providers/order_provider.dart';

AnalyticsSnapshot computeAnalytics({
  required List<Order> orders,
  DateTime? startDate,
  DateTime? endDate,
}) {
  final start = startDate ?? DateTime.now().subtract(const Duration(days: 30));
  final end = endDate ?? DateTime.now();

  final active = orders
      .where((o) =>
          o.isActive &&
          !o.date.isBefore(start) &&
          !o.date.isAfter(end.add(const Duration(days: 1))))
      .toList();

  double totalRevenue = 0;
  int totalItemsSold = 0;
  final nameQty = <String, int>{};
  final nameRevenue = <String, double>{};
  final categoryCount = <String, int>{};
  final hourly = List<int>.filled(24, 0);
  final dayRevenue = <DateTime, double>{};

  for (final o in active) {
    totalRevenue += o.totalAmount;
    totalItemsSold += o.items.length;
    hourly[o.date.hour] += o.items.length;
    final day = DateTime(o.date.year, o.date.month, o.date.day);
    dayRevenue[day] = (dayRevenue[day] ?? 0) + o.totalAmount;
    for (final d in o.items) {
      nameQty[d.name] = (nameQty[d.name] ?? 0) + 1;
      nameRevenue[d.name] = (nameRevenue[d.name] ?? 0) + d.price;
      categoryCount[d.category] = (categoryCount[d.category] ?? 0) + 1;
    }
  }

  final popular = nameQty.entries
      .map((e) => PopularItem(
          name: e.key, quantity: e.value, revenue: nameRevenue[e.key] ?? 0))
      .toList()
    ..sort((a, b) => b.quantity.compareTo(a.quantity));

  final categories = categoryCount.entries
      .map((e) => CategorySlice(category: e.key, count: e.value))
      .toList()
    ..sort((a, b) => b.count.compareTo(a.count));

  final days = dayRevenue.keys.toList()..sort();
  final revenueValues = days.map((d) => dayRevenue[d]!).toList();
  final revenueLabels = days.map((d) => '${d.day}/${d.month}').toList();

  int topHour = 0;
  for (int i = 1; i < 24; i++) {
    if (hourly[i] > hourly[topHour]) topHour = i;
  }

  final totalOrders = active.length;
  final averageOrderValue =
      totalOrders == 0 ? 0.0 : totalRevenue / totalOrders;

  return AnalyticsSnapshot(
    totalRevenue: totalRevenue,
    totalOrders: totalOrders,
    totalItemsSold: totalItemsSold,
    averageOrderValue: averageOrderValue,
    popularItems: popular,
    hourlySales: hourly,
    revenueValues: revenueValues,
    revenueLabels: revenueLabels,
    categoryMix: categories,
    topHour: topHour,
  );
}
