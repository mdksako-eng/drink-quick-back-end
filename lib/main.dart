// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/providers/order_provider.dart';
import 'package:drinks_calculator_fixed/screens/auth_screen.dart';
import 'package:drinks_calculator_fixed/screens/calculator_screen.dart';
import 'package:drinks_calculator_fixed/services/storage_service.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:drinks_calculator_fixed/providers/inventory_provider.dart';
import 'package:drinks_calculator_fixed/services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:drinks_calculator_fixed/services/supabase_service.dart';
import 'package:drinks_calculator_fixed/utils/payment_helper.dart';
import 'package:drinks_calculator_fixed/providers/sync_provider.dart';
import 'package:drinks_calculator_fixed/screens/lock_screen.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';
import 'package:drinks_calculator_fixed/widgets/activity_detector.dart';
import 'package:drinks_calculator_fixed/widgets/offline_indicator.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

// Global navigator key for showing dialogs from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ✅ Fixed: Made MyAppState public
final GlobalKey<MyAppState> appKey = GlobalKey<MyAppState>();

// ============================================================
// 🔐 GLOBAL LOCK OVERLAY STATE
// ============================================================
// The LockScreen must cover EVERY screen that exposes user data. A normal
// "home route replaces content" approach does NOT cover pushed routes
// (drinks, inventory, settings, order history, etc.), so we render the lock
// screen as a true top-level overlay above the entire Navigator via
// MaterialApp.builder. AuthWrapper publishes the desired lock state here.
class LockOverlayParams {
  final bool isBackgroundLock;
  final String? sessionTerminatedMessage;
  final String? previousDevice;

  const LockOverlayParams({
    this.isBackgroundLock = false,
    this.sessionTerminatedMessage,
    this.previousDevice,
  });
}

/// null = unlocked; non-null = show lock screen on top of all routes.
final ValueNotifier<LockOverlayParams?> lockOverlayState =
    ValueNotifier<LockOverlayParams?>(null);

/// Set by AuthWrapper so the overlay's unlock button reaches the same
/// handler that resets session-termination state.
VoidCallback? globalLockAuthenticated;

// ============================================================
// ✅ NEW: ThemeProvider for real-time theme management
// ============================================================
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  Color _primaryColor = const Color(0xFF667EEA);
  bool _compactMode = false;
  bool _isInitialized = false;

  ThemeMode get themeMode => _themeMode;
  Color get primaryColor => _primaryColor;
  bool get compactMode => _compactMode;
  bool get isInitialized => _isInitialized;

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex = prefs.getInt('theme_mode') ?? 0;
    final primaryColorHex = prefs.getString('primary_color') ?? '#667EEA';
    final compactMode = prefs.getBool('compact_mode') ?? false;

    _themeMode = themeModeIndex == 1 ? ThemeMode.dark : ThemeMode.light;
    _primaryColor = Color(int.parse(primaryColorHex.replaceFirst('#', '0xFF')));
    _compactMode = compactMode;
    _isInitialized = true;
    notifyListeners();

    debugPrint(
        '🎨 Theme loaded: ${_themeMode == ThemeMode.dark ? "Dark" : "Light"}');
    debugPrint('🎨 Primary color: ${_primaryColor.toString()}');
  }

  Future<void> setTheme(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode == ThemeMode.dark ? 1 : 0);
    notifyListeners();

    debugPrint(
        '🎨 Theme changed to: ${mode == ThemeMode.dark ? "Dark" : "Light"}');
  }

  Future<void> setPrimaryColor(Color color) async {
    if (_primaryColor == color) return;

    _primaryColor = color;
    final prefs = await SharedPreferences.getInstance();
    final hex = color.value.toRadixString(16).padLeft(8, '0');
    await prefs.setString('primary_color', '#${hex.substring(2)}');
    notifyListeners();

    debugPrint('🎨 Primary color changed to: ${color.toString()}');
  }

  Future<void> setCompactMode(bool value) async {
    if (_compactMode == value) return;

    _compactMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('compact_mode', value);
    notifyListeners();

    debugPrint('🎨 Compact mode: $value');
  }

  Future<void> refresh() async {
    await loadTheme();
  }

  // ✅ Toggle between Light and Dark
  void toggleTheme() {
    final newMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    setTheme(newMode);
  }
}

