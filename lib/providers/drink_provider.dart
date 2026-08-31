// providers/drink_provider.dart
import 'package:flutter/foundation.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/services/storage_service.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';
import 'package:drinks_calculator_fixed/services/secure_storage_service.dart';
import 'package:drinks_calculator_fixed/config/api_config.dart';

class DrinkProvider with ChangeNotifier {
  List<Drink> _customDrinks = [];
  List<Drink> _allDrinks = [];
  bool _isSyncing = false;
  bool _isOffline = false;
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isLoadingFromSupabase = false;

  // Store current user info for storage operations
  String? _currentUserId;
  int? _currentCompanyId;
  String? _currentUserRole;

  List<Drink> get customDrinks => _customDrinks;
  List<Drink> get allDrinks => _allDrinks;
  bool get isSyncing => _isSyncing;
  bool get isOffline => _isOffline;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;

  // ✅ Set user context from outside
  void setUserContext(String? userId, int? companyId, String? role) {
    _currentUserId = userId;
    _currentCompanyId = companyId;
    _currentUserRole = role;
    debugPrint(
        '📦 DrinkProvider user context set: company=$companyId, user=$userId, role=$role');
  }

  DrinkProvider() {
    Future.microtask(() async {
      await initialize();
    });
  }

  Future<void> initialize() async {
    if (_isInitialized || _isLoading) return;
    _isLoading = true;
    try {
      await _loadLocalData();
      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing DrinkProvider: $e');
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  void _safeNotifyListeners() {
    Future.microtask(() {
      if (!_isLoading) {
        notifyListeners();
      }
    });
  }

  Future<void> _loadLocalData() async {
    if (_currentUserId == null) return;

    Map<String, dynamic>? data;

    if (_currentUserRole == 'Customer') {
      data = await SecureStorageService.loadDataForUser(
        userId: _currentUserId!,
        key: 'drinks',
      );
    } else if (_currentCompanyId != null) {
      data = await SecureStorageService.loadDataForCompany(
        companyId: _currentCompanyId!,
        key: 'drinks',
      );
    }

    if (data != null && data['drinks'] != null) {
      final storedDrinks = data['drinks'] as List;
      _customDrinks =
          storedDrinks.map((drinkMap) => Drink.fromJson(drinkMap)).toList();
      _allDrinks = [..._customDrinks];
      debugPrint('✅ Loaded ${_customDrinks.length} drinks from secure storage');
    } else {
      _customDrinks = [];
      _allDrinks = [];
    }
  }

  Future<void> loadDrinksFromSupabase() async {
    if (_isLoadingFromSupabase) {
      debugPrint('⏭️ Skipping duplicate Supabase load');
      return;
    }
    debugPrint('🔍 loadDrinksFromSupabase called');
    debugPrint('   canUseSupabase: ${SupabaseService.canUseSupabase}');

    if (!SupabaseService.canUseSupabase) {
      debugPrint('⚠️ Cannot load from Supabase - not available');
      return;
    }

    try {
      _isLoading = true;
      _safeNotifyListeners();

      // ✅ Clear existing drinks before loading new ones
      _customDrinks.clear();
      _allDrinks.clear();

      final supabaseDrinks = await SupabaseService.getDrinks();
      debugPrint('📊 Got ${supabaseDrinks.length} drinks from Supabase');

      if (supabaseDrinks.isNotEmpty) {
        final drinks =
            supabaseDrinks.map((json) => Drink.fromJson(json)).toList();
        _customDrinks = drinks;
        _allDrinks = [...drinks];
        await _saveToLocalStorage();
        debugPrint('✅ Loaded ${drinks.length} drinks from Supabase');
      } else {
        debugPrint('⚠️ No drinks found in Supabase');
        await _saveToLocalStorage(); // Save empty list
      }
    } catch (e) {
      debugPrint('❌ Error loading from Supabase: $e');
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> _saveToLocalStorage() async {
    if (_currentUserId == null) return;

    final drinksJson = _customDrinks.map((d) => d.toJson()).toList();

    if (_currentUserRole == 'Customer') {
      await SecureStorageService.saveDataForUser(
        userId: _currentUserId!,
        key: 'drinks',
        data: {'drinks': drinksJson},
      );
    } else if (_currentCompanyId != null) {
      await SecureStorageService.saveDataForCompany(
        companyId: _currentCompanyId!,
        key: 'drinks',
        data: {'drinks': drinksJson},
      );
    }
  }

  Future<void> clearAllDrinks() async {
    debugPrint('🔍 clearAllDrinks called - Stack trace:');
    debugPrint(StackTrace.current.toString());

    if (_isLoading) {
      debugPrint('⏭️ Skipping clearAllDrinks - currently loading');
      return;
    }
    _customDrinks.clear();
    _allDrinks.clear();

    if (_currentUserId != null) {
      if (_currentUserRole == 'Customer') {
        await SecureStorageService.clearUserData(_currentUserId!);
      } else if (_currentCompanyId != null) {
        await SecureStorageService.clearCompanyData(_currentCompanyId!);
      }
    }
    await _saveToLocalStorage();
    _safeNotifyListeners();
    debugPrint('🧹 All drinks cleared from secure storage');
  }

  Future<void> addDrink(Drink drink) async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      _customDrinks.add(drink);
      _allDrinks.add(drink);
      await _saveToLocalStorage();

      final canSync = SupabaseService.canUseSupabase;
      if (canSync) {
        final success = await SupabaseService.saveDrink(drink.toJson());
        if (success) {
          debugPrint('✅ Drink synced to Supabase: ${drink.name}');
        } else {
          debugPrint('❌ Failed to sync drink to Supabase');
        }
      }
    } catch (e) {
      debugPrint('Error adding drink: $e');
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> updateDrink(String id, Drink updatedDrink) async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      final index = _customDrinks.indexWhere((drink) => drink.id == id);
      if (index != -1) {
        _customDrinks[index] = updatedDrink;
        final allIndex = _allDrinks.indexWhere((drink) => drink.id == id);
        if (allIndex != -1) {
          _allDrinks[allIndex] = updatedDrink;
        }
        await _saveToLocalStorage();

        final canSync = SupabaseService.canUseSupabase;
        if (canSync) {
          final success =
              await SupabaseService.updateDrink(id, updatedDrink.toJson());
          if (success) {
            debugPrint('✅ Drink updated in Supabase: ${updatedDrink.name}');
          } else {
            debugPrint('❌ Failed to update drink in Supabase');
          }
        }
      }
    } catch (e) {
      debugPrint('Error updating drink: $e');
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> deleteDrink(String id) async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      _customDrinks.removeWhere((drink) => drink.id == id);
      _allDrinks.removeWhere((drink) => drink.id == id);
      await _saveToLocalStorage();

      final canSync = SupabaseService.canUseSupabase;
      if (canSync) {
        final success = await SupabaseService.deleteDrink(id);
        if (success) {
          debugPrint('✅ Drink deleted from Supabase');
        } else {
          debugPrint('❌ Failed to delete drink from Supabase');
        }
      }
    } catch (e) {
      debugPrint('Error deleting drink: $e');
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> loadDrinks() async {
    await initialize();
  }

  Future<void> refreshDrinks() async {
    await _loadLocalData();
    _safeNotifyListeners();
  }
// Add these methods after deleteDrink() or before the end of the class

  Future<void> createBackup() async {
    await StorageService.createBackup();
    debugPrint('✅ Backup created');
  }

  Future<void> restoreBackup([String? backupKey]) async {
    try {
      if (backupKey == null) {
        final backupKeys = StorageService.getBackupKeys();
        if (backupKeys.isEmpty) {
          debugPrint('No backups found');
          return;
        }
        backupKey = backupKeys.first;
      }

      final success = await StorageService.restoreFromBackup(backupKey);
      if (success) {
        await _loadLocalData();
        _safeNotifyListeners();
        debugPrint('✅ Backup restored successfully');
      } else {
        debugPrint('❌ Failed to restore backup');
      }
    } catch (e) {
      debugPrint('Error restoring backup: $e');
    }
  }

  Future<void> forceSync() async {
    // Sync local data to Supabase
    if (SupabaseService.canUseSupabase) {
      for (final drink in _customDrinks) {
        await SupabaseService.saveDrink(drink.toJson());
      }
      debugPrint('✅ Force sync completed');
    } else {
      debugPrint('⚠️ Cannot sync - Supabase not available');
    }
  }

  // Get statistics about storage
  Map<String, dynamic> getStorageStats() {
    return StorageService.getStorageStats();
  }

  // Get list of available backups
  List<String> getBackupList() {
    return StorageService.getBackupKeys();
  }
}
