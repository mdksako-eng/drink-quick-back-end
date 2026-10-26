// screens/purchasing_screen.dart
// 🛒 Buying stock: suppliers and purchase orders.
//
// The forecast recommends what to reorder; this is where that becomes an order
// (draft → sent → received) and where a delivery puts the stock back on the
// shelf at the price actually paid.
//
// A MANAGER creates, sends and cancels — that commits the shop's money. ANY
// staff member may receive, because that is a physical fact at the door like a
// restock; the backend re-checks both (utils/purchasing.js).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/purchasing_model.dart';
import '../providers/auth_provider.dart';
import '../providers/drink_provider.dart';
import '../providers/purchasing_provider.dart';
import '../utils/helpers.dart';
import '../utils/i18n.dart';
import '../widgets/offline_indicator.dart';

class PurchasingScreen extends StatefulWidget {
  const PurchasingScreen({super.key});

  @override
  State<PurchasingScreen> createState() => _PurchasingScreenState();
}

class _PurchasingScreenState extends State<PurchasingScreen> {
  String? get _role => context.read<AuthProvider>().user?.role;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PurchasingProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PurchasingProvider>(context);
    final manager = provider.canWrite(_role);
    final receiver = provider.canReceive(_role);
    final closed = provider.orders.where((order) => !order.isOpen).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(t('purMenu')),
        actions: [
          if (manager)
            IconButton(
              icon: const Icon(Icons.local_shipping_outlined),
              tooltip: t('purAddSupplier'),
              onPressed: () => _addSupplier(provider),
            ),
        ],
      ),
      floatingActionButton: manager
          ? FloatingActionButton.extended(
              onPressed: () => _newOrder(provider),
              icon: const Icon(Icons.add),
              label: Text(t('purNewOrder')),
            )
          : null,
      body: OfflineIndicator(
        child: RefreshIndicator(
          onRefresh: provider.load,
          child: provider.loading && !provider.hasLoaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    if (provider.open.isNotEmpty) ...[
                      Text(t('purOpen'),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ...provider.open.map((order) =>
                          _orderCard(provider, order, manager, receiver)),
                      const SizedBox(height: 20),
                    ],
                    Text(t('purHistory'),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (provider.orders.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(t('purNone')),
                        ),
                      )
                    else
                      ...closed.map((order) =>
                          _orderCard(provider, order, manager, receiver)),
                  ],
                ),
        ),
      ),
    );
  }

  /// One order: what it is, where it stands, and the one or two actions that are
  /// actually possible from here.
  Widget _orderCard(
    PurchasingProvider provider,
    PurchaseOrder order,
    bool manager,
    bool receiver,
  ) {
    final supplier = provider.supplierOf(order);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.reference.isEmpty ? '#${order.id}' : order.reference,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _statusChip(order.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${t('purSupplier')}: ${supplier?.name ?? t('purNoSupplier')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${order.totalUnits} ${t('purUnits')} · '
              '${order.totalAmount.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (order.lines.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  order.lines
                      .map((line) => '${line.quantity}× ${line.drinkName}')
                      .join(', '),
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (order.isOpen)
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  if (manager && order.isDraft)
                    TextButton(
                      onPressed: () => _run(
                        provider,
                        () => provider.setStatus(order.id, 'sent'),
                        onSuccess: 'purSentOk',
                      ),
                      child: Text(t('purSend')),
                    ),
                  if (receiver && order.isSent)
                    TextButton(
                      onPressed: () => _receive(provider, order),
                      child: Text(t('purReceive')),
                    ),
                  if (manager)
                    TextButton(
                      onPressed: () => _run(
                        provider,
                        () => provider.setStatus(order.id, 'cancelled'),
                        onSuccess: 'purCancelledOk',
                      ),
                      child: Text(t('purCancel')),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final key = switch (status) {
      'sent' => 'purSent',
      'received' => 'purReceived',
      'cancelled' => 'purCancelled',
      _ => 'purDraft',
    };
    return Chip(
      label: Text(t(key), style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
    );
  }

  /// Runs an action and reports the outcome — including a server refusal, which
  /// is a real answer and must never look like success.
  Future<void> _run(
    PurchasingProvider provider,
    Future<String?> Function() action, {
    String? onSuccess,
  }) async {
    final failure = await action();
    if (!mounted) return;
    if (failure == null) {
      Helpers.showToast(t(onSuccess ?? 'purCreated'));
    } else if (failure == 'offline') {
      Helpers.showToast(t('purOffline'), isError: true);
    } else {
      Helpers.showToast(t('purRefused'), isError: true);
    }
  }

  /// Managers add a supplier: a name, and a phone to send the order to.
  Future<void> _addSupplier(PurchasingProvider provider) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('purAddSupplier')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: t('purSupplierName')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: t('purSupplierPhone')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('save')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final name = nameController.text.trim();
    if (name.isEmpty) {
      Helpers.showToast(t('purSupplierName'), isError: true);
      return;
    }
    await _run(
      provider,
      () => provider.saveSupplier(
        name: name,
        phone: phoneController.text.trim(),
      ),
      onSuccess: 'purSupplierSaved',
    );
  }

  /// Managers build a draft order: pick the supplier, add the lines, create it.
  Future<void> _newOrder(PurchasingProvider provider) async {
    final lines = <Map<String, dynamic>>[];
    int? supplierId =
        provider.suppliers.isNotEmpty ? provider.suppliers.first.id : null;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(t('purNewOrder')),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('purSupplier'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (provider.suppliers.isEmpty)
                  Text(t('purAddSupplierFirst'),
                      style: Theme.of(context).textTheme.bodySmall)
                else
                  Wrap(
                    spacing: 6,
                    children: provider.suppliers
                        .map((supplier) => ChoiceChip(
                              label: Text(supplier.name),
                              selected: supplierId == supplier.id,
                              onSelected: (_) => setDialogState(
                                  () => supplierId = supplier.id),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 12),
                Text(t('purLines'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (lines.isEmpty)
                  Text(t('purNoLines'),
                      style: Theme.of(context).textTheme.bodySmall)
                else
                  ...lines.map((line) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${line['quantity']}× ${line['drink_name']}'),
                        subtitle: Text('${line['unit_cost']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setDialogState(() => lines.remove(line)),
                        ),
                      )),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final line = await _lineDialog();
                      if (line != null) setDialogState(() => lines.add(line));
                    },
                    icon: const Icon(Icons.add),
                    label: Text(t('purAddLine')),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: lines.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(t('purCreate')),
            ),
          ],
        ),
      ),
    );
    if (created != true) return;

    await _run(
      provider,
      () => provider.createOrder(supplierId: supplierId, lines: lines),
      onSuccess: 'purCreated',
    );
  }

  /// One line: which drink, how many, at what cost — the cost is prefilled with
  /// what the shop last paid for it, which is the honest starting point.
  Future<Map<String, dynamic>?> _lineDialog() async {
    final drinks = Provider.of<DrinkProvider>(context, listen: false).allDrinks;
    if (drinks.isEmpty) {
      Helpers.showToast(t('purNoDrinks'), isError: true);
      return null;
    }

    final picked = await showDialog<dynamic>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(t('purPickDrink')),
        children: drinks
            .map((drink) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, drink),
                  child: Text(drink.name),
                ))
            .toList(),
      ),
    );
    if (picked == null) return null;

    final qtyController = TextEditingController(text: '1');
    final costController = TextEditingController(
      text: picked.purchasePrice > 0
          ? picked.purchasePrice.toStringAsFixed(0)
          : '0',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(picked.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(labelText: t('purQuantity')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: costController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t('purUnitCost')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('save')),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;

    final quantity = int.tryParse(qtyController.text.trim()) ?? 0;
    if (quantity <= 0) {
      Helpers.showToast(t('purQuantity'), isError: true);
      return null;
    }
    return {
      'drink_id': picked.id,
      'drink_name': picked.name,
      'quantity': quantity,
      'unit_cost': double.tryParse(costController.text.trim()) ?? 0,
    };
  }

  /// Receiving is confirmed first: it puts stock on the shelf, and the order
  /// becomes terminal once it lands.
  Future<void> _receive(
    PurchasingProvider provider,
    PurchaseOrder order,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('purReceive')),
        content: Text(t('purReceiveConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('purReceive')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      provider,
      () => provider.receive(order.id),
      onSuccess: 'purReceivedOk',
    );
  }
}
