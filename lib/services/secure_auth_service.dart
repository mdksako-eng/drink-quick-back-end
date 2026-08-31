// services/secure_auth_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'secure_storage_service.dart';
import 'backend_auth_service.dart'; // 

class SecureAuthService {
  // ✅ Use BackendAuthService.baseUrl for consistency
  static String get _baseUrl => BackendAuthService.baseUrl;
  
  static const Duration sessionTimeout = Duration(hours: 8);
  static const Duration sessionCheckInterval = Duration(seconds: 30);

  static Timer? _sessionCheckTimer;
  static bool _isSessionValid = false;
  static final List<SessionListener> _listeners = [];

  // ✅ Session listener
  static void addListener(SessionListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  static void removeListener(SessionListener listener) {
    _listeners.remove(listener);
  }

  static void _notifySessionTerminated(String? previousDevice) {
    for (final listener in _listeners) {
      listener.onSessionTerminated(previousDevice);
    }
  }

  // ✅ Validate session with server
  static Future<SessionValidationResult> validateSession() async {
    try {
      final session = await SecureStorageService.getSession();
      final token = session['sessionToken'];

      if (token == null || token.isEmpty) {
        debugPrint('🔐 No session token found');
        return SessionValidationResult(valid: false, terminated: false);
      }

      // Check session expiry locally first
      final sessionCreated = session['sessionCreated'];
      if (sessionCreated != null) {
        final created = DateTime.parse(sessionCreated);
        final age = DateTime.now().difference(created);
        if (age > sessionTimeout) {
          debugPrint('🔐 Session expired locally');
          await SecureStorageService.clearSession();
          return SessionValidationResult(valid: false, terminated: false);
        }
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/validate-session'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      debugPrint('🔐 Session validation response: $data');

      if (data['terminated'] == true) {
        debugPrint('🔐 Session terminated by server');
        await SecureStorageService.clearSession();
        return SessionValidationResult(
          valid: false,
          terminated: true,
          previousDevice: data['previousDeviceName'],
        );
      }

      return SessionValidationResult(
        valid: data['valid'] == true,
        terminated: false,
      );
    } catch (e) {
      // Network error - assume session is valid to avoid disrupting user
      debugPrint('🔐 Session validation error (assuming valid): $e');
      return SessionValidationResult(valid: true, terminated: false);
    }
  }

  // ✅ Check if session is still valid (for warnings)
  static Future<Map<String, dynamic>?> getSessionWarning() async {
    try {
      final session = await SecureStorageService.getSession();
      final token = session['sessionToken'];
      final userId = session['userId'];

      if (token == null || token.isEmpty || userId == null) {
        return null;
      }

      // Check with server
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/validate-session'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (data['terminated'] == true) {
        await SecureStorageService.clearSession();
        return {
          'showWarning': true,
          'message': 'Your account is now active on another device.',
          'previousDevice': data['previousDeviceName'] ?? 'another device',
        };
      }

      return null;
    } catch (e) {
      debugPrint('🔐 Get session warning error: $e');
      return null;
    }
  }

  // ✅ Get current user from backend
  static Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final token = await SecureStorageService.getSessionToken();
      if (token == null || token.isEmpty) {
        debugPrint('🔐 No token for getCurrentUser');
        return null;
      }

      final userId = await SecureStorageService.getUserId();
      if (userId == null) {
        debugPrint('🔐 No userId for getCurrentUser');
        return null;
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/api/auth/me?userId=$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('🔐 Current user fetched: ${data['data']?['user']?['username']}');
        return data['data']?['user'];
      } else {
        debugPrint('🔐 Failed to get current user: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('🔐 Get current user error: $e');
      return null;
    }
  }

  // ✅ Check if session is still active
  static Future<bool> isSessionActive() async {
    final result = await validateSession();
    return result.valid && !result.terminated;
  }

  // ✅ Start periodic session validation
  static void startSessionValidation() {
    _sessionCheckTimer?.cancel();
    debugPrint('🔐 Starting session validation');
    
    _sessionCheckTimer = Timer.periodic(sessionCheckInterval, (timer) async {
      final result = await validateSession();
      if (!result.valid && result.terminated) {
        timer.cancel();
        _isSessionValid = false;
        _notifySessionTerminated(result.previousDevice);
      } else if (!result.valid) {
        _isSessionValid = false;
      } else {
        _isSessionValid = true;
      }
    });
    _isSessionValid = true;
  }

  // ✅ Stop session validation
  static void stopSessionValidation() {
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = null;
    _isSessionValid = false;
    debugPrint('🔐 Session validation stopped');
  }

  // ✅ Get session validity status
  static bool get isSessionValid => _isSessionValid;
}

// ============================================================
// 📦 MODELS
// ============================================================

class SessionValidationResult {
  final bool valid;
  final bool terminated;
  final String? previousDevice;

  SessionValidationResult({
    required this.valid,
    required this.terminated,
    this.previousDevice,
  });

  @override
  String toString() {
    return 'SessionValidationResult(valid: $valid, terminated: $terminated, previousDevice: $previousDevice)';
  }
}

abstract class SessionListener {
  void onSessionTerminated(String? previousDevice);
}