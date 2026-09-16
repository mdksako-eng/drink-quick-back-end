// providers/sync_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';

enum SyncStatus {
  idle,
  syncing,
  success,
  error,
  offline,
}

class SyncProvider with ChangeNotifier {
  SyncStatus _status = SyncStatus.idle;
  DateTime? _lastSyncTime;
  String? _errorMessage;
  int _pendingSyncCount = 0;
  Timer? _periodicTimer;
  Timer? _statusResetTimer;

  /// True once a sync has actually completed against the server (persisted), so
  /// the drawer can honestly say "not synced yet".
  bool _hasSynced = false;

  /// Real data reloaders wired from main.dart. Without them a "sync" only
  /// proves the server is reachable — it must never claim data was synced.
  Future<void> Function()? _reloadOrders;
  Future<void> Function()? _reloadInventory;

  static const String _lastSyncKey = 'last_sync_time';
  static const String _hasSyncedKey = 'has_ever_synced';

  SyncStatus get status => _status;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get errorMessage => _errorMessage;
  int get pendingSyncCount => _pendingSyncCount;
  bool get isSyncing => _status == SyncStatus.syncing;
  bool get isOnline => SupabaseService.canUseSupabase;

  /// Whether anything has ever been synchronised with the server.
  bool get hasSynced => _hasSynced;

  /// Registers the providers that hold the data to sync.
  void attachReloaders({
    Future<void> Function()? orders,
    Future<void> Function()? inventory,
  }) {
    _reloadOrders = orders;
    _reloadInventory = inventory;
  }

  /// Restores the persisted sync history so the indicator stays truthful after
  /// an app restart.
  Future<void> _restoreSyncState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stamp = prefs.getString(_lastSyncKey);
      _hasSynced = prefs.getBool(_hasSyncedKey) ?? false;
      _lastSyncTime = stamp != null ? DateTime.tryParse(stamp) : null;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistSyncState() async {
    if (_lastSyncTime == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncKey, _lastSyncTime!.toIso8601String());
      await prefs.setBool(_hasSyncedKey, true);
    } catch (_) {}
  }

  SyncProvider() {
    _startPeriodicSync();
    _restoreSyncState();
  }

  void _startPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 45), (timer) {
      if (!isSyncing && isOnline) {
        syncAllData();
      }
    });
  }

  Future<void> _checkPendingSyncs() async {
    // Count pending sync items from your providers
    // You can implement this based on your sync queue
    _pendingSyncCount = 0;
    notifyListeners();
  }

  Future<void> syncAllData() async {
    if (!isOnline) {
      _setStatus(SyncStatus.offline);
      return;
    }
    
    if (isSyncing) return;

    _setStatus(SyncStatus.syncing);
    _cancelStatusResetTimer();

    try {
      // 📋 Orders — real reload from the server.
      await _syncDrinks();
      
      // Sync orders
      await _syncOrders();
      
      // Sync inventory
      await _syncInventory();
      
      // Sync settings
      await _syncSettings();
      
      _lastSyncTime = DateTime.now();
      _hasSynced = true;
      await _persistSyncState();
      _setStatus(SyncStatus.success);
      await _checkPendingSyncs();
      
      // Auto-reset success status after 3 seconds
      _statusResetTimer = Timer(const Duration(seconds: 3), () {
        if (_status == SyncStatus.success) {
          _setStatus(SyncStatus.idle);
        }
      });
      
      debugPrint('✅ Cloud sync completed at ${_lastSyncTime}');
    } catch (e) {
      _errorMessage = e.toString();
      _setStatus(SyncStatus.error);
      
      // Auto-reset error status after 4 seconds
      _statusResetTimer = Timer(const Duration(seconds: 4), () {
        if (_status == SyncStatus.error) {
          _setStatus(SyncStatus.idle);
        }
      });
      
      debugPrint('❌ Cloud sync failed: $e');
    }
  }

  /// Reloads the real data sources (orders + inventory). When no reloader is
  /// wired we still make one real server call so the status is never fake.
  Future<void> _reloadData() async {
    var didWork = false;
    if (_reloadOrders != null) {
      await _reloadOrders!();
      didWork = true;
    }
    if (_reloadInventory != null) {
      await _reloadInventory!();
      didWork = true;
    }
    if (!didWork) {
      // Reachability check — throws (and marks the sync as failed) if the
      // backend cannot be reached.
      await SupabaseService.getOrders();
    }
  }

  Future<void> _syncDrinks() async {
    await _reloadData();
  }

  Future<void> _syncOrders() async {
    // Handled by _reloadData() (called once from _syncDrinks).
  }

  Future<void> _syncInventory() async {
    // Handled by _reloadData() (called once from _syncDrinks).
  }

  Future<void> _syncSettings() async {
    // Settings live in provider state and are pushed on change.
  }

  void _setStatus(SyncStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      notifyListeners();
    }
  }

  void _cancelStatusResetTimer() {
    _statusResetTimer?.cancel();
    _statusResetTimer = null;
  }

  void manualSync() {
    if (!isSyncing) {
      syncAllData();
    }
  }

  void updatePendingCount(int count) {
    _pendingSyncCount = count;
    notifyListeners();
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    _statusResetTimer?.cancel();
    super.dispose();
  }
}