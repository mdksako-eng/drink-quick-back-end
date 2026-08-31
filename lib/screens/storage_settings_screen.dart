// screens/storage_settings_screen.dart
// screens/storage_settings_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/services/storage_service.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:drinks_calculator_fixed/main.dart';
import 'package:drinks_calculator_fixed/utils/payment_helper.dart';
import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';
import 'package:drinks_calculator_fixed/services/payment_service.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';
import 'package:drinks_calculator_fixed/services/secure_storage_service.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  // ✅ Loading state
  bool _isLoading = false;

  // ✅ Theme settings (User-specific)
  String _primaryColor = '#667EEA';
  bool _compactMode = false;

  // ✅ Company-wide settings (from companies table)
  // Currency settings
  String _currencySymbol = 'Frs';
  String _currencyPosition = 'right';
  String _decimalSeparator = '.';
  String _thousandsSeparator = ',';
  int _decimalPlaces = 0;

  // Company settings
  String _companyName = 'Drink Quick Cal';
  String _companyEmail = '';
  String _companyPhone = '';
  String _companyAddress = '';

  // Business Payment Settings
  bool _businessPaymentsEnabled = false;

  // MTN Mobile Money settings
  bool _mtnEnabled = true;
  String _mtnApiKey = '';
  String _mtnSecretKey = '';
  String _mtnMerchantId = '';
  String _mtnMerchantPhone = '';
  bool _mtnSandboxMode = true;

  // Orange Money settings
  bool _orangeEnabled = true;
  String _orangeApiKey = '';
  String _orangeSecretKey = '';
  String _orangeMerchantId = '';
  String _orangeMerchantPhone = '';
  bool _orangeSandboxMode = true;

  // User-specific settings
  bool _autoSync = false;
  bool _showNotifications = true;

  // Track if there are unsaved changes
  bool _hasUnsavedChanges = false;

  // Test connection states
  bool _testingMtn = false;
  bool _testingOrange = false;
  String? _mtnTestResult;
  String? _orangeTestResult;

  // Timer for phone message
  bool _showValidMessage = false;
  Timer? _validMessageTimer;

  // Controllers
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _companyEmailController = TextEditingController();
  final TextEditingController _companyPhoneController = TextEditingController();
  final TextEditingController _companyAddressController =
      TextEditingController();
  final TextEditingController _mtnApiKeyController = TextEditingController();
  final TextEditingController _mtnSecretKeyController = TextEditingController();
  final TextEditingController _mtnMerchantIdController =
      TextEditingController();
  final TextEditingController _mtnMerchantPhoneController =
      TextEditingController();
  final TextEditingController _orangeApiKeyController = TextEditingController();
  final TextEditingController _orangeSecretKeyController =
      TextEditingController();
  final TextEditingController _orangeMerchantIdController =
      TextEditingController();
  final TextEditingController _orangeMerchantPhoneController =
      TextEditingController();

  // Country selection variables
  String _selectedCountry = 'CM';
  String _selectedCountryCode = '+237';
  final List<Map<String, String>> _countries = [
    {
      'code': 'CM',
      'name': 'Cameroon',
      'dial': '+237',
      'flag': '🇨🇲',
      'format': '6XX XXX XXX'
    },
    {
      'code': 'NG',
      'name': 'Nigeria',
      'dial': '+234',
      'flag': '🇳🇬',
      'format': 'XXX XXX XXXX'
    },
  ];

  // Available colors for theme
  final List<Map<String, dynamic>> _availableColors = [
    {'name': 'Blue', 'code': '#667EEA', 'color': const Color(0xFF667EEA)},
    {'name': 'Orange', 'code': '#FF9800', 'color': const Color(0xFFFF9800)},
    {'name': 'Teal', 'code': '#009688', 'color': const Color(0xFF009688)},
    {'name': 'Pink', 'code': '#E91E63', 'color': const Color(0xFFE91E63)},
  ];

  // Available currency symbols
  final List<Map<String, String>> _availableCurrencies = [
    {'symbol': 'Frs', 'name': 'CFA Franc'},
    {'symbol': '₦', 'name': 'Nigerian Naira'},
  ];

  // ✅ ThemeProvider reference
  late ThemeProvider _themeProvider;

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _themeProvider = Provider.of<ThemeProvider>(context, listen: false);
  }

  @override
  void dispose() {
    _validMessageTimer?.cancel();
    _companyNameController.dispose();
    _companyEmailController.dispose();
    _companyPhoneController.dispose();
    _companyAddressController.dispose();
    _mtnApiKeyController.dispose();
    _mtnSecretKeyController.dispose();
    _mtnMerchantIdController.dispose();
    _mtnMerchantPhoneController.dispose();
    _orangeApiKeyController.dispose();
    _orangeSecretKeyController.dispose();
    _orangeMerchantIdController.dispose();
    _orangeMerchantPhoneController.dispose();
    super.dispose();
  }

  // ============================================================
  // ✅ LOAD SETTINGS - Company-Wide + User-Specific
  // ============================================================
  Future<void> _loadAllSettings() async {
    if (mounted) setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final companyId = authProvider.currentUser?.companyId;
    final userId = authProvider.currentUser?.id;

    debugPrint('📂 ===== LOADING SETTINGS =====');
    debugPrint('🏢 Company ID: $companyId');
    debugPrint('👤 User ID: $userId');

    // ============================================================
    // ✅ STEP 1: Load COMPANY-WIDE settings from companies table
    // ============================================================

    if (companyId != null) {
      try {
        final company = await SupabaseService.getCompany(companyId);
        if (company != null) {
          debugPrint('✅ Loaded company from Supabase: ${company['name']}');

          // ✅ Company info
          _companyName = company['name'] ?? 'Drink Quick Cal';
          _companyEmail = company['email'] ?? '';
          _companyPhone = company['phone'] ?? '';
          _companyAddress = company['address'] ?? '';

          // ✅ COMPANY-WIDE CURRENCY SETTINGS
          _currencySymbol = company['currency_symbol'] ?? 'Frs';
          _currencyPosition = company['currency_position'] ?? 'right';
          _decimalSeparator = company['decimal_separator'] ?? '.';
          _thousandsSeparator = company['thousands_separator'] ?? ',';
          _decimalPlaces = company['decimal_places'] ?? 0;

          // ✅ COMPANY-WIDE PAYMENT SETTINGS (via backend — secrets stay server-side)
          try {
            final paymentSettings =
                await PaymentService.getCompanyPaymentSettings();
            if (paymentSettings != null) {
              _businessPaymentsEnabled =
                  paymentSettings['businessPaymentsEnabled'] ?? false;
              _mtnEnabled = paymentSettings['mtnEnabled'] ?? true;
              _orangeEnabled = paymentSettings['orangeEnabled'] ?? true;
              _mtnMerchantPhone = paymentSettings['mtnMerchantPhone'] ?? '';
              _orangeMerchantPhone = paymentSettings['orangeMerchantPhone'] ?? '';
              _mtnMerchantId = paymentSettings['mtnMerchantId'] ?? '';
              _orangeMerchantId = paymentSettings['orangeMerchantId'] ?? '';
              _mtnSandboxMode = paymentSettings['mtnSandboxMode'] ?? true;
              _orangeSandboxMode = paymentSettings['orangeSandboxMode'] ?? true;
              _mtnApiKey = paymentSettings['mtnApiKey'] ?? '';
              _mtnSecretKey = paymentSettings['mtnSecretKey'] ?? '';
              _orangeApiKey = paymentSettings['orangeApiKey'] ?? '';
              _orangeSecretKey = paymentSettings['orangeSecretKey'] ?? '';
            }
          } catch (e) {
            debugPrint('❌ Error loading payment settings from backend: $e');
          }

          // ✅ Cache to SharedPreferences
          await prefs.setString('company_name', _companyName);
          await prefs.setString('company_email', _companyEmail);
          await prefs.setString('company_phone', _companyPhone);
          await prefs.setString('company_address', _companyAddress);

          // ✅ Cache currency settings
          await prefs.setString('currency_symbol', _currencySymbol);
          await prefs.setString('currency_position', _currencyPosition);
          await prefs.setString('decimal_separator', _decimalSeparator);
          await prefs.setString('thousands_separator', _thousandsSeparator);
          await prefs.setInt('decimal_places', _decimalPlaces);

          // ✅ Cache payment settings
          await prefs.setBool(
              'business_payments_enabled', _businessPaymentsEnabled);
          await prefs.setBool('mtn_enabled', _mtnEnabled);
          await prefs.setBool('orange_enabled', _orangeEnabled);
          await prefs.setString('mtn_merchant_phone', _mtnMerchantPhone);
          await prefs.setString('orange_merchant_phone', _orangeMerchantPhone);
          await prefs.setString('mtn_merchant_id', _mtnMerchantId);
          await prefs.setString('orange_merchant_id', _orangeMerchantId);
          await prefs.setBool('mtn_sandbox_mode', _mtnSandboxMode);
          await prefs.setBool('orange_sandbox_mode', _orangeSandboxMode);

          debugPrint(
              '✅ Company-wide settings loaded: Currency=$_currencySymbol');
        }
      } catch (e) {
        debugPrint('❌ Error loading from Supabase: $e');
        _loadLocalSettings(prefs);
      }
    } else {
      _loadLocalSettings(prefs);
    }

    // ============================================================
    // ✅ STEP 2: Load USER-SPECIFIC settings from settings table
    // ============================================================

    if (userId != null && userId.isNotEmpty) {
      try {
        final userSettings = await SupabaseService.getSettings(userId);
        if (userSettings != null) {
          debugPrint('✅ Loaded user-specific settings');
          final themeModeIndex = userSettings['theme_mode'] ?? 0;
          _themeProvider
              .setTheme(themeModeIndex == 1 ? ThemeMode.dark : ThemeMode.light);

          _primaryColor = userSettings['primary_color'] ?? '#667EEA';
          final newColor =
              Color(int.parse(_primaryColor.replaceFirst('#', '0xFF')));
          _themeProvider.setPrimaryColor(newColor);

          _compactMode = userSettings['compact_mode'] ?? false;
          _themeProvider.setCompactMode(_compactMode);

          _showNotifications = userSettings['show_notifications'] ?? true;
          _autoSync = userSettings['auto_sync'] ?? false;

          debugPrint(
              '✅ User settings loaded: Theme=${themeModeIndex == 1 ? "Dark" : "Light"}');
        }
      } catch (e) {
        debugPrint('❌ Error loading user settings: $e');
        _loadUserSettingsFromPrefs(prefs);
      }
    } else {
      _loadUserSettingsFromPrefs(prefs);
    }

    // ✅ Handle phone number formatting
    final savedPhone = _companyPhone;
    if (savedPhone.isNotEmpty) {
      if (savedPhone.startsWith('+')) {
        final digits = savedPhone.replaceAll(RegExp(r'[^\d]'), '');
        for (final country in _countries) {
          final dialCode = country['dial']!.replaceAll('+', '');
          if (digits.startsWith(dialCode)) {
            _companyPhoneController.text = digits.substring(dialCode.length);
            _selectedCountry = country['code']!;
            _selectedCountryCode = country['dial']!;
            break;
          }
        }
      } else {
        _companyPhoneController.text = savedPhone;
      }
    } else {
      _companyPhoneController.clear();
    }

    // ✅ Update controller values
    _companyNameController.text = _companyName;
    _companyEmailController.text = _companyEmail;
    _companyAddressController.text = _companyAddress;

    // ✅ Set MTN/Orange controller values
    _mtnApiKeyController.text = _mtnApiKey;
    _mtnSecretKeyController.text = _mtnSecretKey;
    _mtnMerchantIdController.text = _mtnMerchantId;
    _mtnMerchantPhoneController.text = _mtnMerchantPhone;
    _orangeApiKeyController.text = _orangeApiKey;
    _orangeSecretKeyController.text = _orangeSecretKey;
    _orangeMerchantIdController.text = _orangeMerchantId;
    _orangeMerchantPhoneController.text = _orangeMerchantPhone;

    setState(() {
      _hasUnsavedChanges = false;
    });

    debugPrint(
        '✅ Settings loaded: Company=$_companyName, Currency=$_currencySymbol');

    if (mounted) setState(() => _isLoading = false);
    debugPrint('📂 ===== LOAD COMPLETE =====');
  }

  // ✅ Helper: Load user settings from SharedPreferences
  void _loadUserSettingsFromPrefs(SharedPreferences prefs) {
    final themeModeIndex = prefs.getInt('theme_mode') ?? 0;
    _themeProvider
        .setTheme(themeModeIndex == 1 ? ThemeMode.dark : ThemeMode.light);
    _primaryColor = prefs.getString('primary_color') ?? '#667EEA';
    final newColor = Color(int.parse(_primaryColor.replaceFirst('#', '0xFF')));
    _themeProvider.setPrimaryColor(newColor);
    _compactMode = prefs.getBool('compact_mode') ?? false;
    _themeProvider.setCompactMode(_compactMode);
    _showNotifications = prefs.getBool('show_notifications') ?? true;
    _autoSync = prefs.getBool('auto_sync') ?? false;
  }

  // ✅ Helper: Load local settings (fallback)
  void _loadLocalSettings(SharedPreferences prefs) {
    _companyName = prefs.getString('company_name') ?? 'Drink Quick Cal';
    _companyEmail = prefs.getString('company_email') ?? '';
    _companyPhone = prefs.getString('company_phone') ?? '';
    _companyAddress = prefs.getString('company_address') ?? '';
    _currencySymbol = prefs.getString('currency_symbol') ?? 'Frs';
    _currencyPosition = prefs.getString('currency_position') ?? 'right';
    _decimalSeparator = prefs.getString('decimal_separator') ?? '.';
    _thousandsSeparator = prefs.getString('thousands_separator') ?? ',';
    _decimalPlaces = prefs.getInt('decimal_places') ?? 0;
    _businessPaymentsEnabled =
        prefs.getBool('business_payments_enabled') ?? false;
    _mtnEnabled = prefs.getBool('mtn_enabled') ?? true;
    _orangeEnabled = prefs.getBool('orange_enabled') ?? true;
    _mtnMerchantPhone = prefs.getString('mtn_merchant_phone') ?? '';
    _orangeMerchantPhone = prefs.getString('orange_merchant_phone') ?? '';
    _mtnMerchantId = prefs.getString('mtn_merchant_id') ?? '';
    _orangeMerchantId = prefs.getString('orange_merchant_id') ?? '';
    _mtnSandboxMode = prefs.getBool('mtn_sandbox_mode') ?? true;
    _orangeSandboxMode = prefs.getBool('orange_sandbox_mode') ?? true;
    _mtnApiKey = prefs.getString('mtn_api_key') ?? '';
    _mtnSecretKey = prefs.getString('mtn_secret_key') ?? '';
    _orangeApiKey = prefs.getString('orange_api_key') ?? '';
    _orangeSecretKey = prefs.getString('orange_secret_key') ?? '';
  }

  void _markUnsaved() {
    setState(() {
      _hasUnsavedChanges = true;
    });
  }

  // ============================================================
  // ✅ SAVE SETTINGS - Company-Wide + User-Specific
  // ============================================================
  Future<void> _saveAllSettings() async {
    if (mounted) setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final companyId = authProvider.currentUser?.companyId;
    final userId = authProvider.currentUser?.id;

    debugPrint('💾 ===== SAVING SETTINGS =====');
    debugPrint('🏢 Company ID: $companyId');
    debugPrint('👤 User ID: $userId');

    // ============================================================
    // ✅ STEP 1: Save COMPANY-WIDE settings to companies table
    // ============================================================

    if (companyId != null) {
      try {
        // ✅ Company info + currency (non-secret) -> Supabase companies table
        final companyUpdate = {
          // Company info
          'name': _companyName,
          'email': _companyEmail,
          'phone': _companyPhone,
          'address': _companyAddress,

          // ✅ COMPANY-WIDE CURRENCY SETTINGS
          'currency_symbol': _currencySymbol,
          'currency_position': _currencyPosition,
          'decimal_separator': _decimalSeparator,
          'thousands_separator': _thousandsSeparator,
          'decimal_places': _decimalPlaces,

          // ✅ COMPANY-WIDE PAYMENT SETTINGS (non-secret only)
          'business_payments_enabled': _businessPaymentsEnabled,
          'mtn_enabled': _mtnEnabled,
          'orange_enabled': _orangeEnabled,
          'mtn_merchant_phone': _mtnMerchantPhone,
          'orange_merchant_phone': _orangeMerchantPhone,
          'mtn_merchant_id': _mtnMerchantId,
          'orange_merchant_id': _orangeMerchantId,
          'mtn_sandbox_mode': _mtnSandboxMode,
          'orange_sandbox_mode': _orangeSandboxMode,

          'updated_at': DateTime.now().toIso8601String(),
        };

        final success =
            await SupabaseService.saveCompanyPaymentSettings(companyUpdate);
        if (success) {
          debugPrint('✅✅✅ COMPANY-WIDE settings saved (currency + payment)');
        } else {
          debugPrint('❌❌❌ Failed to save company settings');
        }

        // ✅ Send payment secrets (api/secret keys) ONLY to the backend
        try {
          final paymentSecrets = {
            'businessPaymentsEnabled': _businessPaymentsEnabled,
            'mtnEnabled': _mtnEnabled,
            'orangeEnabled': _orangeEnabled,
            'mtnMerchantPhone': _mtnMerchantPhone,
            'orangeMerchantPhone': _orangeMerchantPhone,
            'mtnApiKey': _mtnApiKey,
            'mtnSecretKey': _mtnSecretKey,
            'mtnMerchantId': _mtnMerchantId,
            'mtnSandboxMode': _mtnSandboxMode,
            'orangeApiKey': _orangeApiKey,
            'orangeSecretKey': _orangeSecretKey,
            'orangeMerchantId': _orangeMerchantId,
            'orangeSandboxMode': _orangeSandboxMode,
          };
          final secretsSaved =
              await PaymentService.updateCompanyPaymentSettings(paymentSecrets);
          debugPrint(
              '🔐 Payment secrets saved to backend: $secretsSaved');
        } catch (e) {
          debugPrint('❌ Error saving payment secrets to backend: $e');
        }
      } catch (e) {
        debugPrint('❌❌❌ Error saving company settings: $e');
      }
    }

    // ============================================================
    // ✅ STEP 2: Save USER-SPECIFIC settings to settings table
    // ============================================================

    if (userId != null && userId.isNotEmpty) {
      try {
        final settingsData = {
          'user_id': userId,
          'company_id': companyId,
          'theme_mode': _themeProvider.themeMode == ThemeMode.dark ? 1 : 0,
          'primary_color': _primaryColor,
          'compact_mode': _compactMode,
          'show_notifications': _showNotifications,
          'auto_sync': _autoSync,
          'company_name': _companyName,
          'company_email': _companyEmail,
          'company_phone': _companyPhone,
          'company_address': _companyAddress,
          'updated_at': DateTime.now().toIso8601String(),
        };

        await SupabaseService.saveSettings(settingsData);
        debugPrint('✅ User-specific settings saved');
      } catch (e) {
        debugPrint('❌ Error saving user settings: $e');
      }
    }

    // ============================================================
    // ✅ STEP 3: Save to SharedPreferences (local cache)
    // ============================================================

    // Company info
    await prefs.setString('company_name', _companyName);
    await prefs.setString('company_email', _companyEmail);
    _companyPhone = _getFullPhoneNumber();
    await prefs.setString('company_phone', _companyPhone);
    await prefs.setString('company_address', _companyAddress);

    // ✅ Currency (company-wide)
    await prefs.setString('currency_symbol', _currencySymbol);
    await prefs.setString('currency_position', _currencyPosition);
    await prefs.setString('decimal_separator', _decimalSeparator);
    await prefs.setString('thousands_separator', _thousandsSeparator);
    await prefs.setInt('decimal_places', _decimalPlaces);

    // Payment settings (company-wide)
    await prefs.setBool('business_payments_enabled', _businessPaymentsEnabled);
    await prefs.setBool('mtn_enabled', _mtnEnabled);
    await prefs.setBool('orange_enabled', _orangeEnabled);
    await prefs.setString('mtn_merchant_phone', _mtnMerchantPhone);
    await prefs.setString('orange_merchant_phone', _orangeMerchantPhone);
    await prefs.setString('mtn_merchant_id', _mtnMerchantId);
    await prefs.setString('orange_merchant_id', _orangeMerchantId);
    await prefs.setBool('mtn_sandbox_mode', _mtnSandboxMode);
    await prefs.setBool('orange_sandbox_mode', _orangeSandboxMode);

    // 🔐 Secrets (api/secret keys) are NOT stored locally — backend only.
    // Remove any previously cached values.
    if (userId != null && userId.isNotEmpty) {
      await SecureStorageService.deleteEncryptedApiKey(
        userId: userId,
        key: 'mtn_api_key',
      );
      await SecureStorageService.deleteEncryptedApiKey(
        userId: userId,
        key: 'mtn_secret_key',
      );
      await SecureStorageService.deleteEncryptedApiKey(
        userId: userId,
        key: 'orange_api_key',
      );
      await SecureStorageService.deleteEncryptedApiKey(
        userId: userId,
        key: 'orange_secret_key',
      );
    }
    await prefs.remove('mtn_api_key');
    await prefs.remove('mtn_secret_key');
    await prefs.remove('orange_api_key');
    await prefs.remove('orange_secret_key');

    // User-specific settings
    await prefs.setInt(
        'theme_mode', _themeProvider.themeMode == ThemeMode.dark ? 1 : 0);
    await prefs.setString('primary_color', _primaryColor);
    await prefs.setBool('compact_mode', _compactMode);
    await prefs.setBool('show_notifications', _showNotifications);
    await prefs.setBool('auto_sync', _autoSync);

    debugPrint('✅ All settings cached locally');

    // ✅ Refresh CurrencyHelper (now company-wide)
    await CurrencyHelper.refresh();
    await PaymentHelper.refresh();

    setState(() {
      _hasUnsavedChanges = false;
    });

    if (mounted) setState(() => _isLoading = false);

    if (mounted) {
      appKey.currentState?.refreshTheme();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(child: Text('All settings saved successfully!')),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    debugPrint('💾 ===== SAVE COMPLETE =====');
  }

  // ============================================================
  // Helper Methods
  // ============================================================

  Future<void> _testMtnConnection() async {
    setState(() {
      _testingMtn = true;
      _mtnTestResult = null;
    });

    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _testingMtn = false;
      if (_mtnApiKey.isEmpty ||
          _mtnSecretKey.isEmpty ||
          _mtnMerchantId.isEmpty ||
          _mtnMerchantPhone.isEmpty) {
        _mtnTestResult = 'failed';
      } else {
        _mtnTestResult = 'success';
      }
    });

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _mtnTestResult = null;
        });
      }
    });
  }

  Future<void> _testOrangeConnection() async {
    setState(() {
      _testingOrange = true;
      _orangeTestResult = null;
    });

    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _testingOrange = false;
      if (_orangeApiKey.isEmpty ||
          _orangeSecretKey.isEmpty ||
          _orangeMerchantId.isEmpty ||
          _orangeMerchantPhone.isEmpty) {
        _orangeTestResult = 'failed';
      } else {
        _orangeTestResult = 'success';
      }
    });

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _orangeTestResult = null;
        });
      }
    });
  }

  String _formatPhoneNumber(String phone, String countryCode) {
    if (phone.isEmpty) return '';
    String digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    final dialCode = _selectedCountryCode.replaceAll('+', '');
    if (digits.startsWith(dialCode)) {
      digits = digits.substring(dialCode.length);
    }
    switch (countryCode) {
      case 'CM':
        if (digits.length >= 9)
          return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6, 9)}';
        if (digits.length >= 6)
          return '${digits.substring(0, 3)} ${digits.substring(3)}';
        if (digits.length >= 3) return digits.substring(0, 3);
        break;
      case 'NG':
        if (digits.length >= 10)
          return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
        if (digits.length >= 6)
          return '${digits.substring(0, 3)} ${digits.substring(3)}';
        if (digits.length >= 3) return digits.substring(0, 3);
        break;
      default:
        final buffer = StringBuffer();
        for (int i = 0; i < digits.length; i++) {
          if (i > 0 && i % 3 == 0) buffer.write(' ');
          buffer.write(digits[i]);
        }
        return buffer.toString();
    }
    return digits;
  }

  String _getFullPhoneNumber() {
    final digits =
        _companyPhoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return '';
    return '$_selectedCountryCode$digits';
  }

  Future<void> _discardChanges() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Changes'),
        content:
            const Text('Are you sure you want to discard all unsaved changes?'),
        backgroundColor: Theme.of(context).cardColor,
        titleTextStyle: TextStyle(
          color: Theme.of(context).textTheme.bodyLarge?.color,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: TextStyle(color: Theme.of(context).hintColor),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _loadAllSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Changes discarded'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  String _formatCurrencyPreview(double amount) {
    String formattedNumber;

    if (_decimalPlaces == 0) {
      formattedNumber = amount.toInt().toString();
    } else {
      formattedNumber = amount.toStringAsFixed(_decimalPlaces);
    }

    final parts = formattedNumber.split(_decimalSeparator);
    parts[0] = _addThousandsSeparators(parts[0]);
    formattedNumber = parts.join(_decimalSeparator);

    if (_currencyPosition == 'left') {
      return '$_currencySymbol$formattedNumber';
    } else {
      return '$formattedNumber$_currencySymbol';
    }
  }

  String _addThousandsSeparators(String number) {
    if (_thousandsSeparator.isEmpty) return number;

    final buffer = StringBuffer();
    for (int i = 0; i < number.length; i++) {
      if (i > 0 && (number.length - i) % 3 == 0) {
        buffer.write(_thousandsSeparator);
      }
      buffer.write(number[i]);
    }
    return buffer.toString();
  }

  // ============================================================
  // ✅ BUILD METHOD - WITH LOADING INDICATOR
  // ============================================================
  @override
  Widget build(BuildContext context) {
    // ✅ Show loading spinner while loading
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Loading settings...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // ✅ Show actual content when loaded
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final theme = Theme.of(context);
        final primaryColorValue =
            Color(int.parse(_primaryColor.replaceFirst('#', '0xFF')));
        final primaryColorLight = primaryColorValue.withValues(alpha: 0.1);
        final primaryColorVeryLight = primaryColorValue.withValues(alpha: 0.05);
        final authProvider = Provider.of<AuthProvider>(context);
        final role = authProvider.user?.role.toLowerCase() ?? '';
        final isStaff = role == 'staff';
        final isAdmin = role == 'administrator' || role == 'admin';
        final isManager = role == 'manager';
        final isCustomer = role == 'customer';
        final canSeePaymentSettings = !isStaff;
        final canSeeDataManagement = !isStaff;

        return GestureDetector(
          onTap: () => LockService().resetTimer(),
          onPanDown: (_) => LockService().resetTimer(),
          onScaleStart: (_) => LockService().resetTimer(),
          onLongPress: () => LockService().resetTimer(),
          behavior: HitTestBehavior.translucent,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Settings'),
              foregroundColor: Colors.white,
              backgroundColor: primaryColorValue,
              elevation: 4,
              actions: [
                if (_hasUnsavedChanges)
                  TextButton.icon(
                    onPressed: _discardChanges,
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 20),
                    label: const Text('Discard',
                        style: TextStyle(color: Colors.white)),
                  ),
              ],
            ),
            bottomNavigationBar: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    if (_hasUnsavedChanges)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _discardChanges,
                          icon: const Icon(Icons.close, size: 20),
                          label: const Text('Discard'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    if (_hasUnsavedChanges) const SizedBox(width: 12),
                    Expanded(
                      flex: _hasUnsavedChanges ? 2 : 1,
                      child: ElevatedButton.icon(
                        onPressed: _saveAllSettings,
                        icon: Icon(
                          _hasUnsavedChanges ? Icons.save : Icons.check_circle,
                          size: 20,
                        ),
                        label: Text(
                          _hasUnsavedChanges ? 'Save All Changes' : 'Saved',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _hasUnsavedChanges ? Colors.green : Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: theme.brightness == Brightness.dark
                      ? [Colors.grey[900]!, Colors.grey[800]!]
                      : [Colors.grey[50]!, Colors.white],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLivePreviewCard(theme, primaryColorValue,
                        primaryColorVeryLight, primaryColorLight),
                    const SizedBox(height: 20),
                    _buildThemeAppearanceCard(theme, primaryColorValue),
                    const SizedBox(height: 20),
                    _buildCurrencySettingsCard(theme, primaryColorValue),
                    const SizedBox(height: 20),
                    _buildCompanyInfoCard(theme, primaryColorValue),
                    const SizedBox(height: 20),
                    if (!isStaff) ...[
                      _buildBusinessPaymentSettingsCard(
                          theme, primaryColorValue),
                      const SizedBox(height: 20),
                    ],
                    if (canSeePaymentSettings) ...[
                      _buildStorageStatsCard(theme),
                      const SizedBox(height: 20),
                    ],
                    _buildBackupManagementCard(theme, primaryColorValue),
                    const SizedBox(height: 20),
                    _buildSyncSettingsCard(theme, primaryColorValue),
                    const SizedBox(height: 20),
                    if (canSeeDataManagement) ...[
                      _buildDataManagementCard(theme),
                      const SizedBox(height: 20),
                    ],
                    _buildInformationCard(theme),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // Theme Appearance Card
  // ============================================================
  Widget _buildThemeAppearanceCard(ThemeData theme, Color primaryColorValue) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final currentTheme = themeProvider.themeMode;

        return Card(
          elevation: 2,
          color: theme.cardColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.palette, size: 20),
                    SizedBox(width: 8),
                    Text('Theme & Appearance',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Theme Mode',
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: theme.textTheme.bodyLarge?.color)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildThemeOption(
                      Icons.light_mode,
                      'Light',
                      ThemeMode.light,
                      theme,
                      primaryColorValue,
                      currentTheme == ThemeMode.light,
                      () {
                        themeProvider.setTheme(ThemeMode.light);
                        _markUnsaved();
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildThemeOption(
                      Icons.dark_mode,
                      'Dark',
                      ThemeMode.dark,
                      theme,
                      primaryColorValue,
                      currentTheme == ThemeMode.dark,
                      () {
                        themeProvider.setTheme(ThemeMode.dark);
                        _markUnsaved();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Primary Color',
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: theme.textTheme.bodyLarge?.color)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _availableColors.map((color) {
                    final isSelected = _primaryColor == color['code'];
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _primaryColor = color['code'];
                          final newColor = Color(int.parse(
                              color['code'].replaceFirst('#', '0xFF')));
                          themeProvider.setPrimaryColor(newColor);
                          _markUnsaved();
                        });
                      },
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color['color'],
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(
                                      color: theme.brightness == Brightness.dark
                                          ? Colors.white
                                          : Colors.black,
                                      width: 3)
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 4)
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            color['name'],
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? primaryColorValue
                                    : theme.hintColor),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: Text('Compact Mode',
                      style:
                          TextStyle(color: theme.textTheme.bodyLarge?.color)),
                  subtitle: Text(
                      'Reduce spacing and font sizes for more content',
                      style: TextStyle(color: theme.hintColor)),
                  value: _compactMode,
                  onChanged: (value) {
                    setState(() {
                      _compactMode = value;
                      themeProvider.setCompactMode(value);
                      _markUnsaved();
                    });
                  },
                  activeTrackColor: primaryColorValue.withValues(alpha: 0.5),
                  inactiveThumbColor: theme.hintColor,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // Theme Option
  // ============================================================
  Widget _buildThemeOption(
    IconData icon,
    String label,
    ThemeMode mode,
    ThemeData theme,
    Color primaryColorValue,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? primaryColorValue.withValues(alpha: 0.1) : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: isSelected ? primaryColorValue : theme.dividerColor,
                width: isSelected ? 2 : 1),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isSelected ? primaryColorValue : theme.hintColor,
                  size: 24),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? primaryColorValue : theme.hintColor,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal)),
              if (isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: primaryColorValue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w500),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Currency Settings Card
  // ============================================================
  Widget _buildCurrencySettingsCard(ThemeData theme, Color primaryColorValue) {
    final authProvider = Provider.of<AuthProvider>(context);
    final role = authProvider.user?.role.toLowerCase() ?? '';
    final isManager =
        role == 'manager' || role == 'administrator' || role == 'admin';
    final isStaff = role == 'staff';
    final isDark = theme.brightness == Brightness.dark;

    // ✅ Staff sees read-only version with dark theme support
    if (isStaff) {
      return Card(
        elevation: 2,
        color: theme.cardColor, // ✅ Dark: dark grey, Light: white
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.attach_money,
                    size: 20,
                    // ✅ Dark: light grey, Light: grey
                    color: isDark ? Colors.grey.shade400 : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Currency Settings',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        // ✅ Dark: white, Light: black
                        color: theme.textTheme.bodyLarge?.color ?? Colors.black,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      // ✅ Dark: darker grey, Light: light grey
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Read Only',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        // ✅ Dark: light grey, Light: dark grey
                        color: isDark
                            ? Colors.grey.shade300
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Currency settings are managed by your company manager.',
                style: TextStyle(
                  fontSize: 12,
                  // ✅ Dark: lighter grey, Light: grey
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              // ✅ All fields now support dark theme
              _buildReadOnlyField('Currency Symbol', _currencySymbol),
              const SizedBox(height: 12),
              _buildReadOnlyField(
                'Currency Position',
                _currencyPosition == 'left' ? 'Left (\$100)' : 'Right (100Frs)',
              ),
              const SizedBox(height: 12),
              _buildReadOnlyField('Number Format', _getNumberFormatDisplay()),
            ],
          ),
        ),
      );
    }

    // ✅ Manager/Admin sees editable version with dark theme support
    return Card(
      elevation: 2,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.attach_money, size: 20, color: primaryColorValue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Currency Settings',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Company-Wide',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'All staff will use these currency settings.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            // ✅ Dropdown with dark theme support
            DropdownButtonFormField<String>(
              value: _currencySymbol,
              decoration: InputDecoration(
                labelText: 'Currency Symbol',
                labelStyle: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(Icons.attach_money, color: primaryColorValue),
              ),
              dropdownColor: isDark ? Colors.grey.shade800 : Colors.white,
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color ?? Colors.black,
              ),
              items: _availableCurrencies.map((currency) {
                return DropdownMenuItem(
                  value: currency['symbol'],
                  child: Text('${currency['symbol']} - ${currency['name']}'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _currencySymbol = value;
                    _markUnsaved();
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Currency Position',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildRadioOption(
                    'Left (\$100)',
                    _currencyPosition == 'left',
                    () {
                      setState(() {
                        _currencyPosition = 'left';
                        _markUnsaved();
                      });
                    },
                    theme,
                    primaryColorValue,
                    true,
                  ),
                ),
                Expanded(
                  child: _buildRadioOption(
                    'Right (100Frs)',
                    _currencyPosition == 'right',
                    () {
                      setState(() {
                        _currencyPosition = 'right';
                        _markUnsaved();
                      });
                    },
                    theme,
                    primaryColorValue,
                    true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Number Format',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildRadioOption(
                    '0 (1,234)',
                    _decimalPlaces == 0 && _thousandsSeparator == ',',
                    () {
                      setState(() {
                        _decimalPlaces = 0;
                        _thousandsSeparator = ',';
                        _decimalSeparator = '.';
                        _markUnsaved();
                      });
                    },
                    theme,
                    primaryColorValue,
                    true,
                  ),
                ),
                Expanded(
                  child: _buildRadioOption(
                    '0.00 (1,234.00)',
                    _decimalPlaces == 2 && _thousandsSeparator == ',',
                    () {
                      setState(() {
                        _decimalPlaces = 2;
                        _thousandsSeparator = ',';
                        _decimalSeparator = '.';
                        _markUnsaved();
                      });
                    },
                    theme,
                    primaryColorValue,
                    true,
                  ),
                ),
                Expanded(
                  child: _buildRadioOption(
                    '0,00 (1.234,00)',
                    _decimalPlaces == 2 && _decimalSeparator == ',',
                    () {
                      setState(() {
                        _decimalPlaces = 2;
                        _thousandsSeparator = '.';
                        _decimalSeparator = ',';
                        _markUnsaved();
                      });
                    },
                    theme,
                    primaryColorValue,
                    true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        // ✅ Dark mode: darker background, Light mode: light background
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          // ✅ Dark mode: lighter border, Light mode: darker border
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              // ✅ Dark mode: lighter grey, Light mode: darker grey
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          Text(
            value.isNotEmpty ? value : 'Not Set',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              // ✅ Dark mode: white, Light mode: black
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  String _getNumberFormatDisplay() {
    String example = '1234.56';
    String formatted = example;
    if (_decimalPlaces == 0) {
      formatted = '1,234';
    } else if (_decimalPlaces == 2 && _thousandsSeparator == ',') {
      formatted = '1,234.56';
    } else if (_decimalPlaces == 2 && _decimalSeparator == ',') {
      formatted = '1.234,56';
    }
    return formatted;
  }

  // ============================================================
  // Card Builders
  // ============================================================

  Widget _buildLivePreviewCard(ThemeData theme, Color primaryColorValue,
      Color primaryColorVeryLight, Color primaryColorLight) {
    return Card(
      elevation: 4,
      color: primaryColorVeryLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.preview, color: primaryColorValue),
                const SizedBox(width: 8),
                Text(
                  'Live Preview',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: primaryColorValue,
                  ),
                ),
                const Spacer(),
                if (_hasUnsavedChanges)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Unsaved',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: primaryColorValue.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    _companyName.isNotEmpty
                        ? _companyName
                        : 'Your Company Name',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryColorValue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_companyEmail.isNotEmpty)
                    Text(_companyEmail,
                        style: TextStyle(fontSize: 12, color: theme.hintColor)),
                  if (_companyPhone.isNotEmpty)
                    Text(_companyPhone,
                        style: TextStyle(fontSize: 12, color: theme.hintColor)),
                  if (_companyAddress.isNotEmpty)
                    Text(_companyAddress,
                        style: TextStyle(fontSize: 12, color: theme.hintColor)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColorLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Sample Drink',
                            style: TextStyle(
                                color: theme.textTheme.bodyLarge?.color)),
                        Text(
                          _formatCurrencyPreview(1500),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: primaryColorValue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColorLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Amount',
                            style: TextStyle(
                                color: theme.textTheme.bodyLarge?.color)),
                        Text(
                          _formatCurrencyPreview(12500),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: primaryColorValue,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

// ============================================================
// ✅ COMPLETE: Company Information Card with Role-Based Access
// ============================================================
  Widget _buildCompanyInfoCard(ThemeData theme, Color primaryColorValue) {
    final authProvider = Provider.of<AuthProvider>(context);
    final role = authProvider.user?.role.toLowerCase() ?? '';
    final isManager =
        role == 'manager' || role == 'administrator' || role == 'admin';
    final isStaff = role == 'staff';
    final isDark = theme.brightness == Brightness.dark;

    // ✅ Staff sees read-only version
    if (isStaff) {
      return Card(
        elevation: 2,
        color: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.business,
                      size: 20,
                      color: isDark ? Colors.grey.shade400 : Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Company Information',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: theme.textTheme.bodyLarge?.color ?? Colors.black,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Read Only',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.grey.shade300
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Company information is managed by your company manager.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              // ✅ Read-only fields for Staff
              _buildReadOnlyField('Company Name', _companyName),
              const SizedBox(height: 12),
              _buildReadOnlyField('Country', _selectedCountry),
              const SizedBox(height: 12),
              _buildReadOnlyField('Phone Number', _companyPhone),
              const SizedBox(height: 12),
              _buildReadOnlyField('Email Address', _companyEmail),
              const SizedBox(height: 12),
              _buildReadOnlyField('Address',
                  _companyAddress.isNotEmpty ? _companyAddress : 'Not set'),
            ],
          ),
        ),
      );
    }

    // ✅ Manager/Admin sees editable version
    return Card(
      elevation: 2,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.business, size: 20),
                SizedBox(width: 8),
                Text(
                  'Company Information',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ✅ Company Name - Editable
            TextField(
              controller: _companyNameController,
              decoration: InputDecoration(
                labelText: 'Company Name',
                labelStyle: TextStyle(color: theme.hintColor),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primaryColorValue, width: 2),
                ),
                prefixIcon: Icon(Icons.business, color: primaryColorValue),
                filled: true,
                fillColor: theme.cardColor,
              ),
              style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              onChanged: (value) {
                setState(() {
                  _companyName = value;
                  _markUnsaved();
                });
              },
            ),
            const SizedBox(height: 12),
            // ✅ Country - Editable
            DropdownButtonFormField<String>(
              value: _selectedCountry,
              decoration: InputDecoration(
                labelText: 'Country',
                labelStyle: TextStyle(color: theme.hintColor),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primaryColorValue, width: 2),
                ),
                prefixIcon: Icon(Icons.public, color: primaryColorValue),
                filled: true,
                fillColor: theme.cardColor,
              ),
              dropdownColor: theme.cardColor,
              style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              items: _countries.map((country) {
                return DropdownMenuItem<String>(
                  value: country['code'],
                  child: Row(
                    children: [
                      Text(country['flag']!,
                          style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text('${country['name']} (${country['dial']})'),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedCountry = value;
                    final country =
                        _countries.firstWhere((c) => c['code'] == value);
                    _selectedCountryCode = country['dial']!;
                    _markUnsaved();
                  });
                }
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Format: ${_countries.firstWhere((c) => c['code'] == _selectedCountry)['format']}',
              style: TextStyle(
                fontSize: 11,
                color: theme.hintColor,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
            // ✅ Phone Number - Editable
            TextFormField(
              controller: _companyPhoneController,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                hintText: _countries
                    .firstWhere((c) => c['code'] == _selectedCountry)['format'],
                labelStyle: TextStyle(color: theme.hintColor),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primaryColorValue, width: 2),
                ),
                prefixIcon: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Text(
                    _selectedCountryCode,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryColorValue,
                      fontSize: 14,
                    ),
                  ),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
                filled: true,
                fillColor: theme.cardColor,
              ),
              style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              keyboardType: TextInputType.phone,
              onChanged: (value) {
                setState(() {
                  _companyPhone = _getFullPhoneNumber();
                  _markUnsaved();

                  final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                  if (_selectedCountry == 'CM' &&
                      digits.length == 9 &&
                      digits.startsWith('6')) {
                    _showValidMessage = true;
                    _validMessageTimer?.cancel();
                    _validMessageTimer = Timer(const Duration(seconds: 3), () {
                      if (mounted) setState(() => _showValidMessage = false);
                    });
                  } else if (_selectedCountry == 'NG' && digits.length == 10) {
                    _showValidMessage = true;
                    _validMessageTimer?.cancel();
                    _validMessageTimer = Timer(const Duration(seconds: 3), () {
                      if (mounted) setState(() => _showValidMessage = false);
                    });
                  } else {
                    _showValidMessage = false;
                  }
                });
              },
              onFieldSubmitted: (value) {
                final formatted = _formatPhoneNumber(value, _selectedCountry);
                if (formatted != value) {
                  _companyPhoneController.text = formatted;
                  _companyPhoneController.selection =
                      TextSelection.collapsed(offset: formatted.length);
                }
              },
            ),
            const SizedBox(height: 12),
            // ✅ Phone validation message
            Builder(
              builder: (context) {
                final digits = _companyPhoneController.text
                    .replaceAll(RegExp(r'[^\d]'), '');
                if (digits.isEmpty) return const SizedBox.shrink();

                String? warning;
                if (_selectedCountry == 'CM') {
                  if (digits.isNotEmpty && !digits.startsWith('6')) {
                    warning = 'Cameroon numbers must start with 6';
                  } else if (digits.length != 9) {
                    warning =
                        'Cameroon numbers must be 9 digits (currently ${digits.length})';
                  }
                } else if (_selectedCountry == 'NG') {
                  if (digits.length != 10) {
                    warning =
                        'Nigeria numbers must be 10 digits (currently ${digits.length})';
                  }
                }

                if (warning != null) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber,
                            color: Colors.orange, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            warning,
                            style: const TextStyle(
                                color: Colors.orange, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  );
                } else if (_showValidMessage && digits.length >= 7) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 14),
                        const SizedBox(width: 6),
                        const Text(
                          'Valid phone number',
                          style: TextStyle(color: Colors.green, fontSize: 11),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            // ✅ Email Address - Editable
            TextField(
              controller: _companyEmailController,
              decoration: InputDecoration(
                labelText: 'Email Address',
                labelStyle: TextStyle(color: theme.hintColor),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primaryColorValue, width: 2),
                ),
                prefixIcon: Icon(Icons.email, color: primaryColorValue),
                filled: true,
                fillColor: theme.cardColor,
              ),
              style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              keyboardType: TextInputType.emailAddress,
              onChanged: (value) {
                setState(() {
                  _companyEmail = value;
                  _markUnsaved();
                });
              },
            ),
            const SizedBox(height: 12),
            // ✅ Address - Editable
            TextField(
              controller: _companyAddressController,
              decoration: InputDecoration(
                labelText: 'Address',
                labelStyle: TextStyle(color: theme.hintColor),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primaryColorValue, width: 2),
                ),
                prefixIcon: Icon(Icons.location_on, color: primaryColorValue),
                filled: true,
                fillColor: theme.cardColor,
              ),
              style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              maxLines: 2,
              onChanged: (value) {
                setState(() {
                  _companyAddress = value;
                  _markUnsaved();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Business Payment Settings Card
  // ============================================================
  Widget _buildBusinessPaymentSettingsCard(
      ThemeData theme, Color primaryColorValue) {
    final authProvider = Provider.of<AuthProvider>(context);
    final role = authProvider.user?.role.toLowerCase() ?? '';
    final isManager =
        role == 'manager' || role == 'administrator' || role == 'admin';
    final isStaff = role == 'staff';

    if (isStaff) {
      return Card(
        elevation: 2,
        color: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.payment, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Business Payment Settings',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Read Only',
                      style:
                          TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Payment settings are managed by your company manager.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.hintColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              _buildReadOnlySwitch(
                  'Enable Business Payments', _businessPaymentsEnabled),
              const SizedBox(height: 8),
              _buildReadOnlySwitch('MTN Mobile Money', _mtnEnabled),
              const SizedBox(height: 8),
              _buildReadOnlySwitch('Orange Money', _orangeEnabled),
            ],
          ),
        ),
      );
    }

    // ✅ Manager can edit
    return Card(
      elevation: 2,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, size: 20, color: primaryColorValue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Business Payment Settings',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Company-Wide',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.orange),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'All staff will use these payment settings.',
              style: TextStyle(
                fontSize: 12,
                color: theme.hintColor,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text('Enable Business Payments',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodyLarge?.color)),
              subtitle: Text('Allow customers to pay via Mobile Money',
                  style: TextStyle(color: theme.hintColor)),
              value: _businessPaymentsEnabled,
              onChanged: isManager
                  ? (value) {
                      setState(() {
                        _businessPaymentsEnabled = value;
                        _markUnsaved();
                      });
                    }
                  : null,
              activeTrackColor: primaryColorValue.withValues(alpha: 0.5),
              inactiveThumbColor: theme.hintColor,
            ),
            if (_businessPaymentsEnabled) ...[
              const Divider(),
              const SizedBox(height: 8),
              // MTN Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFCC00).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFFFCC00).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFCC00),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Center(
                            child: Text(
                              'MTN',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'MTN Mobile Money',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Switch(
                          value: _mtnEnabled,
                          onChanged: isManager
                              ? (value) {
                                  setState(() {
                                    _mtnEnabled = value;
                                    _markUnsaved();
                                  });
                                }
                              : null,
                          activeTrackColor:
                              const Color(0xFFFFCC00).withOpacity(0.5),
                          activeThumbColor: const Color(0xFFFFCC00),
                        ),
                      ],
                    ),
                    if (_mtnEnabled) ...[
                      const SizedBox(height: 12),
                      Text(
                        'This phone number will RECEIVE payments from customers',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.hintColor,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _mtnMerchantPhoneController,
                        decoration: InputDecoration(
                          labelText: 'Your MTN Phone Number (Receives Money)',
                          hintText: 'e.g., 237XXXXXXXXX',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon: Icon(
                            Icons.phone_android,
                            color: const Color(0xFFFFCC00),
                          ),
                        ),
                        keyboardType: TextInputType.phone,
                        onChanged: isManager
                            ? (value) {
                                setState(() {
                                  _mtnMerchantPhone = value;
                                  _markUnsaved();
                                });
                              }
                            : null,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _mtnMerchantIdController,
                        decoration: InputDecoration(
                          labelText: 'Merchant ID',
                          hintText: 'Enter MTN Merchant ID',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon:
                              Icon(Icons.store, color: primaryColorValue),
                        ),
                        onChanged: isManager
                            ? (value) {
                                setState(() {
                                  _mtnMerchantId = value;
                                  _markUnsaved();
                                });
                              }
                            : null,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _mtnApiKeyController,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          hintText: 'Enter MTN API Key',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon:
                              Icon(Icons.vpn_key, color: primaryColorValue),
                        ),
                        obscureText: true,
                        onChanged: isManager
                            ? (value) {
                                setState(() {
                                  _mtnApiKey = value;
                                  _markUnsaved();
                                });
                              }
                            : null,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _mtnSecretKeyController,
                        decoration: InputDecoration(
                          labelText: 'Secret Key',
                          hintText: 'Enter MTN Secret Key',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon:
                              Icon(Icons.lock, color: primaryColorValue),
                        ),
                        obscureText: true,
                        onChanged: isManager
                            ? (value) {
                                setState(() {
                                  _mtnSecretKey = value;
                                  _markUnsaved();
                                });
                              }
                            : null,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Sandbox Mode'),
                        subtitle:
                            const Text('Use test environment for development'),
                        value: _mtnSandboxMode,
                        onChanged: isManager
                            ? (value) {
                                setState(() {
                                  _mtnSandboxMode = value;
                                  _markUnsaved();
                                });
                              }
                            : null,
                        activeColor: Colors.orange,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _testingMtn ? null : _testMtnConnection,
                          icon: _testingMtn
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _mtnTestResult == 'success'
                                      ? Icons.check_circle
                                      : _mtnTestResult == 'failed'
                                          ? Icons.error
                                          : Icons.wifi_tethering,
                                  size: 18,
                                ),
                          label: Text(_testingMtn
                              ? 'Testing Connection...'
                              : _mtnTestResult == 'success'
                                  ? 'Connection Successful'
                                  : _mtnTestResult == 'failed'
                                      ? 'Connection Failed'
                                      : 'Test MTN Connection'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _mtnTestResult == 'success'
                                ? Colors.green
                                : _mtnTestResult == 'failed'
                                    ? Colors.red
                                    : const Color(0xFFFFCC00),
                            foregroundColor: _mtnTestResult == null
                                ? Colors.black
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Orange Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6600).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFFF6600).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6600),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Center(
                            child: Text(
                              'OM',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Orange Money',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Switch(
                          value: _orangeEnabled,
                          onChanged: isManager
                              ? (value) {
                                  setState(() {
                                    _orangeEnabled = value;
                                    _markUnsaved();
                                  });
                                }
                              : null,
                          activeColor: const Color(0xFFFF6600),
                        ),
                      ],
                    ),
                    if (_orangeEnabled) ...[
                      const SizedBox(height: 12),
                      Text(
                        'This phone number will RECEIVE payments from customers',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.hintColor,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _orangeMerchantPhoneController,
                        decoration: InputDecoration(
                          labelText:
                              'Your Orange Phone Number (Receives Money)',
                          hintText: 'e.g., 237XXXXXXXXX',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon: Icon(
                            Icons.phone_android,
                            color: const Color(0xFFFF6600),
                          ),
                        ),
                        keyboardType: TextInputType.phone,
                        onChanged: isManager
                            ? (value) {
                                setState(() {
                                  _orangeMerchantPhone = value;
                                  _markUnsaved();
                                });
                              }
                            : null,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _orangeMerchantIdController,
                        decoration: InputDecoration(
                          labelText: 'Merchant ID',
                          hintText: 'Enter Orange Merchant ID',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon:
                              Icon(Icons.store, color: primaryColorValue),
                        ),
                        onChanged: isManager
                            ? (value) {
                                setState(() {
                                  _orangeMerchantId = value;
                                  _markUnsaved();
                                });
                              }
                            : null,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _orangeApiKeyController,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          hintText: 'Enter Orange API Key',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon:
                              Icon(Icons.vpn_key, color: primaryColorValue),
                        ),
                        obscureText: true,
                        onChanged: isManager
                            ? (value) {
                                setState(() {
                                  _orangeApiKey = value;
                                  _markUnsaved();
                                });
                              }
                            : null,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _orangeSecretKeyController,
                        decoration: InputDecoration(
                          labelText: 'Secret Key',
                          hintText: 'Enter Orange Secret Key',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon:
                              Icon(Icons.lock, color: primaryColorValue),
                        ),
                        obscureText: true,
                        onChanged: isManager
                            ? (value) {
                                setState(() {
                                  _orangeSecretKey = value;
                                  _markUnsaved();
                                });
                              }
                            : null,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Sandbox Mode'),
                        subtitle:
                            const Text('Use test environment for development'),
                        value: _orangeSandboxMode,
                        onChanged: isManager
                            ? (value) {
                                setState(() {
                                  _orangeSandboxMode = value;
                                  _markUnsaved();
                                });
                              }
                            : null,
                        activeColor: Colors.orange,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                              _testingOrange ? null : _testOrangeConnection,
                          icon: _testingOrange
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _orangeTestResult == 'success'
                                      ? Icons.check_circle
                                      : _orangeTestResult == 'failed'
                                          ? Icons.error
                                          : Icons.wifi_tethering,
                                  size: 18,
                                ),
                          label: Text(_testingOrange
                              ? 'Testing Connection...'
                              : _orangeTestResult == 'success'
                                  ? 'Connection Successful'
                                  : _orangeTestResult == 'failed'
                                      ? 'Connection Failed'
                                      : 'Test Orange Connection'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _orangeTestResult == 'success'
                                ? Colors.green
                                : _orangeTestResult == 'failed'
                                    ? Colors.red
                                    : const Color(0xFFFF6600),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlySwitch(String label, bool value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              // ✅ Dark mode: white, Light mode: black
              color: theme.textTheme.bodyLarge?.color ?? Colors.black,
              fontSize: 14,
            ),
          ),
          Switch(
            value: value,
            onChanged: null,
            // ✅ Dark mode: lighter grey, Light mode: grey
            activeColor: isDark ? Colors.grey.shade400 : Colors.grey,
            inactiveThumbColor:
                isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            inactiveTrackColor:
                isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Storage Stats Card
  // ============================================================
  Widget _buildStorageStatsCard(ThemeData theme) {
    return Card(
      elevation: 2,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Storage Statistics',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: theme.textTheme.bodyLarge?.color)),
            const SizedBox(height: 16),
            Consumer<DrinkProvider>(
              builder: (context, drinkProvider, child) {
                final stats = drinkProvider.getStorageStats();
                return Column(
                  children: [
                    _buildStatRow(
                        'Custom Drinks', '${stats['drinksCount']}', theme),
                    _buildStatRow(
                        'Order History', '${stats['ordersCount']}', theme),
                    _buildStatRow(
                        'Pending Sync Items', '${stats['pendingSync']}', theme),
                    _buildStatRow(
                        'Available Backups', '${stats['backupCount']}', theme),
                    _buildStatRow(
                      'Last Backup',
                      stats['lastBackup'] != 'Never'
                          ? DateFormat('yyyy-MM-dd HH:mm:ss').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                  int.parse(stats['lastBackup'])))
                          : 'Never',
                      theme,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Backup Management Card
  // ============================================================
  Widget _buildBackupManagementCard(ThemeData theme, Color primaryColorValue) {
    return Card(
      elevation: 2,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Backup Management',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: theme.textTheme.bodyLarge?.color)),
            const SizedBox(height: 12),
            Text(
                'Create regular backups to protect your data from accidental loss.',
                style: TextStyle(color: theme.hintColor)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.backup),
                    label: const Text('Create Backup'),
                    onPressed: () async {
                      final drinkProvider =
                          Provider.of<DrinkProvider>(context, listen: false);
                      await drinkProvider.createBackup();
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Backup created!')));
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColorValue),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore Backup'),
                    onPressed: () async {
                      await _showBackupList(context);
                    },
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Sync Settings Card
  // ============================================================
  Widget _buildSyncSettingsCard(ThemeData theme, Color primaryColorValue) {
    return Card(
      elevation: 2,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sync Settings',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: theme.textTheme.bodyLarge?.color)),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text('Auto Sync',
                  style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
              subtitle: Text('Automatically sync data when online',
                  style: TextStyle(color: theme.hintColor)),
              value: _autoSync,
              onChanged: (value) {
                setState(() {
                  _autoSync = value;
                  _markUnsaved();
                });
              },
              activeTrackColor: primaryColorValue.withValues(alpha: 0.5),
              inactiveThumbColor: theme.hintColor,
            ),
            SwitchListTile(
              title: Text('Show Notifications',
                  style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
              subtitle: Text('Display notifications when sync completes',
                  style: TextStyle(color: theme.hintColor)),
              value: _showNotifications,
              onChanged: (value) {
                setState(() {
                  _showNotifications = value;
                  _markUnsaved();
                });
              },
              activeTrackColor: primaryColorValue.withValues(alpha: 0.5),
              inactiveThumbColor: theme.hintColor,
            ),
            ListTile(
              title: Text('Sync Now',
                  style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
              subtitle: Consumer<DrinkProvider>(
                builder: (context, drinkProvider, child) {
                  final stats = drinkProvider.getStorageStats();
                  return Text('${stats['pendingSync']} items pending',
                      style: TextStyle(color: theme.hintColor));
                },
              ),
              trailing: Consumer<DrinkProvider>(
                builder: (context, drinkProvider, child) {
                  return drinkProvider.isSyncing
                      ? const CircularProgressIndicator()
                      : Icon(Icons.sync, color: primaryColorValue);
                },
              ),
              onTap: () async {
                final drinkProvider =
                    Provider.of<DrinkProvider>(context, listen: false);
                if (!drinkProvider.isSyncing && !drinkProvider.isOffline) {
                  await drinkProvider.forceSync();
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Sync completed!')));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Data Management Card
  // ============================================================
  Widget _buildDataManagementCard(ThemeData theme) {
    return Card(
      elevation: 2,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Data Management',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.red)),
            const SizedBox(height: 12),
            Text('Warning: These actions cannot be undone.',
                style: TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_sweep, color: Colors.red),
                    label: const Text('Clear All Data',
                        style: TextStyle(color: Colors.red)),
                    onPressed: () => _showClearConfirmation(context),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text('Delete All Backups',
                        style: TextStyle(color: Colors.red)),
                    onPressed: () => _showDeleteBackupsConfirmation(context),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Information Card
  // ============================================================
  Widget _buildInformationCard(ThemeData theme) {
    return Card(
      elevation: 2,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Information',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: theme.textTheme.bodyLarge?.color)),
            const SizedBox(height: 10),
            Text(
              '• Data is stored locally on your device\n'
              '• Backups protect against data loss\n'
              '• Sync requires internet connection\n'
              '• Offline operations are queued automatically\n'
              '• Currency changes take effect immediately\n'
              '• Theme changes apply immediately\n'
              '• Business payment settings require valid API credentials\n'
              '• Money transfers FROM customer phone TO your merchant phone',
              style: TextStyle(color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Radio Option Builder
  // ============================================================
  Widget _buildRadioOption(
    String label,
    bool selected,
    VoidCallback onTap,
    ThemeData theme,
    Color primaryColorValue,
    bool enabled,
  ) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? primaryColorValue.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? primaryColorValue : theme.dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
              color: selected ? primaryColorValue : theme.hintColor,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? primaryColorValue : theme.hintColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Stat Row Builder
  // ============================================================
  Widget _buildStatRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: theme.hintColor)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: theme.textTheme.bodyLarge?.color)),
        ],
      ),
    );
  }

  // ============================================================
  // Backup List
  // ============================================================
  Future<void> _showBackupList(BuildContext context) async {
    final theme = Theme.of(context);
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final backups = drinkProvider.getBackupList();

    if (backups.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No backups available')));
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Backup'),
          backgroundColor: theme.cardColor,
          titleTextStyle: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontWeight: FontWeight.bold,
              fontSize: 20),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: backups.length,
              itemBuilder: (context, index) {
                final backupKey = backups[index];
                final timestamp = backupKey.replaceFirst('backup_', '');
                final date =
                    DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: theme.cardColor,
                  child: ListTile(
                    title: Text('Backup ${index + 1}',
                        style:
                            TextStyle(color: theme.textTheme.bodyLarge?.color)),
                    subtitle: Text(
                        DateFormat('yyyy-MM-dd HH:mm:ss').format(date),
                        style: TextStyle(color: theme.hintColor)),
                    trailing: IconButton(
                      icon: const Icon(Icons.restore, color: Colors.green),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _confirmRestore(context, backupKey);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'))
          ],
        );
      },
    );
  }

  Future<void> _confirmRestore(BuildContext context, String backupKey) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Backup'),
        content: const Text('This will replace all current data. Continue?'),
        backgroundColor: theme.cardColor,
        titleTextStyle: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(color: theme.hintColor),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore')),
        ],
      ),
    );

    if (confirmed == true) {
      final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
      await drinkProvider.restoreBackup(backupKey);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully!')));
    }
  }

  Future<void> _showClearConfirmation(BuildContext context) async {
    final theme = Theme.of(context);
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
            'This will delete ALL drinks and orders. This action cannot be undone.'),
        backgroundColor: theme.cardColor,
        titleTextStyle: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(color: theme.hintColor),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context, true);
              await StorageService.clearAllData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All data cleared!')));
                await _loadAllSettings();
              }
            },
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteBackupsConfirmation(BuildContext context) async {
    final theme = Theme.of(context);
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Backups'),
        content: const Text('This will permanently delete ALL backup files.'),
        backgroundColor: theme.cardColor,
        titleTextStyle: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(color: theme.hintColor),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context, true);
              await _deleteAllBackups();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All backups deleted!')));
                await _loadAllSettings();
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAllBackups() async {
    final backupKeys = StorageService.getBackupKeys();
    final prefs = await SharedPreferences.getInstance();
    for (final key in backupKeys) {
      await prefs.remove(key);
    }
  }
}