Future<void> _requestStoragePermission() async {
  if (kIsWeb) return;
  try {
    await Permission.manageExternalStorage.request();
    await Permission.storage.request();
    await Permission.notification.request();
    await Permission.microphone.request();
  } catch (e) {
    debugPrint('Permission error: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(
      url: 'https://hcfhnooabhxbdfgvtqhp.supabase.co',
      anonKey:
          'sb_publishable_aTK59GscsMZuzeCx973mIw_SomssAXW', // ⚠️ REPLACE WITH YOUR ACTUAL ANON KEY
    );
    debugPrint('✅ Supabase initialized successfully!');
  } catch (e) {
    debugPrint('❌ Supabase initialization error: $e');
  }
  await StorageService.init();
  await CurrencyHelper.initialize();
  await NotificationService().initialize();
  await _requestStoragePermission();

  // Check Supabase connection
  final supabaseConnected = await SupabaseService.isConnected();
  debugPrint(
      '🔌 Supabase connection: ${supabaseConnected ? "✅ ONLINE" : "❌ OFFLINE"}');

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  bool _isLoading = true;
  late DrinkProvider _drinkProvider;
  late InventoryProvider _inventoryProvider;
  @override
  void initState() {
    super.initState();
    CurrencyHelper.addListener(_refreshCurrency);
    _drinkProvider = DrinkProvider();
    _inventoryProvider = InventoryProvider();

    // ✅ Connect them immediately
    _inventoryProvider.setDrinkProvider(_drinkProvider);
    debugPrint('✅ InventoryProvider connected to DrinkProvider in initState!');
  }

  @override
  void dispose() {
    CurrencyHelper.removeListener(_refreshCurrency);
    super.dispose();
  }

  void _refreshCurrency() {
    if (mounted) {
      setState(() {});
    }
  }

  void refreshTheme() {
    // ✅ Reload theme from ThemeProvider
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    themeProvider.loadTheme();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()..loadTheme()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // ✅ REUSE the same instances using .value
        ChangeNotifierProvider.value(value: _drinkProvider),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
        ChangeNotifierProvider.value(value: _inventoryProvider),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
        ChangeNotifierProvider(create: (_) => PaymentHelper()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          // ✅ Show loading while theme loads
          if (!themeProvider.isInitialized) {
            return const MaterialApp(
              home: Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }

          final primaryColor = themeProvider.primaryColor;
          final themeMode = themeProvider.themeMode;

          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Drinks Ordering and Management',
            debugShowCheckedModeBanner: false,
            theme: _buildLightTheme(primaryColor),
            darkTheme: _buildDarkTheme(primaryColor),
            themeMode: themeMode,
            builder: (context, child) =>
                LockScreenOverlay(child: child ?? const SizedBox.shrink()),
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }

  // ============================================================
  // 🎨 THEME BUILDERS
  // ============================================================

  ThemeData _buildLightTheme(Color primaryColor) {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryColor,
      colorScheme: ColorScheme.light(
        primary: primaryColor,
        secondary: primaryColor,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.black87),
        bodyMedium: TextStyle(color: Colors.black54),
      ),
    );
  }

  ThemeData _buildDarkTheme(Color primaryColor) {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      colorScheme: ColorScheme.dark(
        primary: primaryColor,
        secondary: primaryColor,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
      ),
    );
  }
}

