// utils/price_extension.dart
import 'currency_helper.dart';

extension PriceExtension on double {
  String get formatted => CurrencyHelper.format(this);
}

extension IntPriceExtension on int {
  String get formatted => CurrencyHelper.formatInt(this);
}