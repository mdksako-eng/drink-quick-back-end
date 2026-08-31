// screens/side_slider.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:drinks_calculator_fixed/providers/order_provider.dart';
import 'package:drinks_calculator_fixed/models/order_model.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/utils/helpers.dart';
import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';

class SideSlider extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final BuildContext parentContext;
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color textPrimaryColor;
  final Color textSecondaryColor;
  final bool isDarkMode;
  final Function(List<Drink>, double, double, String, String)? onImportInvoice;

  const SideSlider({
    Key? key,
    required this.isOpen,
    required this.onClose,
    required this.parentContext,
    required this.primaryColor,
    required this.secondaryColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.textPrimaryColor,
    required this.textSecondaryColor,
    required this.isDarkMode,
    this.onImportInvoice,
  }) : super(key: key);

  @override
  State<SideSlider> createState() => _SideSliderState();
}

class _SideSliderState extends State<SideSlider> {
  String _filterPeriod = 'Today';
  String _sortBy = 'Recent';
  String _searchQuery = '';
  bool _showInactive = false;
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();
  bool _canManageOrders = false;

  static const Color _successColor = Color(0xFF27AE60);
  static const Color _errorColor = Color(0xFFE74C3C);
  static const Color _warningColor = Color(0xFFFF9800);
  static const Color _accentColor = Color(0xFF4CC9F0);

  @override
  void initState() {
    super.initState();
    CurrencyHelper.addListener(_refreshCurrency);
    _checkUserRole();
  }

  @override
  void dispose() {
    _searchController.dispose();
    CurrencyHelper.removeListener(_refreshCurrency);
    super.dispose();
  }

  void _refreshCurrency() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkUserRole() async {
    final authProvider =
        Provider.of<AuthProvider>(widget.parentContext, listen: false);
    final role = authProvider.user?.role?.toLowerCase() ?? '';
    setState(() {
      _canManageOrders = role == 'administrator' ||
          role == 'admin' ||
          role == 'manager' ||
          role == 'customer';
    });
  }

  PurchaseHistory _convertOrderToPurchaseHistory(Order order) {
    final Map<String, int> itemCounts = {};
    for (final drink in order.items) {
      itemCounts[drink.name] = (itemCounts[drink.name] ?? 0) + 1;
    }

    final items = itemCounts.entries.map((entry) {
      final drink = order.items.firstWhere((d) => d.name == entry.key);
      return OrderItem(
        drinkName: entry.key,
        quantity: entry.value,
        pricePerUnit: (drink.price ?? 0).toDouble(),
      );
    }).toList();

    return PurchaseHistory(
      id: order.id,
      date: order.date,
      items: items,
      totalAmount: (order.totalAmount ?? 0).toDouble(),
      amountPaid: (order.amountPaid ?? 0).toDouble(),
      isActive: order.isActive,
      customerName: order.customerName ?? '',
    );
  }

  List<PurchaseHistory> _getFilteredOrders(List<Order> allOrders) {
    List<Order> filteredByStatus = _showInactive
        ? allOrders
        : allOrders.where((order) => order.isActive != false).toList();

    final List<PurchaseHistory> purchaseHistories =
        filteredByStatus.map(_convertOrderToPurchaseHistory).toList();

    List<PurchaseHistory> filtered = purchaseHistories;
    if (_searchQuery.isNotEmpty) {
      // filtered = purchaseHistories.where((order) {
      //   return order.id.toLowerCase().contains(_searchQuery.toLowerCase());
      // }).toList();
      filtered = purchaseHistories.where((order) {
        final idMatch =
            order.id.toLowerCase().contains(_searchQuery.toLowerCase());
        final nameMatch = order.customerName
            .toLowerCase()
            .contains(_searchQuery.toLowerCase());
        return idMatch || nameMatch;
      }).toList();
    }

    DateTime now = DateTime.now();
    DateTime startDate;

    switch (_filterPeriod) {
      case 'Today':
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case 'This Week':
        startDate = now.subtract(Duration(days: now.weekday - 1));
        break;
      case 'This Month':
        startDate = DateTime(now.year, now.month, 1);
        break;
      case 'All Time':
      default:
        return _getSortedOrders(filtered);
    }

    filtered = filtered.where((order) {
      return order.date.isAfter(startDate);
    }).toList();

    return _getSortedOrders(filtered);
  }

