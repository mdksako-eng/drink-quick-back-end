// providers/order_provider.dart
// providers/order_provider.dart - COMPLETE FIXED VERSION

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/utils/helpers.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';

class Order {
  final String id;
  final List<Drink> items;
  final double totalAmount;
  final double amountPaid;
  final double balance;
  final String receiptNumber;
  final DateTime date;
  final bool isActive;
  final String customerName;

  Order({
    required this.id,
    required this.items,
    required this.totalAmount,
    required this.amountPaid,
    required this.balance,
    required this.receiptNumber,
    required this.date,
    this.isActive = true,
    this.customerName = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'items': items.map((drink) => drink.toJson()).toList(),
      'totalAmount': totalAmount,
      'amountPaid': amountPaid,
      'balance': balance,
      'receiptNumber': receiptNumber,
      'date': date.toIso8601String(),
      'isActive': isActive,
      'customerName': customerName,
    };
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    // ✅ Handle both String and List formats
    List<dynamic> itemsList = [];

    if (json['items'] is String) {
      // ✅ Parse JSON string to List
      try {
        itemsList = jsonDecode(json['items']) as List<dynamic>;
      } catch (e) {
        print('❌ Error parsing items JSON string: $e');
        itemsList = [];
      }
    } else if (json['items'] is List) {
      itemsList = json['items'] as List<dynamic>;
    }

    final items = itemsList.map((item) => Drink.fromJson(item)).toList();

    // Handle date with fallback
    DateTime? date;
    if (json['date'] != null) {
      try {
        date = DateTime.parse(json['date']);
      } catch (e) {
        date = DateTime.now();
      }
    } else if (json['created_at'] != null) {
      try {
        date = DateTime.parse(json['created_at']);
      } catch (e) {
        date = DateTime.now();
      }
    } else {
      date = DateTime.now();
    }

    return Order(
      id: json['id']?.toString() ?? '',
      items: items,
      totalAmount:
          (json['totalAmount'] ?? json['total_amount'] ?? 0).toDouble(),
      amountPaid: (json['amountPaid'] ?? json['amount_paid'] ?? 0).toDouble(),
      balance: (json['balance'] ?? 0).toDouble(),
      receiptNumber: json['receiptNumber']?.toString() ??
          json['receipt_number']?.toString() ??
          '',
      date: date,
      isActive: json['isActive'] ?? json['is_active'] ?? true,
      customerName: json['customerName']?.toString() ??
          json['customer_name']?.toString() ??
          '',
    );
  }
}

class OrderProvider with ChangeNotifier {
  Order? _currentOrder;
  List<Order> _orderHistory = [];
  bool _isLoading = false;
  bool _isInitialized = false;

  static const String _storageKey = 'order_history';

  Order? get currentOrder => _currentOrder;
  List<Order> get orderHistory => _orderHistory;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;

  // ✅ Don't load in constructor - wait for initialization
  OrderProvider() {
    // Wait for explicit initialization
    print('🏗️ OrderProvider CREATED - waiting for initialization');
  }

  // ✅ Initialize when called (after company context is set)
  Future<void> initialize() async {
    print('🔧 OrderProvider.initialize() called');
    if (_isInitialized) {
      print('   Already initialized, skipping');
      return;
    }
    _isInitialized = true;
    print('   First initialization, loading orders...');
    await _loadOrders();
  }

  // ✅ Load orders from Supabase with company filter
  Future<void> loadOrdersFromSupabase() async {
    print('═══════════════════════════════════════════════════════');
    print('📦 loadOrdersFromSupabase() CALLED');
    print('═══════════════════════════════════════════════════════');

    print('🔍 Debug Info:');
    print('   canUseSupabase: ${SupabaseService.canUseSupabase}');
    print('   currentCompanyId: ${SupabaseService.currentCompanyId}');
    print('   isCustomerMode: ${SupabaseService.isCustomerMode}');

    if (!SupabaseService.canUseSupabase) {
      print('⚠️ Cannot load orders from Supabase - not available');
      print(
          '   Reason: ${SupabaseService.isCustomerMode ? "Customer mode" : "No company ID"}');
      print('═══════════════════════════════════════════════════════');
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();

      print(
          '📤 Calling SupabaseService.getOrders() for company ${SupabaseService.currentCompanyId}...');
      final supabaseOrders = await SupabaseService.getOrders();

      print('📦 Received ${supabaseOrders.length} orders from Supabase');

      if (supabaseOrders.isNotEmpty) {
        print('📦 First order sample: ${supabaseOrders.first['id']}');
        _orderHistory = supabaseOrders
            .map((json) {
              try {
                return Order.fromJson(json);
              } catch (e) {
                print('❌ Error parsing order: $e');
                print('❌ Order JSON: $json');
                return null;
              }
            })
            .whereType<Order>()
            .toList();

        await _saveOrders();
        notifyListeners();
        print('✅ Loaded ${_orderHistory.length} orders from Supabase');
      } else {
        print(
            '⚠️ No orders found in Supabase for company ${SupabaseService.currentCompanyId}');
        _orderHistory = [];
        await _saveOrders();
        notifyListeners();
      }
    } catch (e) {
      print('❌ Error loading orders from Supabase: $e');
      // Fallback to local
      await _loadOrdersFromLocal();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
      print('📦 loadOrdersFromSupabase() COMPLETED');
      print('═══════════════════════════════════════════════════════');
    }
  }

