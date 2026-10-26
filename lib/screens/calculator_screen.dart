// screens/calculator_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../widgets/drink_avatar.dart';
import '../utils/i18n.dart' show t;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/providers/customer_provider.dart';
import 'package:drinks_calculator_fixed/providers/order_provider.dart';
import 'package:drinks_calculator_fixed/providers/plan_provider.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/utils/helpers.dart';
import 'package:drinks_calculator_fixed/utils/payment_error_helper.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'drink_management_screen.dart';
import 'ai_assistant_screen.dart';
import 'responsive_invoice.dart';
import 'auth_screen.dart';
import 'admin_panel.dart';
import 'side_slider.dart';
import '../widgets/custom_drawer.dart';
import 'package:drinks_calculator_fixed/utils/payment_helper.dart';
import 'package:drinks_calculator_fixed/providers/inventory_provider.dart';
import 'package:drinks_calculator_fixed/services/notification_service.dart';
import 'package:drinks_calculator_fixed/services/order_bridge.dart';
import 'package:drinks_calculator_fixed/widgets/floating_ai_button.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';
import 'package:drinks_calculator_fixed/services/payment_service.dart';
import 'package:drinks_calculator_fixed/providers/sync_provider.dart';
import 'package:drinks_calculator_fixed/utils/offline_gate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:drinks_calculator_fixed/screens/notifications_screen.dart';
import '../main.dart' show ThemeProvider;

