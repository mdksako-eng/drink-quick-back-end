// utils/constants.dart
import 'package:drinks_calculator_fixed/models/drink_model.dart';

class AppConstants {
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
