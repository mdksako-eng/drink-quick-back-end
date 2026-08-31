// utils/payment_helper.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/secure_storage_service.dart';
import '../services/payment_service.dart';

class PaymentHelper extends ChangeNotifier {
  static final PaymentHelper _instance = PaymentHelper._internal();
  factory PaymentHelper() => _instance;
  PaymentHelper._internal();

  // ============================================================
  // 📦 STATE
  // ============================================================
  
  bool _businessPaymentsEnabled = false;
  bool _mtnEnabled = false;
  bool _orangeEnabled = false;
  String _mtnMerchantPhone = '';
  String _orangeMerchantPhone = '';
  bool _mtnSandboxMode = true;
  bool _orangeSandboxMode = true;
  
  // ✅ Track if settings are from company
  bool _isCompanySettings = false;
  String? _companyName;
  bool _isLoading = false;
  String? _error;

  // ============================================================
  // 📦 GETTERS
  // ============================================================
  
  bool get businessPaymentsEnabled => _businessPaymentsEnabled;
  bool get mtnEnabled => _mtnEnabled;
  bool get orangeEnabled => _orangeEnabled;
  String get mtnMerchantPhone => _mtnMerchantPhone;
  String get orangeMerchantPhone => _orangeMerchantPhone;
  bool get mtnSandboxMode => _mtnSandboxMode;
  bool get orangeSandboxMode => _orangeSandboxMode;
  bool get isCompanySettings => _isCompanySettings;
  String? get companyName => _companyName;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ============================================================
  // 🔄 LOAD SETTINGS FROM COMPANY
  // ============================================================

  Future<void> loadSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // ✅ Get current user to check role
      final token = await SecureStorageService.getSessionToken();
      if (token == null) {
        debugPrint('⚠️ No auth token found, loading local settings');
        await _loadLocalSettings();
        _isLoading = false;
        notifyListeners();
        return;
      }

      // ✅ Try to load company settings from the backend (secrets stay server-side)
      final company = await PaymentService.getCompanyPaymentSettings();

      if (company != null) {
        // ✅ Use company settings
        _isCompanySettings = true;
        _companyName = company['name'] ?? 'Company';
        _businessPaymentsEnabled = company['businessPaymentsEnabled'] ?? false;
        _mtnEnabled = company['mtnEnabled'] ?? true;
        _orangeEnabled = company['orangeEnabled'] ?? true;
        _mtnMerchantPhone = company['mtnMerchantPhone'] ?? '';
        _orangeMerchantPhone = company['orangeMerchantPhone'] ?? '';
        _mtnSandboxMode = company['mtnSandboxMode'] ?? true;
        _orangeSandboxMode = company['orangeSandboxMode'] ?? true;
        // 🔐 API keys / secret keys are never returned by the backend and never held in the app.

        // ✅ Save non-secret values to local cache
        await _saveToLocalCache();

        debugPrint('✅ Loaded company payment settings from: $_companyName');
      } else {
        // ✅ Fallback to local settings
        debugPrint('📂 No company settings found, loading local settings');
        await _loadLocalSettings();
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Error loading payment settings: $e');
      // ✅ Fallback to local settings on error
      await _loadLocalSettings();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ============================================================
  // 💾 LOCAL SETTINGS (Fallback)
  // ============================================================

  Future<void> _loadLocalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isCompanySettings = false;
    _companyName = null;
    _businessPaymentsEnabled = prefs.getBool('business_payments_enabled') ?? false;
    _mtnEnabled = prefs.getBool('mtn_enabled') ?? true;
    _orangeEnabled = prefs.getBool('orange_enabled') ?? true;
    _mtnMerchantPhone = prefs.getString('mtn_merchant_phone') ?? '';
    _orangeMerchantPhone = prefs.getString('orange_merchant_phone') ?? '';
    // ✅ Secrets are never cached locally — always loaded from the backend
    _mtnSandboxMode = prefs.getBool('mtn_sandbox_mode') ?? true;
    _orangeSandboxMode = prefs.getBool('orange_sandbox_mode') ?? true;
    debugPrint('📂 Loaded local payment settings');
  }

