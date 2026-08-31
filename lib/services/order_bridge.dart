// services/order_bridge.dart
import 'package:flutter/material.dart';
import '../models/drink_model.dart';

/// Bridge service to pass orders from AI to Calculator
class OrderBridge {
  static final OrderBridge _instance = OrderBridge._internal();
  factory OrderBridge() => _instance;
  OrderBridge._internal();

  final List<Map<String, dynamic>> _pendingDrinks = [];
  String _customerName = '';

  List<Map<String, dynamic>> get pendingDrinks => _pendingDrinks;
  String get customerName => _customerName;
  bool get hasPendingOrder => _pendingDrinks.isNotEmpty;

  void addDrink(Drink drink, int quantity) {
    // Check if drink already exists
    final index = _pendingDrinks.indexWhere((d) => d['drink'].id == drink.id);
    if (index != -1) {
      _pendingDrinks[index]['quantity'] += quantity;
    } else {
      _pendingDrinks.add({'drink': drink, 'quantity': quantity});
    }
  }

  void setCustomerName(String name) {
    _customerName = name;
  }

  double get totalAmount {
    return _pendingDrinks.fold(0.0, (sum, item) {
      final drink = item['drink'] as Drink;
      final quantity = item['quantity'] as int;
      return sum + (drink.price * quantity);
    });
  }

  void clearOrder() {
    _pendingDrinks.clear();
    _customerName = '';
  }
}