// utils/constants.dart
import 'package:drinks_calculator_fixed/models/drink_model.dart';

class AppConstants {
  /// The released app version — the `version:` field of `pubspec.yaml` with the
  /// `+build` suffix stripped. **One version for the whole app:** the drawer,
  /// the lock screen, backup metadata and support reports all read this, and
  /// `test/app_info_test.dart` fails if it drifts from pubspec.yaml.
  static const String appVersion = '1.1.0';

  // Empty arrays - no built-in drinks
  static const List<Drink> beers = [];
  static const List<Drink> wines = [];
  static const List<Drink> cocktails = [];

  // Default placeholder image URL
  static const String defaultDrinkImage =
      'https://via.placeholder.com/150/667EEA/FFFFFF?text=Drink';

  // Drink categories
  static const List<String> drinkCategories = [
    'Beer',
    'Wine',
    'Cocktail',
    'Soft Drink',
    'Other'
  ];

  
}
