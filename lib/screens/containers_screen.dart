// screens/containers_screen.dart
// 🧺 Returnable containers (crates and bottles) — who is holding the shop's
// empties. The credit ledger answers "who owes me money"; this answers "who owes
// me containers". A crate in a customer's yard is money standing still.
//
// STAFF hand a container out and take one back at the counter; only a MANAGER
// writes one off (lost or broken) or changes the container list. The backend
// enforces both (utils/containerLedger.js) and owns the ceiling, so nobody can
// give back more than went out — this screen only hides what it would refuse.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/container_model.dart';
import '../providers/auth_provider.dart';
import '../providers/container_provider.dart';
import '../utils/container_ledger_helper.dart';
import '../utils/helpers.dart';
import '../utils/i18n.dart';
import '../widgets/offline_indicator.dart';

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key});

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends State<ContainersScreen> {
  String? get _role => context.read<AuthProvider>().user?.role;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ContainerProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ContainerProvider>(context);
    final manager = provider.canManageTypes(_role);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('contMenu')),
        actions: [
          if (manager)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: t('contAddType'),
              onPressed: () => _addTypeDialog(provider),
            ),
        ],
      ),
      body: OfflineIndicator(
        child: RefreshIndicator(
          onRefresh: provider.load,
          child: provider.loading && !provider.hasTypes
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _totalCard(provider),
                    if (provider.byType.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(t('contByType'),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ...provider.byType.map((row) => _typeRow(row)),
                    ],
                    const SizedBox(height: 20),
                    Text(t('contWhoHolds'),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (provider.holders.isEmpty)
                      _emptyState(provider, manager)
                    else
                      ...provider.holders.map(
                        (holder) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(child: Text('${holder.outstanding}')),
                            title: Text(holder.name),
                            subtitle: Text(holder.customerNumber),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _holderSheet(provider, holder),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Every container out of the shop, and what it is worth as a deposit
  /// (informational only — containers are goods, not cash).
  Widget _totalCard(ContainerProvider provider) {
    final deposit = provider.byType.fold<double>(0, (sum, row) => sum + row.value);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('contOutstanding'),
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              '${provider.totalOutstanding}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (deposit > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${t('contDepositValue')}: ${deposit.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _typeRow(ContainerOutstanding row) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(row.name),
      trailing: Text(
        '${row.outstanding}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _emptyState(ContainerProvider provider, bool manager) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('contNoneOut')),
            const SizedBox(height: 6),
            Text(
              provider.hasTypes ? t('contNoneOutHint') : t('contNoTypesHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (manager && !provider.hasTypes) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _addTypeDialog(provider),
                icon: const Icon(Icons.add),
                label: Text(t('contAddType')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One customer: what they hold per container type, with the three actions.
  /// "Back" and "Write off" are disabled when the pile is empty — the server
  /// would refuse them anyway.
  void _holderSheet(ContainerProvider provider, ContainerHolder holder) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final manager = provider.canManageTypes(_role);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(holder.name,
                    style: Theme.of(context).textTheme.titleLarge),
                Text(holder.customerNumber,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                if (provider.types.isEmpty)
                  Text(t('contNoTypesHint'))
                else
                  ...provider.types.map((type) {
                    final held = provider.heldBy(holder.customerId, type.id);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(type.name),
                      subtitle: Text('${t('contHeld')}: $held'),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _recordDialog(provider, holder, type,
                                  ContainerLedgerHelper.kindOut);
                            },
                            child: Text(t('contGive')),
                          ),
                          TextButton(
                            onPressed: held > 0
                                ? () {
                                    Navigator.pop(sheetContext);
                                    _recordDialog(provider, holder, type,
                                        ContainerLedgerHelper.kindBack);
                                  }
                                : null,
                            child: Text(t('contBack')),
                          ),
                          if (manager)
                            TextButton(
                              onPressed: held > 0
                                  ? () {
                                      Navigator.pop(sheetContext);
                                      _recordDialog(provider, holder, type,
                                          ContainerLedgerHelper.kindWriteOff);
                                    }
                                  : null,
                              child: Text(t('contWriteOff')),
                            ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Ask for the quantity (and an optional reason), check it against what the
  /// customer actually holds, then let the backend decide.
  Future<void> _recordDialog(
    ContainerProvider provider,
    ContainerHolder holder,
    ContainerType type,
    String kind,
  ) async {
    final quantityController = TextEditingController(text: '1');
    final reasonController = TextEditingController();
    final held = provider.heldBy(holder.customerId, type.id);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${t(ContainerLedgerHelper.kindKey(kind))} — ${type.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${holder.name} · ${t('contHeld')}: $held'),
            const SizedBox(height: 12),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(labelText: t('contQuantity')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(labelText: t('contReason')),
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

    final quantity = int.tryParse(quantityController.text.trim()) ?? 0;
    final problem = ContainerLedgerHelper.movementProblem(
      role: _role,
      kind: kind,
      quantity: quantity,
      outstanding: held,
    );
    if (problem != null) {
      Helpers.showToast(t(ContainerLedgerHelper.problemKey(problem)),
          isError: true);
      return;
    }

    final failure = await provider.record(
      customerId: holder.customerId,
      containerTypeId: type.id,
      kind: kind,
      quantity: quantity,
      reason: reasonController.text.trim(),
    );
    if (!mounted) return;
    if (failure == null) {
      Helpers.showToast(t('contRecorded'));
    } else if (failure == 'offline') {
      Helpers.showToast(t('contErrOffline'), isError: true);
    } else {
      Helpers.showToast(t('contErrRefused'), isError: true);
    }
  }

  /// Managers add (or re-price) a container. The deposit is optional: it is only
  /// ever used to show what the outstanding pile is worth.
  Future<void> _addTypeDialog(ContainerProvider provider) async {
    final nameController = TextEditingController();
    final depositController = TextEditingController(text: '0');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('contAddType')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: t('contTypeName')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: depositController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t('contDeposit')),
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
      Helpers.showToast(t('contErrName'), isError: true);
      return;
    }
    final saved = await provider.saveType(
      name: name,
      depositValue: double.tryParse(depositController.text.trim()) ?? 0,
    );
    if (!mounted) return;
    Helpers.showToast(saved ? t('contTypeSaved') : t('contErrOffline'),
        isError: !saved);
  }
}
