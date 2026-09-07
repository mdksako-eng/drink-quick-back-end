// utils/holidays.dart
// Static holiday/event calendar used to adjust demand forecasts.
import '../models/forecast_model.dart';

class StaticHoliday {
  final int month;
  final int day;
  final double multiplier;
  final String nameKey;
  const StaticHoliday(this.month, this.day, this.multiplier, this.nameKey);
}

/// Major fixed-date holidays that typically increase demand.
const List<StaticHoliday> staticHolidays = [
  StaticHoliday(1, 1, 1.5, 'holidayNewYear'),
  StaticHoliday(2, 14, 1.4, 'holidayValentine'),
  StaticHoliday(3, 17, 1.6, 'holidayStPatrick'),
  StaticHoliday(10, 31, 1.3, 'holidayHalloween'),
  StaticHoliday(12, 24, 1.5, 'holidayChristmasEve'),
  StaticHoliday(12, 25, 1.6, 'holidayChristmas'),
  StaticHoliday(12, 31, 1.8, 'holidayNewYearEve'),
];

/// Builds localized event days for static holidays within the horizon.
List<EventDay> upcomingStaticEvents(
  DateTime now,
  int horizonDays,
  String Function(String key) tr,
) {
  final end = now.add(Duration(days: horizonDays));
  final result = <EventDay>[];
  for (final year in [now.year, now.year + 1]) {
    for (final h in staticHolidays) {
      final date = DateTime(year, h.month, h.day);
      if (!date.isBefore(now) && date.isBefore(end)) {
        result.add(EventDay(
            date: date, name: tr(h.nameKey), multiplier: h.multiplier));
      }
    }
  }
  result.sort((a, b) => a.date.compareTo(b.date));
  return result;
}
