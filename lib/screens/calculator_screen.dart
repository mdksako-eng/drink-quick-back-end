// screens/calculator_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/providers/order_provider.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/utils/helpers.dart';
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
import 'package:drinks_calculator_fixed/screens/notifications_screen.dart';

enum PaymentMethod {
  cash,
  mtnMobileMoney,
  orangeMoney,
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
  final TextEditingController _customerPhoneController =
      TextEditingController();
  bool _isProcessingPayment = false;
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
    _loadData();
    _loadBusinessPaymentSettings();
    _loadCompanyName();
    _amountPaidController.addListener(_calculateBalance);
    CurrencyHelper.addListener(_refreshCurrency);
    PaymentHelper.addPaymentListener(_refreshPaymentSettings);
    _searchController.addListener(() {
      _filterDrinks(_searchController.text);
    });
    _loadPendingOrderFromAI();
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
            Helpers.showToast('⚠️ Selected drink is now out of stock',
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
  Future<void> _initOrdersAndSettingsAfterLogin() async {
    try {
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
        Helpers.showToast('Order loaded from AI Assistant!');
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

      if (_selectedPaymentMethod == PaymentMethod.mtnMobileMoney &&
          !_mtnEnabled) {
        _selectedPaymentMethod = PaymentMethod.cash;
        _customerPhoneController.clear();
        _paymentStatus = null;
        _paymentMessage = null;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          Helpers.showToast(
              'MTN Mobile Money was disabled. Switched to Cash payment.');
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
              'Orange Money was disabled. Switched to Cash payment.');
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
              'Business payments disabled. Switched to Cash payment.');
        });
      }

      if (!wasEnabled && _businessPaymentsEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Helpers.showToast('Business payments are now available!');
        });
      }
    });
  }

  Future<void> _deductInventoryFromOrder() async {
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
        final updatedDrink = drink.copyWith(
          currentStock: (drink.currentStock - entry.value).clamp(0, 999999),
        );
        await drinkProvider.updateDrink(drink.id, updatedDrink);
        debugPrint(
            '   ✅ Drink updated: ${drink.name} stock = ${updatedDrink.currentStock}');
      } else {
        debugPrint('   ❌ Failed to remove stock for ${drink.name}');
      }
    }
    await drinkProvider.loadDrinksFromSupabase();
    debugPrint('   ✅ Forced drinks refresh from Supabase');
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
      Helpers.showToast('${drink.name} is out of stock!', isError: true);
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
          'Only ${availableStock} more ${drink.name}(s) available!',
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

    Helpers.showToast('Added $_selectedQuantity ${drink.name}');

    if (scrollToDrink) {
      _scrollTimer?.cancel();
      _scrollTimer = Timer(const Duration(milliseconds: 200), () {
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

  void _decreaseDrinkQuantity(String drinkName) {
    setState(() {
      int lastIndex =
          _selectedDrinks.lastIndexWhere((d) => d.name == drinkName);
      if (lastIndex != -1) {
        _selectedDrinks.removeAt(lastIndex);
        _sortSelectedDrinks();
        _calculateTotal();

        Helpers.showToast('Removed 1 $drinkName');

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
    Helpers.showToast('Order cleared - $count items removed');
  }

  void _showPreviewInvoice() {
    if (_selectedDrinks.isEmpty) {
      Helpers.showToast('No purchases yet! Please add drinks first.',
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
      Helpers.showToast('No drinks selected', isError: true);
      return;
    }

    if (_selectedPaymentMethod == PaymentMethod.cash) {
      if (_amountPaid < _totalAmount) {
        Helpers.showToast('Insufficient payment', isError: true);
        return;
      }
    } else {
      if (_customerPhoneController.text.trim().isEmpty) {
        Helpers.showToast('Please enter customer phone number', isError: true);
        return;
      }
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
      Helpers.showToast('Customer name is required', isError: true);
      return;
    }

    setState(() {
      _isProcessingPayment = true;
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
      }

      if (paymentSuccess) {
        Helpers.showToast('Payment processed successfully!');
        if (_originalOrderId != null && _originalOrderId!.isNotEmpty) {
          final orderProvider =
              Provider.of<OrderProvider>(context, listen: false);
          await orderProvider.toggleOrderStatus(_originalOrderId!, false);
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
      setState(() {
        _paymentStatus = 'failed';
        _paymentMessage = e.toString();
      });
      // 🔔 Notify the in-app notification center
      NotificationService().showPaymentFailed(
        reason: e.toString(),
        paymentMethod: _selectedPaymentMethod.name,
      );
      Helpers.showToast('Payment failed: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isProcessingPayment = false;
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
    if (!_validatePhoneNumber(customerPhone, paymentMethod)) {
      setState(() {
        _paymentStatus = 'failed';
        _paymentMessage = 'Invalid phone number for $paymentMethod';
      });
      Helpers.showToast('Invalid phone number for $paymentMethod',
          isError: true);
      return false;
    }

    // ✅ Initiate payment via backend
    final result = await PaymentService.initiatePayment(
      amount: amount,
      customerPhone: customerPhone,
      paymentMethod: paymentMethod,
      orderId: orderId,
    );

    if (!result['success']) {
      setState(() {
        _paymentStatus = 'failed';
        _paymentMessage = result['error'] ?? 'Payment initiation failed';
      });
      return false;
    }

    final transactionId = result['transactionId'];

    // ✅ Show payment confirmation dialog
    final confirmed = await _showPaymentConfirmationDialog(
      amount: amount,
      customerPhone: customerPhone,
      paymentMethod: paymentMethod,
      transactionId: transactionId,
      companyName: _companyName,
    );

    if (!confirmed) {
      setState(() {
        _paymentStatus = 'failed';
        _paymentMessage = 'Payment was not completed by customer';
      });
      return false;
    }

    // ✅ Complete the order
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    _createdOrder = await orderProvider.createOrderAndGetOrder(
      _selectedDrinks,
      amount,
      customerName,
    );
    await _deductInventoryFromOrder();

    // ✅ Update transaction status in Supabase
    await SupabaseService.updateTransactionStatus(orderId, 'completed');

    return true;
  }

  // ============================================================
  // 💬 PAYMENT CONFIRMATION DIALOG
  // ============================================================

  Future<bool> _showPaymentConfirmationDialog({
    required double amount,
    required String customerPhone,
    required String paymentMethod,
    required String transactionId,
    required String companyName,
  }) async {
    final completer = Completer<bool>();
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
              title: const Text('⏳ Waiting for Payment'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.phone_android,
                      size: 60, color: Colors.orange),
                  const SizedBox(height: 16),
                  Text(
                    'Please check your phone and enter your PIN to approve the payment.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Text('Payment Details:'),
                        Text(
                          'Amount: ${CurrencyHelper.format(amount)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'To: $companyName',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          'Phone: $customerPhone',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    backgroundColor: Colors.grey.shade200,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Waiting for confirmation... (${_attempts * 10}s)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              actions: [
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
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    checkStatus();
                  },
                  child: const Text('Check Status'),
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
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    _createdOrder = await orderProvider.createOrderAndGetOrder(
      _selectedDrinks,
      _amountPaid,
      customerName,
    );
    await _deductInventoryFromOrder();
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

    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Customer Information',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person, size: 50, color: Color(0xFF667EEA)),
            const SizedBox(height: 16),
            const Text('Please enter customer name for this invoice',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Customer Name',
                hintText: 'Enter customer name',
                prefixIcon: const Icon(Icons.person_outline),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF667EEA), width: 2)),
              ),
              autofocus: true,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.pop(context, value.trim());
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Please enter customer name'),
                    backgroundColor: Colors.red));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667EEA),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showResponsiveInvoice() {
    if (_createdOrder == null) {
      Helpers.showToast('No order to display', isError: true);
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
      title: 'Password Required',
      message: 'Enter your password to manage drinks:',
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
                const SizedBox(height: 10),
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
                      hintText: 'Enter password',
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
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text('Enter your login password to continue',
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
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                  width: 1))),
                      child: const Text('Cancel',
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
                              'Access Denied', 'Incorrect password!');
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
                          const SizedBox(width: 8),
                          const Text('Verify',
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
                  const Icon(Icons.error_outline, size: 32, color: Colors.red),
            ),
            const SizedBox(height: 10),
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
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('Try Again',
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
            const Icon(Icons.logout, size: 48, color: Color(0xFFFF6B6B)),
            const SizedBox(height: 10),
            Text('Confirm Logout',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Are you sure you want to logout from your account?',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).hintColor, fontSize: 16)),
            const SizedBox(height: 10),
            Text("You'll be redirected to login screen.",
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
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: const Text('Cancel',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
              ),
              const SizedBox(width: 10),
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
                      backgroundColor: const Color(0xFFFF6B6B),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: const Text('Logout',
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
                                const SizedBox(height: 30),
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
                                            : const Icon(Icons.check_circle,
                                                size: 22, color: Colors.white),
                                        label: Text(
                                            _isProcessingPayment
                                                ? 'Processing...'
                                                : 'Finalize Purchase',
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
              Helpers.showToast(
                  'Invoice loaded! You can now edit and re-process.');
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
                  borderRadius: BorderRadius.circular(12)),
              child: IconButton(
                tooltip: 'Notifications',
                icon: const Icon(Icons.notifications,
                    color: Colors.white, size: 26),
                onPressed: () {
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
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                  constraints:
                      const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
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
                  icon: const Icon(Icons.menu, color: Colors.white, size: 32),
                  onPressed: () {
                    _scaffoldKey.currentState?.openDrawer();
                  }),
            ),
            const SizedBox(width: 16),
            Text('Drinks Quick Cal',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: primaryColor)),
            const Spacer(),
            _buildNotificationBell(primaryColor),
          ],
        ),
        const SizedBox(height: 5),
        Text('Professional Drink Ordering & Management',
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
                  Text('Welcome, ',
                      style: TextStyle(color: Colors.green, fontSize: 13)),
                  Icon(Icons.person, color: primaryColor, size: 16),
                  const SizedBox(width: 8),
                  Text('${user?.username ?? 'User'}',
                      style: TextStyle(color: Colors.green, fontSize: 13)),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20))),
                        icon: const Icon(Icons.edit_note,
                            size: 14, color: Colors.white),
                        label: const Text('Manage Drinks',
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20))),
                        icon: const Icon(Icons.receipt_long,
                            size: 16, color: Colors.white),
                        label: const Text('Invoice History',
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20))),
                      icon: const Icon(Icons.logout,
                          size: 14, color: Colors.white),
                      label: const Text('Logout',
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
                  icon: const Icon(Icons.menu, color: Colors.white, size: 32),
                  onPressed: () {
                    _scaffoldKey.currentState?.openDrawer();
                  }),
            ),
            const SizedBox(width: 16),
            Text('Drinks Quick Cal',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: primaryColor)),
            const SizedBox(width: 16),
            _buildNotificationBell(primaryColor),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              Text('Welcome, ',
                  style: TextStyle(color: Colors.green, fontSize: 13)),
              Icon(Icons.person, color: primaryColor, size: 18),
              const SizedBox(width: 8),
              Text('${user?.username ?? 'User'}',
                  style: TextStyle(color: Colors.green)),
              const SizedBox(width: 12),
              Container(width: 1, height: 20, color: theme.dividerColor),
              const SizedBox(width: 12),
              if (_canManageDrinks()) ...[
                ElevatedButton.icon(
                  onPressed: _showDrinkManagementDialog,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  icon: const Icon(Icons.edit_note,
                      size: 16, color: Colors.white),
                  label: const Text('Manage Drinks',
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20))),
                    icon: const Icon(Icons.receipt_long,
                        size: 18, color: Colors.white),
                    label: const Text('Invoice History',
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
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20))),
                icon: const Icon(Icons.logout, size: 16, color: Colors.white),
                label: const Text('Logout',
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
                  icon: const Icon(Icons.menu, color: Colors.white, size: 32),
                  onPressed: () {
                    _scaffoldKey.currentState?.openDrawer();
                  }),
            ),
            const SizedBox(width: 16),
            Text('Drinks Quick Cal',
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: primaryColor)),
            const SizedBox(width: 16),
            _buildNotificationBell(primaryColor),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(25)),
          child: Row(
            children: [
              Text('Welcome, ',
                  style: TextStyle(color: Colors.green, fontSize: 13)),
              Icon(Icons.person, color: primaryColor, size: 20),
              const SizedBox(width: 10),
              Text('${user?.username ?? 'User'}',
                  style: TextStyle(color: Colors.green, fontSize: 16)),
              const SizedBox(width: 16),
              Container(width: 1, height: 24, color: theme.dividerColor),
              const SizedBox(width: 16),
              if (_canManageDrinks()) ...[
                ElevatedButton.icon(
                  onPressed: _showDrinkManagementDialog,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  icon: const Icon(Icons.edit_note,
                      size: 18, color: Colors.white),
                  label: const Text('Manage Drinks',
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20))),
                    icon: const Icon(Icons.receipt_long,
                        size: 18, color: Colors.white),
                    label: const Text('Invoice History',
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  icon: const Icon(Icons.admin_panel_settings,
                      size: 18, color: Colors.white),
                  label: const Text('Admin Panel',
                      style: TextStyle(fontSize: 14, color: Colors.white)),
                ),
              ],
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _showLogoutDialog,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade400,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20))),
                icon: const Icon(Icons.logout, size: 18, color: Colors.white),
                label: const Text('Logout',
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
        Text('Select Drink:',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: theme.textTheme.bodyLarge?.color)),
        const SizedBox(height: 10),
        CompositedTransformTarget(
          link: _layerLink,
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Search or select a drink...',
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
            offset: const Offset(0, 48),
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
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off,
                                size: 40, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              'No drinks found, kindly add drinks',
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
                            leading: Icon(
                              Icons.local_drink,
                              color: isOutOfStock ? Colors.red : primaryColor,
                              size: 18,
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
                                  const Text(
                                    'OUT OF STOCK',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                if (isLowStock && !isOutOfStock)
                                  Text(
                                    'LOW STOCK (${drink.currentStock})',
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
        const SizedBox(height: 20),
        Text('Select Quantity:',
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
                  Container(
                      width: 40,
                      alignment: Alignment.center,
                      child: Text('$_selectedQuantity',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyLarge?.color))),
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
            ElevatedButton(
              onPressed: () {
                if (_selectedDrinkId != null && sortedDrinks.isNotEmpty) {
                  final selectedDrink =
                      sortedDrinks.firstWhere((d) => d.id == _selectedDrinkId);
                  if (selectedDrink.currentStock <= 0) {
                    Helpers.showToast('${selectedDrink.name} is out of stock!',
                        isError: true);
                    return;
                  }
                  _addDrink(selectedDrink);
                } else {
                  Helpers.showToast('Please select a drink first');
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              child: const Text('Add to Order',
                  style: TextStyle(fontSize: 14, color: Colors.white)),
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
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    icon:
                        const Icon(Icons.delete, size: 18, color: Colors.white),
                    label: const Text('Clear All',
                        style: TextStyle(fontSize: 14, color: Colors.white)))),
            const SizedBox(width: 10),
            Expanded(
                child: ElevatedButton.icon(
                    onPressed: _showPreviewInvoice,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    icon: const Icon(Icons.receipt,
                        size: 18, color: Colors.white),
                    label: const Text('Preview',
                        style: TextStyle(fontSize: 14, color: Colors.white)))),
          ],
        ),
        const SizedBox(height: 20),
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
              Text('Select Drink & Quantity:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: theme.textTheme.bodyLarge?.color)),
              const SizedBox(height: 15),
              CompositedTransformTarget(
                link: _layerLink,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Search or select a drink...',
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
                  offset: const Offset(0, 48),
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
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off,
                                      size: 40, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text(
                                    'No drink found, kindly add drink',
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
                                  leading: Icon(
                                    Icons.local_drink,
                                    color: isOutOfStock
                                        ? Colors.red
                                        : primaryColor,
                                    size: 18,
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
                                        const Text(
                                          'OUT OF STOCK',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      if (isLowStock && !isOutOfStock)
                                        Text(
                                          'LOW STOCK (${drink.currentStock})',
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
                        Text('Quantity:',
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
                              Container(
                                  width: isTablet ? 50 : 60,
                                  alignment: Alignment.center,
                                  child: Text('$_selectedQuantity',
                                      style: TextStyle(
                                          fontSize: isTablet ? 16 : 18,
                                          fontWeight: FontWeight.bold,
                                          color: theme
                                              .textTheme.bodyLarge?.color))),
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
                              Helpers.showToast('Please select a drink first');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 24 : 32,
                                  vertical: isTablet ? 12 : 16)),
                          child: Text('Add to Order',
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
                          icon: const Icon(Icons.delete,
                              size: 20, color: Colors.white),
                          label: Text('Clear All',
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
                          icon: const Icon(Icons.receipt,
                              size: 20, color: Colors.white),
                          label: Text('Preview Invoice',
                              style: TextStyle(
                                  fontSize: isTablet ? 14 : 16,
                                  color: Colors.white)))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 30),
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
                Text('SELECTED DRINKS',
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
                    const SizedBox(height: 10),
                    Text('No drinks selected',
                        style: TextStyle(
                            fontSize: isMobile ? 18 : 20,
                            color: theme.hintColor)),
                    const SizedBox(height: 5),
                    Text('Select drinks above',
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
                              Icon(Icons.local_drink,
                                  color: isNewlyAdded
                                      ? Colors.green
                                      : (isOutOfStock
                                          ? Colors.red
                                          : primaryColor),
                                  size: isMobile ? 20 : 24),
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
                                        const SizedBox(width: 4),
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
                                            child: const Text('OUT OF STOCK',
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
                                  tooltip: 'Remove all'),
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
                Text('Total:',
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
                Text('Adjust Quantity:',
                    style: TextStyle(
                        fontSize: isMobile ? 12 : 14,
                        fontWeight: FontWeight.w600,
                        color: theme.hintColor)),
                if (remainingStock > 0)
                  Text('${remainingStock} more available',
                      style: TextStyle(
                          fontSize: isMobile ? 10 : 12, color: Colors.green)),
                if (remainingStock <= 0)
                  Text('Out of stock!',
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
                      ? 'Add one more (${remainingStock} left)'
                      : 'Out of stock',
                ),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () => _clearDrink(drinkName),
              icon: Icon(Icons.delete_forever, size: isMobile ? 16 : 18),
              label: Text('Remove All',
                  style: TextStyle(fontSize: isMobile ? 12 : 14)),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: () => setState(() => _expandedDrinkName = null),
              icon: Icon(Icons.close, size: isMobile ? 16 : 18),
              label:
                  Text('Close', style: TextStyle(fontSize: isMobile ? 12 : 14)),
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
          Text('Order Summary',
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
                Text('Total Amount:',
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
        Text('Payment Details',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: theme.textTheme.bodyLarge?.color)),
        const SizedBox(height: 15),
        Text('Amount Received:',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: primaryColor)),
        const SizedBox(height: 10),
        TextField(
          controller: _amountPaidController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Enter amount in ${CurrencyHelper.getSymbol()}',
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
        const SizedBox(height: 20),
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
                const SizedBox(height: 8),
                if (_balance >= 0 && _balance > 0)
                  Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                          'Tap to refresh • Change to give back to customer',
                          style: TextStyle(
                              color: Colors.green,
                              fontSize: isMobile ? 12 : 14))),
                if (_balance < 0)
                  Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text('Tap to refresh • Customer needs to pay more',
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
        Text('Payment Method',
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
                    label: 'Cash',
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
                      label: 'Orange',
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
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: _buildPaymentMethodOption(
                      icon: Icons.money,
                      label: 'Cash',
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
                ],
              ),
        if (_selectedPaymentMethod != PaymentMethod.cash) ...[
          const SizedBox(height: 12),
          _buildCustomerPhoneInput(
            controller: _customerPhoneController,
            label: _selectedPaymentMethod == PaymentMethod.mtnMobileMoney
                ? "Customer's MTN Phone Number"
                : "Customer's Orange Phone Number",
            hint: '237XXXXXXXXX',
            color: _selectedPaymentMethod == PaymentMethod.mtnMobileMoney
                ? const Color(0xFFFFCC00)
                : const Color(0xFFFF6600),
            theme: theme,
            isMobile: isMobile,
          ),
          const SizedBox(height: 4),
          Text(
            'Money will be transferred FROM this number TO your merchant account',
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
            const SizedBox(height: 4),
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _paymentStatus == 'processing'
                        ? 'Processing Payment'
                        : _paymentStatus == 'success'
                            ? 'Payment Successful'
                            : 'Payment Failed',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                        fontSize: isMobile ? 14 : 16)),
                if (_paymentMessage != null) ...[
                  const SizedBox(height: 4),
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
