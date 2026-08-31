// providers/inventory_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/inventory_model.dart';
import '../services/inventory_service.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import '../models/drink_model.dart';

class InventoryProvider with ChangeNotifier {
  List<InventoryItem> _inventoryItems = [];
  List<InventoryTransaction> _transactions = [];
  bool _isLoading = false;
  String? _error;
  final InventoryService _inventoryService = InventoryService();
  DrinkProvider? _drinkProvider;

  // ✅ Setter method to connect DrinkProvider
  void setDrinkProvider(DrinkProvider drinkProvider) {
    _drinkProvider = drinkProvider;
    debugPrint('✅ InventoryProvider connected to DrinkProvider');
  }

  Future<void> saveInventoryToStorage() async {
    await _saveToLocalStorage();
  }

  void refreshInventory() {
    notifyListeners();
  }

  List<InventoryItem> get inventoryItems => _inventoryItems;
  List<InventoryTransaction> get transactions => _transactions;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Computed properties
  List<InventoryItem> get lowStockItems =>
      _inventoryItems.where((item) => item.isLowStock).toList();

  int get totalItems =>
      _inventoryItems.fold(0, (sum, item) => sum + item.quantity);

  int get lowStockCount => lowStockItems.length;

  Map<String, List<InventoryItem>> get itemsByCategory {
    final map = <String, List<InventoryItem>>{};
    for (final item in _inventoryItems) {
      map.putIfAbsent(item.category, () => []);
      map[item.category]!.add(item);
    }
    return map;
  }