enum PaymentMethod {
  cash,
  mtnMobileMoney,
  orangeMoney,
  card,
}

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({Key? key}) : super(key: key);

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final bool _isLoadingDrinks = false;
  final List<Drink> _selectedDrinks = [];
  double _totalAmount = 0.0;
  double _amountPaid = 0.0;
  double _balance = 0.0;
  final TextEditingController _amountPaidController = TextEditingController();
  int _selectedQuantity = 1;
  String? _selectedDrinkId;
  bool _isSideSliderOpen = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _lastAddedDrinkName;
  Timer? _notificationTimer;
  Timer? _scrollTimer;
  String? _expandedDrinkName;
  final ScrollController _selectedDrinksScrollController = ScrollController();
  Order? _createdOrder;

  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  bool _businessPaymentsEnabled = false;
  bool _mtnEnabled = false;
  bool _orangeEnabled = false;
  bool _cardEnabled = false;
  final TextEditingController _customerPhoneController =
      TextEditingController();
  bool _isProcessingPayment = false;

  /// 0..1 progress of the "completing order" stages (order → server → stock), shown
  /// as a percentage on the Pay button so a slow sync looks like progress, not a
  /// frozen screen.
  double _completionProgress = 0.0;

  void _setCompletionProgress(double value) {
    if (!mounted) return;
    setState(() => _completionProgress = value.clamp(0.0, 1.0));
  }
  String? _paymentStatus;
  String? _paymentMessage;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Drink> _filteredDrinks = [];
  bool _showDropdown = false;
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  bool _isSelectingDrink = false;
  String? _importedCustomerName;
  String? _customerNameForOrder;
  String? _originalOrderId;
  String _companyName = 'Drink Quick Cal';

  // ============================================================
  // 🚀 LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    NotificationService().initialize();
    _amountPaidController.addListener(_calculateBalance);
    CurrencyHelper.addListener(_refreshCurrency);
    PaymentHelper.addPaymentListener(_refreshPaymentSettings);
    _searchController.addListener(() {
      _filterDrinks(_searchController.text);
    });
    // Defer the initial loads past the first frame: PaymentHelper.loadSettings,
    // DrinkProvider.load* and OrderProvider all call notifyListeners(), which is
    // illegal while the tree is still building (it throws
    // "setState() called during build").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _loadBusinessPaymentSettings();
      _loadCompanyName();
      _loadPendingOrderFromAI();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshDrinks();
      _initOrdersAndSettingsAfterLogin();
    });
    SupabaseService.addInventoryListener(_onInventoryChanged);
    SupabaseService.addOrderListener(_onOrderChanged);
  }

  void _onInventoryChanged() {
    if (!mounted) return;

    print('🔄 CalculatorScreen: Inventory changed by another staff member');

    // Get current state before refresh
    final selectedId = _selectedDrinkId;
    final searchQuery = _searchQuery;

    // Refresh drinks from Supabase
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    drinkProvider.loadDrinksFromSupabase().then((_) {
      if (!mounted) return;

      setState(() {
        // Update dropdown list
        _filteredDrinks = _getSortedDrinks(drinkProvider.customDrinks);

        // Re-apply search filter if active
        if (searchQuery.isNotEmpty) {
          _filterDrinks(searchQuery);
        }

        // If a drink was selected, check if it's still in stock
        if (selectedId != null) {
          // ✅ FIX: Use firstWhere with a default Drink object
          final selectedDrink =
              drinkProvider.customDrinks.firstWhere((d) => d.id == selectedId,
                  orElse: () => Drink(
                        id: '',
                        name: '',
                        price: 0,
                        imageUrl: '',
                      ));

          // Check if the drink is empty (not found) or out of stock
          if (selectedDrink.id.isEmpty || selectedDrink.currentStock <= 0) {
            _selectedDrinkId = null;
            _searchController.clear();
            _searchQuery = '';
            Helpers.showToast(t('calcSelectedOutOfStock'),
                isError: true);
          }
        }
      });
    });
  }

  void _onOrderChanged() {
    if (!mounted) return;

    print('🔄 CalculatorScreen: Order changed by another staff member');

    // Only refresh orders if the side slider is open or we need to update order history
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    orderProvider.loadOrdersFromSupabase();
  }

  @override
  void dispose() {
    _amountPaidController.removeListener(_calculateBalance);
    _amountPaidController.dispose();
    _notificationTimer?.cancel();
    _scrollTimer?.cancel();
    _customerPhoneController.dispose();
    CurrencyHelper.removeListener(_refreshCurrency);
    _selectedDrinksScrollController.dispose();
    PaymentHelper.removePaymentListener(_refreshPaymentSettings);
    _searchController.dispose();
    _searchFocusNode.dispose();
    SupabaseService.removeOrderListener(_onOrderChanged);
    SupabaseService.removeInventoryListener(_onInventoryChanged);
    super.dispose();
  }

  // ============================================================
  // 📥 LOAD METHODS
  // ============================================================

  Future<void> _loadCompanyName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _companyName = prefs.getString('company_name') ?? 'Drink Quick Cal';
    });
  }

  // ✅ Ensure orders + settings are loaded as soon as login is confirmed.
  // Only auto-initialize orders when we actually have a company context;
  // otherwise we'd cache an empty local list and mark OrderProvider as
  // initialized, which would block the real Supabase load later (e.g. for
  // customer/temp logins). Payment/currency refresh is deferred to the next
  // frame to avoid "setState() called during build" from notifyListeners().
  // ✅ Pull cloud settings (theme, company details, currency, notifications)
  // into local prefs at startup/login, so they apply WITHOUT the user having
  // to open the Settings screen first. Company record is authoritative for
  // company name/email/phone/address (invoice + drawer data).
  Future<void> _syncCloudSettingsAtStartup() async {
    try {
      if (!SupabaseService.canUseSupabase) {
        debugPrint('⏭️ Cloud settings sync skipped (no company context)');
        return;
      }
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      bool changed = false;

      // 1️⃣ Cloud user settings (saved by the Settings screen)
      final settings = await SupabaseService.getSettings(user.id.toString());
      if (settings != null) {
        if (settings['theme_mode'] != null) {
          await prefs.setInt(
              'theme_mode', (settings['theme_mode'] as num).toInt());
          changed = true;
        }
        if (settings['primary_color'] != null &&
            settings['primary_color'].toString().isNotEmpty) {
          await prefs.setString(
              'primary_color', settings['primary_color'].toString());
          changed = true;
        }
        if (settings['show_notifications'] != null) {
          await prefs.setBool('show_notifications',
              settings['show_notifications'] == true);
          changed = true;
        }
        // Only overwrite company fields when the cloud actually has a value
        void syncStr(String key, dynamic v) {
          if (v != null && v.toString().trim().isNotEmpty) {
            prefs.setString(key, v.toString());
            changed = true;
          }
        }

        syncStr('company_name', settings['company_name']);
        syncStr('company_email', settings['company_email']);
        syncStr('company_phone', settings['company_phone']);
        syncStr('company_address', settings['company_address']);
      }

      // 2️⃣ Company record (authoritative for business details on invoices)
      final companyId = SupabaseService.currentCompanyId ?? user.companyId;
      if (companyId != null) {
        final company = await SupabaseService.getCompany(companyId);
        if (company != null) {
          final name = company['name']?.toString() ?? '';
          if (name.trim().isNotEmpty) {
            await prefs.setString('company_name', name);
            changed = true;
          }
          final email = company['email']?.toString() ?? '';
          if (email.trim().isNotEmpty) {
            await prefs.setString('company_email', email);
            changed = true;
          }
          final phone = company['phone']?.toString() ?? '';
          if (phone.trim().isNotEmpty) {
            await prefs.setString('company_phone', phone);
            changed = true;
          }
          final address = company['address']?.toString() ?? '';
          if (address.trim().isNotEmpty) {
            await prefs.setString('company_address', address);
            changed = true;
          }
        }
      }

      debugPrint(
          '✅ Cloud settings synced at startup${changed ? " (applied)" : " (no changes)"}');

      // 3️⃣ Re-apply theme from the updated prefs + refresh currency
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          // ignore: invalid_use_of_protected_member
          Provider.of<ThemeProvider>(context, listen: false).loadTheme();
          debugPrint('🎨 Theme re-applied from cloud settings');
        } catch (e) {
          debugPrint('⚠️ Theme re-apply skipped: $e');
        }
        PaymentHelper.refresh();
        CurrencyHelper.refresh();
      });
    } catch (e) {
      debugPrint('❌ Cloud settings sync error: $e');
    }
  }

  // ✅ Ensure orders + settings are loaded as soon as login is confirmed.
  Future<void> _initOrdersAndSettingsAfterLogin() async {
    try {
      // Sync cloud settings (theme, company details) BEFORE refreshing helpers
      await _syncCloudSettingsAtStartup();
      if (!mounted) return;

      if (SupabaseService.canUseSupabase) {
        final orderProvider =
            Provider.of<OrderProvider>(context, listen: false);
        if (!orderProvider.isInitialized) {
          await orderProvider.initialize();
          debugPrint(
              '✅ Orders loaded after login: ${orderProvider.orderHistory.length}');
        } else {
          debugPrint('✅ Orders already initialized - skipping');
        }
      } else {
        debugPrint(
            '⏭️ No company context yet - deferring order load after login');
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        PaymentHelper.refresh();
        CurrencyHelper.refresh();
        debugPrint('✅ Settings refreshed after login');
      });
    } catch (e) {
      debugPrint('❌ _initOrdersAndSettingsAfterLogin error: $e');
    }
  }

  void _refreshCurrency() {
    if (mounted) {
      setState(() {});
    }
  }

  void _loadPendingOrderFromAI() {
    final orderBridge = OrderBridge();
    if (orderBridge.hasPendingOrder) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          for (final item in orderBridge.pendingDrinks) {
            final drink = item['drink'] as Drink;
            final quantity = item['quantity'] as int;
            _selectedDrinkId = drink.id;
            _selectedQuantity = quantity;
            _searchController.text =
                '${drink.name} - ${CurrencyHelper.format(drink.price)}';
            _searchQuery = drink.name;

            for (int i = 0; i < quantity; i++) {
              _selectedDrinks.add(drink);
            }
          }
          _sortSelectedDrinks();
          _calculateTotal();

          if (orderBridge.customerName.isNotEmpty) {
            _customerNameForOrder = orderBridge.customerName;
          }
        });

        orderBridge.clearOrder();
        Helpers.showToast(
            t(orderBridge.source == 'scanner'
                ? 'orderLoadedFromScanner'
                : 'orderLoadedFromAi'));
      });
    }
  }

  Future<void> _refreshDrinks() async {
    if (_isLoadingDrinks) {
      debugPrint('⏭️ Skipping duplicate refresh - already loading');
      return;
    }
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    if (SupabaseService.canUseSupabase) {
      await drinkProvider.loadDrinksFromSupabase();
      if (mounted) {
        setState(() {});
      }
      debugPrint('✅ Drinks refreshed on calculator screen load');
    }
  }

  void _refreshPaymentSettings() {
    if (!mounted) return;

    final paymentHelper = PaymentHelper();

    setState(() {
      bool wasEnabled = _businessPaymentsEnabled;
      bool mtnWasEnabled = _mtnEnabled;
      bool orangeWasEnabled = _orangeEnabled;

      _businessPaymentsEnabled = paymentHelper.businessPaymentsEnabled;
      _mtnEnabled = paymentHelper.mtnEnabled;
      _orangeEnabled = paymentHelper.orangeEnabled;
      _cardEnabled = paymentHelper.cardEnabled;

      if (_selectedPaymentMethod == PaymentMethod.mtnMobileMoney &&
          !_mtnEnabled) {
        _selectedPaymentMethod = PaymentMethod.cash;
        _customerPhoneController.clear();
        _paymentStatus = null;
        _paymentMessage = null;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          Helpers.showToast(
              t('calcMtnDisabled'));
        });
      }

      if (_selectedPaymentMethod == PaymentMethod.orangeMoney &&
          !_orangeEnabled) {
        _selectedPaymentMethod = PaymentMethod.cash;
        _customerPhoneController.clear();
        _paymentStatus = null;
        _paymentMessage = null;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          Helpers.showToast(
              t('calcOrangeDisabled'));
        });
      }

      if (!_businessPaymentsEnabled &&
          _selectedPaymentMethod != PaymentMethod.cash) {
        _selectedPaymentMethod = PaymentMethod.cash;
        _customerPhoneController.clear();
        _paymentStatus = null;
        _paymentMessage = null;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          Helpers.showToast(
              t('calcCamPayDisabled'));
        });
      }

      if (!wasEnabled && _businessPaymentsEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Helpers.showToast(t('calcCamPayEnabled'));
        });
      }
    });
  }

  Future<bool> _deductInventoryFromOrder() async {
    debugPrint('🔴🔴🔴 _deductInventoryFromOrder() CALLED 🔴🔴🔴');
    final inventoryProvider =
        Provider.of<InventoryProvider>(context, listen: false);
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
     if (inventoryProvider.inventoryItems.isEmpty) {
    debugPrint('⚠️ Inventory is empty - reloading...');
    await inventoryProvider.loadInventoryFromSupabase();
    debugPrint('✅ Inventory reloaded: ${inventoryProvider.inventoryItems.length} items');
  }
    final summary = _getDrinkSummary();
    debugPrint('   Summary: $summary');
    debugPrint('   Selected drinks count: ${_selectedDrinks.length}');
    debugPrint('   _createdOrder: ${_createdOrder?.id}');
    final orderId =
        _createdOrder?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    debugPrint('   Order ID: $orderId');

    // 🔒 Every line is committed atomically server-side. If a line cannot be
    // sold (someone else took the last unit) the sale is refused instead of
    // pushing the inventory negative — and the lines this sale already took off
    // the shelf are put back below, so a refused multi-line sale never leaves the
    // inventory short.
    final List<MapEntry<Drink, int>> taken = [];
    for (final entry in summary.entries) {
      final drink = _selectedDrinks.firstWhere((d) => d.name == entry.key);
      debugPrint(
          '   🍺 Deducting ${entry.value} of ${drink.name} (ID: ${drink.id})');

      final stockRemoved = await inventoryProvider.removeStock(
        drinkId: drink.id,
        drinkName: drink.name,
        quantity: entry.value,
        reason: 'sale',
        orderId: orderId,
      );
      debugPrint('   Stock removed result: $stockRemoved');
      if (stockRemoved) {
        taken.add(MapEntry(drink, entry.value));
        final updatedDrink = drink.copyWith(
          currentStock: (drink.currentStock - entry.value).clamp(0, 999999),
        );
        await drinkProvider.updateDrink(drink.id, updatedDrink);
        debugPrint(
            '   ✅ Drink updated: ${drink.name} stock = ${updatedDrink.currentStock}');
      } else {
        final available = inventoryProvider.insufficientAvailable;
        final detail = available != null
            ? '${drink.name}: $available ${t('remainingInStock')}'
            : drink.name;
        debugPrint('   ❌ Failed to remove stock for ${drink.name}');
        await _putBackTakenStock(inventoryProvider, drinkProvider, taken);
        if (mounted) {
          Helpers.showToast(
            '${t('insufficientStockSale')} — $detail',
            isError: true,
          );
          // Re-pull the true balance so the screen shows reality.
          await inventoryProvider.loadInventoryFromSupabase();
          if (mounted) setState(() {});
        }
        return false;
      }
    }
    return true;
  }

  /// Puts back exactly the lines a refused sale had already taken off the shelf.
  ///
  /// Best effort: the failure toast has already told the operator, so a sync
  /// error here must not hide it. Passing back the drink snapshot taken before
  /// the deduction restores the stock level it had a moment ago.
  Future<void> _putBackTakenStock(
    InventoryProvider inventoryProvider,
    DrinkProvider drinkProvider,
    List<MapEntry<Drink, int>> taken,
  ) async {
    for (final line in taken) {
      await inventoryProvider.addStock(
        drinkId: line.key.id,
        drinkName: line.key.name,
        quantity: line.value,
        reason: 'sale_rollback',
      );
      await drinkProvider.updateDrink(line.key.id, line.key);
      debugPrint('   ↩️ Put back ${line.value} × ${line.key.name}');
    }
  }

  Future<void> _loadData() async {
    if (_isLoadingDrinks) {
      debugPrint('⏭️ Skipping duplicate loadData - already loading');
      return;
    }
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    if (SupabaseService.canUseSupabase) {
      await drinkProvider.loadDrinksFromSupabase();
    } else {
      await drinkProvider.loadDrinks();
    }
    _filteredDrinks = _getSortedDrinks(drinkProvider.customDrinks);
  }

  Future<void> _loadBusinessPaymentSettings() async {
    // ✅ Load from PaymentHelper (which now syncs with Supabase)
    final paymentHelper = Provider.of<PaymentHelper>(context, listen: false);
    await paymentHelper.loadSettings();

    if (mounted) {
      setState(() {
        _businessPaymentsEnabled = paymentHelper.businessPaymentsEnabled;
        _mtnEnabled = paymentHelper.mtnEnabled;
        _orangeEnabled = paymentHelper.orangeEnabled;
        _cardEnabled = paymentHelper.cardEnabled;
      });
    }
  }

  // ============================================================
  // 🍺 DRINK MANAGEMENT
  // ============================================================

  List<Drink> _getSortedDrinks(List<Drink> allDrinks) {
    return List<Drink>.from(allDrinks)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void _sortSelectedDrinks() {
    _selectedDrinks
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void _addDrink(Drink drink, {bool scrollToDrink = true}) {
    // ✅ Get LATEST stock from provider
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final currentDrink = drinkProvider.customDrinks.firstWhere(
      (d) => d.id == drink.id,
      orElse: () => drink,
    );

    // ✅ Count how many of this drink are already selected
    final alreadySelected =
        _selectedDrinks.where((d) => d.id == drink.id).length;
    final availableStock = currentDrink.currentStock - alreadySelected;

    if (availableStock <= 0) {
      Helpers.showToast('${drink.name} — ${t('outOfStockToast')}', isError: true);
      if (mounted) {
        setState(() {
          _selectedDrinkId = null;
          _searchController.clear();
          _searchQuery = '';
        });
      }
      return;
    }

    if (availableStock < _selectedQuantity) {
      Helpers.showToast(
          '${drink.name}: $availableStock ${t('calcLeftInStock')}',
          isError: true);
      return;
    }

    // Add the drink
    setState(() {
      for (int i = 0; i < _selectedQuantity; i++) {
        _selectedDrinks.add(drink);
      }
      _sortSelectedDrinks();
      _calculateTotal();

      _lastAddedDrinkName = drink.name;
      _notificationTimer?.cancel();
      _notificationTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _lastAddedDrinkName = null;
          });
        }
      });
    });

    Helpers.showToast('${t('calcAdded')} $_selectedQuantity ${drink.name}');

    if (scrollToDrink) {
      _scrollTimer?.cancel();
      _scrollTimer = Timer(Duration(milliseconds: 200), () {
        if (_selectedDrinksScrollController.hasClients &&
            _selectedDrinks.isNotEmpty) {
          final summary = _getDrinkSummary();
          final entries = summary.entries.toList()
            ..sort(
                (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
          final drinkIndex = entries.indexWhere((e) => e.key == drink.name);
          if (drinkIndex != -1) {
            final itemHeight = 80.0;
            final targetPosition = (drinkIndex * itemHeight).clamp(
                0.0, _selectedDrinksScrollController.position.maxScrollExtent);
            _selectedDrinksScrollController.animateTo(
              targetPosition,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
            );
          }
        }
      });
    }
  }

  /// Lets the user type the quantity with the keyboard instead of tapping the
  /// + / − buttons repeatedly.
  Future<void> _promptQuantity() async {
    final controller = TextEditingController(text: '$_selectedQuantity');
    String? error;

    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void submit() {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed < 1) {
              setDialogState(() => error = t('scanInvalidQuantity'));
              return;
            }
            Navigator.pop(ctx, parsed > 99 ? 99 : parsed);
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.numbers),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(t('calcSelectQuantity'),
                      style: const TextStyle(fontSize: 18))),
            ]),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              onChanged: (_) {
                if (error != null) setDialogState(() => error = null);
              },
              decoration: InputDecoration(
                labelText: t('quantity'),
                errorText: error,
                helperText: '1 - 99',
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(t('cancel'))),
              FilledButton(onPressed: submit, child: Text(t('save'))),
            ],
          );
        },
      ),
    );

    if (value != null && mounted) {
      setState(() => _selectedQuantity = value);
    }
  }

  void _decreaseDrinkQuantity(String drinkName) {
    setState(() {
      int lastIndex =
          _selectedDrinks.lastIndexWhere((d) => d.name == drinkName);
      if (lastIndex != -1) {
        _selectedDrinks.removeAt(lastIndex);
        _sortSelectedDrinks();
        _calculateTotal();

        Helpers.showToast('${t('calcRemoved')} $drinkName');

        if (_selectedDrinks.where((d) => d.name == drinkName).isEmpty) {
          _expandedDrinkName = null;
        }
      }
    });
  }

  void _clearDrink(String drinkName) {
    setState(() {
      _selectedDrinks.removeWhere((drink) => drink.name == drinkName);
      _sortSelectedDrinks();
      _calculateTotal();
      _expandedDrinkName = null;
    });
  }

  void _calculateTotal() {
    _totalAmount = _selectedDrinks.fold(0.0, (sum, drink) => sum + drink.price);
    _calculateBalance();
  }

  void _calculateBalance() {
    _amountPaid = double.tryParse(_amountPaidController.text) ?? 0.0;
    _balance = _amountPaid - _totalAmount;
  }

  void _clearAll() {
    final count = _selectedDrinks.length;
    setState(() {
      _selectedDrinks.clear();
      _totalAmount = 0.0;
      _amountPaid = 0.0;
      _balance = 0.0;
      _amountPaidController.clear();
      _selectedQuantity = 1;
      _selectedDrinkId = null;
      _lastAddedDrinkName = null;
      _expandedDrinkName = null;
      _selectedPaymentMethod = PaymentMethod.cash;
      _customerPhoneController.clear();
      _paymentStatus = null;
      _paymentMessage = null;
      _searchController.clear();
      _searchQuery = '';
      _selectedDrinkId = null;
      _originalOrderId = null;
    });
    Helpers.showToast('${t('calcOrderCleared')} $count');
  }

  void _showPreviewInvoice() {
    if (_selectedDrinks.isEmpty) {
      Helpers.showToast(t('calcNoPurchases'),
          isError: true);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResponsiveInvoice(
          drinks: _selectedDrinks,
          totalAmount: _totalAmount,
          amountPaid: _amountPaid,
          balance: _balance,
          orderId: null,
          customerName: null,
          isPreview: true,
        ),
      ),
    );
  }

  // ============================================================
  // 💰 PAYMENT PROCESSING
  // ============================================================

  Future<void> _processPayment() async {
    if (_selectedDrinks.isEmpty) {
      Helpers.showToast(t('noDrinksSelected'), isError: true);
      return;
    }

    if (_selectedPaymentMethod == PaymentMethod.cash) {
      if (_amountPaid < _totalAmount) {
        Helpers.showToast(t('insufficientPayment'), isError: true);
        return;
      }
    } else if (_selectedPaymentMethod != PaymentMethod.card) {
      if (_customerPhoneController.text.trim().isEmpty) {
        Helpers.showToast(t('pleaseEnterCustomerPhone'), isError: true);
        return;
      }
    }

    // 📶 Offline policy — company tills only (utils/offline_gate.dart):
    //   • card / MTN / Orange need the server, so they cannot be taken offline;
    //   • cash may be sold offline and queued, until the unsynced queue hits its cap;
    //   • once that cap is reached nothing completes until a sync succeeds — the
    //     requirement is "not synced → cannot complete", and the books stay honest.
    final authForGate = Provider.of<AuthProvider>(context, listen: false);
    final syncState = Provider.of<SyncProvider>(context, listen: false);
    final gate = OfflineGate.decide(
      isCompanyTill: authForGate.user?.companyId != null,
      isOnline: syncState.isOnline,
      pendingSync: syncState.pendingSyncCount,
      isElectronic: _selectedPaymentMethod != PaymentMethod.cash,
    );
    if (gate == OfflineSaleDecision.blockedQueueFull) {
      Helpers.showToast(
          '${t('offlineQueueFull')} (${syncState.pendingSyncCount})',
          isError: true);
      return;
    }
    if (gate == OfflineSaleDecision.blockedOfflineElectronic) {
      Helpers.showToast(t('offlineElectronicBlocked'), isError: true);
      return;
    }
    if (gate == OfflineSaleDecision.allowedOfflineCash) {
      // Not an error: the sale goes through and syncs later, but the operator must
      // know it is not on the server yet.
      Helpers.showToast(t('offlineCashOnly'));
    }

    String? customerName;
    if (_customerNameForOrder != null && _customerNameForOrder!.isNotEmpty) {
      customerName = _customerNameForOrder;
      _customerNameForOrder = null;
    } else {
      customerName = _importedCustomerName ?? await _showCustomerNameDialog();
      if (_importedCustomerName != null) {
        _importedCustomerName = null;
      }
    }

    if (customerName == null || customerName.isEmpty) {
      Helpers.showToast(t('customerNameRequired'), isError: true);
      return;
    }

    setState(() {
      _isProcessingPayment = true;
      _completionProgress = 0.0;
      _paymentStatus = null;
      _paymentMessage = null;
    });

    try {
      bool paymentSuccess = false;

      if (_selectedPaymentMethod == PaymentMethod.cash) {
        paymentSuccess = await _processCashPayment(customerName);
      } else if (_selectedPaymentMethod == PaymentMethod.mtnMobileMoney) {
        paymentSuccess = await _processMobileMoneyPayment(
          'mtn',
          _customerPhoneController.text.trim(),
          _totalAmount,
          customerName,
        );
      } else if (_selectedPaymentMethod == PaymentMethod.orangeMoney) {
        paymentSuccess = await _processMobileMoneyPayment(
          'orange',
          _customerPhoneController.text.trim(),
          _totalAmount,
          customerName,
        );
      } else if (_selectedPaymentMethod == PaymentMethod.card) {
        paymentSuccess = await _processMobileMoneyPayment(
          'card',
          '',
          _totalAmount,
          customerName,
        );
      }

      if (paymentSuccess) {
        Helpers.showToast(t('calcPaymentProcessed'));
        if (_originalOrderId != null && _originalOrderId!.isNotEmpty) {
          final orderProvider =
              Provider.of<OrderProvider>(context, listen: false);
          // The invoice this one replaces has to stop counting as a sale — and, for
          // a manager, hand its stock back so the replacement sale does not deduct
          // the same drinks a second time.
          final retired = await orderProvider.voidOrCancelOrder(
              _originalOrderId!, t('reasonReInvoiced'));
          if (!retired) {
            Helpers.showToast(t('orderRetireFailed'), isError: true);
          }
          _originalOrderId = null;
        }

        NotificationService().showOrderCompleted(
          orderId: _createdOrder?.id ?? '',
          customerName: customerName,
          totalAmount: _totalAmount,
          paymentMethod: _selectedPaymentMethod.name,
        );

        final inventoryProvider =
            Provider.of<InventoryProvider>(context, listen: false);
        for (final item in inventoryProvider.lowStockItems) {
          NotificationService().showLowStockAlert(
            drinkName: item.drinkName,
            currentStock: item.quantity,
            minStockLevel: item.minStockLevel,
          );
        }
        _showResponsiveInvoice();
      }
    } catch (e) {
      // A thrown exception is not a message: it can be a stack trace or a provider
      // sentence. The operator sees our sentence; the technical detail is logged.
      debugPrint('❌ Payment flow error: $e');
      final message = PaymentErrorHelper.message(e);
      setState(() {
        _paymentStatus = 'failed';
        _paymentMessage = message;
      });
      // 🔔 Notify the in-app notification center
      NotificationService().showPaymentFailed(
        reason: message,
        paymentMethod: _selectedPaymentMethod.name,
      );
      Helpers.showToast(message, isError: true);
    } finally {
      setState(() {
        _isProcessingPayment = false;
        _completionProgress = 0.0;
      });
    }
  }

  // ============================================================
  // 💳 MOBILE MONEY PAYMENT
  // ============================================================

  Future<bool> _processMobileMoneyPayment(
    String paymentMethod,
    String customerPhone,
    double amount,
    String customerName,
  ) async {
    final orderId =
        _createdOrder?.id ?? DateTime.now().millisecondsSinceEpoch.toString();

    // ✅ Validate phone number
    if (paymentMethod != 'card' && !_validatePhoneNumber(customerPhone, paymentMethod)) {
      // Composed from a translated fragment: t() takes no parameters, and word order
      // differs between EN and FR.
      final message = '${t('calcInvalidPhone')} $paymentMethod';
      setState(() {
        _paymentStatus = 'failed';
        _paymentMessage = message;
      });
      Helpers.showToast(message, isError: true);
      return false;
    }

    // ✅ Ask the server to price the cart. It answers with the authoritative
    // total and, when configured, a signed token the payment routes accept — so a
    // payment can never collect less than the catalogue says. A null reply
    // (older backend, offline) leaves the sale on the previous behaviour.
    String? quoteToken;
    final quote = await PaymentService.quoteCart([
      for (final drink in _selectedDrinks) {'drinkId': drink.id},
    ]);
    if (quote != null && quote['valid'] == true) {
      final serverTotal = (quote['total'] as num?)?.toDouble();
      if (serverTotal != null &&
          (serverTotal - amount).abs() > 0.009) {
        // Never charge a total the operator did not see on the screen.
        final message =
            '${t('calcPriceChanged')} ${CurrencyHelper.format(serverTotal)}';
        debugPrint('⚠️ Cart priced ${CurrencyHelper.format(serverTotal)} by the '
            'server, ${CurrencyHelper.format(amount)} on the till');
        setState(() {
          _paymentStatus = 'failed';
          _paymentMessage = message;
        });
        Helpers.showToast(message, isError: true);
        return false;
      }
      quoteToken = quote['quoteToken'] as String?;
    }

    // ✅ Initiate payment via backend.
    // Prefer the company's OWN CamerPay account when it is connected — the money
    // then reaches this bar directly. When the bar has not connected CamerPay the
    // server says so, and we fall back to the legacy rail with the same result
    // shape, so a bar that never connected keeps selling exactly as before.
    var result = await PaymentService.initiateCampayPayment(
      amount: amount,
      customerPhone: customerPhone,
      paymentMethod: paymentMethod,
      orderId: orderId,
      quoteToken: quoteToken,
    );
    if (result['success'] != true && result['fallback'] == true) {
      debugPrint(
          '↩️ CamerPay not ready for this company — using the legacy payment rail');
      result = await PaymentService.initiatePayment(
        amount: amount,
        customerPhone: customerPhone,
        paymentMethod: paymentMethod,
        orderId: orderId,
        quoteToken: quoteToken,
      );
    }

    if (!result['success']) {
      // In our words, not the provider's: the server sends a code, and its own
      // wording only for the cases where it is actionable (a KYC document limit).
      final failure = PaymentErrorHelper.fromResponse(result);
      debugPrint(
        '❌ CamerPay collection refused: ${failure.code}'
        '${failure.providerMessage == null ? '' : ' — ${failure.providerMessage}'}',
      );
      setState(() {
        _paymentStatus = 'failed';
        _paymentMessage = PaymentErrorHelper.messageWithDetail(failure);
      });
      return false;
    }

    final transactionId = result['transactionId'];

    final paymentUrl = result['paymentUrl'] as String?;
    final qrPng = result['qrPng'] as String?;

    // Card is paid on the CUSTOMER'S phone: the waiting dialog shows a QR, so the
    // till is never pulled into a browser and no device is handed over. Mobile
    // money keeps the old behaviour (open the provider page straight away).
    if (paymentMethod != 'card' &&
        paymentUrl != null &&
        paymentUrl.isNotEmpty) {
      final uri = Uri.parse(paymentUrl);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) await launchUrl(uri);
    }

    // ✅ Show payment confirmation dialog
    final confirmed = await _showPaymentConfirmationDialog(
      amount: amount,
      customerPhone: customerPhone,
      paymentMethod: paymentMethod,
      transactionId: transactionId,
      companyName: _companyName,
      paymentUrl: paymentUrl,
      qrPng: qrPng,
    );

    if (!confirmed) {
      setState(() {
        _paymentStatus = 'failed';
        _paymentMessage = t('paymentNotCompleted');
      });
      return false;
    }

    // ✅ Complete the order
    _setCompletionProgress(0.35);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final staffName =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.username ??
            '';
    _createdOrder = await orderProvider.createOrderAndGetOrder(
      _selectedDrinks,
      amount,
      customerName,
      staffName: staffName,
    );
    _setCompletionProgress(0.70);

    // 🔒 Atomic stock commit; the payment is already collected, so on failure we
    // roll the order back and tell the operator to reconcile.
    final stockOk = await _deductInventoryFromOrder();
    if (!stockOk) {
      // The sale is refused, so the row must stop counting as one — and it must be
      // a CANCELLATION, never a void: only some lines were deducted (they were put
      // back above), so restoring the whole order would invent stock.
      if (_createdOrder != null) {
        final cancelled = await orderProvider.cancelOrder(
            _createdOrder!.id, t('reasonStockRollback'));
        if (!cancelled) {
          Helpers.showToast(t('saleRollbackFailed'), isError: true);
        }
        _createdOrder = null;
      }
      return false;
    }

    _setCompletionProgress(0.90);
    // ✅ Update transaction status in Supabase
    await SupabaseService.updateTransactionStatus(orderId, 'completed');
    _setCompletionProgress(1.0);

    return true;
  }

  // ============================================================
  // 💬 PAYMENT CONFIRMATION DIALOG
  // ============================================================

  /// Waiting dialog for a non-cash payment.
  ///
  /// For card, [qrPng] is the backend-rendered QR of [paymentUrl]: the customer
  /// pays on THEIR phone (card number + 3-D Secure happen on CamerPay/Stripe),
  /// so staff never reads a number and nothing has to be handed over. The two
  /// buttons let the operator open the page here or send it to the customer.
  Future<bool> _showPaymentConfirmationDialog({
    required double amount,
    required String customerPhone,
    required String paymentMethod,
    required String transactionId,
    required String companyName,
    String? paymentUrl,
    String? qrPng,
  }) async {
    final completer = Completer<bool>();
    // Decoded once, before the dialog opens: Image.memory works on bytes.
    Uint8List? qrBytes;
    if (qrPng != null && qrPng.isNotEmpty) {
      try {
        qrBytes = base64Decode(qrPng.split(',').last);
      } catch (e) {
        debugPrint('QR payload could not be decoded: $e');
      }
    }
    final payUrl = paymentUrl ?? '';
    final canPayByLink = payUrl.isNotEmpty;
    bool _isDialogActive = true;
    Timer? _pollingTimer;
    int _attempts = 0;
    const int _maxAttempts = 30; // 5 minutes

    Future<void> checkStatus() async {
      if (!_isDialogActive) return;

      _attempts++;
      try {
        final status = await PaymentService.checkPaymentStatus(transactionId);

        if (status['status'] == 'completed') {
          _isDialogActive = false;
          _pollingTimer?.cancel();
          if (!completer.isCompleted) {
            completer.complete(true);
          }
        } else if (status['status'] == 'failed' ||
            status['status'] == 'rejected') {
          _isDialogActive = false;
          _pollingTimer?.cancel();
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        } else if (_attempts >= _maxAttempts) {
          _isDialogActive = false;
          _pollingTimer?.cancel();
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        }
      } catch (e) {
        // Ignore errors, continue polling
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(t('waitingForPayment')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (qrBytes != null) ...[
                    // White pad on purpose: the till theme may be dark, and a QR
                    // on a dark background does not scan.
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.memory(qrBytes,
                          width: 200, height: 200, gaplessPlayback: true),
                    ),
                    const SizedBox(height: 12),
                    Text(t('payScanQr'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(t('payScanQrHint'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ] else ...[
                    Icon(Icons.phone_android,
                        size: 60, color: Colors.orange),
                    SizedBox(height: 16),
                    Text(
                      t('calcCheckPhonePin'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(t('paymentDetails')),
                        Text(
                          '${t('total')}: ${CurrencyHelper.format(amount)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${t('payTo')}: $companyName',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        if (customerPhone.isNotEmpty)
                          Text(
                            '${t('phoneNumber')}: $customerPhone',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  LinearProgressIndicator(
                    backgroundColor: Colors.grey.shade200,
                    color: Colors.orange,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '${t('calcWaitingConfirmation')} (${_attempts * 10}s)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              actions: [
                if (canPayByLink)
                  TextButton(
                    onPressed: () async {
                      final uri = Uri.parse(payUrl);
                      final ok = await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                      if (!ok) await launchUrl(uri);
                    },
                    child: Text(t('payOpenHere')),
                  ),
                if (canPayByLink)
                  TextButton(
                    onPressed: () async {
                      try {
                        await SharePlus.instance.share(ShareParams(
                            text: '${t('payShareText')} $payUrl'));
                      } catch (e) {
                        debugPrint('Payment link could not be shared: $e');
                      }
                    },
                    child: Text(t('paySendLink')),
                  ),
                TextButton(
                  onPressed: () async {
                    _isDialogActive = false;
                    _pollingTimer?.cancel();
                    await PaymentService.cancelPayment(transactionId);
                    Navigator.pop(dialogContext);
                    if (!completer.isCompleted) {
                      completer.complete(false);
                    }
                  },
                  child: Text(t('cancel')),
                ),
                TextButton(
                  onPressed: () {
                    checkStatus();
                  },
                  child: Text(t('checkStatus')),
                ),
              ],
            );
          },
        );
      },
    );

    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      checkStatus();
    });

    await checkStatus();
    _pollingTimer?.cancel();

    return await completer.future;
  }

  // ============================================================
  // 💵 CASH PAYMENT
  // ============================================================

  Future<bool> _processCashPayment(String customerName) async {
    _setCompletionProgress(0.40);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final staffName =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.username ??
            '';
    _createdOrder = await orderProvider.createOrderAndGetOrder(
      _selectedDrinks,
      _amountPaid,
      customerName,
      staffName: staffName,
    );
    _setCompletionProgress(0.75);

    // 🔒 Commit the stock atomically. If the last unit was taken by someone
    // else in the meantime the sale is rolled back instead of going negative.
    final stockOk = await _deductInventoryFromOrder();
    if (!stockOk) {
      // A rollback, not a void: the lines that made it onto the floor were already
      // put back, so the order must simply stop counting.
      if (_createdOrder != null) {
        final cancelled = await orderProvider.cancelOrder(
            _createdOrder!.id, t('reasonStockRollback'));
        if (!cancelled) {
          Helpers.showToast(t('saleRollbackFailed'), isError: true);
        }
        _createdOrder = null;
      }
      return false;
    }
    return true;
  }

  // ============================================================
  // ✅ VALIDATION
  // ============================================================

  bool _validatePhoneNumber(String phone, String provider) {
    phone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (provider == 'mtn') {
      return RegExp(r'^(237)?(6[5789]|68[0-9])\d{7}$').hasMatch(phone);
    } else if (provider == 'orange') {
      return RegExp(r'^(237)?(6[9]|69[0-9])\d{7}$').hasMatch(phone);
    }
    return false;
  }

  // ============================================================
  // 💬 DIALOGS
  // ============================================================

  Future<String?> _showCustomerNameDialog({String? prefillName}) async {
    final TextEditingController nameController =
        TextEditingController(text: prefillName);
    // Registered, approved customers are offered first; a walk-in just types a
    // name in the field below.
    //
    // ⚠️ The list must be LOADED here: this screen never loaded the customer
    // accounts before, so `approved` was empty unless the operator had opened
    // the Customers screen first in the same session — and the registered
    // customer then never appeared in the customer information at payment time.
    final customerProvider = context.read<CustomerProvider>();
    if (!customerProvider.hasLoaded) {
      await customerProvider.load();
    }
    if (!mounted) return null;
    final approvedCustomers = customerProvider.approved;

    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t('customerInformation'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (approvedCustomers.isNotEmpty) ...[
                Text(t('chooseExistingCustomer'),
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: approvedCustomers.length,
                    itemBuilder: (context, i) {
                      final c = approvedCustomers[i];
                      // The number is the account's identity: it is what the
                      // statement, the ledger and the tab all refer to.
                      final identity = [c.customerNumber, c.phone]
                          .where((part) => part.isNotEmpty)
                          .join(' · ');
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline),
                        title: Text(c.name),
                        subtitle: identity.isEmpty ? null : Text(identity),
                        onTap: () => Navigator.pop(context, c.name),
                      );
                    },
                  ),
                ),
                const Divider(),
                Text(t('walkInCustomer'),
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
              ],
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: t('customerName'),
                  hintText: t('enterCustomerName'),
                  prefixIcon: const Icon(Icons.person_outline),
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF667EEA), width: 2)),
                ),
                autofocus: approvedCustomers.isEmpty,
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.pop(context, value.trim());
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(t('cancel'))),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(t('pleaseEnterCustomerName')),
                    backgroundColor: Colors.red));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF667EEA),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: Text(t('continue')),
          ),
        ],
      ),
    );
  }

  void _showResponsiveInvoice() {
    if (_createdOrder == null) {
      Helpers.showToast(t('noOrderToDisplay'), isError: true);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResponsiveInvoice(
          drinks: _selectedDrinks,
          totalAmount: _totalAmount,
          amountPaid: _selectedPaymentMethod == PaymentMethod.cash
              ? _amountPaid
              : _totalAmount,
          balance:
              _selectedPaymentMethod == PaymentMethod.cash ? _balance : 0.0,
          orderId: _createdOrder!.id,
          customerName: _createdOrder!.customerName,
          isPreview: false,
        ),
      ),
    ).then((_) {
      _clearAll();
    });
  }

  void _showDrinkManagementDialog() {
    _showPasswordDialog(
      title: t('passwordRequired'),
      message: t('manageDrinksPassword'),
      onVerified: () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const DrinkManagementScreen()));
      },
    );
  }

  void _showPasswordDialog(
      {required String title,
      required String message,
      required VoidCallback onVerified}) {
    final passwordController = TextEditingController();
    bool obscureText = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: Theme.of(context).cardColor,
            title: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).primaryColor.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Theme.of(context).primaryColor, width: 2),
                  ),
                  child: Icon(Icons.lock,
                      size: 32, color: Theme.of(context).primaryColor),
                ),
                SizedBox(height: 10),
                Text(title,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).hintColor, fontSize: 16)),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context).dividerColor, width: 1),
                  ),
                  child: TextField(
                    controller: passwordController,
                    obscureText: obscureText,
                    decoration: InputDecoration(
                      hintText: t('enterPassword'),
                      hintStyle: TextStyle(color: Theme.of(context).hintColor),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      prefixIcon: Icon(Icons.password,
                          color: Theme.of(context).primaryColor),
                      suffixIcon: IconButton(
                        icon: Icon(
                            obscureText
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Theme.of(context).primaryColor,
                            size: 20),
                        onPressed: () {
                          setState(() {
                            obscureText = !obscureText;
                          });
                        },
                      ),
                    ),
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                        fontSize: 16),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.info,
                        size: 14, color: Theme.of(context).hintColor),
                    SizedBox(width: 6),
                    Expanded(
                        child: Text(t('enterLoginPassword'),
                            style: TextStyle(
                                color: Theme.of(context).hintColor,
                                fontSize: 12))),
                  ],
                ),
              ],
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).hintColor,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                  width: 1))),
                      child: Text(t('cancel'),
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final authProvider =
                            Provider.of<AuthProvider>(context, listen: false);
                        if (authProvider
                            .verifyPassword(passwordController.text)) {
                          Navigator.pop(context);
                          onVerified();
                        } else {
                          _showErrorDialog(
                              t('accessDeniedDialog'), t('incorrectPassword'));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.verified, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(t('verify'),
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Theme.of(context).cardColor,
        title: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red, width: 2)),
              child:
                  Icon(Icons.error_outline, size: 32, color: Colors.red),
            ),
            SizedBox(height: 10),
            Text(title,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color)),
          ],
        ),
        content: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 16)),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding:
                      EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text(t('tryAgain'),
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Icon(Icons.logout, size: 48, color: Color(0xFFFF6B6B)),
            SizedBox(height: 10),
            Text(t('confirmLogout'),
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t('confirmLogoutDialog'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).hintColor, fontSize: 16)),
            SizedBox(height: 10),
            Text(t('logoutRedirect'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).hintColor.withValues(alpha: 0.8),
                    fontSize: 14)),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      padding: EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: Text(t('cancel'),
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final authProvider =
                        Provider.of<AuthProvider>(context, listen: false);
                    await authProvider.logout();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (context) => const AuthScreen()),
                      (Route<dynamic> route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF6B6B),
                      padding: EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: Text(t('logout'),
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 📊 UTILITY
  // ============================================================

  Map<String, int> _getDrinkSummary() {
    final Map<String, int> summary = {};
    for (final drink in _selectedDrinks) {
      summary[drink.name] = (summary[drink.name] ?? 0) + 1;
    }
    return summary;
  }

  void _toggleSideSlider() {
    setState(() {
      _isSideSliderOpen = !_isSideSliderOpen;
    });
  }

  void _openInvoiceHistory() {
    setState(() {
      _isSideSliderOpen = true;
    });
  }

  bool _canManageDrinks() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null) return false;

    final role = user.role.toLowerCase().trim();

    debugPrint(
        'User: ${user.username}, Role: $role, Can Manage: ${role == 'admin' || role == 'administrator' || role == 'customer' || role == 'manager'}');

    return role == 'admin' ||
        role == 'administrator' ||
        role == 'customer' ||
        role == 'manager';
  }

  bool _isStaff() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null) return false;

    final role = user.role.toLowerCase().trim();
    return role == 'staff';
  }

  void _filterDrinks(String query) {
    if (_isSelectingDrink) return;
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final allDrinks = drinkProvider.customDrinks;

    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredDrinks = _getSortedDrinks(allDrinks);
        _showDropdown = false;
      } else {
        _filteredDrinks = allDrinks
            .where((drink) =>
                drink.name.toLowerCase().contains(query.toLowerCase()))
            .toList()
          ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _showDropdown = true;
      }
    });
  }

  // ============================================================
  // 🏗️ BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final drinkProvider = Provider.of<DrinkProvider>(context);
    final user = authProvider.currentUser;
    final drinkSummary = _getDrinkSummary();
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final isDarkMode = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    final allDrinks = [...drinkProvider.customDrinks];
    final sortedDrinks = _getSortedDrinks(allDrinks);

    return GestureDetector(
      onTap: () => LockService().resetTimer(),
      onPanDown: (_) => LockService().resetTimer(),
      onScaleStart: (_) => LockService().resetTimer(),
      onLongPress: () => LockService().resetTimer(),
      behavior: HitTestBehavior.translucent,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          Scaffold(
            key: _scaffoldKey,
            drawer: CustomDrawer(onInvoiceHistoryTap: _openInvoiceHistory),
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkMode
                      ? [Colors.grey[900]!, Colors.grey[800]!]
                      : [primaryColor, primaryColor.withValues(alpha: 0.7)],
                ),
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;
                    final isTablet = constraints.maxWidth >= 600 &&
                        constraints.maxWidth < 1200;

                    return SingleChildScrollView(
                        child: Container(
                      child: Padding(
                        padding: EdgeInsets.zero,
                        child: Card(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                          color: theme.cardColor,
                          child: Padding(
                            padding: EdgeInsets.all(isMobile
                                ? 16
                                : isTablet
                                    ? 24
                                    : 30),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isMobile)
                                  _buildMobileHeader(user, theme, primaryColor)
                                else if (isTablet)
                                  _buildTabletHeader(user, theme, primaryColor)
                                else
                                  _buildDesktopHeader(
                                      user, theme, primaryColor),
                                SizedBox(height: 30),
                                if (isMobile)
                                  _buildMobileContent(sortedDrinks,
                                      drinkSummary, theme, primaryColor)
                                else
                                  _buildDesktopTabletContent(
                                      sortedDrinks,
                                      drinkSummary,
                                      isTablet,
                                      theme,
                                      primaryColor),
                                const SizedBox(height: 30),
                                if (_businessPaymentsEnabled)
                                  _buildPaymentMethodSelector(
                                      isMobile, theme, primaryColor),
                                const SizedBox(height: 20),
                                _buildPaymentSection(
                                    isMobile, isTablet, theme, primaryColor),
                                const SizedBox(height: 20),
                                if (_isProcessingPayment ||
                                    _paymentStatus != null)
                                  _buildPaymentStatusDisplay(
                                      isMobile, theme, primaryColor),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _isProcessingPayment
                                            ? null
                                            : _processPayment,
                                        icon: _isProcessingPayment
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white))
                                            : Icon(Icons.check_circle,
                                                size: 22, color: Colors.white),
                                        label: Text(
                                            _isProcessingPayment
                                                ? '${t('completingOrder')} ${(_completionProgress * 100).round()}%'
                                                : t('finalizePurchase'),
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _isProcessingPayment
                                              ? Colors.grey
                                              : Colors.green,
                                          padding: EdgeInsets.symmetric(
                                              vertical: isMobile ? 16 : 20),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(15)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ));
                  },
                ),
              ),
            ),
          ),
          SideSlider(
            isOpen: _isSideSliderOpen,
            onClose: _toggleSideSlider,
            parentContext: context,
            primaryColor: Theme.of(context).primaryColor,
            secondaryColor:
                Theme.of(context).primaryColor.withValues(alpha: 0.7),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            cardColor: Theme.of(context).cardColor,
            textPrimaryColor:
                Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
            textSecondaryColor: Theme.of(context).hintColor,
            isDarkMode: Theme.of(context).brightness == Brightness.dark,
            onImportInvoice: (List<Drink> drinks, double amountPaid,
                double balance, String customerName, String originalOrderId) {
              setState(() {
                _selectedDrinks.clear();
                _totalAmount = 0.0;
                _amountPaid = 0.0;
                _balance = 0.0;
                _amountPaidController.clear();
                _selectedQuantity = 1;
                _selectedDrinkId = null;
                _lastAddedDrinkName = null;
                _expandedDrinkName = null;
                _selectedPaymentMethod = PaymentMethod.cash;
                _customerPhoneController.clear();
                _paymentStatus = null;
                _paymentMessage = null;
                _importedCustomerName = customerName;
                _originalOrderId = originalOrderId;
              });
              if (drinks.isNotEmpty) {
                Future.microtask(() {
                  for (final drink in drinks) {
                    _addDrink(drink);
                  }
                  setState(() {
                    _amountPaidController.text = amountPaid.toString();
                    _calculateBalance();
                  });
                });
              }
              Helpers.showToast(t('invoiceLoadedForEdit'));
            },
          ),
          Positioned(
            bottom: 25,
            right: 25,
            child: FloatingAIButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AIAssistantScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🏗️ HEADER BUILDERS
  // ============================================================

  // 🔔 Live notification bell with unread badge — opens the notification
  // center. Used by all three header layouts (mobile/tablet/desktop).
  Widget _buildNotificationBell(Color primaryColor) {
    final service = NotificationService();
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final unread = service.unreadCount;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(10)),
              child: IconButton(
                tooltip: 'Notifications',
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(
                    minWidth: 38, minHeight: 38),
                icon: const Icon(Icons.notifications,
                    color: Colors.white, size: 20),
                onPressed: () {
                  final plan = context.read<PlanProvider>();
                  if (!plan.canAccess('inbox')) {
                    Helpers.showToast(t('upgradeRequired'), isError: true);
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen()),
                  );
                },
              ),
            ),
            if (unread > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                  constraints: const BoxConstraints(
                      minWidth: 16, minHeight: 16),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMobileHeader(User? user, ThemeData theme, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              decoration: BoxDecoration(
                  color: primaryColor, borderRadius: BorderRadius.circular(12)),
              child: IconButton(
                  icon: Icon(Icons.menu, color: Colors.white, size: 32),
                  onPressed: () {
                    _scaffoldKey.currentState?.openDrawer();
                  }),
            ),
            const SizedBox(width: 16),
            // Expanded + ellipsis: a narrow phone must not overflow, and the
            // French heading is longer than the English one.
            Expanded(
              child: Text(t('appName'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: primaryColor)),
            ),
            _buildNotificationBell(primaryColor),
          ],
        ),
        SizedBox(height: 5),
        Text(t('appTagline'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: theme.hintColor)),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${t('welcome')}, ',
                      style: TextStyle(color: Colors.green, fontSize: 13)),
                  Icon(Icons.person, color: primaryColor, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(user?.username ?? t('user'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.green, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_canManageDrinks()) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showDrinkManagementDialog,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20))),
                        icon: Icon(Icons.edit_note,
                            size: 14, color: Colors.white),
                        label: Text(t('manageDrinks'),
                            style:
                                TextStyle(fontSize: 11, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (_isStaff()) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _isSideSliderOpen = true;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20))),
                        icon: Icon(Icons.receipt_long,
                            size: 16, color: Colors.white),
                        label: Text(t('invoiceHistory'),
                            style:
                                TextStyle(fontSize: 12, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showLogoutDialog,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade400,
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20))),
                      icon: Icon(Icons.logout,
                          size: 14, color: Colors.white),
                      label: Text(t('logout'),
                          style: TextStyle(fontSize: 11, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabletHeader(User? user, ThemeData theme, Color primaryColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              decoration: BoxDecoration(
                  color: primaryColor, borderRadius: BorderRadius.circular(12)),
              child: IconButton(
                  icon: Icon(Icons.menu, color: Colors.white, size: 32),
                  onPressed: () {
                    _scaffoldKey.currentState?.openDrawer();
                  }),
            ),
            SizedBox(width: 16),
            Text(t('appName'),
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: primaryColor)),
            const SizedBox(width: 16),
            _buildNotificationBell(primaryColor),
          ],
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              Text('${t('welcome')}, ',
                  style: TextStyle(color: Colors.green, fontSize: 13)),
              Icon(Icons.person, color: primaryColor, size: 18),
              SizedBox(width: 8),
              Text(user?.username ?? t('user'),
                  style: TextStyle(color: Colors.green)),
              const SizedBox(width: 12),
              Container(width: 1, height: 20, color: theme.dividerColor),
              const SizedBox(width: 12),
              if (_canManageDrinks()) ...[
                ElevatedButton.icon(
                  onPressed: _showDrinkManagementDialog,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  icon: Icon(Icons.edit_note,
                      size: 16, color: Colors.white),
                  label: Text(t('manageDrinks'),
                      style: TextStyle(fontSize: 12, color: Colors.white)),
                ),
                const SizedBox(width: 8),
              ] else if (_isStaff()) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isSideSliderOpen = true;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20))),
                    icon: Icon(Icons.receipt_long,
                        size: 18, color: Colors.white),
                    label: Text(t('invoiceHistory'),
                        style: TextStyle(fontSize: 14, color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              ElevatedButton.icon(
                onPressed: _showLogoutDialog,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade400,
                    padding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20))),
                icon: Icon(Icons.logout, size: 16, color: Colors.white),
                label: Text(t('logout'),
                    style: TextStyle(fontSize: 12, color: Colors.white)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopHeader(User? user, ThemeData theme, Color primaryColor) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              decoration: BoxDecoration(
                  color: primaryColor, borderRadius: BorderRadius.circular(12)),
              child: IconButton(
                  icon: Icon(Icons.menu, color: Colors.white, size: 32),
                  onPressed: () {
                    _scaffoldKey.currentState?.openDrawer();
                  }),
            ),
            SizedBox(width: 16),
            Text(t('appName'),
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: primaryColor)),
            const SizedBox(width: 16),
            _buildNotificationBell(primaryColor),
          ],
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(25)),
          child: Row(
            children: [
              Text('${t('welcome')}, ',
                  style: TextStyle(color: Colors.green, fontSize: 13)),
              Icon(Icons.person, color: primaryColor, size: 20),
              SizedBox(width: 10),
              Text(user?.username ?? t('user'),
                  style: TextStyle(color: Colors.green, fontSize: 16)),
              const SizedBox(width: 16),
              Container(width: 1, height: 24, color: theme.dividerColor),
              const SizedBox(width: 16),
              if (_canManageDrinks()) ...[
                ElevatedButton.icon(
                  onPressed: _showDrinkManagementDialog,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  icon: Icon(Icons.edit_note,
                      size: 18, color: Colors.white),
                  label: Text(t('manageDrinks'),
                      style: TextStyle(fontSize: 14, color: Colors.white)),
                ),
                const SizedBox(width: 12),
              ] else if (_isStaff()) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isSideSliderOpen = true;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20))),
                    icon: Icon(Icons.receipt_long,
                        size: 18, color: Colors.white),
                    label: Text(t('invoiceHistory'),
                        style: TextStyle(fontSize: 14, color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (authProvider.isAdmin) ...[
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const AdminPanel()));
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      padding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  icon: Icon(Icons.admin_panel_settings,
                      size: 18, color: Colors.white),
                  label: Text(t('adminPanel'),
                      style: TextStyle(fontSize: 14, color: Colors.white)),
                ),
              ],
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _showLogoutDialog,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade400,
                    padding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20))),
                icon: Icon(Icons.logout, size: 18, color: Colors.white),
                label: Text(t('logout'),
                    style: TextStyle(fontSize: 14, color: Colors.white)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 📱 CONTENT BUILDERS
  // ============================================================

  Widget _buildMobileContent(List<Drink> sortedDrinks,
      Map<String, int> drinkSummary, ThemeData theme, Color primaryColor) {
    return Column(
      children: [
        Text('${t('calcSelectDrink')}:',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: theme.textTheme.bodyLarge?.color)),
        SizedBox(height: 10),
        CompositedTransformTarget(
          link: _layerLink,
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: t('searchDrinks'),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _selectedDrinkId = null;
                          _searchQuery = '';
                        });
                      },
                    )
                  : const Icon(Icons.arrow_drop_down, size: 24),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: theme.dividerColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: primaryColor, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: theme.dividerColor),
              ),
              filled: true,
              fillColor: theme.cardColor,
            ),
            onTap: () {
              setState(() {
                _showDropdown = true;
                if (_filteredDrinks.isEmpty && _searchQuery.isEmpty) {
                  _filteredDrinks = _getSortedDrinks(
                      Provider.of<DrinkProvider>(context, listen: false)
                          .customDrinks);
                }
              });
            },
            style: TextStyle(
                color: theme.textTheme.bodyLarge?.color, fontSize: 14),
          ),
        ),
        if (_showDropdown)
          CompositedTransformFollower(
            link: _layerLink,
            offset: Offset(0, 48),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: _filteredDrinks.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off,
                                size: 40, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              t('noDrinksFound'),
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _filteredDrinks.length,
                        itemBuilder: (context, index) {
                          final drink = _filteredDrinks[index];
                          final isOutOfStock = drink.currentStock <= 0;
                          final isLowStock = drink.currentStock > 0 &&
                              drink.currentStock <= drink.minimumLevel;

                          return ListTile(
                            dense: true,
                            leading: DrinkAvatar(
                              drink: drink,
                              size: 30,
                              foreground: isOutOfStock
                                  ? Colors.red
                                  : primaryColor,
                            ),
                            title: Text(
                              drink.name,
                              style: TextStyle(
                                fontSize: 14,
                                color: isOutOfStock
                                    ? Colors.red
                                    : theme.textTheme.bodyLarge?.color,
                                fontWeight: isOutOfStock
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  CurrencyHelper.format(drink.price),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isOutOfStock
                                        ? Colors.red
                                        : primaryColor,
                                  ),
                                ),
                                if (isOutOfStock)
                                  Text(
                                    t('outOfStock'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                if (isLowStock && !isOutOfStock)
                                  Text(
                                    '${t('calcLowStock')} (${drink.currentStock})',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                            onTap: isOutOfStock
                                ? null
                                : () {
                                    _isSelectingDrink = true;
                                    _searchFocusNode.unfocus();
                                    setState(() {
                                      _selectedDrinkId = drink.id;
                                      _showDropdown = false;
                                      _searchController.text =
                                          '${drink.name} - ${CurrencyHelper.format(drink.price)}';
                                      _searchQuery = drink.name;
                                    });
                                    FocusScope.of(context).unfocus();
                                    Future.delayed(
                                        const Duration(milliseconds: 100), () {
                                      _isSelectingDrink = false;
                                    });
                                  },
                          );
                        },
                      ),
              ),
            ),
          ),
        SizedBox(height: 20),
        Text('${t('calcSelectQuantity')}:',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: theme.textTheme.bodyLarge?.color)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: () {
                        setState(() {
                          if (_selectedQuantity > 1) _selectedQuantity--;
                        });
                      },
                      color: theme.hintColor),
                  // Tap the number to type the quantity with the keyboard.
                  InkWell(
                    onTap: _promptQuantity,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                        width: 44,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('$_selectedQuantity',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: theme.textTheme.bodyLarge?.color))),
                  ),
                  IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: () {
                        setState(() {
                          if (_selectedQuantity < 99) _selectedQuantity++;
                        });
                      },
                      color: theme.hintColor),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Flexible: the button label is longer in French ("Ajouter à la
            // commande") and used to overflow the row on a 390 px phone.
            Flexible(
              child: ElevatedButton(
                onPressed: () {
                  if (_selectedDrinkId != null && sortedDrinks.isNotEmpty) {
                    final selectedDrink =
                        sortedDrinks.firstWhere((d) => d.id == _selectedDrinkId);
                    if (selectedDrink.currentStock <= 0) {
                      Helpers.showToast(
                          '${selectedDrink.name} — ${t('outOfStockToast')}',
                          isError: true);
                      return;
                    }
                    _addDrink(selectedDrink);
                  } else {
                    Helpers.showToast(t('selectDrinkFirst'));
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                child: Text(t('addToOrder'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: Colors.white)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
                child: ElevatedButton.icon(
                    onPressed: _clearAll,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        padding: EdgeInsets.symmetric(vertical: 12)),
                    icon:
                        Icon(Icons.delete, size: 18, color: Colors.white),
                    label: Text(t('clearAll'),
                        style: TextStyle(fontSize: 14, color: Colors.white)))),
            const SizedBox(width: 10),
            Expanded(
                child: ElevatedButton.icon(
                    onPressed: _showPreviewInvoice,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: EdgeInsets.symmetric(vertical: 12)),
                    icon: Icon(Icons.receipt,
                        size: 18, color: Colors.white),
                    label: Text(t('preview'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: Colors.white)))),
          ],
        ),
        SizedBox(height: 20),
        _buildSelectedDrinksList(drinkSummary, true, theme, primaryColor),
      ],
    );
  }

  Widget _buildDesktopTabletContent(
      List<Drink> sortedDrinks,
      Map<String, int> drinkSummary,
      bool isTablet,
      ThemeData theme,
      Color primaryColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t('calcSelectDrinkQty')}:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: theme.textTheme.bodyLarge?.color)),
              SizedBox(height: 15),
              CompositedTransformTarget(
                link: _layerLink,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: t('searchDrinks'),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _selectedDrinkId = null;
                                _searchQuery = '';
                              });
                            },
                          )
                        : const Icon(Icons.arrow_drop_down, size: 24),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    filled: true,
                    fillColor: theme.cardColor,
                  ),
                  onTap: () {
                    setState(() {
                      _showDropdown = true;
                      if (_filteredDrinks.isEmpty && _searchQuery.isEmpty) {
                        _filteredDrinks = _getSortedDrinks(
                            Provider.of<DrinkProvider>(context, listen: false)
                                .customDrinks);
                      }
                    });
                  },
                  style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: isTablet ? 14 : 16),
                ),
              ),
              if (_showDropdown)
                CompositedTransformFollower(
                  link: _layerLink,
                  offset: Offset(0, 48),
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: _filteredDrinks.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off,
                                      size: 40, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text(
                                    t('noDrinkFound'),
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: _filteredDrinks.length,
                              itemBuilder: (context, index) {
                                final drink = _filteredDrinks[index];
                                final isOutOfStock = drink.currentStock <= 0;
                                final isLowStock = drink.currentStock > 0 &&
                                    drink.currentStock <= drink.minimumLevel;

                                return ListTile(
                                  dense: true,
                                  leading: DrinkAvatar(
                                    drink: drink,
                                    size: 30,
                                    foreground: isOutOfStock
                                        ? Colors.red
                                        : primaryColor,
                                  ),
                                  title: Text(
                                    drink.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isOutOfStock
                                          ? Colors.red
                                          : theme.textTheme.bodyLarge?.color,
                                      fontWeight: isOutOfStock
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        CurrencyHelper.format(drink.price),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isOutOfStock
                                              ? Colors.red
                                              : primaryColor,
                                        ),
                                      ),
                                      if (isOutOfStock)
                                        Text(
                                          t('outOfStock'),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      if (isLowStock && !isOutOfStock)
                                        Text(
                                          '${t('calcLowStock')} (${drink.currentStock})',
                                          style: const TextStyle(
                                            fontSize: 9,
                                            color: Colors.orange,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                    ],
                                  ),
                                  onTap: isOutOfStock
                                      ? null
                                      : () {
                                          _isSelectingDrink = true;
                                          _searchFocusNode.unfocus();
                                          setState(() {
                                            _selectedDrinkId = drink.id;
                                            _showDropdown = false;
                                            _searchController.text =
                                                '${drink.name} - ${CurrencyHelper.format(drink.price)}';
                                            _searchQuery = drink.name;
                                          });
                                          FocusScope.of(context).unfocus();
                                          Future.delayed(
                                              const Duration(milliseconds: 100),
                                              () {
                                            _isSelectingDrink = false;
                                          });
                                        },
                                );
                              },
                            ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${t('quantity')}:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: theme.textTheme.bodyLarge?.color)),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                              border: Border.all(color: theme.dividerColor),
                              borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                  icon: Icon(Icons.remove,
                                      size: isTablet ? 20 : 24),
                                  onPressed: () {
                                    setState(() {
                                      if (_selectedQuantity > 1)
                                        _selectedQuantity--;
                                    });
                                  },
                                  color: theme.hintColor),
                              // Tap the number to type the quantity.
                              InkWell(
                                onTap: _promptQuantity,
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                    width: isTablet ? 52 : 62,
                                    alignment: Alignment.center,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Text('$_selectedQuantity',
                                        style: TextStyle(
                                            fontSize: isTablet ? 16 : 18,
                                            fontWeight: FontWeight.bold,
                                            color: theme
                                                .textTheme.bodyLarge?.color))),
                              ),
                              IconButton(
                                  icon:
                                      Icon(Icons.add, size: isTablet ? 20 : 24),
                                  onPressed: () {
                                    setState(() {
                                      if (_selectedQuantity < 99)
                                        _selectedQuantity++;
                                    });
                                  },
                                  color: theme.hintColor),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      children: [
                        const SizedBox(height: 25),
                        ElevatedButton(
                          onPressed: () {
                            if (_selectedDrinkId != null &&
                                sortedDrinks.isNotEmpty) {
                              final selectedDrink = sortedDrinks
                                  .firstWhere((d) => d.id == _selectedDrinkId);
                              _addDrink(selectedDrink);
                            } else {
                              Helpers.showToast(t('calcSelectDrinkFirst'));
                            }
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 24 : 32,
                                  vertical: isTablet ? 12 : 16)),
                          child: Text(t('addToOrder'),
                              style: TextStyle(
                                  fontSize: isTablet ? 14 : 16,
                                  color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              Row(
                children: [
                  Expanded(
                      child: ElevatedButton.icon(
                          onPressed: _clearAll,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade400,
                              padding: EdgeInsets.symmetric(
                                  vertical: isTablet ? 12 : 16)),
                          icon: Icon(Icons.delete,
                              size: 20, color: Colors.white),
                          label: Text(t('clearAll'),
                              style: TextStyle(
                                  fontSize: isTablet ? 14 : 16,
                                  color: Colors.white)))),
                  const SizedBox(width: 15),
                  Expanded(
                      child: ElevatedButton.icon(
                          onPressed: _showPreviewInvoice,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: EdgeInsets.symmetric(
                                  vertical: isTablet ? 12 : 16)),
                          icon: Icon(Icons.receipt,
                              size: 20, color: Colors.white),
                          label: Text(t('previewInvoice'),
                              style: TextStyle(
                                  fontSize: isTablet ? 14 : 16,
                                  color: Colors.white)))),
                ],
              ),
            ],
          ),
        ),
        SizedBox(width: 30),
        Expanded(
            flex: 3,
            child: _buildSelectedDrinksList(
                drinkSummary, isTablet, theme, primaryColor)),
      ],
    );
  }

  Widget _buildSelectedDrinksList(Map<String, int> drinkSummary, bool isMobile,
      ThemeData theme, Color primaryColor) {
    final sortedEntries = drinkSummary.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    // ✅ Get current stock from provider
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: true);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: primaryColor),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(children: [
          // Header
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(t('selectedDrinks'),
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 12 : 14)),
                Row(children: [
                  Icon(Icons.sort_by_alpha,
                      color: Colors.white, size: isMobile ? 14 : 16),
                  const SizedBox(width: 4),
                ]),
              ],
            ),
          ),

          // Empty state
          if (_selectedDrinks.isEmpty)
            SizedBox(
              height: isMobile ? 150 : 250,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_cart,
                        size: isMobile ? 50 : 60, color: theme.hintColor),
                    SizedBox(height: 10),
                    Text(t('noDrinksSelected'),
                        style: TextStyle(
                            fontSize: isMobile ? 18 : 20,
                            color: theme.hintColor)),
                    SizedBox(height: 5),
                    Text(t('selectDrinksAbove'),
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            color: theme.hintColor))
                  ],
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: isMobile ? 300 : 450),
              child: ListView.builder(
                controller: _selectedDrinksScrollController,
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                itemCount: sortedEntries.length,
                itemBuilder: (context, index) {
                  final entry = sortedEntries[index];
                  final drinkName = entry.key;
                  final quantity = entry.value;
                  final drink =
                      _selectedDrinks.firstWhere((d) => d.name == drinkName);
                  final isExpanded = _expandedDrinkName == drinkName;
                  final isNewlyAdded = _lastAddedDrinkName == drinkName;

                  // ✅ Get current stock from provider
                  final currentDrink = drinkProvider.customDrinks.firstWhere(
                    (d) => d.id == drink.id,
                    orElse: () => drink,
                  );
                  final remainingStock = currentDrink.currentStock - quantity;
                  final isOutOfStock = remainingStock <= 0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Card(
                      color: isNewlyAdded
                          ? Colors.green.withValues(alpha: 0.1)
                          : (isExpanded
                              ? primaryColor.withValues(alpha: 0.05)
                              : theme.cardColor),
                      elevation: isNewlyAdded ? 4 : (isExpanded ? 2 : 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isOutOfStock
                            ? BorderSide(color: Colors.red, width: 1)
                            : BorderSide.none,
                      ),
                      child: InkWell(
                        onTap: () => setState(() => _expandedDrinkName =
                            _expandedDrinkName == drinkName ? null : drinkName),
                        borderRadius: BorderRadius.circular(12),
                        child: Column(children: [
                          Padding(
                            padding: EdgeInsets.all(isMobile ? 12 : 16),
                            child: Row(children: [
                              DrinkAvatar(
                                drink: drink,
                                size: isMobile ? 34 : 40,
                                circular: false,
                                foreground: isNewlyAdded
                                    ? Colors.green
                                    : (isOutOfStock
                                        ? Colors.red
                                        : primaryColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(drinkName,
                                            style: TextStyle(
                                                fontSize: isMobile ? 14 : 16,
                                                fontWeight: isNewlyAdded
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                color: isOutOfStock
                                                    ? Colors.red
                                                    : theme.textTheme.bodyLarge
                                                        ?.color)),
                                        if (isNewlyAdded)
                                          Text(' ✓ Added just now!',
                                              style: TextStyle(
                                                  fontSize: isMobile ? 10 : 12,
                                                  color: Colors.green)),
                                      ],
                                    ),
                                    // ✅ Show remaining stock
                                    Row(
                                      children: [
                                        Icon(Icons.inventory,
                                            size: isMobile ? 12 : 14,
                                            color: isOutOfStock
                                                ? Colors.red
                                                : Colors.grey),
                                        SizedBox(width: 4),
                                        Text(
                                          'Remaining: ${remainingStock > 0 ? remainingStock : 0}',
                                          style: TextStyle(
                                            fontSize: isMobile ? 10 : 12,
                                            color: isOutOfStock
                                                ? Colors.red
                                                : Colors.grey[600],
                                            fontWeight: isOutOfStock
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (isOutOfStock)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(t('outOfStock'),
                                                style: TextStyle(
                                                    fontSize: 8,
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${quantity}x',
                                      style: TextStyle(
                                          fontSize: isMobile ? 16 : 18,
                                          fontWeight: FontWeight.bold,
                                          color: isOutOfStock
                                              ? Colors.red
                                              : primaryColor)),
                                  Text(CurrencyHelper.format(drink.price),
                                      style: TextStyle(
                                          fontSize: isMobile ? 11 : 12,
                                          color: theme.hintColor)),
                                  Text(
                                      CurrencyHelper.format(
                                          quantity * drink.price),
                                      style: TextStyle(
                                          fontSize: isMobile ? 14 : 16,
                                          fontWeight: FontWeight.bold,
                                          color: isOutOfStock
                                              ? Colors.red
                                              : primaryColor)),
                                ],
                              ),
                              IconButton(
                                  icon: Icon(Icons.delete_outline,
                                      color: Colors.red.shade400,
                                      size: isMobile ? 20 : 24),
                                  onPressed: () => _clearDrink(drinkName),
                                  tooltip: t('removeAll')),
                            ]),
                          ),
                          if (isExpanded)
                            _buildExpandedQuantityControls(
                              drink: drink,
                              drinkName: drinkName,
                              quantity: quantity,
                              remainingStock: remainingStock,
                              isMobile: isMobile,
                              theme: theme,
                              primaryColor: primaryColor,
                            ),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),

          // Total
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${t('total')}:',
                    style: TextStyle(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color)),
                Text(CurrencyHelper.format(_totalAmount),
                    style: TextStyle(
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.bold,
                        color: primaryColor)),
              ],
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildExpandedQuantityControls({
    required Drink drink,
    required String drinkName,
    required int quantity,
    required int remainingStock,
    required bool isMobile,
    required ThemeData theme,
    required Color primaryColor,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Column(children: [
        Divider(color: theme.dividerColor),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${t('calcAdjustQuantity')}:',
                    style: TextStyle(
                        fontSize: isMobile ? 12 : 14,
                        fontWeight: FontWeight.w600,
                        color: theme.hintColor)),
                if (remainingStock > 0)
                  Text('$remainingStock ${t('calcMoreAvailable')}',
                      style: TextStyle(
                          fontSize: isMobile ? 10 : 12, color: Colors.green)),
                if (remainingStock <= 0)
                  Text(t('outOfStockToast'),
                      style: TextStyle(
                          fontSize: isMobile ? 10 : 12,
                          color: Colors.red,
                          fontWeight: FontWeight.bold)),
              ],
            ),
            Row(children: [
              // Decrease button
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: Icon(Icons.remove, size: isMobile ? 18 : 20),
                  onPressed: quantity > 1
                      ? () => _decreaseDrinkQuantity(drinkName)
                      : null,
                  color: quantity > 1 ? Colors.red : Colors.grey,
                ),
              ),
              Container(
                width: isMobile ? 50 : 60,
                alignment: Alignment.center,
                child: Text('$quantity',
                    style: TextStyle(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: primaryColor)),
              ),
              // Add button with stock check
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: Icon(Icons.add, size: isMobile ? 18 : 20),
                  onPressed: remainingStock > 0
                      ? () => _addDrink(drink, scrollToDrink: false)
                      : null,
                  color: remainingStock > 0 ? Colors.green : Colors.grey,
                  tooltip: remainingStock > 0
                      ? '${t('calcAddOneMore')} ($remainingStock ${t('calcLeftShort')})'
                      : t('outOfStockToast'),
                ),
              ),
            ]),
          ],
        ),
        SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () => _clearDrink(drinkName),
              icon: Icon(Icons.delete_forever, size: isMobile ? 16 : 18),
              label: Text(t('removeAll'),
                  style: TextStyle(fontSize: isMobile ? 12 : 14)),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: () => setState(() => _expandedDrinkName = null),
              icon: Icon(Icons.close, size: isMobile ? 16 : 18),
              label:
                  Text(t('close'), style: TextStyle(fontSize: isMobile ? 12 : 14)),
              style: TextButton.styleFrom(foregroundColor: theme.hintColor),
            ),
          ),
        ]),
      ]),
    );
  }
  // ============================================================
  // 💳 PAYMENT UI BUILDERS
  // ============================================================

  Widget _buildPaymentSection(
      bool isMobile, bool isTablet, ThemeData theme, Color primaryColor) {
    if (_selectedPaymentMethod != PaymentMethod.cash &&
        _businessPaymentsEnabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('orderSummary'),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: theme.textTheme.bodyLarge?.color)),
          const SizedBox(height: 15),
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primaryColor.withValues(alpha: 0.2))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${t('total')}:',
                    style: TextStyle(
                        fontSize: isMobile ? 16 : 20,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color)),
                Text(CurrencyHelper.format(_totalAmount),
                    style: TextStyle(
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.bold,
                        color: primaryColor)),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('paymentDetails'),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: theme.textTheme.bodyLarge?.color)),
        SizedBox(height: 15),
        Text('${t('inv_amountReceived')}:',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: primaryColor)),
        const SizedBox(height: 10),
        TextField(
          controller: _amountPaidController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '${t('calcEnterAmount')} ${CurrencyHelper.getSymbol()}',
            prefixIcon: Icon(Icons.attach_money, size: isMobile ? 20 : 24),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: theme.dividerColor)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: primaryColor, width: 2)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: theme.dividerColor)),
          ),
          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        ),
        SizedBox(height: 20),
        GestureDetector(
          onTap: () {
            _calculateBalance();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'Balance refreshed: ${CurrencyHelper.format(_balance.abs())}'),
                backgroundColor: primaryColor,
                duration: const Duration(seconds: 2)));
          },
          child: Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
                color: _balance >= 0
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _balance >= 0 ? Colors.green : Colors.red,
                    width: 2)),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Text(_balance >= 0 ? 'Change:' : 'Balance Due:',
                          style: TextStyle(
                              fontSize: isMobile ? 16 : 20,
                              fontWeight: FontWeight.bold,
                              color:
                                  _balance >= 0 ? Colors.green : Colors.red)),
                      SizedBox(width: isMobile ? 6 : 8),
                      Icon(Icons.refresh,
                          color: _balance >= 0 ? Colors.green : Colors.red,
                          size: isMobile ? 16 : 20)
                    ]),
                    Text(CurrencyHelper.format(_balance.abs()),
                        style: TextStyle(
                            fontSize: isMobile ? 20 : 28,
                            fontWeight: FontWeight.bold,
                            color: _balance >= 0 ? Colors.green : Colors.red)),
                  ],
                ),
                SizedBox(height: 8),
                if (_balance >= 0 && _balance > 0)
                  Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Text(
                          t('calcTapToRefreshChange'),
                          style: TextStyle(
                              color: Colors.green,
                              fontSize: isMobile ? 12 : 14))),
                if (_balance < 0)
                  Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Text(t('calcTapToRefreshDue'),
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: isMobile ? 12 : 14))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodSelector(
      bool isMobile, ThemeData theme, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('paymentMethod'),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isMobile ? 16 : 18,
                color: theme.textTheme.bodyLarge?.color)),
        const SizedBox(height: 12),
        isMobile
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildPaymentMethodOption(
                    icon: Icons.money,
                    label: t('cash'),
                    isSelected: _selectedPaymentMethod == PaymentMethod.cash,
                    color: Colors.green,
                    onTap: () {
                      setState(() {
                        _selectedPaymentMethod = PaymentMethod.cash;
                      });
                    },
                    theme: theme,
                    isMobile: isMobile,
                  ),
                  if (_mtnEnabled)
                    _buildPaymentMethodOption(
                      icon: Icons.phone_android,
                      label: 'MTN MoMo',
                      isSelected: _selectedPaymentMethod ==
                          PaymentMethod.mtnMobileMoney,
                      color: const Color(0xFFFFCC00),
                      textColor: Colors.black,
                      onTap: () {
                        setState(() {
                          _selectedPaymentMethod = PaymentMethod.mtnMobileMoney;
                        });
                      },
                      theme: theme,
                      isMobile: isMobile,
                    ),
                  if (_orangeEnabled)
                    _buildPaymentMethodOption(
                      icon: Icons.phone_android,
                      label: 'Orange Money',
                      isSelected:
                          _selectedPaymentMethod == PaymentMethod.orangeMoney,
                      color: const Color(0xFFFF6600),
                      onTap: () {
                        setState(() {
                          _selectedPaymentMethod = PaymentMethod.orangeMoney;
                        });
                      },
                      theme: theme,
                      isMobile: isMobile,
                    ),
                  if (_cardEnabled)
                    _buildPaymentMethodOption(
                      icon: Icons.credit_card,
                      label: 'Card',
                      isSelected: _selectedPaymentMethod == PaymentMethod.card,
                      color: Colors.blue,
                      onTap: () {
                        setState(() {
                          _selectedPaymentMethod = PaymentMethod.card;
                        });
                      },
                      theme: theme,
                      isMobile: isMobile,
                    ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: _buildPaymentMethodOption(
                      icon: Icons.money,
                      label: t('cash'),
                      isSelected: _selectedPaymentMethod == PaymentMethod.cash,
                      color: Colors.green,
                      onTap: () {
                        setState(() {
                          _selectedPaymentMethod = PaymentMethod.cash;
                        });
                      },
                      theme: theme,
                      isMobile: isMobile,
                    ),
                  ),
                  if (_mtnEnabled) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPaymentMethodOption(
                        icon: Icons.phone_android,
                        label: 'MTN MoMo',
                        isSelected: _selectedPaymentMethod ==
                            PaymentMethod.mtnMobileMoney,
                        color: const Color(0xFFFFCC00),
                        textColor: Colors.black,
                        onTap: () {
                          setState(() {
                            _selectedPaymentMethod =
                                PaymentMethod.mtnMobileMoney;
                          });
                        },
                        theme: theme,
                        isMobile: isMobile,
                      ),
                    ),
                  ],
                  if (_orangeEnabled) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPaymentMethodOption(
                        icon: Icons.phone_android,
                        label: 'Orange Money',
                        isSelected:
                            _selectedPaymentMethod == PaymentMethod.orangeMoney,
                        color: const Color(0xFFFF6600),
                        onTap: () {
                          setState(() {
                            _selectedPaymentMethod = PaymentMethod.orangeMoney;
                          });
                        },
                        theme: theme,
                        isMobile: isMobile,
                      ),
                    ),
                  ],
                  if (_cardEnabled) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPaymentMethodOption(
                        icon: Icons.credit_card,
                        label: 'Card',
                        isSelected:
                            _selectedPaymentMethod == PaymentMethod.card,
                        color: Colors.blue,
                        onTap: () {
                          setState(() {
                            _selectedPaymentMethod = PaymentMethod.card;
                          });
                        },
                        theme: theme,
                        isMobile: isMobile,
                      ),
                    ),
                  ],
                ],
              ),
        if (_selectedPaymentMethod != PaymentMethod.cash &&
            _selectedPaymentMethod != PaymentMethod.card) ...[
          SizedBox(height: 12),
          _buildCustomerPhoneInput(
            controller: _customerPhoneController,
            label: _selectedPaymentMethod == PaymentMethod.mtnMobileMoney
                ? "Customer's MTN Phone Number"
                : "Customer's Orange Phone Number",
            hint: '237XXXXXXXXX',
            color: _selectedPaymentMethod == PaymentMethod.mtnMobileMoney
                ? Color(0xFFFFCC00)
                : Color(0xFFFF6600),
            theme: theme,
            isMobile: isMobile,
          ),
          SizedBox(height: 4),
          Text(
            t('calcMomoTransferHint'),
            style: TextStyle(
              fontSize: isMobile ? 10 : 11,
              color: theme.hintColor,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPaymentMethodOption({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color color,
    Color? textColor,
    required VoidCallback onTap,
    required ThemeData theme,
    bool isMobile = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isSelected ? color : theme.dividerColor,
                width: isSelected ? 2 : 1)),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : theme.hintColor, size: 24),
            SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? (textColor ?? color) : theme.hintColor),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerPhoneInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required Color color,
    required ThemeData theme,
    bool isMobile = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: isMobile ? 12 : 14),
        hintText: hint,
        hintStyle: TextStyle(fontSize: isMobile ? 11 : 13),
        prefixIcon:
            Icon(Icons.phone_android, color: color, size: isMobile ? 18 : 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 16,
          vertical: isMobile ? 12 : 14,
        ),
        filled: true,
        fillColor: color.withValues(alpha: 0.05),
      ),
      style: TextStyle(color: theme.textTheme.bodyLarge?.color),
    );
  }

  Widget _buildPaymentStatusDisplay(
      bool isMobile, ThemeData theme, Color primaryColor) {
    Color statusColor;
    IconData statusIcon;
    if (_paymentStatus == 'processing') {
      statusColor = Colors.orange;
      statusIcon = Icons.hourglass_top;
    } else if (_paymentStatus == 'success') {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (_paymentStatus == 'failed') {
      statusColor = Colors.red;
      statusIcon = Icons.error;
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor.withValues(alpha: 0.3))),
      child: Row(
        children: [
          if (_paymentStatus == 'processing')
            SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: statusColor))
          else
            Icon(statusIcon, color: statusColor, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _paymentStatus == 'processing'
                        ? t('processingPayment')
                        : _paymentStatus == 'success'
                            ? t('paymentSuccessful')
                            : t('paymentFailed'),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                        fontSize: isMobile ? 14 : 16)),
                if (_paymentMessage != null) ...[
                  SizedBox(height: 4),
                  Text(_paymentMessage!,
                      style: TextStyle(
                          color: theme.hintColor, fontSize: isMobile ? 12 : 14))
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