// ============================================================================
// AUTH WRAPPER
// ============================================================================

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  // ========== STATE VARIABLES ==========
  bool _isInitialized = false;
  bool _isCheckingAuth = true;
  bool _showLockScreen = false;
  bool _sessionTerminated = false;
  String? _terminatedMessage;
  String? _previousDevice;
  bool _isAuthenticated = false;
  bool _isAuthInProgress = false;

  // ========== LIFECYCLE ==========
     @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    globalLockAuthenticated = _onAuthenticated;
    // Defer heavy async init (autoLogin, etc.) until *after* the first frame
    // so the splash screen renders immediately and we don't call
    // notifyListeners() during AuthWrapper's own build (which would throw
    // "setState() or markNeedsBuild() called during build").
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeApp());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    globalLockAuthenticated = null;
    LockService().dispose();
    super.dispose();
  }

  // Publish the current lock intent to the top-level overlay so it covers
  // every route (including pushed screens), not just the home widget.
  void _emitLock() {
    if (_showLockScreen || _sessionTerminated || LockService().isLocked) {
      lockOverlayState.value = LockOverlayParams(
        isBackgroundLock: _showLockScreen && !_sessionTerminated,
        sessionTerminatedMessage: _sessionTerminated ? _terminatedMessage : null,
        previousDevice: _sessionTerminated ? _previousDevice : null,
      );
    } else {
      lockOverlayState.value = null;
    }
  }

  // ========== LIFECYCLE OBSERVER ==========
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      LockService().onPaused();
      if (_isAuthenticated && !_showLockScreen) {
        LockService().lock();
        if (mounted) {
          setState(() => _showLockScreen = true);
        }
      }
      _emitLock();
    } else if (state == AppLifecycleState.resumed) {
      LockService().onResumed();

      if (_isAuthenticated) {
        if (LockService().isLocked) {
          if (mounted) {
            setState(() => _showLockScreen = true);
          }
        } else {
          LockService().resetTimer();
          if (mounted && _showLockScreen) {
            setState(() => _showLockScreen = false);
          }
        }
      }

      _emitLock();
      _checkSessionOnResume();
    }
  }

  // ========== LOCK CALLBACKS ==========
  void _onLock() {
    if (mounted && _isAuthenticated) {
      setState(() {
        _showLockScreen = true;
      });
      _emitLock();
    }
  }

  void _onUnlock() {
    if (mounted) {
      setState(() {
        _showLockScreen = false;
        LockService().resetTimer();
      });
      _emitLock();
    }
  }

  // ========== SESSION CHECK ON RESUME ==========
  Future<void> _checkSessionOnResume() async {
    if (!_isAuthenticated || _isAuthInProgress) return;

    debugPrint('🔍 Checking session validity on app resume...');

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final isValid = await authProvider.checkSessionValidity();

      if (!isValid) {
        debugPrint('🔴 Session invalid on resume - showing termination dialog');
        if (mounted) {
          setState(() {
            _sessionTerminated = true;
            _terminatedMessage =
                'Your session was terminated on another device.';
            _previousDevice = authProvider.previousDeviceName;
          });
          _emitLock();
        }
      }
    } catch (e) {
      debugPrint('⚠️ Session check on resume error: $e');
    }
  }

  // ========== AUTHENTICATION ==========
  void _onAuthenticated() {
    if (_isAuthInProgress) return;

    _isAuthInProgress = true;

    LockService().unlock();

    if (mounted) {
      setState(() {
        _showLockScreen = false;
        _sessionTerminated = false;
        _terminatedMessage = null;
        _previousDevice = null;
        _isAuthenticated = true;
        _isAuthInProgress = false;
      });
      _emitLock();
    } else {
      _isAuthInProgress = false;
    }
  }

  // ========== APP INITIALIZATION ==========
  Future<void> _initializeApp() async {
    if (!mounted) return;

    try {
      LockService().initialize(
        onLock: _onLock,
        onUnlock: _onUnlock,
      );

      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      final sessionWarning = authProvider.getSessionWarningInfo();
      if (sessionWarning['showWarning'] == true) {
        _sessionTerminated = true;
        _terminatedMessage = sessionWarning['message'];
        _previousDevice = sessionWarning['previousDevice'];
      }

      await authProvider.autoLogin();

      final user = authProvider.currentUser;
      if (user != null && user.id.isNotEmpty) {
        _isAuthenticated = true;

        final isValid = await authProvider.checkSessionValidity();
        if (!isValid) {
          _sessionTerminated = true;
          _isAuthenticated = false;
          _terminatedMessage = 'Your session was terminated on another device.';
          _previousDevice = authProvider.previousDeviceName;

          if (mounted) {
            setState(() => _showLockScreen = true);
          }
        }

        if (!_sessionTerminated) {
          if (mounted) {
            setState(() => _showLockScreen = true);
          }

          await _loadCompanyDataWithCleanup(user, authProvider);
        }
      } else {
        _isAuthenticated = false;
      }

      _emitLock();
    } catch (e) {
      debugPrint('❌ Auth initialization error: $e');
      _isAuthenticated = false;
      _emitLock();
    }

    if (mounted) {
      setState(() {
        _isCheckingAuth = false;
        _isInitialized = true;
      });
    }
  }

  // ============================================================
  // 🔐 COMPANY DATA LOADING
  // ============================================================

  Future<void> _loadCompanyDataWithCleanup(
      User user, AuthProvider authProvider) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCompanyId = prefs.getInt('last_company_id');
    final currentCompanyId = user.companyId;
    final role = user.role;

    debugPrint('📋 Company Check:');
    debugPrint('   User: ${user.username}');
    debugPrint('   Role: $role');
    debugPrint('   Current Company ID: $currentCompanyId');
    debugPrint('   Last Company ID: $lastCompanyId');

    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final inventoryProvider =
        Provider.of<InventoryProvider>(context, listen: false);

    if ((role == 'Manager' || role == 'Staff') && currentCompanyId == null) {
      debugPrint('⚠️ Manager/Staff with NO company_id - clearing all data');

      await drinkProvider.clearAllDrinks();
      await orderProvider.clearAllOrders();
      await inventoryProvider.clearAllInventory();

      await prefs.remove('last_company_id');
      SupabaseService.disableForCustomer();

      debugPrint('✅ Data cleared - no company');
      return;
    }

    if ((role == 'Manager' || role == 'Staff') && currentCompanyId != null) {
      if (lastCompanyId != null && lastCompanyId != currentCompanyId) {
        debugPrint('🔄 Company CHANGED: $lastCompanyId → $currentCompanyId');
        await drinkProvider.clearAllDrinks();
        await orderProvider.clearAllOrders();
        await inventoryProvider.clearAllInventory();
        debugPrint('🧹 Old data cleared');
      } else if (lastCompanyId == null) {
        debugPrint('🔄 First login for Manager/Staff - no data to clear');
      } else {
        debugPrint('✅ Same company - no clearing needed');
      }

      await prefs.setInt('last_company_id', currentCompanyId);

      SupabaseService.setCompanyContext(
          currentCompanyId, int.tryParse(user.id));
      debugPrint('✅ Supabase context set: company=$currentCompanyId');

      await _loadUserSettings(user.id);
      await CurrencyHelper.refresh();
      await PaymentHelper.refresh();

      if (!authProvider.isOnline) {
        debugPrint('❌ No internet - cannot load company data');

        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.wifi_off, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Internet connection required to load company data. Please connect and try again.',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
        return;
      }

      try {
        debugPrint('🔄 Loading drinks from Supabase...');
        await drinkProvider.loadDrinksFromSupabase();
        debugPrint('✅ Drinks loaded: ${drinkProvider.customDrinks.length}');

        debugPrint('🔄 Initializing OrderProvider...');
        await orderProvider.initialize();
        debugPrint('✅ OrderProvider initialized');

        debugPrint('🔄 Loading orders from Supabase...');
        await orderProvider.loadOrdersFromSupabase();
        debugPrint('✅ Orders loaded: ${orderProvider.orderHistory.length}');

        debugPrint('🔄 Loading inventory from Supabase...');
        await inventoryProvider.loadInventoryFromSupabase();
        debugPrint('✅ Inventory loaded');
// ✅ Verify inventory loaded for staff
        if (role == 'Staff') {
          debugPrint(
              '🔍 Staff user - inventory items: ${inventoryProvider.inventoryItems.length}');
          if (inventoryProvider.inventoryItems.isEmpty) {
            debugPrint('⚠️ WARNING: Staff user has NO inventory items!');
            // ✅ Force reload
            await inventoryProvider.loadInventoryFromSupabase();
            debugPrint(
                '✅ Inventory reloaded: ${inventoryProvider.inventoryItems.length} items');
          }
        }

        // ✅ 🔥 CRITICAL FIX: Connect InventoryProvider to DrinkProvider HERE
        inventoryProvider.setDrinkProvider(drinkProvider);
        debugPrint(
            '✅ InventoryProvider connected to DrinkProvider in AuthWrapper!');

        if (mounted) {
          setState(() {});
        }

        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Text('Data loaded successfully!'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ Error loading company data: $e');

        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(' Failed to load data: $e'),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }

      if (mounted) setState(() {});
      debugPrint('✅ Data loaded from company $currentCompanyId');
      return;
    }

    if (role == 'Customer') {
      debugPrint('👤 Customer mode - checking for old company data');

      if (lastCompanyId != null) {
        debugPrint(
            '🔄 Customer previously had company $lastCompanyId - clearing data');

        await drinkProvider.clearAllDrinks();
        await orderProvider.clearAllOrders();
        await inventoryProvider.clearAllInventory();

        await prefs.remove('last_company_id');
        debugPrint('🧹 Old company data cleared');
      }

      SupabaseService.disableForCustomer();
      debugPrint('✅ Customer mode - Supabase disabled');

      await drinkProvider.loadDrinks();
      await orderProvider.reloadOrders();

      if (mounted) setState(() {});
      return;
    }

    debugPrint('⚠️ Unknown role: $role - clearing data');

    await drinkProvider.clearAllDrinks();
    await orderProvider.clearAllOrders();
    await inventoryProvider.clearAllInventory();

    await prefs.remove('last_company_id');
    SupabaseService.disableForCustomer();

    debugPrint('✅ Data cleared - unknown role');
  }

  // ========== USER SETTINGS ==========
  Future<void> _loadUserSettings(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final supabaseSettings = await SupabaseService.getSettings(userId);

      if (supabaseSettings != null) {
        // ✅ Load theme settings into ThemeProvider
        final themeProvider =
            Provider.of<ThemeProvider>(context, listen: false);

        await prefs.setInt('theme_mode', supabaseSettings['theme_mode'] ?? 0);
        await prefs.setString(
            'primary_color', supabaseSettings['primary_color'] ?? '#667EEA');
        await prefs.setString(
            'currency_symbol', supabaseSettings['currency_symbol'] ?? 'Frs');
        await prefs.setString('currency_position',
            supabaseSettings['currency_position'] ?? 'right');
        await prefs.setString(
            'decimal_separator', supabaseSettings['decimal_separator'] ?? '.');
        await prefs.setString('thousands_separator',
            supabaseSettings['thousands_separator'] ?? ',');
        await prefs.setInt(
            'decimal_places', supabaseSettings['decimal_places'] ?? 0);
        await prefs.setString('company_name',
            supabaseSettings['company_name'] ?? 'Drink Quick Cal');
        await prefs.setString(
            'company_email', supabaseSettings['company_email'] ?? '');
        await prefs.setString(
            'company_phone', supabaseSettings['company_phone'] ?? '');
        await prefs.setString(
            'company_address', supabaseSettings['company_address'] ?? '');
        await prefs.setBool('business_payments_enabled',
            supabaseSettings['business_payments'] ?? false);
        await prefs.setBool(
            'mtn_enabled', supabaseSettings['mtn_enabled'] ?? true);
        await prefs.setBool(
            'orange_enabled', supabaseSettings['orange_enabled'] ?? true);
        await prefs.setBool(
            'auto_sync', supabaseSettings['auto_sync'] ?? false);
        await prefs.setBool('show_notifications',
            supabaseSettings['show_notifications'] ?? true);
        await prefs.setBool(
            'compact_mode', supabaseSettings['compact_mode'] ?? false);

        await StorageService.saveCurrencySettings(
          symbol: supabaseSettings['currency_symbol'] ?? 'Frs',
          position: supabaseSettings['currency_position'] ?? 'right',
          decimalSeparator: supabaseSettings['decimal_separator'] ?? '.',
          thousandsSeparator: supabaseSettings['thousands_separator'] ?? ',',
          decimalPlaces: supabaseSettings['decimal_places'] ?? 0,
        );

        await CurrencyHelper.refresh();
        await PaymentHelper.refresh();

        // ✅ Refresh theme provider
        await themeProvider.loadTheme();

        if (mounted) {
          appKey.currentState?.refreshTheme();
          await Future.delayed(Duration.zero);
          setState(() {});
        }

        debugPrint('✅ Settings loaded from Supabase for user: $userId');
      } else {
        debugPrint('⚠️ No settings found in Supabase for user: $userId');
      }
    } catch (e) {
      debugPrint('❌ Error loading settings: $e');
    }
  }

  // ========== BUILD ==========
  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _isCheckingAuth) {
      return _buildSplashScreen();
    }

    return Consumer<AuthProvider>(
      key: ValueKey(Provider.of<AuthProvider>(context).currentUser?.companyId),
      builder: (context, authProvider, _) {
        final currentUser = authProvider.currentUser;
        final isValidUser = currentUser != null &&
            currentUser.username.isNotEmpty &&
            currentUser.id.isNotEmpty &&
            currentUser.id != 'temp_id';

        if (isValidUser) {
          _isAuthenticated = true;

          return ActivityDetector(
            child: OfflineIndicator(
              child: const CalculatorScreen(),
            ),
          );
        } else {
          return const AuthScreen();
        }
      },
    );
  }

  // ========== SPLASH SCREEN ==========
  Widget _buildSplashScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(25),
                  image: const DecorationImage(
                    image: AssetImage('assets/icons/icon.png'),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Drinks Quick Cal',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Professional Drink Ordering & Management',
                style: TextStyle(
                  fontSize: 16,
                  color: Color.fromARGB(255, 218, 212, 212),
                ),
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                _isCheckingAuth
                    ? 'Checking authentication...'
                    : 'Loading app...',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ============================================================================
// 🔒 LOCK SCREEN OVERLAY
// ============================================================================
// Rendered via MaterialApp.builder so it sits ABOVE the entire Navigator.
// This guarantees the lock screen covers every route that exposes user data
// (calculator, pushed screens, dialogs, bottom sheets), not just the home
// widget. It is driven by the global [lockOverlayState] that AuthWrapper
// publishes whenever the app locks / unlocks / session is terminated.
class LockScreenOverlay extends StatelessWidget {
  final Widget child;

  const LockScreenOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LockOverlayParams?>(
      valueListenable: lockOverlayState,
      builder: (context, lockParams, _) {
        return Stack(
          textDirection: TextDirection.ltr,
          children: [
            child,
            if (lockParams != null)
              Positioned.fill(
                child: Consumer<AuthProvider>(
                  builder: (context, authProvider, _) {
                    final user = authProvider.currentUser;
                    return LockScreen(
                      userId: user?.id ?? '',
                      onAuthenticated: () =>
                          globalLockAuthenticated?.call(),
                      isBackgroundLock: lockParams.isBackgroundLock,
                      sessionTerminatedMessage:
                          lockParams.sessionTerminatedMessage,
                      previousDevice: lockParams.previousDevice,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
