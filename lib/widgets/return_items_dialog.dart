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
import 'package:flutter/services.dart';

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

  /// One editable quantity box per line, so 20 of a 24-unit sale is typed, not
  /// tapped twenty times.
  final Map<String, TextEditingController> _quantities = {};
  final TextEditingController _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  TextEditingController _quantityField(ReturnableLine line) {
    final existing = _quantities[line.drinkId];
    if (existing != null) return existing;
    final controller =
        TextEditingController(text: '${_chosen[line.drinkId] ?? 0}');
    _quantities[line.drinkId] = controller;
    return controller;
  }

  /// Keeps a line's box in step with its value (used by the − / + and "all left").
  void _syncQuantityField(ReturnableLine line) {
    final controller = _quantities[line.drinkId];
    if (controller == null) return;
    final text = '${line.clampQuantity(_chosen[line.drinkId] ?? 0)}';
    if (controller.text != text) controller.text = text;
  }

  void _step(ReturnableLine line, int delta) {
    setState(() {
      _chosen[line.drinkId] =
          line.clampQuantity((_chosen[line.drinkId] ?? 0) + delta);
      _error = null;
      _syncQuantityField(line);
    });
  }

  /// Everything left on this line in one tap — a whole pack, or a whole sale.
  void _setLineToAll(ReturnableLine line) {
    setState(() {
      _chosen[line.drinkId] = line.remaining;
      _error = null;
      _syncQuantityField(line);
    });
  }

  /// The whole invoice comes back: every line, everything left.
  void _setEverything() {
    setState(() {
      _chosen
        ..clear()
        ..addAll(OrderReturnHelper.allRemaining(widget.lines));
      _error = null;
      for (final line in widget.lines) {
        _syncQuantityField(line);
      }
    });
  }

  /// A typed quantity is clamped to what is still returnable; the box itself is
  /// only rewritten when focus leaves it, so typing is never fought.
  void _onTyped(ReturnableLine line, String value) {
    final parsed = int.tryParse(value.trim()) ?? 0;
    setState(() {
      _chosen[line.drinkId] = line.clampQuantity(parsed);
      _error = null;
    });
  }

  void _normalise(ReturnableLine line) {
    setState(() => _syncQuantityField(line));
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _setEverything,
                  icon: const Icon(Icons.done_all, size: 16),
                  label: Text(
                    t('returnEverything'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(height: 4),
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

  Widget _stepButton(IconData icon, VoidCallback? onPressed) => IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        tooltip: t('returnItems'),
      );

  Widget _line(ReturnableLine line, ThemeData theme) {
    final detail = [
      '${t('returnSold')}: ${line.sold}',
      if (line.returned > 0) '${t('returnAlreadyBack')}: ${line.returned}',
      '${t('returnLeft')}: ${line.remaining}',
    ].join(' · ');

    // Nothing left on this line: say so instead of offering a dead stepper.
    if (!line.canReturn) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                line.drinkName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.disabledColor),
              ),
            ),
            Flexible(
              child: Text(
                detail,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.disabledColor),
              ),
            ),
          ],
        ),
      );
    }

    final chosen = line.clampQuantity(_chosen[line.drinkId] ?? 0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.drinkName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                line.amountFor(chosen).formatted,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          Row(
            children: [
              Flexible(
                child: Text(
                  detail,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => _setLineToAll(line),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                child: Text(
                  t('returnAllLeft'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              _stepButton(
                Icons.remove_circle_outline,
                chosen > 0 ? () => _step(line, -1) : null,
              ),
              // Type the quantity: a whole sale of drinks comes back in tens, not
              // one tap at a time.
              SizedBox(
                width: 48,
                child: TextField(
                  controller: _quantityField(line),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => _onTyped(line, value),
                  onEditingComplete: () => _normalise(line),
                  onTapOutside: (_) => _normalise(line),
                ),
              ),
              _stepButton(
                Icons.add_circle_outline,
                chosen < line.remaining ? () => _step(line, 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
