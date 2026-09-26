// screens/customer_ledger_screen.dart
// Customer accounts ("customer numbers") and their credit ledger (tabs).
//
// WHO DECIDES WHAT: any staff member may ENROL a customer; only a manager may
// approve, reject, block or re-limit an account. The Approvals tab is the
// manager's queue and the decision buttons only appear for them — the backend
// enforces the same rule (utils/customerApproval.js), so this is only what the
// UI hides.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/customer_model.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_provider.dart';
import '../services/whatsapp_service.dart';
import '../utils/company_name_helper.dart';
import '../utils/customer_ledger_helper.dart';
import '../utils/helpers.dart';
import '../utils/i18n.dart';
import '../utils/price_extension.dart';
import '../utils/whatsapp_helper.dart';

class CustomerLedgerScreen extends StatefulWidget {
  const CustomerLedgerScreen({super.key});

  @override
  State<CustomerLedgerScreen> createState() => _CustomerLedgerScreenState();
}

class _CustomerLedgerScreenState extends State<CustomerLedgerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    // Defer the load until after the first frame: the provider notifies its
    // listeners synchronously, which must not happen during build().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CustomerProvider>().load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String? get _role => context.read<AuthProvider>().user?.role;

  /// Staff may enrol; only a manager decides.
  bool get _canEnroll => CustomerLedgerHelper.canEnroll(_role);
  bool get _canDecide => CustomerLedgerHelper.canDecide(_role);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;
    final provider = context.watch<CustomerProvider>();
    final pending = provider.pendingCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('custTitle')),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: t('custTabCustomers')),
            Tab(
              text: pending > 0
                  ? '${t('custTabApprovals')} ($pending)'
                  : t('custTabApprovals'),
            ),
          ],
        ),
      ),
      floatingActionButton: _canEnroll
          ? FloatingActionButton.extended(
              onPressed: _enrollDialog,
              backgroundColor: primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt),
              label: Text(t('custEnroll')),
            )
          : null,
      body: Column(
        children: [
          if (provider.offline) _offlineBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                RefreshIndicator(
                  onRefresh: () => context.read<CustomerProvider>().load(),
                  child: _customersTab(provider, primary),
                ),
                RefreshIndicator(
                  onRefresh: () => context.read<CustomerProvider>().load(),
                  child: _approvalsTab(provider, primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offlineBanner() => Container(
        width: double.infinity,
        color: Colors.orange.withValues(alpha: 0.15),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          const Icon(Icons.cloud_off, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t('custOffline'),
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
        ]),
      );

  Widget _emptyState(IconData icon, String message) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Icon(icon, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
      );

  /// Everyone with an approved account, biggest debt first.
  Widget _customersTab(CustomerProvider provider, Color primary) {
    final customers = provider.byDebt;
    if (customers.isEmpty) {
      return _emptyState(Icons.people_outline, t('custNoCustomers'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: customers.length,
      itemBuilder: (context, index) =>
          _customerTile(provider, customers[index], primary),
    );
  }

  /// The manager's queue: staff enrolments waiting for a decision.
  Widget _approvalsTab(CustomerProvider provider, Color primary) {
    final waiting = provider.pending;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (!_canDecide)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.lock_outline, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(t('custPendingNote'),
                      style: const TextStyle(fontSize: 12)),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        if (waiting.isEmpty)
          _emptyState(Icons.verified_user_outlined, t('custNoPending'))
        else
          ...waiting.map((c) => _customerTile(provider, c, primary)),
      ],
    );
  }

  Widget _customerTile(CustomerProvider provider, Customer customer, Color primary) {
    final totals = provider.totalsFor(customer.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: primary.withValues(alpha: 0.12),
          child: Icon(Icons.person_outline, color: primary),
        ),
        title: Row(children: [
          Expanded(
            child: Text(
              customer.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 6),
          _statusChip(customer.status),
        ]),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${t('custNumber')} ${customer.customerNumber}'
              '${customer.phone.isEmpty ? '' : ' · ${customer.phone}'}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              _balanceLabel(totals),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: totals.owes ? Colors.red : Colors.green,
              ),
            ),
            if (customer.creditLimit > 0)
              Text(
                '${t('custSetLimit')}: ${customer.creditLimit.formatted}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
          ],
        ),
        isThreeLine: true,
        onTap: () => _openCustomer(provider, customer),
        trailing: _canDecide ? _decisionButton(provider, customer) : null,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case CustomerLedgerHelper.statusApproved:
        return Colors.green;
      case CustomerLedgerHelper.statusRejected:
        return Colors.red;
      case CustomerLedgerHelper.statusBlocked:
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        t(CustomerLedgerHelper.statusKey(status)),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  String _balanceLabel(LedgerTotals totals) {
    if (totals.inCredit) {
      return '${t('custInCredit')} ${(-totals.balance).formatted}';
    }
    return '${t('custOwes')} ${totals.balance.formatted}';
  }

  /// The manager's decision menu — the only place an account status changes.
  Widget _decisionButton(CustomerProvider provider, Customer customer) {
    final canApprove = customer.status == CustomerLedgerHelper.statusPending ||
        customer.status == CustomerLedgerHelper.statusBlocked ||
        customer.status == CustomerLedgerHelper.statusRejected;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case 'approve':
            _decide(provider, customer,
                status: CustomerLedgerHelper.statusApproved);
            break;
          case 'reject':
            _decide(provider, customer,
                status: CustomerLedgerHelper.statusRejected);
            break;
          case 'block':
            _decide(provider, customer,
                status: CustomerLedgerHelper.statusBlocked);
            break;
          case 'limit':
            _setLimitDialog(provider, customer);
            break;
        }
      },
      itemBuilder: (context) => [
        if (canApprove) PopupMenuItem(value: 'approve', child: Text(t('approve'))),
        if (customer.status == CustomerLedgerHelper.statusPending)
          PopupMenuItem(value: 'reject', child: Text(t('reject'))),
        if (customer.status == CustomerLedgerHelper.statusApproved)
          PopupMenuItem(value: 'block', child: Text(t('custBlock'))),
        PopupMenuItem(value: 'limit', child: Text(t('custSetLimit'))),
      ],
    );
  }

  Future<void> _decide(
    CustomerProvider provider,
    Customer customer, {
    required String status,
  }) async {
    final ok = await provider.decide(customer.id, status: status);
    if (!mounted) return;
    if (!ok) {
      Helpers.showToast(t('custDecisionFailed'), isError: true);
      return;
    }
    Helpers.showToast(t(CustomerLedgerHelper.statusKey(status)));
  }

  /// Enrol a customer. Staff enrolments wait for the manager; the manager's own
  /// enrolment is approved immediately (the backend decides which).
  Future<void> _enrollDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('custEnroll')),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t('customerName')),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? t('pleaseEnterCustomerName') : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: t('phone')),
            ),
            const SizedBox(height: 8),
            if (!_canDecide)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  t('custPendingNote'),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(t('save')),
          ),
        ],
      ),
    );

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    nameController.dispose();
    phoneController.dispose();
    if (accepted != true || !mounted) return;

    final created = await context.read<CustomerProvider>().enroll(
          name: name,
          phone: phone,
        );
    if (!mounted) return;
    if (created == null) {
      Helpers.showToast(t('custEnrollFailed'), isError: true);
      return;
    }

    final approved = CustomerLedgerHelper.canHoldCredit(created);
    Helpers.showToast(approved ? t('custEnrolled') : t('custEnrolledPending'));
    // A staff enrolment lands in the approvals queue, so show that tab.
    _tabs.animateTo(approved ? 0 : 1);
  }

  /// The manager sets (or changes) how much credit an account may run up.
  Future<void> _setLimitDialog(
    CustomerProvider provider,
    Customer customer,
  ) async {
    final controller = TextEditingController(
      text: customer.creditLimit > 0
          ? customer.creditLimit.toStringAsFixed(0)
          : '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('custSetLimit')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: t('amount')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('save')),
          ),
        ],
      ),
    );

    final limit =
        double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;
    controller.dispose();
    if (saved != true || !mounted) return;

    final ok = await provider.decide(customer.id, creditLimit: limit);
    if (!mounted) return;
    Helpers.showToast(ok ? t('custSaved') : t('custDecisionFailed'),
        isError: !ok);
  }

  /// The account sheet: totals, the ledger, and the charge / payment actions.
  Future<void> _openCustomer(
    CustomerProvider provider,
    Customer customer,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.94,
        builder: (sheetContext, scrollController) {
          // Watch inside the sheet: a new entry refreshes the balances here as
          // soon as the provider reloads from the server.
          final live = Provider.of<CustomerProvider>(sheetContext);
          final current = live.customers.firstWhere(
            (c) => c.id == customer.id,
            orElse: () => customer,
          );
          return _sheetContent(scrollController, live, current);
        },
      ),
    );
  }

  Widget _sheetContent(
    ScrollController controller,
    CustomerProvider provider,
    Customer customer,
  ) {
    final totals = provider.totalsFor(customer.id);
    final entries = provider.entriesFor(customer.id);

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Row(children: [
          Expanded(
            child: Text(
              customer.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          _statusChip(customer.status),
        ]),
        const SizedBox(height: 4),
        Text(
          '${t('custNumber')} ${customer.customerNumber}'
          '${customer.phone.isEmpty ? '' : ' · ${customer.phone}'}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(child: _metric(t('custCharged'), totals.charged)),
              Expanded(child: _metric(t('custPaid'), totals.paid)),
              Expanded(
                child: _metric(
                  t('custBalance'),
                  totals.balance,
                  highlight: totals.owes,
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (CustomerLedgerHelper.canHoldCredit(customer))
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _entryDialog(customer, 'charge'),
                icon: const Icon(Icons.add_card, size: 18),
                label: Text(t('custAddCharge')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _entryDialog(customer, 'payment'),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text(t('custAddPayment')),
              ),
            ),
          ])
        else
          Text(
            t('custNoCredit'),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: WhatsAppService.hasNumber(customer.phone)
                ? () => _sendStatement(provider, customer)
                : null,
            icon: const Icon(Icons.chat_outlined, size: 18),
            label: Text(t('waSendStatement')),
          ),
        ),
        const SizedBox(height: 16),
        Text(t('custLedgerTitle'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (entries.isEmpty)
          Text(
            t('custLedgerEmpty'),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          )
        else
          ...entries.map((e) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  e.isPayment ? Icons.south_west : Icons.north_east,
                  size: 18,
                  color: e.isPayment ? Colors.green : Colors.red,
                ),
                title: Text(
                  e.reason.isEmpty
                      ? (e.isPayment ? t('custAddPayment') : t('custAddCharge'))
                      : e.reason,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  <String>[
                    if (e.createdAt != null)
                      DateFormat('MMM d, HH:mm').format(e.createdAt!),
                    if (e.performedByName.isNotEmpty) e.performedByName,
                  ].join(' · '),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                trailing: Text(
                  '${e.isPayment ? '-' : '+'}${e.amount.formatted}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: e.isPayment ? Colors.green : Colors.red,
                  ),
                ),
              )),
      ],
    );
  }

  Widget _metric(String label, double value, {bool highlight = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text(
            value.formatted,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: highlight ? Colors.red : null,
            ),
          ),
        ],
      );

  /// Charge the tab, or record a payment against it.
  Future<void> _entryDialog(
    Customer customer,
    String kind, {
    bool overrideLimit = false,
  }) async {
    final isCharge = kind == 'charge';
    final amountController = TextEditingController();
    final reasonController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCharge ? t('custAddCharge') : t('custAddPayment')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t('amount')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: reasonController,
            decoration: InputDecoration(labelText: t('custReasonOptional')),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('save')),
          ),
        ],
      ),
    );

    final amount =
        double.tryParse(amountController.text.trim().replaceAll(',', '')) ?? 0;
    final reason = reasonController.text.trim();
    amountController.dispose();
    reasonController.dispose();
    if (saved != true || !mounted) return;
    if (amount <= 0) {
      Helpers.showToast(t('custSaveFailed'), isError: true);
      return;
    }

    final provider = context.read<CustomerProvider>();
    final result = await provider.addEntry(
      customerId: customer.id,
      kind: kind,
      amount: amount,
      reason: reason.isEmpty ? null : reason,
      method: isCharge ? null : 'cash',
      overrideLimit: overrideLimit,
    );
    if (!mounted) return;

    if (result.ok) {
      Helpers.showToast(t('custSaved'));
      return;
    }

    // Past the manager's limit: a manager may still confirm the charge.
    if (result.limitExceeded) {
      if (CustomerLedgerHelper.canDecide(_role)) {
        final allow = await _askOverride();
        if (!mounted) return;
        if (allow == true) {
          final retry = await provider.addEntry(
            customerId: customer.id,
            kind: kind,
            amount: amount,
            reason: reason.isEmpty ? null : reason,
            method: isCharge ? null : 'cash',
            overrideLimit: true,
          );
          if (!mounted) return;
          Helpers.showToast(
            retry.ok ? t('custSaved') : t('custSaveFailed'),
            isError: !retry.ok,
          );
          return;
        }
      }
      if (mounted) Helpers.showToast(t('custLimitExceeded'), isError: true);
      return;
    }

    Helpers.showToast(result.message ?? t('custSaveFailed'), isError: true);
  }

  /// Sends the customer's statement on WhatsApp (disabled without a number).
  Future<void> _sendStatement(
    CustomerProvider provider,
    Customer customer,
  ) async {
    final totals = provider.totalsFor(customer.id);
    final entries = provider.entriesFor(customer.id).take(20).toList();
    final company = await CompanyNameHelper.resolve();

    final message = WhatsAppHelper.message(
      title: t('waTitleStatement'),
      subtitle:
          '${t('custNumber')} ${customer.customerNumber} · ${customer.name}',
      rows: WhatsAppHelper.rows([
        WhatsAppHelper.row(t('custCharged'), totals.charged.formatted),
        WhatsAppHelper.row(t('custPaid'), totals.paid.formatted),
        ...entries.map(
          (e) => WhatsAppHelper.row(
            e.createdAt == null
                ? (e.isPayment ? t('custAddPayment') : t('custAddCharge'))
                : DateFormat('MM/dd').format(e.createdAt!),
            '${e.amount.formatted}${e.reason.isEmpty ? '' : ' · ${e.reason}'}',
          ),
        ),
      ]),
      totalLabel: t('custBalance'),
      totalValue: totals.balance.formatted,
      footer: '${t('waSentBy')} ${company ?? 'Drink Quick Cal'}',
    );

    final ok = await WhatsAppService.send(
      phone: customer.phone,
      message: message,
    );
    if (!mounted || ok) return;
    Helpers.showToast(
      t(WhatsAppService.hasNumber(customer.phone)
          ? 'waUnavailable'
          : 'waNoPhone'),
      isError: true,
    );
  }

  /// Confirms a charge that goes past the credit limit — manager only.
  Future<bool?> _askOverride() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('custOverride')),
          content: Text(t('custOverrideBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('no')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('yes')),
            ),
          ],
        ),
      );
}
