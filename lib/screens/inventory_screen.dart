// screens/inventory_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:drinks_calculator_fixed/providers/inventory_provider.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/models/inventory_model.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:drinks_calculator_fixed/utils/helpers.dart';
import 'inventory_report_screen.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';
import 'package:drinks_calculator_fixed/services/notification_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({Key? key}) : super(key: key);

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _searchQuery = '';
  String _filterCategory = 'All';
  String _sortBy = 'Name';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInventory();
    // ✅ Listen to real-time inventory changes
    SupabaseService.addInventoryListener(_onInventoryChanged);
  }

  void _onInventoryChanged() {
    // ✅ Refresh inventory when changes occur
    if (mounted) {
      _loadInventory();

      // ✅ Show notification to staff
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔄 Inventory updated by another staff member'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    SupabaseService.removeInventoryListener(_onInventoryChanged);
    super.dispose();
  }

  Future<void> _loadInventory() async {
    final inventoryProvider =
        Provider.of<InventoryProvider>(context, listen: false);
    await inventoryProvider.loadInventory();
    if (mounted) {
      setState(() {});
    }
  }

  List<InventoryItem> _getFilteredItems(List<InventoryItem> items) {
    List<InventoryItem> filtered = items;

    // Search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((item) =>
              item.drinkName.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    // Category filter
    if (_filterCategory != 'All') {
      filtered =
          filtered.where((item) => item.category == _filterCategory).toList();
    }

    // Sort
    switch (_sortBy) {
      case 'Name':
        filtered.sort((a, b) => a.drinkName.compareTo(b.drinkName));
        break;
      case 'Quantity (High)':
        filtered.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
      case 'Quantity (Low)':
        filtered.sort((a, b) => a.quantity.compareTo(b.quantity));
        break;
      case 'Recently Restocked':
        filtered.sort((a, b) => b.lastRestocked.compareTo(a.lastRestocked));
        break;
    }

    return filtered;
  }

  void _showAddStockDialog(InventoryItem item) {
    final quantityController = TextEditingController();
    final reasonController = TextEditingController(text: 'Restock');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.add_shopping_cart, color: Colors.green),
            const SizedBox(width: 10),
            Expanded(child: Text('Add Stock: ${item.drinkName}')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current stock: ${item.quantity}',
                style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantity to add',
                prefixIcon: Icon(Icons.numbers),
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final quantity = int.tryParse(quantityController.text);
              if (quantity != null && quantity > 0) {
                // Get providers
                final inventoryProvider =
                    Provider.of<InventoryProvider>(this.context, listen: false);

                // Add stock to inventory (provider handles everything)
                await inventoryProvider.addStock(
                  drinkId: item.drinkId,
                  drinkName: item.drinkName,
                  quantity: quantity,
                  reason: reasonController.text.isNotEmpty
                      ? reasonController.text
                      : 'Restock',
                );

                // 🔔 Notify the in-app notification center
                final newTotal = item.quantity + quantity;
                NotificationService().showStockRestocked(
                  drinkName: item.drinkName,
                  quantity: quantity,
                  newTotal: newTotal,
                );
                if (newTotal == 0) {
                  NotificationService()
                      .showOutOfStockAlert(drinkName: item.drinkName);
                } else if (newTotal <= item.minStockLevel) {
                  NotificationService().showLowStockAlert(
                    drinkName: item.drinkName,
                    currentStock: newTotal,
                    minStockLevel: item.minStockLevel,
                  );
                }

                if (mounted) {
                  Navigator.pop(context);
                  Helpers.showToast(
                      'Added $quantity ${item.drinkName} to stock');
                }
              }
            },
            icon: const Icon(Icons.check, color: Colors.white),
            label:
                const Text('Add Stock', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );
  }

  void _showDrinkDetailsDialog(
      InventoryItem item, DrinkProvider drinkProvider) {
    final drink = drinkProvider.customDrinks
        .where((d) => d.id == item.drinkId)
        .firstOrNull;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: item.isLowStock
                    ? Colors.orange.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.local_drink,
                color: item.isLowStock ? Colors.orange : Colors.green,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.drinkName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                  if (item.isLowStock)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Text('LOW STOCK',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stock Section
              _buildDetailSection('📦 Stock Information', [
                _buildDetailRow(
                    'Current Stock', '${item.quantity} ${item.unit}(s)'),
                _buildDetailRow(
                    'Minimum Level', '${item.minStockLevel} ${item.unit}(s)'),
                _buildDetailRow(
                    'Status', item.isLowStock ? '⚠️ Low Stock' : '✅ In Stock'),
                _buildDetailRow('Last Restocked',
                    DateFormat('MMM dd, yyyy').format(item.lastRestocked)),
              ]),
              const Divider(),

              // Pricing Section
              _buildDetailSection('💰 Pricing', [
                _buildDetailRow('Purchase Price',
                    CurrencyHelper.format(item.purchasePrice)),
                _buildDetailRow('Selling Price',
                    drink != null ? CurrencyHelper.format(drink.price) : 'N/A'),
                if (drink != null && item.purchasePrice > 0) ...[
                  _buildDetailRow('Profit per Unit',
                      CurrencyHelper.format(drink.price - item.purchasePrice)),
                  _buildDetailRow('Profit Margin',
                      '${(((drink.price - item.purchasePrice) / item.purchasePrice) * 100).toStringAsFixed(1)}%'),
                  _buildDetailRow(
                      'Total Stock Value',
                      CurrencyHelper.format(
                          item.purchasePrice * item.quantity)),
                  _buildDetailRow('Potential Revenue',
                      CurrencyHelper.format(drink.price * item.quantity)),
                  _buildDetailRow(
                      'Potential Profit',
                      CurrencyHelper.format(
                          (drink.price - item.purchasePrice) * item.quantity)),
                ],
              ]),
              const Divider(),

              // Category Section
              _buildDetailSection('📋 Classification', [
                _buildDetailRow('Category', item.category),
                _buildDetailRow('Unit', item.unit),
                _buildDetailRow('Drink ID', item.drinkId),
                _buildDetailRow('Inventory ID', item.id),
              ]),
              const Divider(),

              // Quick Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddStockDialog(item);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Stock'),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showUpdateMinStockDialog(item);
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Set Min'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        ...children,
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  void _showUpdateMinStockDialog(InventoryItem item) {
    final controller =
        TextEditingController(text: item.minStockLevel.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Update Minimum Stock Level'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minimum stock level',
            prefixIcon: Icon(Icons.warning),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final minLevel = int.tryParse(controller.text);
              if (minLevel != null && minLevel >= 0) {
                final provider =
                    Provider.of<InventoryProvider>(this.context, listen: false);
                provider.updateMinStockLevel(item.drinkId, minLevel);
                if (mounted) {
                Navigator.pop(context);
                Helpers.showToast(
                    'Updated min stock level for ${item.drinkName}');
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Update', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventoryProvider = Provider.of<InventoryProvider>(context);
    final drinkProvider = Provider.of<DrinkProvider>(context);
    final theme = Theme.of(context);
    final filteredItems = _getFilteredItems(inventoryProvider.inventoryItems);
    final categories = ['All', ...inventoryProvider.itemsByCategory.keys];

    return GestureDetector(
      onTap: () => LockService().resetTimer(),
      onPanDown: (_) => LockService().resetTimer(),
      onScaleStart: (_) => LockService().resetTimer(),
      onLongPress: () => LockService().resetTimer(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventory Management'),
          backgroundColor: theme.primaryColor,
          foregroundColor: Colors.white,
          actions: [
            // Report button
            IconButton(
              icon: const Icon(Icons.assessment),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const InventoryReportScreen()),
                );
              },
              tooltip: 'Reports',
            ),
            // Low stock alert
            if (inventoryProvider.lowStockCount > 0)
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.warning_amber),
                    onPressed: () {
                      setState(() {
                        _filterCategory = 'All';
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${inventoryProvider.lowStockCount}',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        body: inventoryProvider.isLoading && inventoryProvider.inventoryItems.isEmpty
            ? const _InventorySkeletonList()
            : Column(
                children: [
                  // Stats Bar
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: theme.primaryColor.withOpacity(0.05),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatChip(
                            'Total Items',
                            '${inventoryProvider.totalItems}',
                            Icons.inventory,
                            Colors.blue),
                        _buildStatChip(
                            'Products',
                            '${inventoryProvider.inventoryItems.length}',
                            Icons.category,
                            Colors.green),
                        _buildStatChip(
                            'Low Stock',
                            '${inventoryProvider.lowStockCount}',
                            Icons.warning,
                            Colors.orange),
                      ],
                    ),
                  ),

                  // Search & Filter
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search inventory...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              // Category filter
                              ...categories.map((cat) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: FilterChip(
                                      label: Text(cat),
                                      selected: _filterCategory == cat,
                                      onSelected: (selected) {
                                        setState(() => _filterCategory =
                                            selected ? cat : 'All');
                                      },
                                    ),
                                  )),
                              const SizedBox(width: 8),
                              const VerticalDivider(),
                              const SizedBox(width: 8),
                              // Sort
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.sort),
                                tooltip: 'Sort by',
                                onSelected: (value) =>
                                    setState(() => _sortBy = value),
                                itemBuilder: (context) => [
                                  'Name',
                                  'Quantity (High)',
                                  'Quantity (Low)',
                                  'Recently Restocked'
                                ]
                                    .map((s) =>
                                        PopupMenuItem(value: s, child: Text(s)))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Items List
                  Expanded(
                    child: filteredItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inventory_2,
                                    size: 80, color: Colors.grey[300]),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No items found for "$_searchQuery"'
                                      : 'No inventory items',
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _loadInventory(),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(8),
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                return _buildInventoryCard(item, drinkProvider);
                              },
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStatChip(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 16)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildInventoryCard(InventoryItem item, DrinkProvider drinkProvider) {
    final isLowStock = item.isLowStock;
    final drink = drinkProvider.customDrinks
        .where((d) => d.id == item.drinkId)
        .firstOrNull;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      borderOnForeground: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLowStock
                ? Colors.orange.withOpacity(0.5)
                : Colors.transparent,
            width: isLowStock ? 2 : 0,
          ),
        ),
        child: ListTile(
          onTap: () => _showDrinkDetailsDialog(item, drinkProvider),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isLowStock
                  ? Colors.orange.withOpacity(0.1)
                  : Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.local_drink,
              color: isLowStock ? Colors.orange : Colors.green,
              size: 28,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  item.drinkName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
              if (isLowStock)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('LOW',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.inventory, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text('Stock: ${item.quantity}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  const SizedBox(width: 16),
                  Icon(Icons.shopping_cart, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text('Min: ${item.minStockLevel}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.category, size: 12, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('${item.unit}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                  const SizedBox(width: 16),
                  if (item.purchasePrice > 0)
                    Text('Cost: ${CurrencyHelper.format(item.purchasePrice)}',
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 11)),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 12, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    'Restocked: ${DateFormat('MMM dd').format(item.lastRestocked)}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                  const SizedBox(width: 16),
                  if (drink != null)
                    Text(
                      'Price: ${CurrencyHelper.format(drink.price)}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                ],
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'add':
                  _showAddStockDialog(item);
                  break;
                case 'min':
                  _showUpdateMinStockDialog(item);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'add',
                  child: Row(children: [
                    Icon(Icons.add, size: 18),
                    SizedBox(width: 8),
                    Text('Add Stock')
                  ])),
              const PopupMenuItem(
                  value: 'min',
                  child: Row(children: [
                    Icon(Icons.edit, size: 18),
                    SizedBox(width: 8),
                    Text('Set Min Level')
                  ])),
            ],
          ),
        ),
      ),
    );
  }
}


/// Skeleton placeholder shown while inventory loads (shimmer-style).
class _InventorySkeletonList extends StatefulWidget {
  const _InventorySkeletonList();

  @override
  State<_InventorySkeletonList> createState() => _InventorySkeletonListState();
}

class _InventorySkeletonListState extends State<_InventorySkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_controller),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: 8,
        itemBuilder: (context, index) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 16, width: 140, color: Colors.grey[300],
                          decoration: BoxDecoration(color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(6))),
                      const SizedBox(height: 10),
                      Container(height: 12, color: Colors.grey[200],
                          decoration: BoxDecoration(color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(6))),
                      const SizedBox(height: 8),
                      Container(width: 90, height: 12, color: Colors.grey[200],
                          decoration: BoxDecoration(color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(6))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
