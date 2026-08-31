// screens/inventory_report_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:drinks_calculator_fixed/providers/inventory_provider.dart';
import 'package:drinks_calculator_fixed/models/inventory_model.dart';
import 'package:drinks_calculator_fixed/utils/export_helper.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';

class InventoryReportScreen extends StatefulWidget {
  const InventoryReportScreen({Key? key}) : super(key: key);

  @override
  State<InventoryReportScreen> createState() => _InventoryReportScreenState();
}

class _InventoryReportScreenState extends State<InventoryReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  InventoryReport? _report;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _generateReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _generateReport() {
    final provider = Provider.of<InventoryProvider>(context, listen: false);
    setState(() {
      _report =
          provider.generateReport(startDate: _startDate, endDate: _endDate);
    });
  }

  Future<void> _selectDateRange() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: Theme.of(context).primaryColor,
                    onPrimary: Colors.white,
                    surface: Colors.grey[850]!,
                    onSurface: Colors.white,
                  )
                : ColorScheme.light(
                    primary: Theme.of(context).primaryColor,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black,
                  ),
            dialogTheme: DialogThemeData(
              backgroundColor: isDark ? Colors.grey[850] : Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _generateReport();
    }
  }

  // ========== PROFIT CALCULATIONS ==========

  double _getTotalRevenue() {
    if (_report == null) return 0;
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);

    return _report!.transactions
        .where((t) => t.isOutgoing && t.reason == 'sale')
        .fold(0.0, (sum, t) {
      // Get actual selling price from drinks
      final drink = drinkProvider.customDrinks.firstWhere(
        (d) => d.id == t.drinkId,
        orElse: () => Drink(id: '', name: '', price: 0, imageUrl: ''),
      );
      return sum + (drink.price * t.quantity);
    });
  }

  double _getTotalCost() {
    if (_report == null) return 0;
    return _report!.transactions
        .where((t) => t.isOutgoing && t.reason == 'sale')
        .fold(0.0, (sum, t) {
      final item = _report!.currentStock.firstWhere(
        (i) => i.drinkId == t.drinkId,
        orElse: () => InventoryItem(
          id: '',
          drinkId: '',
          drinkName: '',
          quantity: 0,
          lastRestocked: DateTime.now(),
        ),
      );
      return sum + (item.purchasePrice * t.quantity);
    });
  }

  double _getTotalProfit() {
    final revenue = _getTotalRevenue();
    final cost = _getTotalCost();
    return revenue - cost;
  }

  double _getProfitMargin() {
    final revenue = _getTotalRevenue();
    if (revenue == 0) return 0;
    final cost = _getTotalCost();
    return ((revenue - cost) / revenue) * 100;
  }

  Map<String, double> _getProfitByCategory() {
    final map = <String, double>{};
    if (_report == null) return map;
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    for (final t in _report!.transactions
        .where((t) => t.isOutgoing && t.reason == 'sale')) {
      final drink = drinkProvider.customDrinks.firstWhere(
        (d) => d.id == t.drinkId,
        orElse: () => Drink(id: '', name: '', price: 0, imageUrl: ''),
      );
      final item = _report!.currentStock.firstWhere(
        (i) => i.drinkId == t.drinkId,
        orElse: () => InventoryItem(
          id: '',
          drinkId: '',
          drinkName: '',
          quantity: 0,
          lastRestocked: DateTime.now(),
          category: 'Other',
        ),
      );
      final cat = item.category;
      final profit = (drink.price - item.purchasePrice) * t.quantity;
      map[cat] = (map[cat] ?? 0) + profit;
    }
    return map;
  }

  List<MapEntry<String, double>> _getTopProfitableDrinks() {
    final map = <String, double>{};
    if (_report == null) return [];
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);

    for (final t in _report!.transactions
        .where((t) => t.isOutgoing && t.reason == 'sale')) {
      final drink = drinkProvider.customDrinks.firstWhere(
        (d) => d.id == t.drinkId,
        orElse: () => Drink(id: '', name: '', price: 0, imageUrl: ''),
      );
      final item = _report!.currentStock.firstWhere(
        (i) => i.drinkId == t.drinkId,
        orElse: () => InventoryItem(
          id: '',
          drinkId: '',
          drinkName: t.drinkName,
          quantity: 0,
          lastRestocked: DateTime.now(),
        ),
      );
      final profit = (drink.price - item.purchasePrice) * t.quantity;
      map[t.drinkName] = (map[t.drinkName] ?? 0) + profit;
    }

    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => LockService().resetTimer(),
      onPanDown: (_) => LockService().resetTimer(),
      onScaleStart: (_) => LockService().resetTimer(),
      onLongPress: () => LockService().resetTimer(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports & Analytics'),
          backgroundColor: theme.primaryColor,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.inventory), text: 'Inventory'),
              Tab(icon: Icon(Icons.analytics), text: 'Profit'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () {
                if (_report != null) {
                  ExportHelper.exportInventoryReport(_report!, context);
                }
              },
              tooltip: 'Export Report',
            ),
          ],
        ),
        body: _report == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildInventoryTab(theme),
                  _buildProfitTab(theme),
                ],
              ),
      ),
    );
  }

  // ==================== INVENTORY TAB ====================

  Widget _buildInventoryTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date Range Selector
          _buildDateRangeCard(theme),
          const SizedBox(height: 16),

          // Summary Cards
          Row(
            children: [
              Expanded(
                  child: _buildSummaryCard(
                      'Total Stock',
                      '${_report!.currentStock.fold(0, (s, i) => s + i.quantity)}',
                      Icons.inventory,
                      Colors.blue)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildSummaryCard(
                      'Items In',
                      '${_report!.totalItemsIn}',
                      Icons.add_shopping_cart,
                      Colors.green)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _buildSummaryCard(
                      'Items Out',
                      '${_report!.totalItemsOut}',
                      Icons.remove_shopping_cart,
                      Colors.red)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildSummaryCard(
                      'Low Stock',
                      '${_report!.lowStockCount}',
                      Icons.warning,
                      Colors.orange)),
            ],
          ),
          const SizedBox(height: 24),

          // Current Stock
          const Text('Current Stock Levels',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...(_report!.currentStock.isEmpty
              ? [
                  const Center(
                      child: Text('No items in inventory',
                          style: TextStyle(color: Colors.grey)))
                ]
              : _report!.currentStock
                  .take(10)
                  .map((item) => _buildStockItem(item))),
          if (_report!.currentStock.length > 10)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('+ ${_report!.currentStock.length - 10} more items',
                  style: TextStyle(
                      color: Colors.grey[500], fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 24),

          // Sales by Category
          if (_report!.salesByCategory.isNotEmpty) ...[
            const Text('Sales by Category',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._report!.salesByCategory.entries
                .map((entry) => _buildCategoryRow(entry.key, entry.value)),
          ],
          const SizedBox(height: 24),

          // Recent Transactions
          const Text('Recent Transactions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...(_report!.transactions.isEmpty
              ? [
                  const Center(
                      child: Text('No transactions in this period',
                          style: TextStyle(color: Colors.grey)))
                ]
              : _report!.transactions
                  .take(10)
                  .map((txn) => _buildTransactionItem(txn))),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ==================== PROFIT TAB ====================

  Widget _buildProfitTab(ThemeData theme) {
    final totalRevenue = _getTotalRevenue();
    final totalCost = _getTotalCost();
    final totalProfit = totalRevenue - totalCost;
    final profitMargin = _getProfitMargin();
    final profitByCategory = _getProfitByCategory();
    final topDrinks = _getTopProfitableDrinks();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date Range Selector
          _buildDateRangeCard(theme),
          const SizedBox(height: 16),

          // Profit Summary Cards
          Row(
            children: [
              Expanded(
                  child: _buildProfitCard(
                      'Revenue',
                      CurrencyHelper.format(totalRevenue),
                      Icons.trending_up,
                      Colors.blue)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildProfitCard(
                      'Cost',
                      CurrencyHelper.format(totalCost),
                      Icons.trending_down,
                      Colors.red)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _buildProfitCard(
                      'Profit',
                      CurrencyHelper.format(totalProfit),
                      Icons.savings,
                      Colors.green)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildProfitCard(
                      'Margin',
                      '${profitMargin.toStringAsFixed(1)}%',
                      Icons.pie_chart,
                      Colors.purple)),
            ],
          ),
          const SizedBox(height: 24),

          // Profit by Category
          if (profitByCategory.isNotEmpty) ...[
            const Text('Profit by Category',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              color: theme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: profitByCategory.entries.map((entry) {
                    final maxProfit =
                        profitByCategory.values.reduce((a, b) => a > b ? a : b);
                    final ratio = maxProfit > 0 ? entry.value / maxProfit : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(entry.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500)),
                              Text(CurrencyHelper.format(entry.value),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: theme.primaryColor)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: ratio,
                              backgroundColor: Colors.grey[200],
                              color: theme.primaryColor,
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Top 5 Profitable Drinks
          if (topDrinks.isNotEmpty) ...[
            const Text('Top 5 Most Profitable Drinks',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...topDrinks.asMap().entries.map((entry) {
              final index = entry.key;
              final drink = entry.value;
              final medals = ['🥇', '🥈', '🥉', '4️⃣', '5️⃣'];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                color: theme.cardColor,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                    child: Text(medals[index],
                        style: const TextStyle(fontSize: 20)),
                  ),
                  title: Text(drink.key,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: Text(
                    CurrencyHelper.format(drink.value),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green),
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ==================== SHARED WIDGETS ====================

  Widget _buildDateRangeCard(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: theme.cardColor,
      elevation: 2,
      child: InkWell(
        onTap: _selectDateRange,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.date_range, color: Colors.blue),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Report Period',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: theme.textTheme.bodyLarge?.color)),
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormat('MMM dd, yyyy').format(_startDate)} - ${DateFormat('MMM dd, yyyy').format(_endDate)}',
                    style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color, fontSize: 13),
                  ),
                ],
              ),
              const Spacer(),
              Icon(Icons.edit, color: theme.hintColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).cardColor,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title,
                style:
                    TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildProfitCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).cardColor,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title,
                style:
                    TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildStockItem(InventoryItem item) {
    final isLowStock = item.isLowStock;
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isLowStock
              ? Colors.orange.withValues(alpha: 0.2)
              : Colors.green.withValues(alpha: 0.2),
          child: Icon(Icons.local_drink,
              color: isLowStock ? Colors.orange : Colors.green, size: 20),
        ),
        title: Text(item.drinkName,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${item.quantity}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isLowStock ? Colors.orange : Colors.green)),
            if (isLowStock) ...[
              const SizedBox(width: 8),
              const Icon(Icons.warning, color: Colors.orange, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow(String category, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(category, style: const TextStyle(fontSize: 14))),
          Text('$count sold',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor)),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(InventoryTransaction txn) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: txn.isIncoming
            ? Colors.green.withValues(alpha: 0.2)
            : Colors.red.withValues(alpha: 0.2),
        child: Icon(txn.isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
            color: txn.isIncoming ? Colors.green : Colors.red, size: 18),
      ),
      title: Text(txn.drinkName,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
      subtitle: Text('${txn.reason} • ${DateFormat('MMM dd').format(txn.date)}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      trailing: Text(
        '${txn.isIncoming ? '+' : '-'}${txn.quantity}',
        style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: txn.isIncoming ? Colors.green : Colors.red),
      ),
    );
  }
}
