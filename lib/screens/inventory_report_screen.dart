// screens/inventory_report_screen.dart
import 'package:flutter/material.dart';
import 'package:drinks_calculator_fixed/providers/plan_provider.dart';
import '../widgets/upgrade_required.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:drinks_calculator_fixed/providers/inventory_provider.dart';
import 'package:drinks_calculator_fixed/models/inventory_model.dart';
import 'package:drinks_calculator_fixed/utils/export_helper.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';
import '../utils/i18n.dart';
import '../utils/report_profit_helper.dart';

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
  //
  // Priced by utils/report_profit_helper.dart: it reads the ledger's at-sale prices
  // rather than today's catalogue prices, so editing a price no longer rewrites an
  // older report, and a missing price is reported instead of counted as 0.

  ProfitSummary _profitSummary() {
    if (_report == null) return ProfitSummary.empty;

    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final Map<String, Drink> drinks = {
      for (final Drink d in drinkProvider.customDrinks) d.id: d,
    };
    final Map<String, InventoryItem> stock = {
      for (final InventoryItem i in _report!.currentStock) i.drinkId: i,
    };

    return summariseProfit(
      _report!.transactions
          .where((t) => t.isOutgoing && t.reason == 'sale')
          .map((t) {
        final drink = drinks[t.drinkId];
        final item = stock[t.drinkId];
        return ProfitLine(
          drinkId: t.drinkId,
          drinkName: t.drinkName,
          quantity: t.quantity,
          category: item?.category,
          // What the ledger recorded when the unit was sold — the one basis that
          // cannot move under the report's feet.
          sellingPriceAtSale: t.sellingPriceAtSale,
          purchasePriceAtSale: t.purchasePriceAtSale,
          // Legacy movements predate those columns, so the catalogue is all that is
          // left for them; the helper reads a cost of 0 as "not on record".
          catalogueSellingPrice: drink?.price,
          cataloguePurchasePrice: item?.purchasePrice,
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!context.read<PlanProvider>().canAccess('reports')) {
      return const UpgradeRequiredView();
    }
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => LockService().resetTimer(),
      onPanDown: (_) => LockService().resetTimer(),
      onScaleStart: (_) => LockService().resetTimer(),
      onLongPress: () => LockService().resetTimer(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('rpt_title')),
          backgroundColor: theme.primaryColor,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.inventory), text: t('rpt_tabInventory')),
              Tab(icon: Icon(Icons.analytics), text: t('rpt_tabProfit')),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () {
                if (_report != null) {
                  // The batch dates live on the drinks, so pass them along for
                  // the expiry section of the export.
                  final drinks =
                      Provider.of<DrinkProvider>(context, listen: false)
                          .customDrinks;
                  ExportHelper.exportInventoryReport(
                    _report!,
                    context,
                    drinks: drinks,
                    // The very same summary the cards above show — one calculation, so
                    // the file and the screen can never disagree.
                    profit: _profitSummary(),
                    currencySymbol: CurrencyHelper.getSymbol(),
                  );
                }
              },
              tooltip: t('rpt_export'),
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
                      t('rpt_totalStock'),
                      '${_report!.currentStock.fold(0, (s, i) => s + i.quantity)}',
                      Icons.inventory,
                      Colors.blue)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildSummaryCard(
                      t('rpt_itemsIn'),
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
                      t('rpt_itemsOut'),
                      '${_report!.totalItemsOut}',
                      Icons.remove_shopping_cart,
                      Colors.red)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildSummaryCard(
                      t('rpt_lowStock'),
                      '${_report!.lowStockCount}',
                      Icons.warning,
                      Colors.orange)),
            ],
          ),
          const SizedBox(height: 24),

          // Current Stock
          Text(t('rpt_currentStockLevels'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...(_report!.currentStock.isEmpty
              ? [
                  Center(
                      child: Text(t('rpt_noItems'),
                          style: TextStyle(color: Colors.grey)))
                ]
              : _report!.currentStock
                  .take(10)
                  .map((item) => _buildStockItem(item))),
          if (_report!.currentStock.length > 10)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('+ ${_report!.currentStock.length - 10} ${t('rpt_moreItems')}',
                  style: TextStyle(
                      color: Colors.grey[500], fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 24),

          // Sales by Category
          if (_report!.salesByCategory.isNotEmpty) ...[
            Text(t('rpt_salesByCategory'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._report!.salesByCategory.entries
                .map((entry) => _buildCategoryRow(entry.key, entry.value)),
          ],
          const SizedBox(height: 24),

          // Recent Transactions
          Text(t('rpt_recentTransactions'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...(_report!.transactions.isEmpty
              ? [
                  Center(
                      child: Text(t('rpt_noTransactions'),
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

  /// The caveat shown under the figures whenever some units had no cost on record or
  /// could not be valued at all. A margin computed on incomplete data has to say so —
  /// silently showing 100 % is what the old calculation did.
  Widget _buildCaveatNote(ThemeData theme, ProfitSummary summary) {
    final lines = <String>[
      if (summary.unitsWithoutCost > 0) t('rpt_caveatNoCost'),
      if (summary.unitsUnvalued > 0) t('rpt_caveatUnvalued'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Text(
                    line,
                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitTab(ThemeData theme) {
    final summary = _profitSummary();
    final totalRevenue = summary.revenue;
    final totalCost = summary.cost;
    final totalProfit = summary.profit;
    final profitMargin = summary.marginPercent;
    final profitByCategory = summary.profitByCategory;
    final topDrinks = summary.topProfitableDrinks;

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
                      t('rpt_revenue'),
                      CurrencyHelper.format(totalRevenue),
                      Icons.trending_up,
                      Colors.blue)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildProfitCard(
                      t('rpt_cost'),
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
                      t('rpt_profit'),
                      CurrencyHelper.format(totalProfit),
                      Icons.savings,
                      Colors.green)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildProfitCard(
                      t('rpt_margin'),
                      '${profitMargin.toStringAsFixed(1)}%',
                      Icons.pie_chart,
                      Colors.purple)),
            ],
          ),
          const SizedBox(height: 8),
          // 🏷️ The two "general" prices: what the shop actually charged and paid per
          // unit sold in this period (utils/report_profit_helper.dart).
          Row(
            children: [
              Expanded(
                  child: _buildProfitCard(
                      t('rpt_avgSellingPrice'),
                      CurrencyHelper.format(summary.averageSellingPrice),
                      Icons.sell_outlined,
                      Colors.teal)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildProfitCard(
                      t('rpt_avgPurchasePrice'),
                      CurrencyHelper.format(summary.averagePurchasePrice),
                      Icons.shopping_bag_outlined,
                      Colors.orange)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              '${t('rpt_perUnitSold')} · ${summary.unitsSold}',
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
          ),
          if (summary.hasCaveat) ...[
            const SizedBox(height: 12),
            _buildCaveatNote(theme, summary),
          ],
          const SizedBox(height: 24),

          // Profit by Category
          if (profitByCategory.isNotEmpty) ...[
            Text(t('rpt_profitByCategory'),
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
            Text(t('rpt_top5'),
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
              // Expanded, not a bare Column + Spacer: the label and the two formatted
              // dates are unbounded text, and a longer translation (or a locale that
              // spells its months out) used to push this Row past the card edge.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('rpt_reportPeriod'),
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
              ),
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
          Text('$count ${t('rpt_sold')}',
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
