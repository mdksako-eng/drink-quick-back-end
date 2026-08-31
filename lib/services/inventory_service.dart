// services/inventory_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/inventory_model.dart';

class InventoryService {
  final String _baseUrl = ApiConfig.baseUrl;

  // Sync inventory with backend
  Future<bool> syncInventory(
    List<InventoryItem> items,
    List<InventoryTransaction> transactions,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/inventory/sync'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'items': items.map((i) => i.toJson()).toList(),
          'transactions': transactions.map((t) => t.toJson()).toList(),
        }),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print('Inventory sync error: $e');
      return false;
    }
  }

  // Get inventory from backend
  Future<Map<String, dynamic>?> getInventory() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/inventory'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Get inventory error: $e');
      return null;
    }
  }

  // Add stock (backend)
  Future<bool> addStock({
    required String drinkId,
    required String drinkName,
    required int quantity,
    String reason = 'restock',
    String? performedBy,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/inventory/add-stock'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'drinkId': drinkId,
          'drinkName': drinkName,
          'quantity': quantity,
          'reason': reason,
          'performedBy': performedBy,
        }),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print('Add stock error: $e');
      return false;
    }
  }

  // Remove stock (backend)
  Future<bool> removeStock({
    required String drinkId,
    required String drinkName,
    required int quantity,
    String reason = 'sale',
    String? orderId,
    String? performedBy,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/inventory/remove-stock'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'drinkId': drinkId,
          'drinkName': drinkName,
          'quantity': quantity,
          'reason': reason,
          'orderId': orderId,
          'performedBy': performedBy,
        }),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print('Remove stock error: $e');
      return false;
    }
  }

  // Get transaction history
  Future<List<InventoryTransaction>?> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      String url = '$_baseUrl/api/inventory/transactions';
      if (startDate != null && endDate != null) {
        url += '?startDate=${startDate.toIso8601String()}&endDate=${endDate.toIso8601String()}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> transactions = data['transactions'] ?? [];
        return transactions.map((t) => InventoryTransaction.fromJson(t)).toList();
      }
      return null;
    } catch (e) {
      print('Get transactions error: $e');
      return null;
    }
  }

  // Get low stock alerts
  Future<List<InventoryItem>?> getLowStockItems() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/inventory/low-stock'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['items'] ?? [];
        return items.map((i) => InventoryItem.fromJson(i)).toList();
      }
      return null;
    } catch (e) {
      print('Get low stock error: $e');
      return null;
    }
  }

  // Generate report (backend)
  Future<Map<String, dynamic>?> generateReport({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/inventory/report'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'startDate': startDate.toIso8601String(),
          'endDate': endDate.toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Generate report error: $e');
      return null;
    }
  }
}