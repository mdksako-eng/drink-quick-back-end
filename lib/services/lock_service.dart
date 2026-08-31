// services/lock_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LockService {
  static final LockService _instance = LockService._internal();
  factory LockService() => _instance;
  LockService._internal();

  static const String _lockStateKey = 'lock_state';
  static const String _lastActivityKey = 'last_activity_time';
  static const Duration _inactivityTimeout = Duration(minutes: 2);

  Timer? _inactivityTimer;
  bool _isLocked = false;
  bool _isInitialized = false;
  VoidCallback? _onLock;
  VoidCallback? _onUnlock;
  bool _isDisposed = false;

  // ========== GETTERS ==========
  bool get isLocked => _isLocked;
  bool get isInitialized => _isInitialized;
  bool get isDisposed => _isDisposed;

  // ========== INITIALIZATION ==========
  Future<void> initialize({
    required VoidCallback onLock,
    required VoidCallback onUnlock,
  }) async {
    if (_isInitialized || _isDisposed) return;

    _onLock = onLock;
    _onUnlock = onUnlock;
    _isInitialized = true;

    // ✅ Restore lock state from storage
    await _restoreLockState();

    // ✅ Resume timer if not locked
    if (!_isLocked) {
      _resetTimer();
    }

    debugPrint('🔒 LockService initialized. Locked: $_isLocked');
  }

  // ========== PERSISTENCE ==========
  Future<void> _saveLockState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_lockStateKey, _isLocked);
    } catch (e) {
      debugPrint('❌ Failed to save lock state: $e');
    }
  }

  Future<void> _restoreLockState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isLocked = prefs.getBool(_lockStateKey) ?? false;

      // ✅ Check if lock should still be active
      if (_isLocked) {
        final lastActivity = prefs.getInt(_lastActivityKey);
        if (lastActivity != null) {
          final elapsed = DateTime.now().millisecondsSinceEpoch - lastActivity;
          if (elapsed > _inactivityTimeout.inMilliseconds) {
            // ✅ Lock is still valid
            _isLocked = true;
          } else {
            // ✅ User was active before app closed
            _isLocked = false;
            await _saveLockState();
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to restore lock state: $e');
      _isLocked = false;
    }
  }

  Future<void> _updateLastActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastActivityKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // Ignore
    }
  }

  // ========== TIMER MANAGEMENT ==========
  void _resetTimer() {
    if (!_isInitialized || _isDisposed || _isLocked) return;

    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, () {
      _lockApp();
    });
    
    _updateLastActivity();
  }

  void resetTimer() {
    if (!_isInitialized || _isDisposed || _isLocked) return;
    _resetTimer();
  }

  // ========== LOCK / UNLOCK ==========
  void lock() {
    if (_isLocked || _isDisposed) return;
    _lockApp();
  }

  void _lockApp() {
    if (_isLocked || !_isInitialized || _isDisposed) return;

    _isLocked = true;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _saveLockState();
    _onLock?.call();

    debugPrint('🔒 App locked');
  }

  void unlock() {
    if (!_isLocked || _isDisposed) return;

    _isLocked = false;
    _saveLockState();
    _resetTimer();
    _onUnlock?.call();

    debugPrint('🔓 App unlocked');
  }

  // ========== LIFECYCLE ==========
  void onPaused() {
    if (_isDisposed) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _saveLockState();
  }

  void onResumed() {
    if (_isDisposed) return;
    
    // ✅ Check if lock should be active
    if (_isLocked) {
      // Stay locked
      return;
    }
    
    // ✅ Restart timer
    _resetTimer();
  }

  // ========== DISPOSAL ==========
  void dispose() {
    if (_isDisposed) return;
    
    _isDisposed = true;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _onLock = null;
    _onUnlock = null;
    _isInitialized = false;
    _saveLockState();

    debugPrint('🔒 LockService disposed');
  }

  // ========== UTILITY ==========
  Future<void> resetLockState() async {
    _isLocked = false;
    await _saveLockState();
    if (!_isDisposed) {
      _resetTimer();
    }
  }
}