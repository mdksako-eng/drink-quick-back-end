// services/supabase_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

// ✅ Import for Realtime
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static int? _currentCompanyId;
  static int? _currentUserId;
  static bool _isCustomerMode = false;

  // ============================================================
  // ✅ REALTIME SUBSCRIPTION - FIXED
  // ============================================================
  static RealtimeChannel? _inventoryChannel;
  static RealtimeChannel? _orderChannel;
  static final List<Function> _inventoryListeners = [];
  static final List<Function> _orderListeners = [];

  static int? get currentCompanyId => _currentCompanyId;
  static int? get currentUserId => _currentUserId;
  static bool get isCustomerMode => _isCustomerMode;
  static bool get canUseSupabase =>
      !_isCustomerMode && _currentCompanyId != null;

  static Map<String, String> get _headers => ApiConfig.supabaseHeaders;

  static void setCompanyContext(int? companyId, int? userId) {
    _currentCompanyId = companyId;
    _currentUserId = userId;
    print('🔐 Supabase context: company=$companyId, user=$userId');

    if (companyId != null && !_isCustomerMode) {
      _subscribeToRealtime(companyId);
    }
  }

  static void disableForCustomer() {
    _currentCompanyId = null;
    _currentUserId = null;
    _isCustomerMode = true;
    _unsubscribeFromRealtime();
    print('🚫 Supabase disabled for customer mode');
  }

  static void clearContext() {
    _currentCompanyId = null;
    _currentUserId = null;
    _unsubscribeFromRealtime();
    print('🔐 Supabase context cleared');
  }

  // ============================================================
  // ✅ REALTIME SUBSCRIPTION - FIXED API
  // ============================================================

  static void _subscribeToRealtime(int companyId) {
    if (_inventoryChannel != null || _orderChannel != null) {
      print('⚠️ Already subscribed to real-time');
      return;
    }

    print('📡 Subscribing to real-time for company: $companyId');

    try {
      final supabase = Supabase.instance.client;

      // ✅ INVENTORY CHANNEL - FIXED
      _inventoryChannel = supabase.channel('inventory_changes_$companyId');
      _inventoryChannel!
          .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'inventory',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId.toString(),
        ),
        callback: (payload) {
          print('🔄🔥 INVENTORY REAL-TIME EVENT RECEIVED!');
          print('   Event type: ${payload.eventType}');
          print('   New data: ${payload.newRecord}');
          print('   Old data: ${payload.oldRecord}');
          _notifyInventoryListeners();
        },
      )
          .subscribe((status, error) {
        if (error != null) {
          print('❌ Inventory subscription error: $error');
        } else {
          print('✅ Inventory subscription status: $status');
        }
      });

      // ✅ ORDERS CHANNEL - FIXED
      _orderChannel = supabase.channel('order_changes_$companyId');
      _orderChannel!
          .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'company_id',
          value: companyId.toString(),
        ),
        callback: (payload) {
          print('🔄🔥 ORDER REAL-TIME EVENT RECEIVED!');
          print('   Event type: ${payload.eventType}');
          print('   New data: ${payload.newRecord}');
          print('   Old data: ${payload.oldRecord}');
          _notifyOrderListeners();
        },
      )
          .subscribe((status, error) {
        if (error != null) {
          print('❌ Order subscription error: $error');
        } else {
          print('✅ Order subscription status: $status');
        }
      });
    } catch (e) {
      print('❌ Error subscribing to real-time: $e');
    }
  }

  static void _unsubscribeFromRealtime() {
    try {
      _inventoryChannel?.unsubscribe();
      _inventoryChannel = null;
      _orderChannel?.unsubscribe();
      _orderChannel = null;
      _inventoryListeners.clear();
      _orderListeners.clear();
      print('📡 Unsubscribed from real-time');
    } catch (e) {
      print('❌ Error unsubscribing: $e');
    }
  }

  static void addInventoryListener(Function listener) {
    if (!_inventoryListeners.contains(listener)) {
      _inventoryListeners.add(listener);
    }
  }

  static void removeInventoryListener(Function listener) {
    _inventoryListeners.remove(listener);
  }

  static void addOrderListener(Function listener) {
    if (!_orderListeners.contains(listener)) {
      _orderListeners.add(listener);
    }
  }

  static void removeOrderListener(Function listener) {
    _orderListeners.remove(listener);
  }

  static void _notifyInventoryListeners() {
    for (final listener in _inventoryListeners) {
      try {
        listener();
      } catch (e) {
        print('❌ Inventory listener error: $e');
      }
    }
  }

  static void _notifyOrderListeners() {
    for (final listener in _orderListeners) {
      try {
        listener();
      } catch (e) {
        print('❌ Order listener error: $e');
      }
    }
  }

  // ============================================================
  // 🍺 DRINKS
  // ============================================================

  static Future<List<Map<String, dynamic>>> getDrinks() async {
    print('🔍 getDrinks() called');
    print('   canUseSupabase: $canUseSupabase');
    print('   _currentCompanyId: $_currentCompanyId');
    if (_currentCompanyId == null) {
      print('⚠️ No company_id set - returning empty list');
      return [];
    }
    if (!canUseSupabase) {
      print('⚠️ Supabase not available (customer mode or no company)');
      return [];
    }

    try {
      final url =
          '${ApiConfig.supabaseDrinks}?company_id=eq.$_currentCompanyId&select=*';
      print('   URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      );

      print('📨 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(jsonDecode(response.body));
        print('✅ Found ${data.length} drinks in Supabase');

        if (data.isNotEmpty) {
          print('   First drink: ${data.first['name']}');
        }

        final mappedDrinks = data
            .map((drink) => {
                  'id': drink['id'],
                  'name': drink['name'],
                  'price': drink['price'],
                  'category': drink['category'],
                  'imageUrl': drink['image_url'],
                  'currentStock': drink['current_stock'] ?? 0,
                  'minimumLevel': drink['minimum_level'] ?? 5,
                  'purchasePrice': drink['purchase_price'] ?? 0,
                  'unit': drink['unit'] ?? 'Bottle',
                })
            .toList();

        print('✅ Mapped ${mappedDrinks.length} drinks');
        return mappedDrinks;
      } else {
        print('❌ Failed to get drinks: ${response.statusCode}');
        print('   Body: ${response.body}');
        return [];
      }
    } catch (e) {
      print('❌ Supabase getDrinks error: $e');
      return [];
    }
  }

  static Future<bool> saveDrink(Map<String, dynamic> drink) async {
    if (!canUseSupabase) {
      print('⚠️ Cannot save drink - Supabase not available');
      return false;
    }

    try {
      final cleanedDrink = {
        'id': drink['id'],
        'name': drink['name'],
        'price': drink['price'],
        'category': drink['category'],
        'image_url': drink['imageUrl'],
        'company_id': _currentCompanyId,
        'created_by': _currentUserId,
        'is_active': true,
        'current_stock': drink['currentStock'] ?? 0,
        'minimum_level': drink['minimumLevel'] ?? 5,
        'purchase_price': drink['purchasePrice'] ?? 0,
        'unit': drink['unit'] ?? 'Bottle',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      print('📤 Saving drink to Supabase: ${drink['name']}');
      print('   Current stock: ${cleanedDrink['current_stock']}');

      final response = await http.post(
        Uri.parse(ApiConfig.supabaseDrinks),
        headers: {..._headers, 'Prefer': 'return=representation'},
        body: jsonEncode(cleanedDrink),
      );

      if (response.statusCode == 201) {
        print('✅ Drink saved to Supabase: ${drink['name']}');
        return true;
      } else {
        print('❌ Failed to save drink. Status: ${response.statusCode}');
        print('   Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Supabase saveDrink error: $e');
      return false;
    }
  }

  static Future<bool> updateDrink(String id, Map<String, dynamic> drink) async {
    if (!canUseSupabase) {
      print('⚠️ Cannot update drink - Supabase not available');
      return false;
    }

    try {
      final cleanedDrink = {
        'name': drink['name'],
        'price': drink['price'],
        'category': drink['category'],
        'image_url': drink['imageUrl'],
        'current_stock': drink['currentStock'],
        'minimum_level': drink['minimumLevel'],
        'purchase_price': drink['purchasePrice'],
        'unit': drink['unit'],
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await http.patch(
        Uri.parse(
            '${ApiConfig.supabaseDrinks}?id=eq.$id&company_id=eq.$_currentCompanyId'),
        headers: _headers,
        body: jsonEncode(cleanedDrink),
      );

      return response.statusCode == 204;
    } catch (e) {
      print('Supabase updateDrink error: $e');
      return false;
    }
  }

  static Future<bool> deleteDrink(String id) async {
    if (!canUseSupabase) {
      print('⚠️ Cannot save drink - Supabase not available');
      return false;
    }
    try {
      final response = await http.delete(
        Uri.parse(
            '${ApiConfig.supabaseDrinks}?id=eq.$id&company_id=eq.$_currentCompanyId'),
        headers: _headers,
      );
      return response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // 📋 ORDERS
  // ============================================================

  static Future<List<Map<String, dynamic>>> getOrders() async {
    if (!canUseSupabase) {
      print('⚠️ Cannot get orders - Supabase not available');
      return [];
    }

    try {
      final response = await http.get(
        Uri.parse(
            '${ApiConfig.supabaseOrders}?company_id=eq.$_currentCompanyId&select=*&order=created_at.desc'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(jsonDecode(response.body));
        print('✅ Found ${data.length} orders in Supabase');

        return data
            .map((order) => {
                  'id': order['id'],
                  'items': jsonDecode(order['items'] as String),
                  'totalAmount': order['total_amount'],
                  'amountPaid': order['amount_paid'],
                  'balance': order['balance'],
                  'receiptNumber': order['receipt_number'],
                  'date': order['date'],
                  'isActive': order['is_active'],
                  'customerName': order['customer_name'],
                })
            .toList();
      } else {
        print('❌ Failed to get orders: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Supabase getOrders error: $e');
      return [];
    }
  }

  static Future<bool> saveOrder(Map<String, dynamic> order) async {
    if (!canUseSupabase) {
      print('⚠️ Cannot save order - Supabase not available');
      return false;
    }

    try {
      print('📤 Saving order to Supabase: ${order['id']}');
      print('📦 Order data received: $order');

      String itemsJson;
      if (order['items'] is String) {
        itemsJson = order['items'];
      } else {
        itemsJson = jsonEncode(order['items']);
      }

      final mappedOrder = {
        'id': order['id']?.toString() ?? '',
        'company_id': _currentCompanyId,
        'items': itemsJson,
        'total_amount': (order['totalAmount'] ?? 0).toDouble(),
        'amount_paid': (order['amountPaid'] ?? 0).toDouble(),
        'balance': (order['balance'] ?? 0).toDouble(),
        'receipt_number': order['receiptNumber'] ?? '',
        'date': order['date'] ?? DateTime.now().toIso8601String(),
        'is_active': order['isActive'] ?? true,
        'customer_name': order['customerName'] ?? '',
        'created_by': _currentUserId,
        'created_at': DateTime.now().toIso8601String(),
      };

      print('📦 Mapped order: $mappedOrder');

      final response = await http.post(
        Uri.parse(ApiConfig.supabaseOrders),
        headers: {..._headers, 'Prefer': 'return=representation'},
        body: jsonEncode(mappedOrder),
      );

      print('📨 Order save response: ${response.statusCode}');
      if (response.statusCode == 201) {
        print('✅ Order saved to Supabase');
        return true;
      } else {
        print('❌ Failed to save order: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Supabase saveOrder error: $e');
      return false;
    }
  }

  static Future<bool> updateOrderStatus(String id, bool isActive) async {
    try {
      final response = await http.patch(
        Uri.parse(
            '${ApiConfig.supabaseOrders}?id=eq.$id&company_id=eq.$_currentCompanyId'),
        headers: _headers,
        body: jsonEncode({'is_active': isActive}),
      );
      return response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // 📦 INVENTORY
  // ============================================================

  static Future<List<Map<String, dynamic>>> getInventory() async {
    print('🔍 getInventory() called');
    print('   _currentCompanyId: $_currentCompanyId');

    if (!canUseSupabase) {
      print('⚠️ Cannot get inventory - Supabase not available');
      return [];
    }

    try {
      final url =
          '${ApiConfig.supabaseInventory}?company_id=eq.$_currentCompanyId&select=*';
      print('   URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      );

      print('📨 getInventory response status: ${response.statusCode}');
      print('📨 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(jsonDecode(response.body));
        print('✅ Found ${data.length} inventory items');
        for (final item in data) {
          print('   - ${item['drink_name']}: ${item['quantity']}');
        }
        return data;
      } else {
        print('❌ Failed to get inventory: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Supabase getInventory error: $e');
      return [];
    }
  }

  static Future<bool> saveInventory(Map<String, dynamic> item) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.supabaseInventory),
        headers: {..._headers, 'Prefer': 'return=representation'},
        body: jsonEncode({
          ...item,
          'company_id': _currentCompanyId,
        }),
      );
      return response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> updateInventory(
      String id, Map<String, dynamic> item) async {
    try {
      final response = await http.patch(
        Uri.parse(
            '${ApiConfig.supabaseInventory}?id=eq.$id&company_id=eq.$_currentCompanyId'),
        headers: _headers,
        body: jsonEncode(item),
      );
      return response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> upsertInventory(Map<String, dynamic> item) async {
    print('🔵 upsertInventory called');
    print('   Item: $item');

    if (!canUseSupabase) {
      print('❌ upsertInventory: cannot use Supabase');
      return false;
    }

    try {
      final drinkId = item['drinkId'] ?? item['drink_id'];
      if (drinkId == null || drinkId.toString().isEmpty) {
        print('❌ upsertInventory: drink_id is missing or empty');
        return false;
      }

      print('   drink_id: $drinkId');
      print('   company_id: $_currentCompanyId');

      final checkResponse = await http.get(
        Uri.parse(
            '${ApiConfig.supabaseInventory}?drink_id=eq.$drinkId&company_id=eq.$_currentCompanyId&select=id'),
        headers: _headers,
      );

      print('   Check response status: ${checkResponse.statusCode}');

      if (checkResponse.statusCode == 200) {
        final existingData = jsonDecode(checkResponse.body);
        final bool exists = existingData is List && existingData.isNotEmpty;

        final inventoryData = {
          'drink_id': drinkId,
          'drink_name': item['drinkName'] ?? item['drink_name'] ?? '',
          'quantity': item['quantity'] ?? 0,
          'min_stock_level':
              item['minStockLevel'] ?? item['min_stock_level'] ?? 5,
          'category': item['category'] ?? 'Beer',
          'unit': item['unit'] ?? 'Bottle',
          'purchase_price':
              (item['purchasePrice'] ?? item['purchase_price'] ?? 0).toDouble(),
          'last_restocked': (item['lastRestocked'] ??
              item['last_restocked'] ??
              DateTime.now().toIso8601String()),
          'company_id': _currentCompanyId,
        };

        if (exists) {
          print('   Updating existing inventory record...');
          final updateResponse = await http.patch(
            Uri.parse(
                '${ApiConfig.supabaseInventory}?drink_id=eq.$drinkId&company_id=eq.$_currentCompanyId'),
            headers: _headers,
            body: jsonEncode(inventoryData),
          );
          print('   Update response status: ${updateResponse.statusCode}');
          return updateResponse.statusCode == 204;
        } else {
          print('   Inserting new inventory record...');
          final insertResponse = await http.post(
            Uri.parse(ApiConfig.supabaseInventory),
            headers: {..._headers, 'Prefer': 'return=representation'},
            body: jsonEncode({
              'id':
                  item['id'] ?? 'inv_${DateTime.now().millisecondsSinceEpoch}',
              ...inventoryData,
            }),
          );
          print('   Insert response status: ${insertResponse.statusCode}');
          print('   Insert response body: ${insertResponse.body}');
          return insertResponse.statusCode == 201;
        }
      }

      return false;
    } catch (e) {
      print('❌ Supabase upsertInventory error: $e');
      return false;
    }
  }

  // ============================================================
  // 🏢 COMPANY
  // ============================================================

  static Future<Map<String, dynamic>?> getCompany(int companyId) async {
    if (!canUseSupabase) {
      print('⚠️ Cannot get company - Supabase not available');
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.supabaseCompanies}?id=eq.$companyId&select=*'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(jsonDecode(response.body));
        if (data.isNotEmpty) {
          return data.first;
        }
      }
      return null;
    } catch (e) {
      print('❌ Supabase getCompany error: $e');
      return null;
    }
  }

  // ============================================================
  // 📊 TRANSACTIONS
  // ============================================================

  static Future<List<Map<String, dynamic>>> getTransactions() async {
    if (!canUseSupabase) return [];

    try {
      final response = await http.get(
        Uri.parse(
            '${ApiConfig.supabaseTransactions}?company_id=eq.$_currentCompanyId&select=*&order=date.desc'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(jsonDecode(response.body));
        print('✅ Found ${data.length} transactions in Supabase');

        return data
            .map((txn) => {
                  'id': txn['id'],
                  'drinkId': txn['drink_id'],
                  'drinkName': txn['drink_name'],
                  'quantity': txn['quantity'],
                  'type': txn['type'],
                  'date': txn['date'],
                  'reason': txn['reason'],
                  'orderId': txn['order_id'],
                  'performedBy': txn['performed_by'],
                  'company_id': txn['company_id'],
                })
            .toList();
      }
    } catch (e) {
      print('Supabase getTransactions: $e');
    }
    return [];
  }

  static Future<bool> saveTransaction(Map<String, dynamic> transaction) async {
    if (!canUseSupabase) {
      print('⚠️ Cannot save transaction - Supabase not available');
      return false;
    }

    try {
      print('📤 Saving transaction to Supabase...');
      print('   Transaction data: $transaction');

      final mappedTransaction = {
        'id': transaction['id'],
        'company_id': transaction['company_id'] ?? _currentCompanyId,
        'drink_id': transaction['drinkId'] ?? transaction['drink_id'],
        'drink_name': transaction['drinkName'] ?? transaction['drink_name'],
        'quantity': transaction['quantity'],
        'type': transaction['type'],
        'reason': transaction['reason'] ?? 'sale',
        'order_id': transaction['orderId'] ?? transaction['order_id'],
        'performed_by':
            transaction['performedBy'] ?? transaction['performed_by'],
        'date': transaction['date'] ?? DateTime.now().toIso8601String(),
      };

      print('   Mapped transaction: $mappedTransaction');

      final response = await http.post(
        Uri.parse(ApiConfig.supabaseTransactions),
        headers: {..._headers, 'Prefer': 'return=representation'},
        body: jsonEncode(mappedTransaction),
      );

      print('   Transaction save response: ${response.statusCode}');
      if (response.statusCode == 201) {
        print('✅ Transaction saved to Supabase');
        return true;
      } else {
        print('❌ Failed to save transaction: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Supabase saveTransaction error: $e');
      return false;
    }
  }

  // ============================================================
  // ⚙️ SETTINGS
  // ============================================================

  static Future<Map<String, dynamic>?> getSettings(String userId) async {
    final intUserId = int.tryParse(userId);
    if (intUserId == null) {
      print('⚠️ Invalid userId: $userId');
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse(
          '${ApiConfig.supabaseSettings}?user_id=eq.$intUserId&company_id=eq.$_currentCompanyId&select=*',
        ),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(jsonDecode(response.body));
        return data.isNotEmpty ? data.first : null;
      }
    } catch (e) {
      print('Supabase getSettings: $e');
    }
    return null;
  }

  static Future<bool> saveSettings(Map<String, dynamic> settings) async {
    final intUserId = int.tryParse(settings['user_id']?.toString() ?? '');
    if (intUserId == null) {
      print('⚠️ Cannot save settings: Invalid user_id');
      return false;
    }

    try {
      final cleanedSettings = {
        'user_id': intUserId,
        'company_id': _currentCompanyId,
        'theme_mode': settings['theme_mode'] ?? 0,
        'primary_color': settings['primary_color'] ?? '#667EEA',
        'compact_mode': settings['compact_mode'] ?? false,
        'show_notifications': settings['show_notifications'] ?? true,
        'auto_sync': settings['auto_sync'] ?? false,
        'company_name': settings['company_name'] ?? '',
        'company_email': settings['company_email'] ?? '',
        'company_phone': settings['company_phone'] ?? '',
        'company_address': settings['company_address'] ?? '',
        'updated_at': DateTime.now().toIso8601String(),
      };

      final existing = await getSettings(settings['user_id']);

      if (existing != null) {
        final response = await http.patch(
          Uri.parse(
            '${ApiConfig.supabaseSettings}?user_id=eq.$intUserId&company_id=eq.$_currentCompanyId',
          ),
          headers: _headers,
          body: jsonEncode(cleanedSettings),
        );
        return response.statusCode == 204;
      } else {
        cleanedSettings['created_at'] = DateTime.now().toIso8601String();
        final response = await http.post(
          Uri.parse(ApiConfig.supabaseSettings),
          headers: {..._headers, 'Prefer': 'return=representation'},
          body: jsonEncode(cleanedSettings),
        );
        return response.statusCode == 201;
      }
    } catch (e) {
      print('Supabase saveSettings error: $e');
      return false;
    }
  }

  // ============================================================
  // 🔌 HEALTH CHECK
  // ============================================================

  static Future<bool> isConnected() async {
    try {
      final response = await http
          .get(
            Uri.parse('${ApiConfig.supabaseRestUrl}/drinks?limit=1'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // 💰 COMPANY PAYMENT SETTINGS
  // ============================================================

  static Future<Map<String, dynamic>?> getCompanyPaymentSettings() async {
    if (_currentCompanyId == null) {
      print('⚠️ Cannot get company payment settings - no company_id');
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse(
          '${ApiConfig.supabaseRestUrl}/companies?id=eq.$_currentCompanyId&select=*',
        ),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(jsonDecode(response.body));
        if (data.isNotEmpty) {
          final company = data.first;
          print('✅ Loaded company: ${company['name']}');
          return company;
        }
        print('⚠️ Company not found for ID: $_currentCompanyId');
        return null;
      } else {
        print('❌ Failed to get company: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ getCompanyPaymentSettings error: $e');
      return null;
    }
  }

  static Future<bool> saveCompanyPaymentSettings(
      Map<String, dynamic> settings) async {
    if (_currentCompanyId == null) {
      print('⚠️ Cannot save company payment settings - no company_id');
      return false;
    }

    try {
      final paymentSettings = {
        'name': settings['name'],
        'email': settings['email'],
        'phone': settings['phone'],
        'address': settings['address'],
        'currency_symbol': settings['currency_symbol'] ?? 'Frs',
        'currency_position': settings['currency_position'] ?? 'right',
        'decimal_separator': settings['decimal_separator'] ?? '.',
        'thousands_separator': settings['thousands_separator'] ?? ',',
        'decimal_places': settings['decimal_places'] ?? 0,
        'business_payments_enabled':
            settings['business_payments_enabled'] ?? false,
        'mtn_enabled': settings['mtn_enabled'] ?? true,
        'orange_enabled': settings['orange_enabled'] ?? true,
        'mtn_merchant_phone': settings['mtn_merchant_phone'] ?? '',
        'orange_merchant_phone': settings['orange_merchant_phone'] ?? '',
        'mtn_merchant_id': settings['mtn_merchant_id'] ?? '',
        'orange_merchant_id': settings['orange_merchant_id'] ?? '',
        'mtn_sandbox_mode': settings['mtn_sandbox_mode'] ?? true,
        'orange_sandbox_mode': settings['orange_sandbox_mode'] ?? true,
        'mtn_api_key_encrypted': settings['mtn_api_key_encrypted'] ?? '',
        'mtn_secret_key_encrypted': settings['mtn_secret_key_encrypted'] ?? '',
        'orange_api_key_encrypted': settings['orange_api_key_encrypted'] ?? '',
        'orange_secret_key_encrypted':
            settings['orange_secret_key_encrypted'] ?? '',
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await http.patch(
        Uri.parse(
          '${ApiConfig.supabaseCompanies}?id=eq.$_currentCompanyId',
        ),
        headers: {..._headers, 'Prefer': 'return=representation'},
        body: jsonEncode(paymentSettings),
      );

      if (response.statusCode == 204 || response.statusCode == 200) {
        print('✅ Company settings updated');
        return true;
      } else {
        print(
            '❌ Failed to update company: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ saveCompanyPaymentSettings error: $e');
      return false;
    }
  }

  // ============================================================
  // 💳 PAYMENT TRANSACTIONS
  // ============================================================

  static Future<bool> savePaymentTransaction(
      Map<String, dynamic> transaction) async {
    if (_currentCompanyId == null) {
      print('⚠️ Cannot save payment transaction - no company_id');
      return false;
    }

    try {
      final mappedTransaction = {
        'order_id': transaction['orderId'],
        'company_id': _currentCompanyId,
        'customer_phone': transaction['customerPhone'],
        'amount': transaction['amount'],
        'payment_method': transaction['paymentMethod'],
        'transaction_id': transaction['transactionId'],
        'status': transaction['status'] ?? 'pending',
        'reference': transaction['reference'],
        'error_message': transaction['errorMessage'],
        'created_at': DateTime.now().toIso8601String(),
      };

      final response = await http.post(
        Uri.parse(ApiConfig.supabasePaymentTransactions),
        headers: {..._headers, 'Prefer': 'return=representation'},
        body: jsonEncode(mappedTransaction),
      );

      if (response.statusCode == 201) {
        print('✅ Payment transaction saved');
        return true;
      } else {
        print(
            '❌ Failed to save transaction: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ savePaymentTransaction error: $e');
      return false;
    }
  }

  static Future<bool> updateTransactionStatus(String orderId, String status,
      {String? errorMessage}) async {
    if (_currentCompanyId == null) {
      print('⚠️ Cannot update transaction - no company_id');
      return false;
    }

    try {
      final updates = {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
        if (status == 'completed')
          'confirmed_at': DateTime.now().toIso8601String(),
        if (errorMessage != null) 'error_message': errorMessage,
      };

      final response = await http.patch(
        Uri.parse(
          '${ApiConfig.supabasePaymentTransactions}?order_id=eq.$orderId&company_id=eq.$_currentCompanyId',
        ),
        headers: _headers,
        body: jsonEncode(updates),
      );

      return response.statusCode == 204;
    } catch (e) {
      print('❌ updateTransactionStatus error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getTransactionByOrderId(
      String orderId) async {
    if (_currentCompanyId == null) return null;

    try {
      final response = await http.get(
        Uri.parse(
          '${ApiConfig.supabasePaymentTransactions}?order_id=eq.$orderId&company_id=eq.$_currentCompanyId&select=*',
        ),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(jsonDecode(response.body));
        if (data.isNotEmpty) {
          return data.first;
        }
        return null;
      } else {
        print('❌ Failed to get transaction: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ getTransactionByOrderId error: $e');
      return null;
    }
  }
}
