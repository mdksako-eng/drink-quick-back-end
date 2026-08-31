// services/storage_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static late SharedPreferences _prefs;
  static const String _drinksKey = 'custom_drinks';
  static const String _ordersKey = 'order_history';
  static const String _settingsKey = 'app_settings';
  static const String _syncQueueKey = 'sync_queue';

  // ============================================================
  // 🔐 INITIALIZATION
  // ============================================================

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ============================================================
  // 🍺 DRINKS STORAGE
  // ============================================================

  static Future<bool> saveCustomDrinks(List<Map<String, dynamic>> drinks) async {
    try {
      final jsonString = jsonEncode(drinks);
      return await _prefs.setString(_drinksKey, jsonString);
    } catch (e) {
      debugPrint('❌ Error saving drinks: $e');
      return false;
    }
  }

  static List<Map<String, dynamic>> loadCustomDrinks() {
    try {
      final jsonString = _prefs.getString(_drinksKey);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((item) => item as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('❌ Error loading drinks: $e');
      return [];
    }
  }

  static Future<bool> addCustomDrink(Map<String, dynamic> drink) async {
    final drinks = loadCustomDrinks();
    drinks.add(drink);
    return await saveCustomDrinks(drinks);
  }

  // ============================================================
  // 🔄 SYNC QUEUE METHODS
  // ============================================================

  static Future<bool> addToSyncQueue(String operation, Map<String, dynamic> data) async {
    try {
      final queue = loadSyncQueue();
      queue.add({
        'operation': operation,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
        'synced': false,
      });

      final jsonString = jsonEncode(queue);
      return await _prefs.setString(_syncQueueKey, jsonString);
    } catch (e) {
      debugPrint('❌ Error adding to sync queue: $e');
      return false;
    }
  }

  static List<Map<String, dynamic>> loadSyncQueue() {
    try {
      final jsonString = _prefs.getString(_syncQueueKey);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((item) => item as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('❌ Error loading sync queue: $e');
      return [];
    }
  }

  static Future<bool> clearSyncedItems() async {
    try {
      final queue = loadSyncQueue();
      final pendingItems = queue.where((item) => !item['synced']).toList();

      final jsonString = jsonEncode(pendingItems);
      return await _prefs.setString(_syncQueueKey, jsonString);
    } catch (e) {
      debugPrint('❌ Error clearing synced items: $e');
      return false;
    }
  }

  // ============================================================
  // 💾 BACKUP METHODS
  // ============================================================

  static Future<Map<String, dynamic>> createBackup() async {
    final backup = {
      'timestamp': DateTime.now().toIso8601String(),
      'drinks': loadCustomDrinks(),
      'orders': loadOrders(),
      'settings': loadSettings(),
      'version': '1.1.0',
    };

    final backupString = jsonEncode(backup);
    await _prefs.setString('backup_${DateTime.now().millisecondsSinceEpoch}', backupString);

    return backup;
  }

  static Future<bool> restoreFromBackup(String backupKey) async {
    try {
      final backupString = _prefs.getString(backupKey);
      if (backupString == null) return false;

      final backup = jsonDecode(backupString) as Map<String, dynamic>;

      await saveCustomDrinks(List<Map<String, dynamic>>.from(backup['drinks']));
      await saveOrders(List<Map<String, dynamic>>.from(backup['orders']));
      await saveSettings(Map<String, dynamic>.from(backup['settings']));

      return true;
    } catch (e) {
      debugPrint('❌ Error restoring backup: $e');
      return false;
    }
  }

  // ============================================================
  // 📋 ORDERS STORAGE
  // ============================================================

  static Future<bool> saveOrders(List<Map<String, dynamic>> orders) async {
    try {
      final jsonString = jsonEncode(orders);
      return await _prefs.setString(_ordersKey, jsonString);
    } catch (e) {
      debugPrint('❌ Error saving orders: $e');
      return false;
    }
  }

  static List<Map<String, dynamic>> loadOrders() {
    try {
      final jsonString = _prefs.getString(_ordersKey);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((item) => item as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('❌ Error loading orders: $e');
      return [];
    }
  }

  static Future<bool> addOrder(Map<String, dynamic> order) async {
    final orders = loadOrders();
    orders.add(order);
    return await saveOrders(orders);
  }

  // ============================================================
  // ⚙️ SETTINGS STORAGE - COMPLETE WITH THEME SUPPORT
  // ============================================================

  static Future<bool> saveSettings(Map<String, dynamic> settings) async {
    try {
      // ✅ Ensure all theme settings are properly saved
      final cleanSettings = {
        // Theme settings
        'theme_mode': settings['theme_mode'] ?? 0,
        'primary_color': settings['primary_color'] ?? '#667EEA',
        'compact_mode': settings['compact_mode'] ?? false,
        
        // Currency settings
        'currency_symbol': settings['currency_symbol'] ?? 'Frs',
        'currency_position': settings['currency_position'] ?? 'right',
        'decimal_separator': settings['decimal_separator'] ?? '.',
        'thousands_separator': settings['thousands_separator'] ?? ',',
        'decimal_places': settings['decimal_places'] ?? 0,
        
        // Company settings
        'company_name': settings['company_name'] ?? 'Drink Quick Cal',
        'company_email': settings['company_email'] ?? '',
        'company_phone': settings['company_phone'] ?? '',
        'company_address': settings['company_address'] ?? '',
        
        // Payment settings
        'business_payments_enabled': settings['business_payments_enabled'] ?? false,
        'mtn_enabled': settings['mtn_enabled'] ?? true,
        'mtn_api_key': settings['mtn_api_key'] ?? '',
        'mtn_secret_key': settings['mtn_secret_key'] ?? '',
        'mtn_merchant_id': settings['mtn_merchant_id'] ?? '',
        'mtn_merchant_phone': settings['mtn_merchant_phone'] ?? '',
        'mtn_sandbox_mode': settings['mtn_sandbox_mode'] ?? true,
        'orange_enabled': settings['orange_enabled'] ?? true,
        'orange_api_key': settings['orange_api_key'] ?? '',
        'orange_secret_key': settings['orange_secret_key'] ?? '',
        'orange_merchant_id': settings['orange_merchant_id'] ?? '',
        'orange_merchant_phone': settings['orange_merchant_phone'] ?? '',
        'orange_sandbox_mode': settings['orange_sandbox_mode'] ?? true,
        
        // Other settings
        'auto_sync': settings['auto_sync'] ?? false,
        'show_notifications': settings['show_notifications'] ?? true,
        
        // Legacy compatibility
        'theme': settings['theme_mode'] == 1 ? 'dark' : 'light',
        'currency': settings['currency_symbol'] ?? 'Frs',
        'notifications': settings['show_notifications'] ?? true,
        'autoSync': settings['auto_sync'] ?? false,
      };

      final jsonString = jsonEncode(cleanSettings);
      final result = await _prefs.setString(_settingsKey, jsonString);
      
      debugPrint('✅ Settings saved successfully');
      return result;
    } catch (e) {
      debugPrint('❌ Error saving settings: $e');
      return false;
    }
  }

  static Map<String, dynamic> loadSettings() {
    try {
      final jsonString = _prefs.getString(_settingsKey);
      if (jsonString == null || jsonString.isEmpty) {
        // ✅ Return default settings with theme support
        return {
          // Theme settings
          'theme_mode': 0,  // 0 = Light, 1 = Dark
          'primary_color': '#667EEA',
          'compact_mode': false,
          
          // Currency settings
          'currency_symbol': 'Frs',
          'currency_position': 'right',
          'decimal_separator': '.',
          'thousands_separator': ',',
          'decimal_places': 0,
          
          // Company settings
          'company_name': 'Drink Quick Cal',
          'company_email': '',
          'company_phone': '',
          'company_address': '',
          
          // Payment settings
          'business_payments_enabled': false,
          'mtn_enabled': true,
          'mtn_api_key': '',
          'mtn_secret_key': '',
          'mtn_merchant_id': '',
          'mtn_merchant_phone': '',
          'mtn_sandbox_mode': true,
          'orange_enabled': true,
          'orange_api_key': '',
          'orange_secret_key': '',
          'orange_merchant_id': '',
          'orange_merchant_phone': '',
          'orange_sandbox_mode': true,
          
          // Other settings
          'auto_sync': false,
          'show_notifications': true,
          
          // Legacy compatibility
          'theme': 'light',
          'currency': 'Frs',
          'notifications': true,
          'autoSync': false,
        };
      }
      
      final Map<String, dynamic> settings = jsonDecode(jsonString);
      
      // ✅ Ensure theme settings exist for backward compatibility
      if (!settings.containsKey('theme_mode')) {
        settings['theme_mode'] = settings['theme'] == 'dark' ? 1 : 0;
      }
      if (!settings.containsKey('primary_color')) {
        settings['primary_color'] = '#667EEA';
      }
      if (!settings.containsKey('compact_mode')) {
        settings['compact_mode'] = false;
      }
      
      return settings;
    } catch (e) {
      debugPrint('❌ Error loading settings: $e');
      return {
        'theme_mode': 0,
        'primary_color': '#667EEA',
        'compact_mode': false,
        'currency_symbol': 'Frs',
        'currency_position': 'right',
        'decimal_separator': '.',
        'thousands_separator': ',',
        'decimal_places': 0,
        'company_name': 'Drink Quick Cal',
        'company_email': '',
        'company_phone': '',
        'company_address': '',
        'business_payments_enabled': false,
        'mtn_enabled': true,
        'mtn_api_key': '',
        'mtn_secret_key': '',
        'mtn_merchant_id': '',
        'mtn_merchant_phone': '',
        'mtn_sandbox_mode': true,
        'orange_enabled': true,
        'orange_api_key': '',
        'orange_secret_key': '',
        'orange_merchant_id': '',
        'orange_merchant_phone': '',
        'orange_sandbox_mode': true,
        'auto_sync': false,
        'show_notifications': true,
        'theme': 'light',
        'currency': 'Frs',
        'notifications': true,
        'autoSync': false,
      };
    }
  }

  // ============================================================
  // 💰 CURRENCY SETTINGS
  // ============================================================
  
  static Future<bool> saveCurrencySettings({
    required String symbol,
    required String position,
    required String decimalSeparator,
    required String thousandsSeparator,
    required int decimalPlaces,
  }) async {
    try {
      final settings = loadSettings();
      settings['currency_symbol'] = symbol;
      settings['currency_position'] = position;
      settings['decimal_separator'] = decimalSeparator;
      settings['thousands_separator'] = thousandsSeparator;
      settings['decimal_places'] = decimalPlaces;
      return await saveSettings(settings);
    } catch (e) {
      debugPrint('❌ Error saving currency settings: $e');
      return false;
    }
  }
  
  static Map<String, dynamic> loadCurrencySettings() {
    final settings = loadSettings();
    return {
      'symbol': settings['currency_symbol'] ?? 'Frs',
      'position': settings['currency_position'] ?? 'right',
      'decimalSeparator': settings['decimal_separator'] ?? '.',
      'thousandsSeparator': settings['thousands_separator'] ?? ',',
      'decimalPlaces': settings['decimal_places'] ?? 0,
    };
  }

  // ============================================================
  // 🎨 THEME SETTINGS (NEW)
  // ============================================================
  
  static Future<bool> saveThemeSettings({
    required int themeMode,  // 0 = Light, 1 = Dark
    required String primaryColor,
    required bool compactMode,
  }) async {
    try {
      final settings = loadSettings();
      settings['theme_mode'] = themeMode;
      settings['primary_color'] = primaryColor;
      settings['compact_mode'] = compactMode;
      settings['theme'] = themeMode == 1 ? 'dark' : 'light';
      return await saveSettings(settings);
    } catch (e) {
      debugPrint('❌ Error saving theme settings: $e');
      return false;
    }
  }
  
  static Map<String, dynamic> loadThemeSettings() {
    final settings = loadSettings();
    return {
      'themeMode': settings['theme_mode'] ?? 0,
      'primaryColor': settings['primary_color'] ?? '#667EEA',
      'compactMode': settings['compact_mode'] ?? false,
    };
  }

  // ============================================================
  // 🧹 UTILITY METHODS
  // ============================================================

  static Future<void> clearAllData() async {
    await _prefs.remove(_drinksKey);
    await _prefs.remove(_ordersKey);
    await _prefs.remove(_settingsKey);
    await _prefs.remove(_syncQueueKey);

    final keys = _prefs.getKeys().where((key) => key.startsWith('backup_')).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
    
    debugPrint('🧹 All data cleared');
  }

  static Map<String, dynamic> getStorageStats() {
    final drinks = loadCustomDrinks();
    final orders = loadOrders();
    final queue = loadSyncQueue();

    final backupKeys = _prefs.getKeys().where((key) => key.startsWith('backup_')).toList();

    return {
      'drinksCount': drinks.length,
      'ordersCount': orders.length,
      'pendingSync': queue.length,
      'lastBackup': backupKeys.isNotEmpty
          ? backupKeys.last.replaceFirst('backup_', '')
          : 'Never',
      'backupCount': backupKeys.length,
    };
  }

  static List<String> getBackupKeys() {
    final keys = _prefs.getKeys().where((key) => key.startsWith('backup_')).toList();
    keys.sort((a, b) => b.compareTo(a));
    return keys;
  }
}