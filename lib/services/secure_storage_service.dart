// services/secure_storage_service.dart
// Complete file with API key encryption

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  // ✅ Hardware-backed secure storage
  static final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      // Auto-clear a Keystore-backed value that can no longer be decrypted
      // (e.g. after an app reinstall/restore or key invalidation). Without
      // this, reads throw AndroidError "BAD_DECRYPT" and crash the login flow.
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.passcode,
    ),
  );

  // ✅ Unique encryption key per device
  static String? _cachedEncryptionKey;
  static const String _encryptionKeyKey = 'app_master_key';
  static const String _deviceIdKey = 'device_unique_id';
  static const String _sessionTokenKey = 'session_token';
  static const String _userIdKey = 'user_id';
  static const String _deviceFingerprintKey = 'device_fingerprint';
  static const String _sessionCreatedKey = 'session_created';

  // ============================================================
  // 🛡️ CORRUPTION-SAFE READS
  // ============================================================

  /// Reads a value from secure storage but treats decryption failures
  /// (PlatformException, e.g. Keystore "BAD_DECRYPT" after a reinstall or
  /// device key change) as "no value" instead of letting the exception bubble
  /// up and break login. On repeated failures it wipes all secure storage so
  /// the app can start clean.
  static Future<String?> _readSafely(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      debugPrint('⚠️ SecureStorage read failed for "$key": $e');
      try {
        // Clear the whole encrypted vault — the stored values can no longer
        // be decrypted anyway, so there is nothing worth keeping.
        await _secureStorage.deleteAll();
        _cachedEncryptionKey = null;
        debugPrint('🧹 Cleared corrupt secure storage (resetOnError path)');
      } catch (_) {}
      return null;
    }
  }

  /// Safe wrapper for writes — if the Keystore is invalid, don't let a stale
  /// value persist and never throw into the caller.
  static Future<void> _writeSafely(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (e) {
      debugPrint('⚠️ SecureStorage write failed for "$key": $e');
    }
  }

  static Future<void> _deleteSafely(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (e) {
      debugPrint('⚠️ SecureStorage delete failed for "$key": $e');
    }
  }

  // ============================================================
  // 🔑 ENCRYPTION METHODS
  // ============================================================

  static Future<String> _getOrCreateEncryptionKey() async {
    if (_cachedEncryptionKey != null) return _cachedEncryptionKey!;

    var existingKey = await _readSafely(_encryptionKeyKey);
    if (existingKey != null && existingKey.isNotEmpty) {
      _cachedEncryptionKey = existingKey;
      return existingKey;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    final key = base64Url.encode(bytes);

    await _writeSafely(_encryptionKeyKey, key);
    _cachedEncryptionKey = key;

    debugPrint('🔐 🔑 Generated unique encryption key for this device');
    return key;
  }

  static Future<String> _encryptData(String data) async {
    if (data.isEmpty) return '';
    final key = await _getOrCreateEncryptionKey();
    final keyBytes = utf8.encode(key);
    final dataBytes = utf8.encode(data);

    final result = List<int>.generate(dataBytes.length, (i) {
      return dataBytes[i] ^ keyBytes[i % keyBytes.length];
    });

    return base64Url.encode(result);
  }

  static Future<String> _decryptData(String encryptedData) async {
    if (encryptedData.isEmpty) return '';
    final key = await _getOrCreateEncryptionKey();
    final keyBytes = utf8.encode(key);
    final dataBytes = base64Url.decode(encryptedData);

    final result = List<int>.generate(dataBytes.length, (i) {
      return dataBytes[i] ^ keyBytes[i % keyBytes.length];
    });

    return utf8.decode(result);
  }

  // ✅ PUBLIC encrypt/decrypt methods for external use
  static Future<String> encryptData(String data) async {
    return await _encryptData(data);
  }

  static Future<String> decryptData(String encryptedData) async {
    return await _decryptData(encryptedData);
  }

  static Future<String> _generateHMAC(String data) async {
    final key = await _getOrCreateEncryptionKey();
    final hmac = Hmac(sha256, utf8.encode(key));
    final digest = hmac.convert(utf8.encode(data));
    return digest.toString();
  }

  // ============================================================
  // 📱 DEVICE ID & FINGERPRINT
  // ============================================================

  static Future<String> getDeviceId() async {
    var deviceId = await _readSafely(_deviceIdKey);
    if (deviceId != null && deviceId.isNotEmpty) return deviceId;

    final random = Random.secure();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    deviceId = base64Url.encode(bytes);

    await _writeSafely(_deviceIdKey, deviceId);
    return deviceId;
  }

  static Future<String> getDeviceFingerprint() async {
    var fingerprint = await _readSafely(_deviceFingerprintKey);
    if (fingerprint != null && fingerprint.isNotEmpty) return fingerprint;

    final deviceId = await getDeviceId();
    final random = Random.secure();
    final salt = List<int>.generate(8, (i) => random.nextInt(256));
    final saltString = base64Url.encode(salt);
    final combined = '$deviceId:$saltString';
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    fingerprint = digest.toString();

    await _writeSafely(_deviceFingerprintKey, fingerprint);
    return fingerprint;
  }

  // ============================================================
  // 👤 SESSION MANAGEMENT
  // ============================================================

  static Future<void> saveSession({
    required int userId,
    required String sessionToken,
    required String deviceFingerprint,
  }) async {
    await _writeSafely(_userIdKey, userId.toString());
    await _writeSafely(_sessionTokenKey, sessionToken);
    await _writeSafely(_deviceFingerprintKey, deviceFingerprint);
    await _writeSafely(_sessionCreatedKey, DateTime.now().toIso8601String());
  }

  static Future<Map<String, String?>> getSession() async {
    return {
      'userId': await _readSafely(_userIdKey),
      'sessionToken': await _readSafely(_sessionTokenKey),
      'deviceFingerprint': await _readSafely(_deviceFingerprintKey),
      'sessionCreated': await _readSafely(_sessionCreatedKey),
    };
  }

  static Future<bool> hasActiveSession() async {
    final token = await _readSafely(_sessionTokenKey);
    final userId = await _readSafely(_userIdKey);
    return token != null && token.isNotEmpty && userId != null && userId.isNotEmpty;
  }

  static Future<void> clearSession() async {
    await _deleteSafely(_userIdKey);
    await _deleteSafely(_sessionTokenKey);
    await _deleteSafely(_deviceFingerprintKey);
    await _deleteSafely(_sessionCreatedKey);
    debugPrint('🔐 🔓 Session cleared');
  }

  static Future<int?> getUserId() async {
    final userId = await _readSafely(_userIdKey);
    if (userId == null) return null;
    return int.tryParse(userId);
  }

  static Future<String?> getSessionToken() async {
    return await _readSafely(_sessionTokenKey);
  }

  // ============================================================
  // 🔑 PIN MANAGEMENT
  // ============================================================

  static const String _pinKeyPrefix = 'app_pin';
  static const String _usersWithPinsKey = 'users_with_pins';

  static Future<void> savePin(String pin, {String? userId}) async {
    final key = userId != null ? '${_pinKeyPrefix}_$userId' : _pinKeyPrefix;
    await _secureStorage.write(key: key, value: pin);

    if (userId != null) {
      final prefs = await SharedPreferences.getInstance();
      final usersWithPins = prefs.getStringList(_usersWithPinsKey) ?? [];
      if (!usersWithPins.contains(userId)) {
        usersWithPins.add(userId);
        await prefs.setStringList(_usersWithPinsKey, usersWithPins);
      }
    }
    debugPrint('🔐 🔑 PIN saved${userId != null ? " for user $userId" : ""}');
  }

  static Future<String?> readPin({String? userId}) async {
    final key = userId != null ? '${_pinKeyPrefix}_$userId' : _pinKeyPrefix;
    return await _secureStorage.read(key: key);
  }

  static Future<bool> hasPin({String? userId}) async {
    final key = userId != null ? '${_pinKeyPrefix}_$userId' : _pinKeyPrefix;
    final pin = await _secureStorage.read(key: key);
    return pin != null && pin.isNotEmpty;
  }

  static Future<void> deletePin({String? userId}) async {
    final key = userId != null ? '${_pinKeyPrefix}_$userId' : _pinKeyPrefix;
    await _secureStorage.delete(key: key);

    if (userId != null) {
      final prefs = await SharedPreferences.getInstance();
      final usersWithPins = prefs.getStringList(_usersWithPinsKey) ?? [];
      usersWithPins.remove(userId);
      await prefs.setStringList(_usersWithPinsKey, usersWithPins);
    }
    debugPrint('🔐 🗑️ PIN deleted${userId != null ? " for user $userId" : ""}');
  }

  static Future<bool> verifyPin(String pin, {String? userId}) async {
    final savedPin = await readPin(userId: userId);
    return savedPin != null && savedPin == pin;
  }

  static Future<List<String>> getUsersWithPins() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_usersWithPinsKey) ?? [];
  }

  // ============================================================
  // 💾 DATA STORAGE (Company & User)
  // ============================================================

  static Future<void> saveDataForCompany({
    required int companyId,
    required String key,
    required Map<String, dynamic> data,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = '${key}_company_$companyId';

    final secureData = {
      ...data,
      'company_id': companyId,
      'data_type': 'company',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    final jsonString = json.encode(secureData);
    final encryptedData = await _encryptData(jsonString);
    final signature = await _generateHMAC(encryptedData);

    await prefs.setString(storageKey, encryptedData);
    await prefs.setString('${storageKey}_sig', signature);
  }

  static Future<Map<String, dynamic>?> loadDataForCompany({
    required int companyId,
    required String key,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = '${key}_company_$companyId';

    final encryptedData = prefs.getString(storageKey);
    final savedSignature = prefs.getString('${storageKey}_sig');

    if (encryptedData == null || savedSignature == null) return null;

    try {
      final expectedSignature = await _generateHMAC(encryptedData);
      if (savedSignature != expectedSignature) {
        debugPrint('🔐 ⚠️ Data tampered for company $companyId');
        await prefs.remove(storageKey);
        await prefs.remove('${storageKey}_sig');
        return null;
      }

      final jsonString = await _decryptData(encryptedData);
      final data = json.decode(jsonString);

      if (data['company_id'] != companyId) {
        debugPrint('🔐 ⚠️ Company ID mismatch');
        return null;
      }

      final timestamp = data['timestamp'] as int;
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > 7 * 24 * 60 * 60 * 1000) {
        debugPrint('🔐 ⚠️ Data expired for company $companyId');
        await prefs.remove(storageKey);
        await prefs.remove('${storageKey}_sig');
        return null;
      }

      return data;
    } catch (e) {
      debugPrint('🔐 ❌ Decryption failed: $e');
      return null;
    }
  }

  static Future<void> saveDataForUser({
    required String userId,
    required String key,
    required Map<String, dynamic> data,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = '${key}_user_$userId';

    final secureData = {
      ...data,
      'user_id': userId,
      'data_type': 'user',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    final jsonString = json.encode(secureData);
    final encryptedData = await _encryptData(jsonString);
    final signature = await _generateHMAC(encryptedData);

    await prefs.setString(storageKey, encryptedData);
    await prefs.setString('${storageKey}_sig', signature);
  }

  static Future<Map<String, dynamic>?> loadDataForUser({
    required String userId,
    required String key,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = '${key}_user_$userId';

    final encryptedData = prefs.getString(storageKey);
    final savedSignature = prefs.getString('${storageKey}_sig');

    if (encryptedData == null || savedSignature == null) return null;

    try {
      final expectedSignature = await _generateHMAC(encryptedData);
      if (savedSignature != expectedSignature) {
        debugPrint('🔐 ⚠️ Data tampered for user $userId');
        await prefs.remove(storageKey);
        await prefs.remove('${storageKey}_sig');
        return null;
      }

      final jsonString = await _decryptData(encryptedData);
      final data = json.decode(jsonString);

      if (data['user_id'] != userId) {
        debugPrint('🔐 ⚠️ User ID mismatch');
        return null;
      }

      final timestamp = data['timestamp'] as int;
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > 3 * 24 * 60 * 60 * 1000) {
        debugPrint('🔐 ⚠️ Data expired for user $userId');
        await prefs.remove(storageKey);
        await prefs.remove('${storageKey}_sig');
        return null;
      }

      return data;
    } catch (e) {
      debugPrint('🔐 ❌ Decryption failed: $e');
      return null;
    }
  }

  // ============================================================
  // 🔐 API KEY ENCRYPTION METHODS
  // ============================================================

  /// Save an encrypted API key for a user
  static Future<bool> saveEncryptedApiKey({
    required String userId,
    required String key,
    required String value,
  }) async {
    try {
      if (value.isEmpty) {
        debugPrint('⚠️ Empty API key, skipping encryption for $key');
        return true;
      }

      final encrypted = await _encryptData(value);
      final signature = await _generateHMAC(encrypted);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_${key}_${userId}', encrypted);
      await prefs.setString('api_${key}_${userId}_sig', signature);

      debugPrint('🔐 ✅ API key $key encrypted and saved');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to encrypt API key $key: $e');
      return false;
    }
  }

  /// Load and decrypt an API key for a user
  static Future<String?> loadEncryptedApiKey({
    required String userId,
    required String key,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encrypted = prefs.getString('api_${key}_${userId}');
      final signature = prefs.getString('api_${key}_${userId}_sig');

      if (encrypted == null || signature == null) {
        debugPrint('⚠️ No encrypted API key found for $key');
        return null;
      }

      final expectedSignature = await _generateHMAC(encrypted);
      if (signature != expectedSignature) {
        debugPrint('⚠️ API key $key has been tampered!');
        return null;
      }

      final decrypted = await _decryptData(encrypted);
      debugPrint('🔐 ✅ API key $key loaded and decrypted');
      return decrypted;
    } catch (e) {
      debugPrint('❌ Failed to decrypt API key $key: $e');
      return null;
    }
  }

  /// Delete an encrypted API key for a user
  static Future<bool> deleteEncryptedApiKey({
    required String userId,
    required String key,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('api_${key}_${userId}');
      await prefs.remove('api_${key}_${userId}_sig');
      debugPrint('🗑️ API key $key deleted');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to delete API key $key: $e');
      return false;
    }
  }

  /// Check if an encrypted API key exists
  static Future<bool> hasEncryptedApiKey({
    required String userId,
    required String key,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encrypted = prefs.getString('api_${key}_${userId}');
      return encrypted != null && encrypted.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // 🧹 CLEAR METHODS
  // ============================================================

  static Future<void> clearAppData() async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = prefs.getKeys().where((key) =>
        key.contains('_company_') ||
        key.contains('_user_') ||
        key.contains('_sig') ||
        key.startsWith('api_'));
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
    debugPrint('🔐 🧹 App data cleared');
  }

  static Future<void> clearSessionOnly() async {
    await _secureStorage.delete(key: _userIdKey);
    await _secureStorage.delete(key: _sessionTokenKey);
    await _secureStorage.delete(key: _deviceFingerprintKey);
    await _secureStorage.delete(key: _sessionCreatedKey);
    debugPrint('🔐 🔓 Session cleared');
  }

  static Future<void> clearAllPins() async {
    await _secureStorage.delete(key: _pinKeyPrefix);
    final prefs = await SharedPreferences.getInstance();
    final usersWithPins = prefs.getStringList(_usersWithPinsKey) ?? [];
    for (final userId in usersWithPins) {
      final pinKey = '${_pinKeyPrefix}_$userId';
      await _secureStorage.delete(key: pinKey);
    }
    await prefs.remove(_usersWithPinsKey);
    debugPrint('🔐 🗑️ All PINs cleared');
  }

  static Future<void> clearPinForUser(String userId) async {
    final pinKey = '${_pinKeyPrefix}_$userId';
    await _secureStorage.delete(key: pinKey);
    final prefs = await SharedPreferences.getInstance();
    final usersWithPins = prefs.getStringList(_usersWithPinsKey) ?? [];
    usersWithPins.remove(userId);
    await prefs.setStringList(_usersWithPinsKey, usersWithPins);
    debugPrint('🔐 🗑️ PIN cleared for user $userId');
  }

  static Future<void> clearCompanyData(int companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = prefs.getKeys().where((key) =>
        key.contains('_company_$companyId') ||
        key.contains('_company_${companyId}_sig'));
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
    debugPrint('🔐 🧹 Company data cleared for ID: $companyId');
  }

  static Future<void> clearUserData(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = prefs.getKeys().where((key) =>
        key.contains('_user_$userId') ||
        key.contains('_user_${userId}_sig') ||
        key.startsWith('api_') && key.contains(userId));
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
    debugPrint('🔐 🧹 User data cleared for ID: $userId');
  }

  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = prefs.getKeys().where((key) =>
        key.contains('_company_') ||
        key.contains('_user_') ||
        key.contains('_sig') ||
        key.startsWith('api_') ||
        key == _usersWithPinsKey);
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
    await _secureStorage.deleteAll();
    _cachedEncryptionKey = null;
    debugPrint('🔐 🧹 ALL data cleared');
  }

  static Future<void> factoryReset() async {
    await clearAllData();
  }

  // ============================================================
  // 📊 STATS & UTILITY
  // ============================================================

  static Future<Map<String, dynamic>> getStorageStats() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();

    int companyKeys = 0;
    int userKeys = 0;
    int sigKeys = 0;
    int apiKeys = 0;
    int totalSize = 0;

    for (final key in allKeys) {
      if (key.contains('_company_')) companyKeys++;
      if (key.contains('_user_')) userKeys++;
      if (key.contains('_sig')) sigKeys++;
      if (key.startsWith('api_')) apiKeys++;

      final value = prefs.getString(key);
      if (value != null) totalSize += value.length;
    }

    final usersWithPins = await getUsersWithPins();

    return {
      'companyKeys': companyKeys,
      'userKeys': userKeys,
      'signatureKeys': sigKeys,
      'apiKeys': apiKeys,
      'totalKeys': allKeys.length,
      'totalSizeKB': (totalSize / 1024).toStringAsFixed(2),
      'hasEncryptionKey': await _secureStorage.containsKey(key: _encryptionKeyKey),
      'hasSession': await hasActiveSession(),
      'hasAppPin': await hasPin(),
      'usersWithPins': usersWithPins.length,
      'userPinList': usersWithPins,
    };
  }
}