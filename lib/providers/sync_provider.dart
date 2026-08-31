// providers/sync_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
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

  SyncStatus get status => _status;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get errorMessage => _errorMessage;
  int get pendingSyncCount => _pendingSyncCount;
  bool get isSyncing => _status == SyncStatus.syncing;
  bool get isOnline => SupabaseService.canUseSupabase;

  SyncProvider() {
    _startPeriodicSync();
    _checkPendingSyncs();
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
      // Sync drinks
      await _syncDrinks();
      
      // Sync orders
      await _syncOrders();
      
      // Sync inventory
      await _syncInventory();
      
      // Sync settings
      await _syncSettings();
      
      _lastSyncTime = DateTime.now();
      _setStatus(SyncStatus.success);
      
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

  Future<void> _syncDrinks() async {
    // This will be called from DrinkProvider
    // For now, just a placeholder
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> _syncOrders() async {
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _syncInventory() async {
    await Future.delayed(const Duration(milliseconds: 400));
  }

  Future<void> _syncSettings() async {
    await Future.delayed(const Duration(milliseconds: 200));
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