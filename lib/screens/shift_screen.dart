// screens/shift_screen.dart
// The till session: open a shift with the float in the drawer, watch the live
// Z-report, then close it with the cash you counted.
//
// A staff member closes their own shift; a manager may close anyone's (the
// backend enforces the rule, see utils/shiftMath.js).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shift_model.dart';
import '../providers/shift_provider.dart';
import '../services/whatsapp_service.dart';
import '../utils/company_name_helper.dart';
import '../utils/helpers.dart';
import '../utils/i18n.dart';
import '../utils/price_extension.dart';
import '../utils/shift_helper.dart';
import '../utils/whatsapp_helper.dart';

class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  @override
  void initState() {
    super.initState();
    // Defer the load: the provider notifies its listeners synchronously, which
    // must not happen during this screen's first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ShiftProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;
    final provider = context.watch<ShiftProvider>();
    final past = provider.history.where((s) => !s.isOpen).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(t('shiftTitle')),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<ShiftProvider>().load(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (provider.offline) _offlineNote(),
            if (provider.isOpen)
              _openCard(provider, primary)
            else
              _closedState(provider, primary),
            const SizedBox(height: 20),
            Text(
              t('shiftHistory'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (past.isEmpty)
              Text(
                t('shiftNoHistory'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              )
            else
              ...past.take(30).map(_historyTile),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _offlineNote() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.cloud_off, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t('shiftOffline'),
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
        ]),
      );

  /// Nothing open yet: the staff member starts the till.
  Widget _closedState(ShiftProvider provider, Color primary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.lock_open, color: primary),
              const SizedBox(width: 8),
              Text(
                t('shiftNoShift'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              t('shiftNoShiftHint'),
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openDialog(provider),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(t('shiftOpen')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDialog(ShiftProvider provider) async {
    final controller = TextEditingController(text: '0');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('shiftOpen')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t('shiftOpeningFloat')),
          ),
          const SizedBox(height: 8),
          Text(
            t('shiftFloatHint'),
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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

    final floatValue =
        double.tryParse(controller.text.trim().replaceAll(',', ''));
    controller.dispose();
    if (saved != true || !mounted) return;
    if (!ShiftHelper.isValidAmount(floatValue)) {
      Helpers.showToast(t('shiftOpenFailed'), isError: true);
      return;
    }

    final ok = await provider.open(openingFloat: floatValue!);
    if (!mounted) return;
    Helpers.showToast(
      ok ? t('shiftOpened') : t('shiftAlreadyOpen'),
      isError: !ok,
    );
  }

  /// The open shift: the live Z-report plus the cash-up button.
  Widget _openCard(ShiftProvider provider, Color primary) {
    final shift = provider.current!;
    final summary = provider.summary;
    return Card(
      color: primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.timer_outlined, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('shiftStatusOpen'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              _chip(t(ShiftHelper.statusKey(shift.status)), primary),
            ]),
            const SizedBox(height: 6),
            Text(
              '${t('shiftOpenedAt')}: ${_time(shift.openedAt)} · '
              '${ShiftHelper.durationLabel(shift.openedAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 14),
            if (summary != null) ...[
              Row(children: [
                Expanded(child: _metric(t('shiftSales'), summary.sales.formatted)),
                Expanded(
                    child: _metric(t('shiftCollected'), summary.collected.formatted)),
                Expanded(child: _metric(t('shiftExpectedCash'),
                    summary.expectedCash.formatted, highlight: true)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _metric(t('shiftOnCredit'), summary.onCredit.formatted)),
                Expanded(child: _metric(t('shiftOrders'), '${summary.orderCount}')),
                const Spacer(),
              ]),
              const SizedBox(height: 8),
              Text(
                t('shiftCreditHint'),
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ] else
              Text(
                t('shiftNoNumbers'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: provider.loading
                      ? null
                      : () => _closeDialog(provider, summary),
                  icon: const Icon(Icons.lock_outline, size: 20),
                  label: Text(t('shiftClose')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // The owner's copy: send the current numbers before cashing up.
              OutlinedButton(
                onPressed:
                    summary == null ? null : () => _sendReport(summary),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 14),
                ),
                child: const Icon(Icons.chat_outlined, size: 20),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _closeDialog(
    ShiftProvider provider,
    ShiftSummary? summary,
  ) async {
    final countedController = TextEditingController(
      text: summary == null ? '' : summary.expectedCash.toStringAsFixed(0),
    );
    final payoutController = TextEditingController();
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('shiftClose')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            t('shiftCountHint'),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: countedController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t('shiftCounted')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: payoutController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t('shiftPayouts')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: notesController,
            decoration: InputDecoration(labelText: t('shiftNotes')),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('shiftClose')),
          ),
        ],
      ),
    );

    double? parse(TextEditingController c) {
      final text = c.text.trim().replaceAll(',', '');
      return text.isEmpty ? null : double.tryParse(text);
    }

    final counted = parse(countedController);
    final payout = parse(payoutController);
    final notes = notesController.text.trim();
    countedController.dispose();
    payoutController.dispose();
    notesController.dispose();

    if (confirmed != true || !mounted) return;
    if (!ShiftHelper.isValidAmount(counted)) {
      Helpers.showToast(t('shiftCloseFailed'), isError: true);
      return;
    }

    final frozen = await provider.close(
      cashCounted: counted!,
      cashPayouts: payout,
      notes: notes.isEmpty ? null : notes,
    );
    if (!mounted) return;
    if (frozen == null) {
      Helpers.showToast(t('shiftCloseFailed'), isError: true);
      return;
    }
    Helpers.showToast(t('shiftClosed'));
    _showZReport(frozen);
  }

  /// The frozen report of the shift that was just closed.
  void _showZReport(ShiftSummary s) {
    final varianceColor = _varianceColor(s.variance);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('shiftZReport')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(t('shiftSales'), s.sales.formatted),
            _row(t('shiftCollected'), s.collected.formatted),
            _row(t('shiftOnCredit'), s.onCredit.formatted),
            _row(t('shiftPayouts'), s.payouts.formatted),
            const Divider(),
            _row(t('shiftExpectedCash'), s.expectedCash.formatted),
            _row(t('shiftCounted'), (s.counted ?? 0).formatted),
            _row(
              t('shiftVariance'),
              (s.variance ?? 0).formatted,
              color: varianceColor,
            ),
            if (s.byMethod.isNotEmpty) ...[
              const Divider(),
              ...s.byMethod.entries.map((e) => _row(e.key, e.value.formatted)),
            ],
            const SizedBox(height: 8),
            Text(
              t(ShiftHelper.varianceKey(s.variance)),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: varianceColor,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _sendReport(s),
            icon: const Icon(Icons.chat_outlined, size: 18),
            label: Text(t('waSendZReport')),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('ok'))),
        ],
      ),
    );
  }

  /// Sends the Z-report on WhatsApp: to the shop's own number when it is on
  /// file, otherwise WhatsApp asks which contact to send it to.
  Future<void> _sendReport(ShiftSummary summary) async {
    final shift = context.read<ShiftProvider>().current;
    final company = await CompanyNameHelper.resolve();
    final prefs = await SharedPreferences.getInstance();
    final shopPhone = prefs.getString('company_phone');

    final message = WhatsAppHelper.message(
      title: t('waTitleZReport'),
      subtitle: shift == null
          ? company
          : '${company == null ? '' : '$company · '}'
              '${shift.staffName} · ${_time(shift.openedAt)} → '
              '${_time(shift.closedAt)}',
      rows: WhatsAppHelper.rows([
        WhatsAppHelper.row(t('shiftSales'), summary.sales.formatted),
        WhatsAppHelper.row(t('shiftCollected'), summary.collected.formatted),
        WhatsAppHelper.row(t('shiftOnCredit'), summary.onCredit.formatted),
        WhatsAppHelper.row(t('shiftPayouts'), summary.payouts.formatted),
        WhatsAppHelper.row(t('shiftOrders'), '${summary.orderCount}'),
        WhatsAppHelper.row(t('shiftCounted'), (summary.counted ?? 0).formatted),
      ]),
      totalLabel: t('shiftExpectedCash'),
      totalValue: summary.expectedCash.formatted,
      notes: [
        '${t('shiftVariance')}: ${(summary.variance ?? 0).formatted}'
            ' (${t(ShiftHelper.varianceKey(summary.variance))})',
      ],
      footer: '${t('waSentBy')} ${company ?? 'Drink Quick Cal'}',
    );

    final ok = WhatsAppService.hasNumber(shopPhone)
        ? await WhatsAppService.send(phone: shopPhone, message: message)
        : await WhatsAppService.share(message: message);
    if (!mounted || ok) return;
    Helpers.showToast(t('waUnavailable'), isError: true);
  }

  Widget _row(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ]),
      );

  Color _varianceColor(double? variance) {
    if (ShiftHelper.balanced(variance)) return Colors.green;
    return ShiftHelper.isShort(variance) ? Colors.red : Colors.orange;
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      );

  Widget _historyTile(Shift shift) {
    final variance = shift.variance;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading:
            Icon(Icons.check_circle_outline, color: _varianceColor(variance)),
        title: Text(
          shift.staffName.isEmpty ? t('shiftTitle') : shift.staffName,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${_time(shift.openedAt)} → ${_time(shift.closedAt)} · '
          '${ShiftHelper.durationLabel(shift.openedAt, closedAt: shift.closedAt)}',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              shift.totalSales.formatted,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            Text(
              '${t(ShiftHelper.varianceKey(variance))} '
              '${variance == null ? '' : variance.formatted}',
              style: TextStyle(fontSize: 11, color: _varianceColor(variance)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, {bool highlight = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: highlight ? Colors.red : null,
            ),
          ),
        ],
      );

  String _time(DateTime? value) =>
      value == null ? '-' : DateFormat('MMM d, HH:mm').format(value);
}