// utils/currency_helper.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CurrencyHelper {
  static String _currencySymbol = 'Frs';
  static String _currencyPosition = 'right';
  static String _decimalSeparator = '.';
  static String _thousandsSeparator = ',';
  static int _decimalPlaces = 0;
  static bool _isInitialized = false;
  
  // Listeners for currency changes
  static final List<VoidCallback> _listeners = [];

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _currencySymbol = prefs.getString('currency_symbol') ?? 'Frs';
    _currencyPosition = prefs.getString('currency_position') ?? 'right';
    _decimalSeparator = prefs.getString('decimal_separator') ?? '.';
    _thousandsSeparator = prefs.getString('thousands_separator') ?? ',';
    _decimalPlaces = prefs.getInt('decimal_places') ?? 0;
    _isInitialized = true;
    
    debugPrint('CurrencyHelper initialized: $_currencySymbol');
  }

  static String format(double amount) {
    if (!_isInitialized) {
      initialize();
    }
    
    String formattedNumber;
    
    if (_decimalPlaces == 0) {
      formattedNumber = amount.toInt().toString();
    } else {
      formattedNumber = amount.toStringAsFixed(_decimalPlaces);
    }
    
    final parts = formattedNumber.split(_decimalSeparator);
    parts[0] = _addThousandsSeparators(parts[0]);
    formattedNumber = parts.join(_decimalSeparator);
    
    if (_currencyPosition == 'left') {
      return '$_currencySymbol$formattedNumber';
    } else {
      return '$formattedNumber$_currencySymbol';
    }
  }

  static String formatInt(int amount) {
    return format(amount.toDouble());
  }

  static String _addThousandsSeparators(String number) {
    if (_thousandsSeparator.isEmpty) return number;
    
    final buffer = StringBuffer();
    for (int i = 0; i < number.length; i++) {
      if (i > 0 && (number.length - i) % 3 == 0) {
        buffer.write(_thousandsSeparator);
      }
      buffer.write(number[i]);
    }
    return buffer.toString();
  }

  static String getSymbol() => _currencySymbol;
  static String getPosition() => _currencyPosition;
  static int getDecimalPlaces() => _decimalPlaces;
  
  // Add listener
  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }
  
  // Remove listener
  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
  
  // Notify all listeners of currency change
  static void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }
  
  // Refresh and notify
  static Future<void> refresh() async {
    _isInitialized = false;
    await initialize();
    notifyListeners();
    debugPrint('CurrencyHelper refreshed: $_currencySymbol');
  }
}