// widgets/return_items_dialog.dart
// "Return 1 of 2" — choose how many units come back, say why, done.
//
// The numbers shown come from the server (sold / already returned / left), never
// from local arithmetic: another device may have returned a unit, and the backend
// refuses a whole return that asks for more than is left. This dialog can
// therefore never offer a quantity the server will reject.
//
// Pops {'reason': String, 'items': [{'drink_id', 'drink_name', 'quantity'}]} when
// the manager confirms, or null when they back out.
import 'package:flutter/material.dart';

import '../utils/i18n.dart';
import '../utils/order_return_helper.dart';
import '../utils/price_extension.dart';

class ReturnItemsDialog extends StatefulWidget {
  const ReturnItemsDialog({super.key, required this.lines, this.orderLabel});

  /// What is left to give back, straight from GET /orders/:id/returns.
  final List<ReturnableLine> lines;

  /// Receipt / invoice reference shown in the title, when there is one.
  final String? orderLabel;

  @override
  State<ReturnItemsDialog> createState() => _ReturnItemsDialogState();
}

class _ReturnItemsDialogState extends State<ReturnItemsDialog> {
  /// drinkId -> units to give back (starts at 0: nothing goes back by accident).
  final Map<String, int> _chosen = {};
  final TextEditingController _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _step(ReturnableLine line, int delta) {
    final next = line.clampQuantity((_chosen[line.drinkId] ?? 0) + delta);
    setState(() {
      _chosen[line.drinkId] = next;
      _error = null;
    });
  }

  int get _units => OrderReturnHelper.totalUnits(widget.lines, _chosen);
  double get _amount => OrderReturnHelper.totalAmount(widget.lines, _chosen);

  void _confirm() {
    final reason = _reason.text.trim();
    if (_units <= 0) {
      setState(() => _error = t('returnNoItems'));
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = t('returnReasonRequired'));
      return;
    }
    Navigator.pop(context, {
      'reason': reason,
      'items': OrderReturnHelper.requestItems(widget.lines, _chosen),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.orderLabel;
    final title = (label == null || label.isEmpty)
        ? t('returnItems')
        : '${t('returnItems')} · $label';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('returnItemsHint'), style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              for (final line in widget.lines) _line(line, theme),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${t('returnSelected')}: $_units',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _amount.formatted,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: t('voidReason'),
                  hintText: t('returnReasonHint'),
                  errorText: _error,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('cancel')),
        ),
        ElevatedButton(
          onPressed: _units > 0 ? _confirm : null,
          style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.error),
          child: Text(t('returnConfirm')),
        ),
      ],
    );
  }

  Widget _line(ReturnableLine line, ThemeData theme) {
    final chosen = line.clampQuantity(_chosen[line.drinkId] ?? 0);
    final detail = [
      '${t('returnSold')}: ${line.sold}',
      if (line.returned > 0) '${t('returnAlreadyBack')}: ${line.returned}',
      '${t('returnLeft')}: ${line.remaining}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.drinkName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            onPressed: chosen > 0 ? () => _step(line, -1) : null,
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: t('returnItems'),
          ),
          Text('$chosen', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            onPressed: chosen < line.remaining ? () => _step(line, 1) : null,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: t('returnItems'),
          ),
          SizedBox(
            width: 84,
            child: Text(
              line.amountFor(chosen).formatted,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