  Future<void> _loadOrders() async {
    print('📂 _loadOrders() called');
    try {
      _isLoading = true;
      notifyListeners();

      if (SupabaseService.canUseSupabase) {
        print('   Loading from Supabase...');
        await loadOrdersFromSupabase();
      } else {
        print('   Loading from local storage...');
        await _loadOrdersFromLocal();
      }
    } catch (e) {
      print('❌ Error loading orders: $e');
      _orderHistory = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadOrdersFromLocal() async {
    print('📂 _loadOrdersFromLocal() called');
    try {
      final prefs = await SharedPreferences.getInstance();
      final ordersJson = prefs.getString(_storageKey);

      if (ordersJson != null && ordersJson.isNotEmpty) {
        final List<dynamic> ordersList = json.decode(ordersJson);
        _orderHistory =
            ordersList.map((orderMap) => Order.fromJson(orderMap)).toList();
        print('✅ Loaded ${_orderHistory.length} orders from local storage');
      } else {
        print('ℹ️ No orders found in local storage');
        _orderHistory = [];
      }
    } catch (e) {
      print('❌ Error loading local orders: $e');
      _orderHistory = [];
    }
  }

  Future<void> _saveOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String ordersJson =
          json.encode(_orderHistory.map((order) => order.toJson()).toList());
      await prefs.setString(_storageKey, ordersJson);
      print('💾 Saved ${_orderHistory.length} orders to storage');
    } catch (e) {
      print('❌ Error saving orders: $e');
      throw e;
    }
  }

