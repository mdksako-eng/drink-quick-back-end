// models/analytics_model.dart
// Pure data classes for the manager dashboard analytics.

class PopularItem {
  final String name;
  final int quantity;
  final double revenue;

  const PopularItem({
    required this.name,
    required this.quantity,
    required this.revenue,
  });
}

class CategorySlice {
  final String category;
  final int count;

  const CategorySlice({required this.category, required this.count});
}

class AnalyticsSnapshot {
  final double totalRevenue;
  final int totalOrders;
  final int totalItemsSold;
  final double averageOrderValue;
  final List<PopularItem> popularItems;
  final List<int> hourlySales; // 24 buckets (0..23)
  final List<double> revenueValues; // daily totals, ascending
  final List<String> revenueLabels; // e.g. '12/8'
  final List<CategorySlice> categoryMix;
  final int topHour;

  const AnalyticsSnapshot({
    required this.totalRevenue,
    required this.totalOrders,
    required this.totalItemsSold,
    required this.averageOrderValue,
    required this.popularItems,
    required this.hourlySales,
    required this.revenueValues,
    required this.revenueLabels,
    required this.categoryMix,
    required this.topHour,
  });
}

