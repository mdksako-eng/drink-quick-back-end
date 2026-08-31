// lib/services/drink_service.dart
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/utils/constants.dart'; // Added import

class DrinkService {
  static List<Drink> getAllDrinks() {
    return [
      ...AppConstants.beers,
      ...AppConstants.wines,
      ...AppConstants.cocktails,
    ];
  }
}
