// providers/order_provider.dart
// providers/order_provider.dart - COMPLETE FIXED VERSION

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/utils/helpers.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';
import 'package:drinks_calculator_fixed/services/notification_service.dart';
import 'package:drinks_calculator_fixed/utils/json_num.dart';
import 'package:drinks_calculator_fixed/utils/order_totals.dart';

class Order {
  final String id;
  final List<Drink> items;
  final double totalAmount;
  final double amountPaid;
  final double balance;
  final String receiptNumber;
  final DateTime date;
  final bool isActive;

  /// The void trace: set when a manager corrected this order after the fact.
  final DateTime? voidedAt;
  final String voidReason;
  final String voidedByName;

  bool get isVoided => voidedAt != null;
  final String customerName;
  final String staffName;

  /// The registered customer account this sale belongs to, when one was chosen.
  /// A tab (part of the sale left unpaid) is a DEBT, so it needs this account:
  /// the credit ledger keeps the balance and the statement is sent to it.
  final int? customerId;

  /// The part of this sale that went on the customer's tab (0 for a normal sale).
  /// Deliberately NOT [balance]: that is the change handed back on a cash sale.
  final double tabAmount;

  Order({
    required this.id,
    required this.items,
    required this.totalAmount,
    required this.amountPaid,
    required this.balance,
    required this.receiptNumber,
    required this.date,
    this.isActive = true,
    this.voidedAt,
    this.voidReason = '',
    this.voidedByName = '',
    this.customerName = '',
    this.staffName = '',
    this.customerId,
    this.tabAmount = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'items': items.map((drink) => drink.toJson()).toList(),
      'totalAmount': totalAmount,
      'amountPaid': amountPaid,
      'balance': balance,
      'tabAmount': tabAmount,
      'customerId': customerId,
      'receiptNumber': receiptNumber,
      'date': date.toIso8601String(),
      'isActive': isActive,
      'voidedAt': voidedAt?.toIso8601String(),
      'voidReason': voidReason,
      'voidedByName': voidedByName,
      'customerName': customerName,
      'staffName': staffName,
      'staff_name': staffName,
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
      // Money fields are read tolerantly on purpose: orders.tab_amount is
      // NUMERIC(12,2) and Postgres hands NUMERIC back as a string ("0.00"), so
      // `.toDouble()` here threw and — because this runs per row — every order
      // was skipped, leaving 0 of 128 loaded.
      totalAmount: asDouble(json['totalAmount'] ?? json['total_amount']) ?? 0,
      amountPaid: asDouble(json['amountPaid'] ?? json['amount_paid']) ?? 0,
      balance: asDouble(json['balance']) ?? 0,
      tabAmount: asDouble(json['tabAmount'] ?? json['tab_amount']) ?? 0,
      customerId: int.tryParse(
          '${json['customerId'] ?? json['customer_id'] ?? ''}'),
      receiptNumber: json['receiptNumber']?.toString() ??
          json['receipt_number']?.toString() ??
          '',
      date: date,
      isActive: json['isActive'] ?? json['is_active'] ?? true,
      voidedAt: DateTime.tryParse(
          '${json['voidedAt'] ?? json['voided_at'] ?? ''}'),
      voidReason: (json['voidReason'] ?? json['void_reason'] ?? '').toString(),
      voidedByName:
          (json['voidedByName'] ?? json['voided_by_name'] ?? '').toString(),
      customerName: json['customerName']?.toString() ??
          json['customer_name']?.toString() ??
          '',
      staffName: json['staffName']?.toString() ??
          json['staff_name']?.toString() ??
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
    // Don't latch "initialized" without a company context — otherwise the
    // provider loads 0 local orders and never retries once the company
    // (e.g. from an approved join) becomes available.
    if (!SupabaseService.canUseSupabase) {
      print('   ⏭️ No company context yet - deferring initialization');
      return;
    }
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
      List<Drink> items, double amountPaid, String customerName,
      {String staffName = '', int? customerId, double tabAmount = 0}) async {
    try {
      _isLoading = true;
      notifyListeners();

      final totalAmount = items.fold(0.0, (sum, item) => sum + item.price);
      final balance = amountPaid - totalAmount;
      final receiptNumber = 'REC-${DateTime.now().millisecondsSinceEpoch}';
      final orderId = DateTime.now().millisecondsSinceEpoch.toString();

      final List<Drink> copiedItems = [];
      for (final drink in items) {
        // Keep the whole drink: the order snapshot must not lose the purchase
        // price, unit or barcode the reports and the profit summary read.
        copiedItems.add(drink.copyWith());
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
        staffName: staffName,
        customerId: customerId,
        tabAmount: tabAmount,
      );

      print('🔍 Creating order: ${order.id}');
      print('🔍 canUseSupabase: ${SupabaseService.canUseSupabase}');

      _orderHistory.add(order);
      await _saveOrders();

      // 🔔 Notify the in-app notification center
      // 🔢 Count UNITS, not cart lines: the cart merges a repeated drink into one
      // line with a quantity (calculator_screen builds `quantity: entry.value`), so
      // `copiedItems.length` reported "1 item" for a sale of 24 crates.
      NotificationService().showOrderCreated(
        orderId: order.id,
        itemCount: totalUnits(copiedItems),
        totalAmount: totalAmount,
      );

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

  /// Voids an order (manager only) and refreshes the list. A void keeps who,
  /// when and why, and stops the order counting as a sale — never a delete.
  Future<bool> voidOrder(String orderId, String reason) async {
    final ok = await SupabaseService.voidOrder(orderId, reason);
    if (ok) await reloadOrders();
    return ok;
  }

  /// Undoes a void (manager only) — the order counts as a sale again.
  Future<bool> restoreOrder(String orderId) async {
    final ok = await SupabaseService.restoreOrder(orderId);
    if (ok) await reloadOrders();
    return ok;
  }

  /// Cancels a sale that never completed — a refused stock commit, a rolled-back
  /// multi-line sale. The reason is recorded on the server and the order stops
  /// counting as a sale; stock is deliberately NOT touched here, because the
  /// caller has already put back the lines it managed to take off the shelf.
  ///
  /// Returns false when the backend refused (offline, expired session), so the
  /// caller can warn the operator instead of claiming a success the server never
  /// recorded.
  Future<bool> cancelOrder(String orderId, String reason) async {
    final ok = await SupabaseService.cancelOrder(orderId, reason);
    if (ok) await reloadOrders();
    return ok;
  }

  /// Retires the invoice that a re-invoice replaces.
  ///
  /// A void is tried first because it also puts the stock back — which is what
  /// stops the replacement sale from deducting the same drinks twice. When the
  /// acting user may not void (staff), it falls back to a stock-free cancel, so
  /// the old invoice stops counting as a sale either way instead of the pair
  /// being counted twice.
  Future<bool> voidOrCancelOrder(String orderId, String reason) async {
    final voided = await SupabaseService.voidOrder(orderId, reason);
    if (voided) {
      await reloadOrders();
      return true;
    }
    return cancelOrder(orderId, reason);
  }

  /// What a return dialog needs for one order, or `null` when the backend could
  /// not answer (offline, expired session) — the caller must not draw an empty
  /// dialog on `null`, or "we could not ask" would look like "nothing to return".
  Future<Map<String, dynamic>?> loadReturnableLines(String orderId) =>
      SupabaseService.fetchOrderReturns(orderId);

  /// Gives items back (manager only): the units return to the shelf and the money
  /// to the customer, and the sale keeps counting as billed — the refund shows up
  /// as its own Returns line on the Z-report instead of a rewritten invoice.
  ///
  /// Returns the backend's answer, or `null` when it refused (staff, everything
  /// already returned, a drink that is not stocked) with `message` explaining why.
  Future<Map<String, dynamic>?> returnItems(
    String orderId, {
    required String reason,
    required List<Map<String, dynamic>> items,
  }) async {
    final result = await SupabaseService.returnOrderItems(
      orderId,
      reason: reason,
      items: items,
    );
    if (result != null && result['success'] == true) await reloadOrders();
    return result;
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
      _isInitialized = false;
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