  List<PurchaseHistory> _getSortedOrders(List<PurchaseHistory> orders) {
    List<PurchaseHistory> sorted = List<PurchaseHistory>.from(orders);

    switch (_sortBy) {
      case 'Recent':
        sorted.sort((a, b) => b.date.compareTo(a.date));
        break;
      case 'Oldest':
        sorted.sort((a, b) => a.date.compareTo(b.date));
        break;
      case 'High Amount':
        sorted.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
        break;
      case 'Low Amount':
        sorted.sort((a, b) => a.totalAmount.compareTo(b.totalAmount));
        break;
    }

    return sorted;
  }

  double _getTotalRevenue(List<PurchaseHistory> orders) {
    return orders.fold(0.0, (sum, order) => sum + order.totalAmount);
  }

  int _getTotalItems(List<PurchaseHistory> orders) {
    return orders.fold(0, (sum, order) => sum + order.items.length);
  }

  String _formatCurrency(double amount) {
    return CurrencyHelper.format(amount);
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
    });
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(widget.parentContext).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleInvoiceStatus(PurchaseHistory order) async {
    if (!_canManageOrders) {
      _showToast('Only administrators can modify invoice status',
          isError: true);
      return;
    }

    final bool currentlyActive = order.isActive;

    final confirmed = await showDialog<bool>(
      context: widget.parentContext,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              currentlyActive ? Icons.block : Icons.check_circle,
              color: currentlyActive ? _warningColor : _successColor,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              currentlyActive ? 'Deactivate Invoice' : 'Activate Invoice',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: widget.textPrimaryColor,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentlyActive
                  ? 'Are you sure you want to deactivate invoice #${order.id.substring(0, 8)}?'
                  : 'Are you sure you want to activate invoice #${order.id.substring(0, 8)}?',
              style: TextStyle(color: widget.textSecondaryColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Total: ${_formatCurrency(order.totalAmount)}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: widget.textPrimaryColor,
              ),
            ),
            Text(
              'Date: ${DateFormat('MMM dd, yyyy').format(order.date)}',
              style: TextStyle(color: widget.textSecondaryColor),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: currentlyActive
                    ? _warningColor.withValues(alpha: 0.1)
                    : _successColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: currentlyActive
                      ? _warningColor.withValues(alpha: 0.3)
                      : _successColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    currentlyActive ? Icons.warning : Icons.info,
                    color: currentlyActive ? _warningColor : _successColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentlyActive
                          ? 'Deactivated invoices will be hidden from reports and cannot be edited.'
                          : 'Activated invoices will appear in reports and can be edited.',
                      style: TextStyle(
                        color: currentlyActive ? _warningColor : _successColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: currentlyActive ? _warningColor : _successColor,
            ),
            child: Text(currentlyActive ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        final orderProvider =
            Provider.of<OrderProvider>(widget.parentContext, listen: false);
        await orderProvider.toggleOrderStatus(order.id, !currentlyActive);
        _showToast(currentlyActive
            ? 'Invoice deactivated successfully'
            : 'Invoice activated successfully');
        setState(() {});
      } catch (e) {
        _showToast('Failed to update invoice status', isError: true);
      }
    }
  }

  Future<void> _importInvoice(PurchaseHistory order) async {
    // ✅ Check if order is active
    if (!order.isActive) {
      _showToast('Cannot edit deactivated invoice', isError: true);
      return;
    }

    // ✅ Show loading indicator
    setState(() => _isLoading = true);

    try {
      // ✅ Get drink provider
      final drinkProvider = Provider.of<DrinkProvider>(
        widget.parentContext,
        listen: false,
      );

      List<Drink> drinksToImport = [];
      final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      int counter = 0;

      // ✅ Loop through each item in the order
      for (final item in order.items) {
        // ✅ Find existing drink or create fallback
        final existingDrink = drinkProvider.customDrinks.firstWhere(
          (d) => d.name == item.drinkName,
          orElse: () => Drink(
            id: '',
            name: item.drinkName,
            price: item.pricePerUnit,
            category: 'Imported',
            imageUrl: '',
          ),
        );

        // ✅ Create individual drinks for each quantity
        for (int i = 0; i < item.quantity; i++) {
          counter++;
          drinksToImport.add(Drink(
            id: 'import_${baseTimestamp}_${counter}_${DateTime.now().microsecondsSinceEpoch}_${item.drinkName.replaceAll(' ', '_')}',
            name: item.drinkName,
            price: item.pricePerUnit,
            category: 'Imported',
            imageUrl: '',
            currentStock: existingDrink.currentStock,
            minimumLevel: existingDrink.minimumLevel,
            purchasePrice: existingDrink.purchasePrice,
            unit: existingDrink.unit,
          ));
        }
      }

      // ✅ Check if there are drinks to import
      if (drinksToImport.isEmpty) {
        _showToast('No drinks to import', isError: true);
        return;
      }

      // ✅ Call the import callback
      if (widget.onImportInvoice != null) {
        widget.onImportInvoice!(
          drinksToImport,
          order.amountPaid,
          order.balance,
          order.customerName,
          order.id,
        );
      }

      // ✅ Close the slider
      widget.onClose();

      // ✅ Show success message
      if (mounted) {
        _showToast('Invoice loaded! You can now edit and re-process.');
      }
    } catch (e) {
      // ✅ Handle any errors
      if (mounted) {
        _showToast('Failed to import invoice: ${e.toString()}', isError: true);
      }
      // ✅ Log the error for debugging
      print('❌ Import invoice error: $e');
      print('   Stack trace: ${StackTrace.current}');
    } finally {
      // ✅ Always reset loading state
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildFilterChip(String label, String value) {
    bool isSelected = _filterPeriod == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filterPeriod = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? widget.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? widget.primaryColor
                : widget.textSecondaryColor.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : widget.textSecondaryColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSortChip(String label, String value) {
    bool isSelected = _sortBy == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _sortBy = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? _accentColor.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? _accentColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? _accentColor : widget.textSecondaryColor,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OrderProvider>(
      builder: (context, orderProvider, child) {
        final allOrders = orderProvider.orderHistory;
        final filteredOrders = _getFilteredOrders(allOrders);
        final totalRevenue = _getTotalRevenue(filteredOrders);
        final totalItems = _getTotalItems(filteredOrders);

        final screenWidth = MediaQuery.of(widget.parentContext).size.width;
        final screenHeight = MediaQuery.of(widget.parentContext).size.height;
        final double sliderWidth = screenWidth < 600
            ? screenWidth * 0.85
            : screenWidth < 1200
                ? 500.0
                : 380.0;

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          right: widget.isOpen ? 0.0 : -sliderWidth,
          top: 0.0,
          bottom: 0.0,
          width: sliderWidth,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () => LockService().resetTimer(),
              onPanDown: (_) => LockService().resetTimer(),
              onScaleStart: (_) => LockService().resetTimer(),
              onLongPress: () => LockService().resetTimer(),
              behavior: HitTestBehavior.translucent,
              child: Container(
                width: sliderWidth,
                decoration: BoxDecoration(
                  color: widget.cardColor,
                  border: Border(
                    left: BorderSide(
                      color: widget.primaryColor.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withOpacity(widget.isDarkMode ? 0.3 : 0.15),
                      blurRadius: 25,
                      spreadRadius: 0,
                      offset: const Offset(-5, 0),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(widget.parentContext).padding.top +
                            12.0,
                        bottom: 12.0,
                        left: 16.0,
                        right: 16.0,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [widget.primaryColor, widget.secondaryColor],
                        ),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              LockService().resetTimer();
                              widget.onClose();
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.close,
                                  color: Colors.white, size: 24),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Invoice History',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${filteredOrders.length} invoice${filteredOrders.length != 1 ? 's' : ''}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (screenWidth >= 600)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.3)),
                              ),
                              child: Text(
                                '${filteredOrders.length} items',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.all(
                                  screenWidth < 600 ? 10.0 : 14.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: widget.backgroundColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          widget.primaryColor.withOpacity(0.1)),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(
                                      screenWidth < 600 ? 10.0 : 14.0),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          _buildStatItem(
                                            icon: Icons.receipt,
                                            label: 'Invoices',
                                            value: filteredOrders.length
                                                .toString(),
                                            color: widget.primaryColor,
                                            screenWidth: screenWidth,
                                          ),
                                          _buildStatItem(
                                            icon: Icons.shopping_cart,
                                            label: 'Items',
                                            value: totalItems.toString(),
                                            color: _accentColor,
                                            screenWidth: screenWidth,
                                          ),
                                          _buildStatItem(
                                            icon: Icons.attach_money,
                                            label: 'Revenue',
                                            value:
                                                _formatCurrency(totalRevenue),
                                            color: _successColor,
                                            screenWidth: screenWidth,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: screenWidth < 600 ? 12.0 : 16.0,
                                vertical: 8.0,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: widget.cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          widget.primaryColor.withOpacity(0.2)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _searchController,
                                        decoration: InputDecoration(
                                          hintText: 'Search by Order ID...',
                                          hintStyle: TextStyle(
                                              color: widget.textSecondaryColor
                                                  .withValues(alpha: 0.7)),
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          prefixIcon: Icon(Icons.search,
                                              color: widget.primaryColor,
                                              size: 20),
                                        ),
                                        style: TextStyle(
                                            color: widget.textPrimaryColor),
                                        onChanged: (value) {
                                          setState(() {
                                            _searchQuery = value;
                                          });
                                        },
                                      ),
                                    ),
                                    if (_searchQuery.isNotEmpty)
                                      IconButton(
                                        icon: Icon(Icons.clear,
                                            color: _errorColor, size: 20),
                                        onPressed: _clearSearch,
                                        tooltip: 'Clear search',
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (_canManageOrders)
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: screenWidth < 600 ? 12.0 : 16.0,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: widget.backgroundColor,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.visibility,
                                          size: 18, color: widget.primaryColor),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Show deactivated invoices',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: widget.textPrimaryColor,
                                        ),
                                      ),
                                      const Spacer(),
                                      Switch(
                                        value: _showInactive,
                                        onChanged: (value) {
                                          setState(() {
                                            _showInactive = value;
                                          });
                                        },
                                        activeColor: widget.primaryColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: screenWidth < 600 ? 12.0 : 16.0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.filter_alt,
                                        size: 16,
                                        color: widget.primaryColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Filter:',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: widget.textPrimaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        _buildFilterChip('Today', 'Today'),
                                        const SizedBox(width: 8),
                                        _buildFilterChip('Week', 'This Week'),
                                        const SizedBox(width: 8),
                                        _buildFilterChip('Month', 'This Month'),
                                        const SizedBox(width: 8),
                                        _buildFilterChip('All', 'All Time'),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.sort,
                                            size: 16,
                                            color: widget.primaryColor,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Sort:',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: widget.textPrimaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            _buildSortChip('Recent', 'Recent'),
                                            const SizedBox(width: 6),
                                            _buildSortChip('Oldest', 'Oldest'),
                                            const SizedBox(width: 6),
                                            _buildSortChip(
                                                'High', 'High Amount'),
                                            const SizedBox(width: 6),
                                            _buildSortChip('Low', 'Low Amount'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              height: 1,
                              color: widget.primaryColor.withOpacity(0.1),
                            ),
                            const SizedBox(height: 8),
                            filteredOrders.isEmpty
                                ? Container(
                                    height: screenHeight * 0.4,
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.receipt_long,
                                              size: 60,
                                              color: widget.textSecondaryColor
                                                  .withOpacity(0.2),
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              _searchQuery.isNotEmpty
                                                  ? 'No invoices found for "#$_searchQuery"'
                                                  : 'No invoices found',
                                              style: TextStyle(
                                                fontSize: 16,
                                                color:
                                                    widget.textSecondaryColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              _searchQuery.isNotEmpty
                                                  ? 'Try a different Order ID'
                                                  : _filterPeriod == 'Today'
                                                      ? 'No invoices for today yet'
                                                      : 'Try changing the filter period',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: widget.textSecondaryColor
                                                    .withOpacity(0.7),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    padding: EdgeInsets.only(
                                      bottom: screenWidth < 600 ? 80.0 : 20.0,
                                      top: 8.0,
                                    ),
                                    itemCount: filteredOrders.length,
                                    itemBuilder: (context, index) {
                                      final order = filteredOrders[index];
                                      return _buildOrderCard(
                                          order, index, screenWidth);
                                    },
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required double screenWidth,
  }) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(screenWidth < 600 ? 6.0 : 8.0),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child:
              Icon(icon, size: screenWidth < 600 ? 18.0 : 20.0, color: color),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: screenWidth < 600 ? 14.0 : 16.0,
            fontWeight: FontWeight.bold,
            color: widget.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: screenWidth < 600 ? 10.0 : 11.0,
            color: widget.textSecondaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(PurchaseHistory order, int index, double screenWidth) {
    final isMobile = screenWidth < 600;
    final bool isActive = order.isActive;

    return GestureDetector(
      onTap: () => _showOrderDetails(order, screenWidth),
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 12.0 : 16.0,
          vertical: 8.0,
        ),
        decoration: BoxDecoration(
          color: isActive ? widget.cardColor : _warningColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(isMobile ? 10.0 : 12.0),
          border: Border.all(
            color: isActive
                ? widget.primaryColor.withOpacity(0.1)
                : _warningColor.withOpacity(0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            DateFormat('MMM dd, yyyy').format(order.date),
                            style: TextStyle(
                              fontSize: isMobile ? 11.0 : 12.0,
                              fontWeight: FontWeight.w600,
                              color: widget.textPrimaryColor,
                            ),
                          ),
                          if (!isActive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _warningColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'DEACTIVATED',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        DateFormat('hh:mm a').format(order.date),
                        style: TextStyle(
                          fontSize: isMobile ? 10.0 : 11.0,
                          color: widget.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatCurrency(order.totalAmount),
                        style: TextStyle(
                          fontSize: isMobile ? 18.0 : 20.0,
                          fontWeight: FontWeight.bold,
                          color: isActive ? widget.primaryColor : _warningColor,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: order.balance >= 0
                              ? _successColor.withValues(alpha: 0.1)
                              : _errorColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          order.balance >= 0 ? 'PAID' : 'PENDING',
                          style: TextStyle(
                            fontSize: isMobile ? 9.0 : 10.0,
                            fontWeight: FontWeight.bold,
                            color: order.balance >= 0
                                ? _successColor
                                : _errorColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Customer Name
              if (order.customerName.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.person,
                        size: isMobile ? 12.0 : 14.0,
                        color: widget.textSecondaryColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.customerName,
                        style: TextStyle(
                          fontSize: isMobile ? 11.0 : 12.0,
                          color: widget.textSecondaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.receipt,
                    size: isMobile ? 14.0 : 16.0,
                    color: widget.textSecondaryColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Order #${order.id}', // FULL ORDER ID - NOT truncated
                      style: TextStyle(
                        fontSize: isMobile ? 12.0 : 13.0,
                        color: widget.textPrimaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (screenWidth >= 600)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: widget.backgroundColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Items Preview:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: widget.textSecondaryColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Column(
                        children: order.items.take(2).map((item) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              children: [
                                Text(
                                  '•',
                                  style: TextStyle(
                                    color: widget.textSecondaryColor,
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    item.drinkName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: widget.textPrimaryColor,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${item.quantity} × ${_formatCurrency(item.pricePerUnit)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: widget.textSecondaryColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      if (order.items.length > 2)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '+ ${order.items.length - 2} more items',
                            style: TextStyle(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: widget.textSecondaryColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: order.balance >= 0
                      ? _successColor.withOpacity(0.05)
                      : _errorColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: order.balance >= 0
                        ? _successColor.withOpacity(0.2)
                        : _errorColor.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order.balance >= 0 ? 'Change:' : 'Due:',
                      style: TextStyle(
                        fontSize: isMobile ? 12.0 : 13.0,
                        fontWeight: FontWeight.w600,
                        color: order.balance >= 0 ? _successColor : _errorColor,
                      ),
                    ),
                    Text(
                      _formatCurrency(order.balance.abs()),
                      style: TextStyle(
                        fontSize: isMobile ? 14.0 : 16.0,
                        fontWeight: FontWeight.bold,
                        color: order.balance >= 0 ? _successColor : _errorColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isActive ? () => _importInvoice(order) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isActive
                            ? widget.primaryColor.withOpacity(0.1)
                            : widget.primaryColor.withOpacity(0.05),
                        foregroundColor:
                            isActive ? widget.primaryColor : Colors.grey,
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 8.0 : 10.0,
                          horizontal: 12.0,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isActive
                                ? widget.primaryColor.withOpacity(0.3)
                                : Colors.grey.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        elevation: 0,
                      ),
                      icon: Icon(
                        Icons.edit_note,
                        size: isMobile ? 16.0 : 18.0,
                        color: isActive ? widget.primaryColor : Colors.grey,
                      ),
                      label: Text(
                        'Edit & Re-invoice',
                        style: TextStyle(
                          fontSize: isMobile ? 11.0 : 12.0,
                          fontWeight: FontWeight.w600,
                          color: isActive ? widget.primaryColor : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_canManageOrders)
                    SizedBox(
                      width: 40,
                      height: isMobile ? 36 : 42,
                      child: ElevatedButton(
                        onPressed: () => _toggleInvoiceStatus(order),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isActive
                              ? _warningColor.withOpacity(0.1)
                              : _successColor.withOpacity(0.1),
                          foregroundColor:
                              isActive ? _warningColor : _successColor,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isActive
                                  ? _warningColor.withOpacity(0.3)
                                  : _successColor.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          elevation: 0,
                        ),
                        child: Icon(
                          isActive ? Icons.block : Icons.check_circle,
                          size: isMobile ? 18.0 : 20.0,
                          color: isActive ? _warningColor : _successColor,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOrderDetails(PurchaseHistory order, double screenWidth) {
    final isMobile = screenWidth < 600;
    final bool isActive = order.isActive;
    final screenHeight = MediaQuery.of(widget.parentContext).size.height;

    showDialog(
      context: widget.parentContext,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isMobile ? 16.0 : 20.0),
        ),
        child: Container(
          width: isMobile ? screenWidth * 0.9 : 500.0,
          constraints: BoxConstraints(
            maxHeight: screenHeight * 0.85,
          ),
          padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      Icons.receipt_long,
                      size: isMobile ? 24.0 : 28.0,
                      color: widget.primaryColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Invoice Details',
                                style: TextStyle(
                                  fontSize: isMobile ? 16.0 : 18.0,
                                  fontWeight: FontWeight.bold,
                                  color: widget.textPrimaryColor,
                                ),
                              ),
                              if (!isActive) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _warningColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'DEACTIVATED',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          // FULL ORDER ID displayed here
                          Text(
                            'Order #${order.id}',
                            style: TextStyle(
                              fontSize: isMobile ? 12.0 : 13.0,
                              color: widget.textSecondaryColor,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: isMobile ? 20.0 : 24.0,
                        color: widget.textSecondaryColor,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                Divider(color: widget.primaryColor.withOpacity(0.1), height: 1),
                const SizedBox(height: 20),
                // Customer Name
                if (order.customerName.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.person,
                          size: isMobile ? 16.0 : 18.0,
                          color: widget.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        order.customerName,
                        style: TextStyle(
                          fontSize: isMobile ? 14.0 : 16.0,
                          fontWeight: FontWeight.w600,
                          color: widget.textPrimaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                // Date and Time
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: isMobile ? 16.0 : 18.0,
                      color: widget.textSecondaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMMM dd, yyyy').format(order.date),
                      style: TextStyle(
                        fontSize: isMobile ? 13.0 : 14.0,
                        color: widget.textSecondaryColor,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.access_time,
                      size: isMobile ? 16.0 : 18.0,
                      color: widget.textSecondaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('hh:mm a').format(order.date),
                      style: TextStyle(
                        fontSize: isMobile ? 13.0 : 14.0,
                        color: widget.textSecondaryColor,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Items List Title
                Text(
                  'Items Ordered:',
                  style: TextStyle(
                    fontSize: isMobile ? 16.0 : 18.0,
                    fontWeight: FontWeight.w600,
                    color: widget.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 12),

                // Items List - Scrollable
                Container(
                  constraints: BoxConstraints(
                    maxHeight: isMobile ? 300 : 400,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: order.items.length,
                    itemBuilder: (context, index) {
                      final item = order.items[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.all(isMobile ? 10.0 : 12.0),
                        decoration: BoxDecoration(
                          color: widget.backgroundColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.drinkName,
                                    style: TextStyle(
                                      fontSize: isMobile ? 14.0 : 16.0,
                                      fontWeight: FontWeight.w500,
                                      color: widget.textPrimaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${item.quantity} × ${_formatCurrency(item.pricePerUnit)} each',
                                    style: TextStyle(
                                      fontSize: isMobile ? 12.0 : 13.0,
                                      color: widget.textSecondaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _formatCurrency(item.totalPrice),
                              style: TextStyle(
                                fontSize: isMobile ? 16.0 : 18.0,
                                fontWeight: FontWeight.bold,
                                color: widget.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),
                Divider(color: widget.primaryColor.withOpacity(0.1), height: 1),
                const SizedBox(height: 20),

                // Summary
                Container(
                  padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
                  decoration: BoxDecoration(
                    color: widget.primaryColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.primaryColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        'Total Items',
                        '${order.items.length} items',
                        isMobile: isMobile,
                      ),
                      _buildDetailRow(
                        'Subtotal',
                        _formatCurrency(order.totalAmount),
                        isMobile: isMobile,
                      ),
                      _buildDetailRow(
                        'Amount Received',
                        _formatCurrency(order.amountPaid),
                        isMobile: isMobile,
                      ),
                      const Divider(height: 20),
                      _buildDetailRow(
                        order.balance >= 0 ? 'Change Due' : 'Balance Due',
                        _formatCurrency(order.balance.abs()),
                        isMobile: isMobile,
                        isBold: true,
                        color: order.balance >= 0 ? _successColor : _errorColor,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Action Buttons Row
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isActive
                            ? () {
                                Navigator.pop(context);
                                _importInvoice(order);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isActive ? widget.primaryColor : Colors.grey,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: isMobile ? 14.0 : 16.0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon:
                            Icon(Icons.edit_note, size: isMobile ? 18.0 : 20.0),
                        label: Text(
                          'Edit & Re-invoice',
                          style: TextStyle(
                            fontSize: isMobile ? 14.0 : 15.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_canManageOrders)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _toggleInvoiceStatus(order);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                isActive ? _warningColor : _successColor,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              vertical: isMobile ? 14.0 : 16.0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: Icon(
                            isActive ? Icons.block : Icons.check_circle,
                            size: isMobile ? 18.0 : 20.0,
                          ),
                          label: Text(
                            isActive ? 'Deactivate' : 'Activate',
                            style: TextStyle(
                              fontSize: isMobile ? 14.0 : 15.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    required bool isMobile,
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isMobile ? 13.0 : 14.0,
              color: widget.textSecondaryColor,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 14.0 : 15.0,
              color: color ?? widget.textPrimaryColor,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
