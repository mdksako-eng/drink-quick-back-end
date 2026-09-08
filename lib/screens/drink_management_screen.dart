// screens/drink_management_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/utils/helpers.dart';
import 'package:drinks_calculator_fixed/widgets/drink_card.dart';
import 'package:drinks_calculator_fixed/utils/constants.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:drinks_calculator_fixed/providers/inventory_provider.dart';
import 'package:drinks_calculator_fixed/models/inventory_model.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';
import '../utils/i18n.dart';

class DrinkManagementScreen extends StatefulWidget {
  const DrinkManagementScreen({Key? key}) : super(key: key);

  @override
  State<DrinkManagementScreen> createState() => _DrinkManagementScreenState();
}

class _DrinkManagementScreenState extends State<DrinkManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _searchController = TextEditingController();
  final _currentStockController = TextEditingController();
  final _minimumLevelController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _unitsPerPackController = TextEditingController();
  String _selectedUnit = 'Bottle';
  final List<String> _units = [
    'Bottle',
    'Can',
    'Glass',
    'Liter',
    'ml',
    'Piece',
    'Pack',
    'Crate'
  ];
  String? _editingDrinkId;
  final List<String> _categories = AppConstants.drinkCategories;
  String _selectedCategory = AppConstants.drinkCategories.first;

  // Sorting and filtering
  String _sortBy = 'name';
  bool _sortAscending = true;
  String _searchQuery = '';

  // Real-time validation states
  String? _sellingPriceError;
  bool _showProfitPreview = false;

  @override
  void initState() {
    super.initState();
    _loadDrinks().then((_) {
      setState(() {}); // Refresh UI after loading
    });
    _searchController.addListener(_onSearchChanged);
    CurrencyHelper.addListener(_refreshCurrency);

    // Add real-time listeners for profit calculation and validation
    _purchasePriceController.addListener(_onPriceChanged);
    _priceController.addListener(_onPriceChanged);
    _nameController.addListener(() {
      setState(() {});
    });
    _currentStockController.addListener(() {
      // ADD THIS
      setState(() {}); // ADD THIS
    });
    SupabaseService.addInventoryListener(_onInventoryChanged);
  }

  @override
  void dispose() {
    _purchasePriceController.removeListener(_onPriceChanged);
    _priceController.removeListener(_onPriceChanged);
    _nameController.removeListener(() {});
    _nameController.dispose();
    _priceController.dispose();
    _imageUrlController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    CurrencyHelper.removeListener(_refreshCurrency);
    _currentStockController.dispose();
    _minimumLevelController.dispose();
    _purchasePriceController.dispose();
    _barcodeController.dispose();
    _unitsPerPackController.dispose();
    _currentStockController.removeListener(() {});
    SupabaseService.removeInventoryListener(_onInventoryChanged);
    super.dispose();
  }

  void _onPriceChanged() {
    setState(() {
      // Real-time validation
      final sellingPriceText = _priceController.text.trim();
      final purchasePriceText = _purchasePriceController.text.trim();

      if (sellingPriceText.isNotEmpty && purchasePriceText.isNotEmpty) {
        final sellingPrice = double.tryParse(sellingPriceText);
        final purchasePrice = double.tryParse(purchasePriceText);

        if (sellingPrice != null && purchasePrice != null) {
          if (sellingPrice <= purchasePrice) {
            _sellingPriceError =
                t('dm_priceError');
            _showProfitPreview = false;
          } else {
            _sellingPriceError = null;
            _showProfitPreview = true;
          }
        } else {
          _sellingPriceError = null;
          _showProfitPreview = false;
        }
      } else {
        _sellingPriceError = null;
        _showProfitPreview = false;
      }
    });
  }

  void _refreshCurrency() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onInventoryChanged() {
    if (!mounted) return;

    print(
        '🔄 DrinkManagementScreen: Inventory changed by another staff member');

    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    drinkProvider.loadDrinksFromSupabase().then((_) {
      if (mounted) {
        setState(() {});
        Helpers.showToast('🔄 ${t('dm_invUpdated')}');
      }
    });
  }

  Future<void> _loadDrinks() async {
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);

    if (SupabaseService.canUseSupabase) {
      await drinkProvider.loadDrinksFromSupabase();
      debugPrint('✅ Loaded drinks from Supabase');
    } else {
      await drinkProvider.loadDrinks();
      debugPrint('✅ Loaded drinks from local storage');
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase().trim();
      });
    }
  }

  List<Drink> _getAllDrinks(DrinkProvider drinkProvider) {
    List<Drink> drinks = [...drinkProvider.customDrinks];

    if (_searchQuery.isNotEmpty) {
      drinks = drinks.where((drink) {
        return drink.name.toLowerCase().contains(_searchQuery) ||
            drink.category.toLowerCase().contains(_searchQuery) ||
            drink.price.toString().contains(_searchQuery);
      }).toList();
    }

    drinks.sort((a, b) {
      int comparison;
      switch (_sortBy) {
        case 'name':
          comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case 'price':
          comparison = a.price.compareTo(b.price);
          break;
        case 'category':
          comparison =
              a.category.toLowerCase().compareTo(b.category.toLowerCase());
          break;
        default:
          comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _sortAscending ? comparison : -comparison;
    });

    return drinks;
  }

  void _clearForm() {
    _nameController.clear();
    _priceController.clear();
    _imageUrlController.clear();
    _currentStockController.clear();
    _minimumLevelController.text = '5';
    _purchasePriceController.clear();
    _barcodeController.clear();
    _unitsPerPackController.text = '1';
    _editingDrinkId = null;
    _selectedCategory = AppConstants.drinkCategories.first;
    _selectedUnit = 'Bottle';
    _sellingPriceError = null;
    _showProfitPreview = false;
  }

  void _editDrink(Drink drink) {
    setState(() {
      _editingDrinkId = drink.id;
      _nameController.text = drink.name;
      _priceController.text = drink.price.toStringAsFixed(0);
      _selectedCategory = drink.category;
      _imageUrlController.text = drink.imageUrl;
      _currentStockController.text = drink.currentStock.toString();
      _minimumLevelController.text = drink.minimumLevel.toString();
      _purchasePriceController.text = drink.purchasePrice.toStringAsFixed(0);
      _selectedUnit = drink.unit;
      _barcodeController.text = drink.barcode;
      _unitsPerPackController.text = drink.unitsPerPack.toString();
      _sellingPriceError = null;
      _showProfitPreview = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Scrollable.ensureVisible(_formKey.currentContext!);
    });
  }

  Future<void> _deleteDrink(String id) async {
    final confirmed = await Helpers.showConfirmationDialog(
      context,
      t('dm_deleteTitle'),
      t('dm_deleteConfirm'),
    );

    if (confirmed) {
      final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
      final inventoryProvider =
          Provider.of<InventoryProvider>(context, listen: false);

      final drink = drinkProvider.customDrinks.firstWhere((d) => d.id == id);
      await drinkProvider.deleteDrink(id);
      await inventoryProvider.deleteInventoryItem(id);

      Helpers.showToast('${drink.name} ${t('dm_deleted')}');
      setState(() {});
    }
  }

  Future<void> _saveDrink() async {
    if (!_formKey.currentState!.validate()) return;

    // Check real-time validation
    if (_sellingPriceError != null) {
      Helpers.showToast(_sellingPriceError!, isError: true);
      return;
    }

    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final inventoryProvider =
        Provider.of<InventoryProvider>(context, listen: false);
    final drinkName = _nameController.text.trim();

    // Check for duplicate drink name
    final isDuplicate = drinkProvider.customDrinks.any((d) {
      final sameName = d.name.toLowerCase() == drinkName.toLowerCase();
      if (_editingDrinkId != null) {
        return sameName && d.id != _editingDrinkId;
      }
      return sameName;
    });

    if (isDuplicate) {
      Helpers.showToast(t('dm_duplicate').replaceAll('@name', drinkName),
          isError: true);
      return;
    }

    final int newStock = int.tryParse(_currentStockController.text) ?? 0;

    final drink = Drink(
      id: _editingDrinkId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      price: double.parse(_priceController.text),
      category: _selectedCategory,
      imageUrl: _imageUrlController.text.trim().isEmpty
          ? AppConstants.defaultDrinkImage
          : _imageUrlController.text.trim(),
      currentStock: newStock,
      minimumLevel: int.tryParse(_minimumLevelController.text) ?? 5,
      unit: _selectedUnit,
      purchasePrice: double.tryParse(_purchasePriceController.text) ?? 0,
      barcode: _barcodeController.text.trim(),
      unitsPerPack: int.tryParse(_unitsPerPackController.text) ?? 1,
    );

    if (_editingDrinkId != null) {
      // ✅ Update drink
      await drinkProvider.updateDrink(_editingDrinkId!, drink);

      // ✅ Find existing inventory item
      final existingItem = inventoryProvider.inventoryItems
          .where((item) => item.drinkId == _editingDrinkId)
          .firstOrNull;

      if (existingItem != null) {
        // ✅ Update existing inventory item
        existingItem.quantity = newStock;
        existingItem.minStockLevel = drink.minimumLevel;
        existingItem.category = drink.category;
        existingItem.unit = drink.unit;
        existingItem.purchasePrice = drink.purchasePrice;
        existingItem.drinkName = drink.name;
        existingItem.lastRestocked = DateTime.now();

        // ✅ Force refresh and save
        inventoryProvider.refreshInventory();
        await inventoryProvider.saveInventoryToStorage();

        // ✅ Sync to Supabase (THIS IS THE KEY FIX)
        final success =
            await SupabaseService.upsertInventory(existingItem.toJson());
        debugPrint(
            '✅ Inventory updated in Supabase: ${drink.name} stock = $newStock, success: $success');

        // ✅ Also sync the drink to Supabase
        await SupabaseService.updateDrink(_editingDrinkId!, drink.toJson());
      } else {
        // ✅ Create new inventory item
        await inventoryProvider.addInventoryItem(InventoryItem(
          id: 'inv_${DateTime.now().millisecondsSinceEpoch}',
          drinkId: drink.id,
          drinkName: drink.name,
          quantity: newStock,
          minStockLevel: drink.minimumLevel,
          lastRestocked: DateTime.now(),
          category: drink.category,
          unit: drink.unit,
          purchasePrice: drink.purchasePrice,
        ));
        debugPrint('✅ New inventory item created: ${drink.name}');
      }

      Helpers.showToast('${drink.name} ${t('dm_updated')}');
    } else {
      // ✅ Add new drink
      await drinkProvider.addDrink(drink);

      // ✅ Add inventory item
      await inventoryProvider.addInventoryItem(InventoryItem(
        id: 'inv_${DateTime.now().millisecondsSinceEpoch}',
        drinkId: drink.id,
        drinkName: drink.name,
        quantity: newStock,
        minStockLevel: drink.minimumLevel,
        lastRestocked: DateTime.now(),
        category: drink.category,
        unit: drink.unit,
        purchasePrice: drink.purchasePrice,
      ));

      Helpers.showToast('${drink.name} ${t('dm_added')}');
    }

    _clearForm();
    setState(() {});
  }

  void _toggleSort(String field) {
    setState(() {
      if (_sortBy == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = field;
        _sortAscending = true;
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final drinkProvider = Provider.of<DrinkProvider>(context);
    final allDrinks = _getAllDrinks(drinkProvider);
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final isDarkMode = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => LockService().resetTimer(),
      onPanDown: (_) => LockService().resetTimer(),
      onScaleStart: (_) => LockService().resetTimer(),
      onLongPress: () => LockService().resetTimer(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Drink Management',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          centerTitle: true,
          backgroundColor: primaryColor,
          elevation: 4,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            if (_editingDrinkId != null)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _clearForm,
                tooltip: t('dm_clearForm'),
              ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDarkMode
                  ? [Colors.grey[900]!, Colors.grey[800]!]
                  : [Colors.grey[50]!, Colors.white],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;
                final isTablet =
                    constraints.maxWidth >= 600 && constraints.maxWidth < 1200;

                return SingleChildScrollView(
                  padding: EdgeInsets.all(isMobile ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Search and Sort Card
                      _buildSearchSortCard(isMobile, primaryColor, allDrinks),
                      SizedBox(height: isMobile ? 16 : 24),

                      // Add/Edit Drink Form Card
                      _buildFormCard(isMobile, isTablet, primaryColor, theme),
                      SizedBox(height: isMobile ? 24 : 32),

                      // Custom Drinks Header
                      _buildDrinksHeader(
                          isMobile, primaryColor, allDrinks, drinkProvider),
                      SizedBox(height: isMobile ? 16 : 24),

                      // Drinks Grid
                      if (allDrinks.isEmpty)
                        _buildEmptyState(isMobile, primaryColor, theme)
                      else
                        _buildDrinksGrid(isMobile, isTablet, allDrinks),
                      SizedBox(height: isMobile ? 24 : 32),

                      // Quick Tips
                      if (allDrinks.isNotEmpty)
                        _buildTipsCard(isMobile, primaryColor, theme),
                      SizedBox(height: isMobile ? 20 : 30),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ==================== WIDGET BUILDERS ====================

  Widget _buildSearchSortCard(
      bool isMobile, Color primaryColor, List<Drink> allDrinks) {
    final theme = Theme.of(context);
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: theme.cardColor,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          children: [
            // Search Bar
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
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
                        hintText: t('dm_searchHint'),
                        hintStyle: TextStyle(
                            color: theme.hintColor,
                            fontSize: isMobile ? 14 : 16),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: isMobile ? 14 : 16),
                        prefixIcon:
                            Icon(Icons.search, color: primaryColor, size: 22),
                      ),
                      style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                          fontSize: isMobile ? 14 : 16),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.clear, color: Colors.red, size: 22),
                      onPressed: _clearSearch,
                      tooltip: t('dm_clearSearch'),
                    ),
                ],
              ),
            ),
            SizedBox(height: isMobile ? 12 : 16),
            // Sort Options
            Container(
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
              ),
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('dm_sortDrinks'),
                        style: TextStyle(
                            fontSize: isMobile ? 14 : 16,
                            fontWeight: FontWeight.bold,
                            color: primaryColor)),
                    SizedBox(height: isMobile ? 8 : 12),
                    Wrap(
                      spacing: isMobile ? 8 : 12,
                      runSpacing: isMobile ? 8 : 12,
                      children: [
                        _buildSortChip(t('sort_name'), 'name', isMobile, primaryColor),
                        _buildSortChip(
                            'Price', 'price', isMobile, primaryColor),
                        _buildSortChip(
                            'Category', 'category', isMobile, primaryColor),
                      ],
                    ),
                    if (_searchQuery.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            Icon(Icons.filter_list,
                                color: primaryColor, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Showing ${allDrinks.length} result${allDrinks.length != 1 ? 's' : ''} for "$_searchQuery"',
                              style: TextStyle(
                                  fontSize: isMobile ? 13 : 14,
                                  color: primaryColor,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard(
      bool isMobile, bool isTablet, Color primaryColor, ThemeData theme) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: theme.cardColor,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Form Header
              _buildFormHeader(isMobile, primaryColor),
              const SizedBox(height: 24),

              // Drink Name
              _buildNameField(isMobile, primaryColor, theme),
              SizedBox(height: isMobile ? 16 : 20),

              // Duplicate name warning - shows in real-time as you type
              Builder(
                builder: (context) {
                  final nameText = _nameController.text.trim();
                  if (nameText.isEmpty) return const SizedBox.shrink();

                  final drinkProvider =
                      Provider.of<DrinkProvider>(context, listen: true);
                  final isDuplicate = drinkProvider.customDrinks.any((d) {
                    final sameName =
                        d.name.toLowerCase() == nameText.toLowerCase();
                    if (_editingDrinkId != null) {
                      return sameName && d.id != _editingDrinkId;
                    }
                    return sameName;
                  });

                  if (isDuplicate) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning,
                              color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t('dm_duplicate').replaceAll('@name', nameText),
                              style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              SizedBox(height: isMobile ? 16 : 20),

              // Purchase Price
              _buildPurchasePriceField(isMobile, primaryColor, theme),
              SizedBox(height: isMobile ? 16 : 20),

              // Selling Price
              _buildSellingPriceField(isMobile, primaryColor, theme),

              // Real-time error
              if (_sellingPriceError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _sellingPriceError!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: isMobile ? 16 : 20),

              // Category
              _buildCategoryDropdown(isMobile, primaryColor, theme),
              SizedBox(height: isMobile ? 16 : 20),

              // Unit
              _buildUnitDropdown(isMobile, primaryColor, theme),
              SizedBox(height: isMobile ? 16 : 20),

              // Current Stock
              _buildStockField(isMobile, primaryColor),
              SizedBox(height: isMobile ? 16 : 20),

              // Minimum Level
              _buildMinLevelField(isMobile, primaryColor),
              SizedBox(height: isMobile ? 16 : 20),

              // Profit margin preview (per unit)
              if (_showProfitPreview) _buildProfitPreview(),

              // Profit × Stock preview
              if (_showProfitPreview && _currentStockController.text.isNotEmpty)
                Builder(
                  builder: (context) {
                    final stock =
                        int.tryParse(_currentStockController.text) ?? 0;
                    final sellingPrice =
                        double.tryParse(_priceController.text) ?? 0;
                    final purchasePrice =
                        double.tryParse(_purchasePriceController.text) ?? 0;

                    if (stock > 0 &&
                        sellingPrice > purchasePrice &&
                        purchasePrice > 0) {
                      final profitPerUnit = sellingPrice - purchasePrice;
                      final totalProfit = profitPerUnit * stock;
                      final totalRevenue = sellingPrice * stock;
                      final totalCost = purchasePrice * stock;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.inventory,
                                    color: Colors.blue, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Stock Value ($stock ${_selectedUnit}(s)):',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildStockPreviewRow(
                                t('dm_totalCost'), CurrencyHelper.format(totalCost)),
                            _buildStockPreviewRow(t('dm_potentialRevenue'),
                                CurrencyHelper.format(totalRevenue)),
                            const Divider(height: 16),
                            _buildStockPreviewRow(t('dm_potentialProfit'),
                                CurrencyHelper.format(totalProfit),
                                isBold: true, color: Colors.green),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

              // Image URL
              _buildImageUrlField(isMobile, primaryColor, theme),
              SizedBox(height: isMobile ? 16 : 20),

              // Barcode (optional — for scanner / wholesale)
              _buildBarcodeField(isMobile, primaryColor, theme),
              SizedBox(height: isMobile ? 16 : 20),

              // Units per pack (wholesale case size)
              _buildUnitsPerPackField(isMobile, primaryColor, theme),
              SizedBox(height: isMobile ? 8 : 10),
              Row(
                children: [
                  Icon(Icons.info, color: primaryColor, size: 14),
                  const SizedBox(width: 6),
                  Text(t('dm_emptyImageHint'),
                      style: TextStyle(
                          fontSize: isMobile ? 11 : 12, color: primaryColor)),
                ],
              ),
              SizedBox(height: isMobile ? 20 : 28),

              // Action Buttons
              isMobile ? _buildMobileButtons(isMobile) : _buildDesktopButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormHeader(bool isMobile, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration:
                BoxDecoration(color: primaryColor, shape: BoxShape.circle),
            child: Icon(
              _editingDrinkId != null ? Icons.edit_note : Icons.add_circle,
              color: Colors.white,
              size: isMobile ? 20 : 24,
            ),
          ),
          SizedBox(width: isMobile ? 12 : 16),
          Expanded(
            child: Text(
              _editingDrinkId != null ? t('dm_editDrink') : t('dm_addNewDrink'),
              style: TextStyle(
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.bold,
                  color: primaryColor),
            ),
          ),
          if (_editingDrinkId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange, width: 1),
              ),
              child: Text(t('dm_editing'),
                  style: TextStyle(
                      fontSize: isMobile ? 12 : 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange)),
            ),
        ],
      ),
    );
  }

  Widget _buildNameField(bool isMobile, Color primaryColor, ThemeData theme) {
    return TextFormField(
      controller: _nameController,
      decoration: InputDecoration(
        labelText: t('dm_name'),
        labelStyle: TextStyle(color: theme.hintColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.dividerColor)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 2)),
        prefixIcon: Icon(Icons.local_drink, color: primaryColor),
        filled: true,
        fillColor: theme.cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      style: TextStyle(
          color: theme.textTheme.bodyLarge?.color,
          fontSize: isMobile ? 14 : 16),
      validator: (value) {
        if (value == null || value.trim().isEmpty)
          return t('dm_nameRequired');
        if (value.trim().length < 2)
          return t('dm_nameTooShort');
        return null;
      },
    );
  }

  Widget _buildPurchasePriceField(
      bool isMobile, Color primaryColor, ThemeData theme) {
    return TextFormField(
      controller: _purchasePriceController,
      decoration: InputDecoration(
        labelText: '${t('dm_purchasePrice')} (${CurrencyHelper.getSymbol()})',
        labelStyle: TextStyle(color: theme.hintColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.dividerColor)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 2)),
        prefixIcon: Icon(Icons.attach_money, color: primaryColor),
        suffixText: CurrencyHelper.getSymbol(),
        suffixStyle:
            TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
        filled: true,
        fillColor: theme.cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      style: TextStyle(
          color: theme.textTheme.bodyLarge?.color,
          fontSize: isMobile ? 14 : 16),
      keyboardType: TextInputType.number,
      validator: (value) {
        if (value == null || value.trim().isEmpty)
          return t('dm_purchasePriceRequired');
        final price = double.tryParse(value);
        if (price == null) return t('dm_validNumber');
        if (price <= 0) return t('dm_pricePositive');
        if (price > 100000)
          return '${t('dm_priceMax')} 100,000 ${CurrencyHelper.getSymbol()}';
        return null;
      },
    );
  }

  Widget _buildSellingPriceField(
      bool isMobile, Color primaryColor, ThemeData theme) {
    return TextFormField(
      controller: _priceController,
      decoration: InputDecoration(
        labelText: '${t('dm_sellingPrice')} (${CurrencyHelper.getSymbol()})',
        labelStyle: TextStyle(color: theme.hintColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.dividerColor)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 2)),
        prefixIcon: Icon(Icons.attach_money, color: primaryColor),
        suffixText: CurrencyHelper.getSymbol(),
        suffixStyle:
            TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
        filled: true,
        fillColor: theme.cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        // errorText: _sellingPriceError,
      ),
      style: TextStyle(
          color: theme.textTheme.bodyLarge?.color,
          fontSize: isMobile ? 14 : 16),
      keyboardType: TextInputType.number,
      validator: (value) {
        if (value == null || value.trim().isEmpty)
          return t('dm_sellingPriceRequired');
        final price = double.tryParse(value);
        if (price == null) return t('dm_validNumber');
        if (price <= 0) return t('dm_pricePositive');
        if (price > 100000)
          return '${t('dm_priceMax')} 100,000 ${CurrencyHelper.getSymbol()}';
        return null;
      },
    );
  }

  Widget _buildProfitPreview() {
    final sellingPrice = double.tryParse(_priceController.text) ?? 0;
    final purchasePrice = double.tryParse(_purchasePriceController.text) ?? 0;

    if (sellingPrice > purchasePrice && purchasePrice > 0) {
      final profit = sellingPrice - purchasePrice;
      final profitPercent = (profit / purchasePrice) * 100;
      final isGoodProfit = profitPercent >= 20;

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isGoodProfit
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isGoodProfit
                ? Colors.green.withValues(alpha: 0.3)
                : Colors.orange.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isGoodProfit ? Icons.trending_up : Icons.trending_down,
              color: isGoodProfit ? Colors.green : Colors.orange,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profit: ${CurrencyHelper.format(profit)} (${profitPercent.toStringAsFixed(1)}%)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isGoodProfit ? Colors.green : Colors.orange,
                        fontSize: 14),
                  ),
                  Text(
                    isGoodProfit
                        ? t('dm_goodMargin')
                        : t('dm_lowMargin'),
                    style: TextStyle(
                        fontSize: 11,
                        color: isGoodProfit ? Colors.green : Colors.orange),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCategoryDropdown(
      bool isMobile, Color primaryColor, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category',
            style: TextStyle(
                color: theme.hintColor,
                fontSize: isMobile ? 14 : 15,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
            color: theme.cardColor,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCategory,
                isExpanded: true,
                icon: Icon(Icons.arrow_drop_down, color: primaryColor),
                style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: isMobile ? 14 : 16),
                items: _categories.map((category) {
                  return DropdownMenuItem(
                      value: category,
                      child: Text(t('cat_' + category),
                          style: const TextStyle(fontWeight: FontWeight.w500)));
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null)
                    setState(() => _selectedCategory = newValue);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnitDropdown(
      bool isMobile, Color primaryColor, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Unit',
            style: TextStyle(
                color: theme.hintColor,
                fontSize: isMobile ? 14 : 15,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
            color: theme.cardColor,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedUnit,
                isExpanded: true,
                icon: Icon(Icons.arrow_drop_down, color: primaryColor),
                style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: isMobile ? 14 : 16),
                items: _units
                    .map((unit) =>
                        DropdownMenuItem(value: unit, child: Text(t('unit_' + unit))))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedUnit = value);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStockField(bool isMobile, Color primaryColor) {
    return TextFormField(
      controller: _currentStockController,
      decoration: InputDecoration(
        labelText: t('dm_currentStock'),
        prefixIcon: Icon(Icons.inventory, color: primaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 2)),
      ),
      keyboardType: TextInputType.number,
    );
  }

  Widget _buildMinLevelField(bool isMobile, Color primaryColor) {
    return TextFormField(
      controller: _minimumLevelController,
      decoration: InputDecoration(
        labelText: t('dm_minStock'),
        prefixIcon: Icon(Icons.warning_amber, color: primaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 2)),
        helperText: t('dm_minStockHelper'),
      ),
      keyboardType: TextInputType.number,
    );
  }

  Widget _buildStockPreviewRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageUrlField(
      bool isMobile, Color primaryColor, ThemeData theme) {
    return TextFormField(
      controller: _imageUrlController,
      decoration: InputDecoration(
        labelText: t('dm_imageUrl'),
        labelStyle: TextStyle(color: theme.hintColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.dividerColor)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 2)),
        prefixIcon: Icon(Icons.image, color: primaryColor),
        filled: true,
        fillColor: theme.cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      style: TextStyle(
          color: theme.textTheme.bodyLarge?.color,
          fontSize: isMobile ? 14 : 16),
    );
  }

  Widget _buildBarcodeField(
      bool isMobile, Color primaryColor, ThemeData theme) {
    return TextFormField(
      controller: _barcodeController,
      decoration: InputDecoration(
        labelText: t('barcode'),
        labelStyle: TextStyle(color: theme.hintColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.dividerColor)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 2)),
        prefixIcon: Icon(Icons.qr_code, color: primaryColor),
        filled: true,
        fillColor: theme.cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      style: TextStyle(
          color: theme.textTheme.bodyLarge?.color,
          fontSize: isMobile ? 14 : 16),
    );
  }

  Widget _buildUnitsPerPackField(
      bool isMobile, Color primaryColor, ThemeData theme) {
    return TextFormField(
      controller: _unitsPerPackController,
      decoration: InputDecoration(
        labelText: t('unitsPerPack'),
        prefixIcon: Icon(Icons.all_inbox, color: primaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.dividerColor)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 2)),
        filled: true,
        fillColor: theme.cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      style: TextStyle(
          color: theme.textTheme.bodyLarge?.color,
          fontSize: isMobile ? 14 : 16),
      keyboardType: TextInputType.number,
    );
  }

  Widget _buildMobileButtons(bool isMobile) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _saveDrink,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_editingDrinkId != null ? Icons.save : Icons.add,
                  size: 22, color: Colors.white),
              const SizedBox(width: 8),
              Text(_editingDrinkId != null ? t('dm_updateDrink') : t('dm_addDrink'),
                  style: TextStyle(
                      fontSize: isMobile ? 15 : 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _clearForm,
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.clear, color: Colors.red, size: 22),
              const SizedBox(width: 8),
              Text(t('dm_clearForm'),
                  style: TextStyle(
                      fontSize: isMobile ? 15 : 17,
                      color: Colors.red,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _saveDrink,
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_editingDrinkId != null ? Icons.save : Icons.add,
                    size: 24, color: Colors.white),
                const SizedBox(width: 12),
                Text(_editingDrinkId != null ? t('dm_updateDrink') : t('dm_addDrink'),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: OutlinedButton(
            onPressed: _clearForm,
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.clear, color: Colors.red, size: 24),
                const SizedBox(width: 10),
                Text(t('dm_clear'),
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDrinksHeader(bool isMobile, Color primaryColor,
      List<Drink> allDrinks, DrinkProvider drinkProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [primaryColor, primaryColor.withValues(alpha: 0.7)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: Icon(Icons.local_drink,
                      color: primaryColor, size: isMobile ? 20 : 24)),
              SizedBox(width: isMobile ? 12 : 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('dm_customDrinks'),
                      style: TextStyle(
                          fontSize: isMobile ? 18 : 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  if (_searchQuery.isEmpty)
                    Text(
                        'Sorted by $_sortBy (${_sortAscending ? 'A→Z' : 'Z→A'})',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 13,
                            color: Colors.white.withValues(alpha: 0.9))),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
            child: Row(
              children: [
                Icon(_searchQuery.isNotEmpty ? Icons.search : Icons.inventory,
                    color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  _searchQuery.isNotEmpty
                      ? '${allDrinks.length} found'
                      : 'Total: ${drinkProvider.customDrinks.length}',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: isMobile ? 14 : 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isMobile, Color primaryColor, ThemeData theme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.cardColor,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 24 : 40),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryColor.withValues(alpha: 0.1),
                  border: Border.all(
                      color: primaryColor.withValues(alpha: 0.3), width: 2)),
              child: Icon(
                  _searchQuery.isNotEmpty
                      ? Icons.search_off
                      : Icons.local_drink,
                  size: isMobile ? 50 : 60,
                  color: primaryColor),
            ),
            SizedBox(height: isMobile ? 16 : 20),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No drinks found for "$_searchQuery"'
                  : t('dm_noCustomDrinks'),
              style: TextStyle(
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            Text(
              _searchQuery.isNotEmpty
                  ? t('dm_tryDifferent')
                  : t('dm_addFirst'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: isMobile ? 14 : 16, color: theme.hintColor),
            ),
            SizedBox(height: isMobile ? 20 : 28),
            if (_searchQuery.isNotEmpty)
              ElevatedButton(
                onPressed: _clearSearch,
                style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: EdgeInsets.symmetric(
                        horizontal: 32, vertical: isMobile ? 12 : 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.clear_all, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(t('dm_clearSearchBtn'),
                        style: TextStyle(
                            fontSize: isMobile ? 15 : 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: primaryColor.withValues(alpha: 0.05),
                    border:
                        Border.all(color: primaryColor.withValues(alpha: 0.1))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.tips_and_updates, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(t('dm_proTips'),
                          style: TextStyle(
                              fontSize: isMobile ? 16 : 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange))
                    ]),
                    const SizedBox(height: 12),
                    _buildTipItem(t('dm_tipSearch'),
                        iconColor: primaryColor),
                    _buildTipItem(t('dm_tipSortChips'),
                        iconColor: primaryColor),
                    _buildTipItem(t('dm_tipImageUrl'),
                        iconColor: primaryColor),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrinksGrid(bool isMobile, bool isTablet, List<Drink> allDrinks) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile
            ? 2
            : isTablet
                ? 3
                : 4,
        crossAxisSpacing: isMobile ? 16 : 20,
        mainAxisSpacing: isMobile ? 16 : 20,
        childAspectRatio: isMobile ? 0.85 : 0.9,
      ),
      itemCount: allDrinks.length,
      itemBuilder: (context, index) {
        final drink = allDrinks[index];
        return DrinkCard(
          drink: drink,
          onTap: () => _editDrink(drink),
          onEdit: () => _editDrink(drink),
          onDelete: () => _deleteDrink(drink.id),
          isBuiltIn: false,
          isMobile: isMobile,
        );
      },
    );
  }

  Widget _buildTipsCard(bool isMobile, Color primaryColor, ThemeData theme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.cardColor,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: primaryColor, shape: BoxShape.circle),
                    child: const Icon(Icons.lightbulb,
                        color: Colors.white, size: 20)),
                SizedBox(width: isMobile ? 12 : 16),
                Expanded(
                    child: Text(t('dm_quickMgmtTips'),
                        style: TextStyle(
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.bodyLarge?.color))),
              ],
            ),
            SizedBox(height: isMobile ? 12 : 16),
            _buildTipItem(
                t('dm_tipSearch2'),
                iconColor: primaryColor),
            _buildTipItem(
                t('dm_tipSortChips2'),
                iconColor: primaryColor),
            _buildTipItem(t('dm_tipTapCard'),
                iconColor: primaryColor),
            _buildTipItem(t('dm_tipEmptyImage'),
                iconColor: primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildSortChip(
      String label, String sortField, bool isMobile, Color primaryColor) {
    final bool isSelected = _sortBy == sortField;
    return GestureDetector(
      onTap: () => _toggleSort(sortField),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 16, vertical: isMobile ? 8 : 10),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected ? primaryColor : Colors.grey,
              width: isSelected ? 2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: isMobile ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.grey[700])),
            if (isSelected) const SizedBox(width: 6),
            if (isSelected)
              Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: isMobile ? 14 : 16, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildTipItem(String text, {Color iconColor = Colors.blue}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: iconColor, size: 16),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 14, color: theme.hintColor, height: 1.4))),
        ],
      ),
    );
  }
}