  Future<Order> createOrderAndGetOrder(
      List<Drink> items, double amountPaid, String customerName) async {
    try {
      _isLoading = true;
      notifyListeners();

      final totalAmount = items.fold(0.0, (sum, item) => sum + item.price);
      final balance = amountPaid - totalAmount;
      final receiptNumber = 'REC-${DateTime.now().millisecondsSinceEpoch}';
      final orderId = DateTime.now().millisecondsSinceEpoch.toString();

      final List<Drink> copiedItems = [];
      for (final drink in items) {
        copiedItems.add(Drink(
          id: drink.id,
          name: drink.name,
          price: drink.price,
          category: drink.category,
          imageUrl: drink.imageUrl,
        ));
      }

      final order = Order(
        id: orderId,
        items: copiedItems,
        totalAmount: totalAmount,
        amountPaid: amountPaid,
        balance: balance,
        receiptNumber: receiptNumber,
        date: DateTime.now(),
        isActive: true,
        customerName: customerName,
      );

      print('🔍 Creating order: ${order.id}');
      print('🔍 canUseSupabase: ${SupabaseService.canUseSupabase}');

      _orderHistory.add(order);
      await _saveOrders();

      // Sync to Supabase
      if (SupabaseService.canUseSupabase) {
        final success = await SupabaseService.saveOrder(order.toJson());
        print('🔍 Order save to Supabase: ${success ? "SUCCESS" : "FAILED"}');
      } else {
        print('⚠️ Cannot sync order - Supabase not available');
      }

      Helpers.showToast('Order created successfully!');
      print('➕ Added new order: ${order.receiptNumber} with ID: ${order.id}');

      return order;
    } catch (e) {
      print('❌ Error creating order: $e');
      Helpers.showToast('Error creating order');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearCurrentOrder() {
    _currentOrder = null;
    notifyListeners();
  }

  Future<void> toggleOrderStatus(String orderId, bool isActive) async {
    try {
      _isLoading = true;
      notifyListeners();

      final index = _orderHistory.indexWhere((order) => order.id == orderId);
      if (index != -1) {
        final order = _orderHistory[index];
        final updatedOrder = Order(
          id: order.id,
          items: order.items
              .map((drink) => Drink(
                    id: drink.id,
                    name: drink.name,
                    price: drink.price,
                    category: drink.category,
                    imageUrl: drink.imageUrl,
                  ))
              .toList(),
          totalAmount: order.totalAmount,
          amountPaid: order.amountPaid,
          balance: order.balance,
          receiptNumber: order.receiptNumber,
          date: order.date,
          isActive: isActive,
          customerName: order.customerName,
        );
        _orderHistory[index] = updatedOrder;
        await _saveOrders();
        // Sync to Supabase
        try {
          await SupabaseService.updateOrderStatus(orderId, isActive);
        } catch (e) {
          print('Supabase order status sync error: $e');
        }
        print('${isActive ? '✅ Activated' : '❌ Deactivated'} order: $orderId');
        Helpers.showToast(isActive
            ? 'Order activated successfully'
            : 'Order deactivated successfully');
      } else {
        print('⚠️ Order not found: $orderId');
        Helpers.showToast('Order not found');
      }
    } catch (e) {
      print('❌ Error toggling order status: $e');
      Helpers.showToast('Error updating order status');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<Order> getActiveOrders() {
    return _orderHistory.where((order) => order.isActive == true).toList();
  }

  List<Order> getDeactivatedOrders() {
    return _orderHistory.where((order) => order.isActive == false).toList();
  }

  Future<void> clearAllOrders() async {
    try {
      _isLoading = true;
      notifyListeners();

      _orderHistory.clear();
      await _saveOrders();
      notifyListeners();
      print('🗑️ Cleared all orders');
      Helpers.showToast('All orders cleared');
    } catch (e) {
      print('❌ Error clearing orders: $e');
      Helpers.showToast('Error clearing orders');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Order? getOrderById(String orderId) {
    try {
      return _orderHistory.firstWhere((order) => order.id == orderId);
    } catch (e) {
      return null;
    }
  }

  double getTotalRevenue() {
    return _orderHistory
        .where((order) => order.isActive == true)
        .fold(0.0, (sum, order) => sum + order.totalAmount);
  }

  int getTotalItemsSold() {
    return _orderHistory
        .where((order) => order.isActive == true)
        .fold(0, (sum, order) => sum + order.items.length);
  }

  List<Order> getTodaysOrders() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    return _orderHistory.where((order) {
      return order.isActive == true &&
          order.date.isAfter(todayStart) &&
          order.date.isBefore(todayEnd);
    }).toList();
  }

  List<Order> getThisWeeksOrders() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startDate =
        DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final endDate = startDate.add(const Duration(days: 7));

    return _orderHistory.where((order) {
      return order.isActive == true &&
          order.date.isAfter(startDate) &&
          order.date.isBefore(endDate);
    }).toList();
  }

  List<Order> getThisMonthsOrders() {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, 1);
    final endDate = DateTime(now.year, now.month + 1, 1);

    return _orderHistory.where((order) {
      return order.isActive == true &&
          order.date.isAfter(startDate) &&
          order.date.isBefore(endDate);
    }).toList();
  }

  List<Order> getOrdersByDateRange(DateTime startDate, DateTime endDate) {
    return _orderHistory.where((order) {
      return order.isActive == true &&
          order.date.isAfter(startDate) &&
          order.date.isBefore(endDate);
    }).toList();
  }

  String exportOrdersToJson() {
    return json.encode(_orderHistory.map((order) => order.toJson()).toList());
  }

  Future<void> importOrdersFromJson(String jsonString) async {
    try {
      _isLoading = true;
      notifyListeners();

      final List<dynamic> ordersList = json.decode(jsonString);
      _orderHistory =
          ordersList.map((orderMap) => Order.fromJson(orderMap)).toList();
      await _saveOrders();

      print('📥 Imported ${_orderHistory.length} orders');
      Helpers.showToast('Orders imported successfully');
    } catch (e) {
      print('❌ Error importing orders: $e');
      Helpers.showToast('Error importing orders');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> reloadOrders() async {
    print('🔄 Reloading orders...');
    await _loadOrders();
  }

  Map<String, dynamic> getStorageStats() {
    final activeOrders = getActiveOrders();
    return {
      'totalOrders': _orderHistory.length,
      'activeOrders': activeOrders.length,
      'deactivatedOrders': getDeactivatedOrders().length,
      'totalRevenue': getTotalRevenue(),
      'totalItemsSold': getTotalItemsSold(),
      'todaysOrders': getTodaysOrders().length,
      'thisWeekOrders': getThisWeeksOrders().length,
      'thisMonthOrders': getThisMonthsOrders().length,
    };
  }
}