  Future<void> _saveToLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('business_payments_enabled', _businessPaymentsEnabled);
    await prefs.setBool('mtn_enabled', _mtnEnabled);
    await prefs.setBool('orange_enabled', _orangeEnabled);
    await prefs.setString('mtn_merchant_phone', _mtnMerchantPhone);
    await prefs.setString('orange_merchant_phone', _orangeMerchantPhone);
    // ✅ Secrets are NOT persisted locally
    // 🔐 Purge any previously cached secrets/ids; keep only non-sensitive flags
    await prefs.remove('mtn_api_key');
    await prefs.remove('mtn_secret_key');
    await prefs.remove('mtn_merchant_id');
    await prefs.setBool('mtn_sandbox_mode', _mtnSandboxMode);
    await prefs.remove('orange_api_key');
    await prefs.remove('orange_secret_key');
    await prefs.remove('orange_merchant_id');
    await prefs.setBool('orange_sandbox_mode', _orangeSandboxMode);
  }

  // ============================================================
  // 💾 SAVE SETTINGS TO COMPANY (Manager only)
  // ============================================================

  Future<bool> saveCompanySettings({
    required bool businessPaymentsEnabled,
    required bool mtnEnabled,
    required bool orangeEnabled,
    required String mtnMerchantPhone,
    required String orangeMerchantPhone,
    required String mtnApiKey,
    required String mtnSecretKey,
    required String mtnMerchantId,
    required bool mtnSandboxMode,
    required String orangeApiKey,
    required String orangeSecretKey,
    required String orangeMerchantId,
    required bool orangeSandboxMode,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final settings = {
        'businessPaymentsEnabled': businessPaymentsEnabled,
        'mtnEnabled': mtnEnabled,
        'orangeEnabled': orangeEnabled,
        'mtnMerchantPhone': mtnMerchantPhone,
        'orangeMerchantPhone': orangeMerchantPhone,
        'mtnApiKey': mtnApiKey,
        'mtnSecretKey': mtnSecretKey,
        'mtnMerchantId': mtnMerchantId,
        'mtnSandboxMode': mtnSandboxMode,
        'orangeApiKey': orangeApiKey,
        'orangeSecretKey': orangeSecretKey,
        'orangeMerchantId': orangeMerchantId,
        'orangeSandboxMode': orangeSandboxMode,
      };

      // ✅ Save to the backend (secrets stay server-side, manager-verified)
      final success = await PaymentService.updateCompanyPaymentSettings(settings);
      
      if (success) {
        // ✅ Update local state
        _businessPaymentsEnabled = businessPaymentsEnabled;
        _mtnEnabled = mtnEnabled;
        _orangeEnabled = orangeEnabled;
        _mtnMerchantPhone = mtnMerchantPhone;
        _orangeMerchantPhone = orangeMerchantPhone;
        _mtnSandboxMode = mtnSandboxMode;
        _orangeSandboxMode = orangeSandboxMode;
        // 🔐 API keys / secret keys are forwarded to the backend, never stored in the app.
        _isCompanySettings = true;
        
        // ✅ Save to local cache
        await _saveToLocalCache();
        
        debugPrint('✅ Company payment settings saved');
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Failed to save company settings';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Error saving company payment settings: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ============================================================
  // 🔄 REFRESH
  // ============================================================

  static Future<void> refresh() async {
    await _instance.loadSettings();
  }

  // ============================================================
  // 👂 LISTENERS
  // ============================================================

  static void addPaymentListener(VoidCallback listener) {
    _instance.addListener(listener);
  }

  static void removePaymentListener(VoidCallback listener) {
    _instance.removeListener(listener);
  }
}