  // Load data
  Future<void> loadInventory() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (SupabaseService.canUseSupabase) {
        await loadInventoryFromSupabase();
      } else {
        await _loadFromLocalStorage();
      }
    } catch (e) {
      _error = 'Failed to load inventory: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadInventoryFromSupabase() async {
    if (!SupabaseService.canUseSupabase) {
      debugPrint('⚠️ Cannot load inventory from Supabase - not available');
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Load inventory items from Supabase
      final supabaseItems = await SupabaseService.getInventory();
      if (supabaseItems.isNotEmpty) {
        _inventoryItems =
            supabaseItems.map((json) => InventoryItem.fromJson(json)).toList();
        debugPrint(
            '✅ Loaded ${_inventoryItems.length} inventory items from Supabase');
      } else {
        debugPrint('⚠️ No inventory items found in Supabase');
      }

      // Load transactions from Supabase
      final supabaseTransactions = await SupabaseService.getTransactions();
      if (supabaseTransactions.isNotEmpty) {
        _transactions = supabaseTransactions
            .map((json) => InventoryTransaction.fromJson(json))
            .toList();
        debugPrint(
            '✅ Loaded ${_transactions.length} transactions from Supabase');
      }

      // Save to local storage as backup
      await _saveToLocalStorage();
    } catch (e) {
      _error = 'Failed to load inventory from Supabase: $e';
      debugPrint('❌ Error loading inventory from Supabase: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();

    final itemsJson = prefs.getString('inventory_items');
    if (itemsJson != null) {
      final List<dynamic> decoded = json.decode(itemsJson);
      _inventoryItems =
          decoded.map((item) => InventoryItem.fromJson(item)).toList();
    }

    final transactionsJson = prefs.getString('inventory_transactions');
    if (transactionsJson != null) {
      final List<dynamic> decoded = json.decode(transactionsJson);
      _transactions =
          decoded.map((t) => InventoryTransaction.fromJson(t)).toList();
    }
  }

  Future<void> _saveToLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();

    final itemsJson =
        json.encode(_inventoryItems.map((item) => item.toJson()).toList());
    await prefs.setString('inventory_items', itemsJson);

    final transactionsJson =
        json.encode(_transactions.map((t) => t.toJson()).toList());
    await prefs.setString('inventory_transactions', transactionsJson);
  }

  // Add new inventory item
  Future<void> addInventoryItem(InventoryItem item) async {
    debugPrint('🔴🔴🔴 addInventoryItem START 🔴🔴🔴');
    debugPrint('   Drink Name: "${item.drinkName}"');
    debugPrint('   Drink ID: "${item.drinkId}"');
    debugPrint('   Quantity: ${item.quantity}');
    debugPrint('   Current inventory count: ${_inventoryItems.length}');

    if (item.drinkId.isEmpty) {
      debugPrint('❌ Cannot add inventory: drink_id is empty');
      return;
    }

    if (item.drinkName.isEmpty) {
      debugPrint('❌ Cannot add inventory: drink_name is empty');
      return;
    }

    // ✅ CRITICAL FIX: Ensure company_id is set
    final companyId = SupabaseService.currentCompanyId;
    debugPrint('   Current company_id from SupabaseService: $companyId');
    debugPrint('   canUseSupabase: ${SupabaseService.canUseSupabase}');

    // Create a complete InventoryItem with company_id
    final completeItem = InventoryItem(
      id: item.id,
      drinkId: item.drinkId,
      drinkName: item.drinkName,
      quantity: item.quantity,
      minStockLevel: item.minStockLevel,
      lastRestocked: item.lastRestocked,
      category: item.category,
      unit: item.unit,
      purchasePrice: item.purchasePrice,
      companyId: SupabaseService.currentCompanyId,
    );

    // Check for existing item
    final existingIndex =
        _inventoryItems.indexWhere((i) => i.drinkId == item.drinkId);

    if (existingIndex != -1) {
      _inventoryItems[existingIndex] = completeItem;
      debugPrint('✅ Updated existing inventory: ${item.drinkName}');
    } else {
      _inventoryItems.add(completeItem);
      debugPrint('✅ Added new inventory: ${item.drinkName}');
    }

    // ✅ Sync to DrinkProvider
    try {
      if (_drinkProvider != null) {
        final drink = _drinkProvider!.customDrinks.firstWhere(
          (d) => d.id == item.drinkId,
          orElse: () => Drink(
            id: '',
            name: '',
            price: 0,
            imageUrl: '',
          ),
        );
        if (drink.id.isNotEmpty && drink.currentStock != item.quantity) {
          final updatedDrink = drink.copyWith(
            currentStock: item.quantity,
          );
          await _drinkProvider!.updateDrink(item.drinkId, updatedDrink);
          debugPrint(
              '✅ DrinkProvider synced: ${item.drinkName} stock = ${item.quantity}');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Could not sync DrinkProvider: $e');
    }

    await _saveToLocalStorage();
    notifyListeners();

    // ✅ Sync to Supabase with complete data
    if (SupabaseService.canUseSupabase) {
      debugPrint('📤 Attempting to sync to Supabase...');
      try {
        final jsonData = completeItem.toJson();
        debugPrint('   JSON being sent: $jsonData');
        final success = await SupabaseService.upsertInventory(jsonData);
        debugPrint('   Sync result: $success');
        if (success) {
          debugPrint('✅ Inventory synced to Supabase: ${item.drinkName}');
        } else {
          debugPrint('❌ Failed to sync inventory to Supabase');
        }
      } catch (e) {
        debugPrint('❌ Exception syncing to Supabase: $e');
      }
    } else {
      debugPrint('⚠️ Cannot sync - Supabase not available');
    }
  }

  // Update item quantity
  Future<void> updateQuantity(String drinkId, int newQuantity) async {
    final index = _inventoryItems.indexWhere((item) => item.drinkId == drinkId);
    if (index != -1) {
      _inventoryItems[index].quantity = newQuantity;
      _inventoryItems[index].lastRestocked = DateTime.now();
      await _saveToLocalStorage();
      notifyListeners();
      // Sync to Supabase
      try {
        await SupabaseService.updateInventory(drinkId, {
          'quantity': newQuantity,
          'last_restocked': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('Supabase update error: $e');
      }
    }
  }

  // Add stock (restock)
  Future<void> addStock({
    required String drinkId,
    required String drinkName,
    required int quantity,
    String reason = 'restock',
    String? performedBy,
  }) async {
    debugPrint('🔴🔴🔴 addStock CALLED: $drinkName +$quantity 🔴🔴🔴');
    if (drinkId.isEmpty) {
      debugPrint('❌ Cannot add stock: drinkId is empty');
      return;
    }

    if (drinkName.isEmpty) {
      debugPrint('❌ Cannot add stock: drinkName is empty');
      return;
    }

    final index = _inventoryItems.indexWhere((item) => item.drinkId == drinkId);
    late final InventoryItem updatedItem;

    if (index != -1) {
      _inventoryItems[index].quantity += quantity;
      _inventoryItems[index].lastRestocked = DateTime.now();
      updatedItem = _inventoryItems[index];
    } else {
      // Create new inventory item WITH companyId
      updatedItem = InventoryItem(
        id: 'inv_${DateTime.now().millisecondsSinceEpoch}',
        drinkId: drinkId,
        drinkName: drinkName,
        quantity: quantity,
        lastRestocked: DateTime.now(),
        companyId: SupabaseService.currentCompanyId,
      );
      _inventoryItems.add(updatedItem);
    }

    // ✅ Sync to DrinkProvider
    try {
      if (_drinkProvider != null) {
        final drink = _drinkProvider!.customDrinks.firstWhere(
          (d) => d.id == drinkId,
          orElse: () => Drink(
            id: '',
            name: '',
            price: 0,
            imageUrl: '',
          ),
        );
        if (drink.id.isNotEmpty) {
          final updatedDrink = drink.copyWith(
            currentStock: (drink.currentStock + quantity).clamp(0, 999999),
          );
          await _drinkProvider!.updateDrink(drinkId, updatedDrink);
          debugPrint(
              '✅ DrinkProvider updated: $drinkName stock = ${updatedDrink.currentStock}');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Could not update DrinkProvider: $e');
    }

    // Record transaction WITH companyId
    final transaction = InventoryTransaction(
      id: 'txn_${DateTime.now().millisecondsSinceEpoch}',
      drinkId: drinkId,
      drinkName: drinkName,
      quantity: quantity,
      type: 'in',
      date: DateTime.now(),
      reason: reason,
      performedBy: performedBy,
      companyId: SupabaseService.currentCompanyId,
    );

    _transactions.add(transaction);

    await _saveToLocalStorage();
    notifyListeners();

    // Sync to Supabase
    if (SupabaseService.canUseSupabase) {
      debugPrint('📤 Syncing to Supabase...');
      try {
        final upsertResult =
            await SupabaseService.upsertInventory(updatedItem.toJson());
        final transactionResult =
            await SupabaseService.saveTransaction(transaction.toJson());

        if (upsertResult && transactionResult) {
          debugPrint('✅ Stock added and synced: $drinkName +$quantity');
        } else {
          debugPrint('❌ Failed to sync to Supabase');
        }
      } catch (e) {
        debugPrint('❌ Supabase sync error: $e');
      }
    }
  }

  // Remove stock (sale, waste, etc.)
  Future<bool> removeStock({
    required String drinkId,
    required String drinkName,
    required int quantity,
    String reason = 'sale',
    String? orderId,
    String? performedBy,
  }) async {
    debugPrint('🔴🔴🔴 removeStock CALLED: $drinkName -$quantity 🔴🔴🔴');
    debugPrint(
        '   _drinkProvider is ${_drinkProvider == null ? "NULL ❌" : "SET ✅"}');
        debugPrint('   Inventory items count: ${_inventoryItems.length}');
    // ✅ If inventory is empty, try reloading
  if (_inventoryItems.isEmpty) {
    debugPrint('⚠️ Inventory is EMPTY! Attempting to reload...');
    await loadInventoryFromSupabase();
    debugPrint('✅ Inventory reloaded: ${_inventoryItems.length} items');
  }
    if (drinkId.isEmpty) {
      debugPrint('❌ Cannot remove stock: drinkId is empty');
      _error = 'Invalid drink ID';
      notifyListeners();
      return false;
    }

    final index = _inventoryItems.indexWhere((item) => item.drinkId == drinkId);

    if (index == -1) {
      _error = 'Item not found in inventory';
      // ✅ Show all available items for debugging
    debugPrint('❌ Item not found in inventory: $drinkName');
    debugPrint('   Available items:');
    for (final item in _inventoryItems) {
      debugPrint('     - ${item.drinkName} (${item.drinkId})');
    }
    _error = 'Item not found in inventory';
      notifyListeners();
      return false;
    }

    if (_inventoryItems[index].quantity < quantity) {
      _error = 'Insufficient stock for $drinkName';
      notifyListeners();
      return false;
    }

    _inventoryItems[index].quantity -= quantity;

    // ✅ Sync to DrinkProvider
    try {
      if (_drinkProvider != null) {
        final drink = _drinkProvider!.customDrinks.firstWhere(
          (d) => d.id == drinkId,
          orElse: () => Drink(
            id: '',
            name: '',
            price: 0,
            imageUrl: '',
          ),
        );
        if (drink.id.isNotEmpty) {
          final updatedDrink = drink.copyWith(
            currentStock: (drink.currentStock - quantity).clamp(0, 999999),
          );
          await _drinkProvider!.updateDrink(drinkId, updatedDrink);
          debugPrint(
              '✅ DrinkProvider updated: $drinkName stock = ${updatedDrink.currentStock}');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Could not update DrinkProvider: $e');
    }

    // ✅ Create transaction
    final transaction = InventoryTransaction(
      id: 'txn_${DateTime.now().millisecondsSinceEpoch}',
      drinkId: drinkId,
      drinkName: drinkName,
      quantity: quantity,
      type: 'out',
      date: DateTime.now(),
      reason: reason,
      orderId: orderId,
      performedBy: performedBy,
      companyId: SupabaseService.currentCompanyId,
    );

    _transactions.add(transaction);

    await _saveToLocalStorage();
    notifyListeners();

    if (SupabaseService.canUseSupabase) {
      try {
        await SupabaseService.upsertInventory(_inventoryItems[index].toJson());
        await SupabaseService.saveTransaction(transaction.toJson());
        debugPrint('✅ Stock removed and synced: $drinkName -$quantity');
      } catch (e) {
        debugPrint('❌ Supabase sync error: $e');
      }
    }

    return true;
  }

  // Update inventory item details (category, unit, purchase price, etc.)
  Future<void> updateInventoryItemDetails({
    required String drinkId,
    String? drinkName,
    int? minStockLevel,
    String? category,
    String? unit,
    double? purchasePrice,
  }) async {
    final index = _inventoryItems.indexWhere((item) => item.drinkId == drinkId);
    if (index != -1) {
      if (drinkName != null) _inventoryItems[index].drinkName = drinkName;
      if (minStockLevel != null)
        _inventoryItems[index].minStockLevel = minStockLevel;
      if (category != null) _inventoryItems[index].category = category;
      if (unit != null) _inventoryItems[index].unit = unit;
      if (purchasePrice != null)
        _inventoryItems[index].purchasePrice = purchasePrice;

      await _saveToLocalStorage();
      notifyListeners();
      // Sync to Supabase
      try {
        await SupabaseService.updateInventory(drinkId, {
          'drink_name': _inventoryItems[index].drinkName,
          'min_stock_level': _inventoryItems[index].minStockLevel,
          'category': _inventoryItems[index].category,
          'unit': _inventoryItems[index].unit,
          'purchase_price': _inventoryItems[index].purchasePrice,
        });
      } catch (e) {
        debugPrint('Supabase update error: $e');
      }
    }
  }

  Future<void> clearAllInventory() async {
    _inventoryItems.clear();
    _transactions.clear();
    await _saveToLocalStorage();
    notifyListeners();
    debugPrint('🧹 All inventory cleared');
  }

  // Make _saveToLocalStorage public or add a public wrapper
  Future<void> saveInventory() async {
    await _saveToLocalStorage();
  }

  // Update min stock level
  Future<void> updateMinStockLevel(String drinkId, int minLevel) async {
    final index = _inventoryItems.indexWhere((item) => item.drinkId == drinkId);
    if (index != -1) {
      _inventoryItems[index].minStockLevel = minLevel;
      await _saveToLocalStorage();
      notifyListeners();
      // Sync to Supabase
      try {
        await SupabaseService.updateInventory(drinkId, {
          'min_stock_level': minLevel,
        });
      } catch (e) {
        debugPrint('Supabase update error: $e');
      }
    }
  }

  // Delete inventory item
  Future<void> deleteInventoryItem(String drinkId) async {
    _inventoryItems.removeWhere((item) => item.drinkId == drinkId);
    await _saveToLocalStorage();
    notifyListeners();
    // Sync to Supabase
    try {
      await SupabaseService.deleteDrink(drinkId); // Delete from drinks table
    } catch (e) {
      debugPrint('Supabase delete error: $e');
    }
  }

  // Generate report
  InventoryReport generateReport({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final filteredTransactions = _transactions
        .where((t) =>
            t.date.isAfter(startDate) &&
            t.date.isBefore(endDate.add(const Duration(days: 1))))
        .toList();

    final totalIn = filteredTransactions
        .where((t) => t.isIncoming)
        .fold(0, (sum, t) => sum + t.quantity);

    final totalOut = filteredTransactions
        .where((t) => t.isOutgoing)
        .fold(0, (sum, t) => sum + t.quantity);

    final salesByCategory = <String, int>{};
    final wasteByItem = <String, int>{};

    for (final t in filteredTransactions) {
      if (t.reason == 'sale') {
        final item = _inventoryItems.firstWhere(
          (i) => i.drinkId == t.drinkId,
          orElse: () => InventoryItem(
            id: '',
            drinkId: '',
            drinkName: '',
            quantity: 0,
            lastRestocked: DateTime.now(),
            category: 'General',
          ),
        );
        salesByCategory[item.category] =
            (salesByCategory[item.category] ?? 0) + t.quantity;
      }
      if (t.reason == 'waste') {
        wasteByItem[t.drinkName] = (wasteByItem[t.drinkName] ?? 0) + t.quantity;
      }
    }

    return InventoryReport(
      startDate: startDate,
      endDate: endDate,
      currentStock: _inventoryItems,
      transactions: filteredTransactions,
      totalItemsIn: totalIn,
      totalItemsOut: totalOut,
      lowStockCount: lowStockCount,
      salesByCategory: salesByCategory,
      wasteByItem: wasteByItem,
    );
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
