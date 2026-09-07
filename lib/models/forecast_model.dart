// models/forecast_model.dart
// Data classes for demand forecasting.

class EventDay {
  final DateTime date;
  final String name;
  final double multiplier; // e.g. 1.25 = +25% demand

  const EventDay({
    required this.date,
    required this.name,
    required this.multiplier,
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'name': name,
        'multiplier': multiplier,
      };

  factory EventDay.fromJson(Map<String, dynamic> json) => EventDay(
        date: DateTime.tryParse('${json['date']}') ?? DateTime.now(),
        name: json['name']?.toString() ?? '',
        multiplier: (json['multiplier'] ?? 1.0).toDouble(),
      );
}

class ForecastItem {
  final String drinkName;
  final double forecastDemand; // projected units over the horizon
  final int currentStock;
  final int minStockLevel;
  final int recommendedOrder; // suggested order quantity
  final double trend; // % change vs previous period
  final double confidence; // 0..1

  const ForecastItem({
    required this.drinkName,
    required this.forecastDemand,
    required this.currentStock,
    required this.minStockLevel,
    required this.recommendedOrder,
    required this.trend,
    required this.confidence,
  });
}

class ForecastResult {
  final int horizonDays;
  final List<ForecastItem> items;
  final List<EventDay> events;

  const ForecastResult({
    required this.horizonDays,
    required this.items,
    required this.events,
  });

  int get totalRecommended =>
      items.fold(0, (sum, i) => sum + i.recommendedOrder);
}
