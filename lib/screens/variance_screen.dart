// screens/variance_screen.dart
// Shrinkage / variance: what left the shelf without being sold, valued at cost
// and split by drink, by staff member and by reason.
//
// Everything here is computed from movements the app already logs
// (inventory_transactions) plus the drink costs — a stock take is the only thing
// that has to be entered by hand, and it is what makes lost stock visible.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/drink_provider.dart';
import '../providers/inventory_provider.dart';
import '../utils/i18n.dart';
import '../utils/price_extension.dart';
import '../utils/variance_helper.dart';

class VarianceScreen extends StatefulWidget {
  const VarianceScreen({super.key});

  @override
  State<VarianceScreen> createState() => _VarianceScreenState();
}

class _VarianceScreenState extends State<VarianceScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;

    final inventory = context.watch<InventoryProvider>();
    final drinks = context.watch<DrinkProvider>().customDrinks;

    final costs = <String, double>{
      for (final drink in drinks) drink.id: drink.purchasePrice,
    };
    final since = DateTime.now().subtract(Duration(days: _days));
    final events = VarianceHelper.fromTransactions(
      inventory.transactions,
      since: since,
      costByDrinkId: costs,
    );
    final totals = VarianceHelper.totals(events);
    final sold = VarianceHelper.soldValue(
      inventory.transactions.where((t) => !t.date.isBefore(since)).toList(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(t('varTitle')),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _periodSelector(),
          const SizedBox(height: 14),
          _summaryCard(theme, totals, sold, events),
          const SizedBox(height: 16),
          if (events.isEmpty)
            _emptyState(theme)
          else ...[
            _rankedSection(
              theme,
              t('varByDrink'),
              Icons.local_drink,
              VarianceHelper.ranked(VarianceHelper.valueByDrink(events)),
            ),
            const SizedBox(height: 14),
            _rankedSection(
              theme,
              t('varByStaff'),
              Icons.person_outline,
              VarianceHelper.ranked(
                VarianceHelper.valueByStaff(
                  events,
                  unknownLabel: t('varUnrecorded'),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _rankedSection(
              theme,
              t('varByReason'),
              Icons.help_outline,
              VarianceHelper.ranked(VarianceHelper.valueByReason(events))
                  .map(
                    (e) => MapEntry(
                      t(VarianceHelper.reasonKey(e.key)),
                      e.value,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
            Text(
              t('varMovements'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            ...events.take(30).map((e) => _eventTile(theme, e)),
          ],
        ],
      ),
    );
  }

  Widget _periodSelector() => SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 7, label: Text('7')),
          ButtonSegment(value: 30, label: Text('30')),
          ButtonSegment(value: 90, label: Text('90')),
        ],
        selected: {_days},
        onSelectionChanged: (selection) =>
            setState(() => _days = selection.first),
      );

  Widget _summaryCard(
    ThemeData theme,
    VarianceTotals totals,
    double sold,
    List<VarianceEvent> events,
  ) {
    final rate = VarianceHelper.lossRate(
      lossValue: totals.value,
      soldValue: sold,
    );
    final rankedDrinks = VarianceHelper.ranked(
      VarianceHelper.valueByDrink(events),
      limit: 1,
    );
    final worst = rankedDrinks.isEmpty ? null : rankedDrinks.first;
    final hasUnexplained = totals.unexplainedValue > 0;

    return Card(
      elevation: 1,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: _metric(t('varLost'), totals.value.formatted)),
              Expanded(child: _metric(t('varUnits'), '${totals.units}')),
              Expanded(
                child: _metric(
                  t('varLossRate'),
                  sold > 0 ? '${(rate * 100).toStringAsFixed(1)}%' : '-',
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Icon(
                hasUnexplained
                    ? Icons.report_problem_outlined
                    : Icons.verified_outlined,
                size: 16,
                color: hasUnexplained ? Colors.orange : Colors.green,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasUnexplained
                      ? '${t('varUnexplained')}: '
                          '${totals.unexplainedValue.formatted} '
                          '(${totals.unexplainedEvents})'
                      : t('varUnexplainedHint'),
                  style: TextStyle(
                    fontSize: 12,
                    color: hasUnexplained ? Colors.orange : Colors.grey[600],
                  ),
                ),
              ),
            ]),
            if (worst != null) ...[
              const SizedBox(height: 8),
              Text(
                '${t('varTopItem')}: ${worst.key} — ${worst.value.formatted}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      );

  /// A ranked "who / what / why" list, biggest first.
  Widget _rankedSection(
    ThemeData theme,
    String title,
    IconData icon,
    List<MapEntry<String, double>> entries,
  ) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final top = entries.first.value;
    return Card(
      elevation: 1,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: theme.primaryColor),
              const SizedBox(width: 8),
              Text(
                title,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ]),
            const SizedBox(height: 8),
            ...entries.map((entry) {
              final share = top <= 0 ? 0.0 : entry.value / top;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          entry.key.isEmpty ? t('varUnrecorded') : entry.key,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        entry.value.formatted,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: share.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: Colors.grey.withValues(alpha: 0.15),
                        color: theme.primaryColor,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _eventTile(ThemeData theme, VarianceEvent event) {
    final unexplained = event.isUnexplained;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(
          unexplained ? Icons.help_outline : Icons.remove_circle_outline,
          size: 20,
          color: unexplained ? Colors.orange : Colors.grey,
        ),
        title: Text(
          event.drinkName.isEmpty ? event.drinkId : event.drinkName,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          <String>[
            t(event.reasonKey),
            if (event.staffName.trim().isNotEmpty) event.staffName.trim(),
            if (event.at != null) _dateLabel(event.at!),
          ].join(' · '),
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '-${event.units}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            Text(
              event.value.formatted,
              style: TextStyle(
                fontSize: 11,
                color: unexplained ? Colors.orange : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime value) {
    final d = value.day.toString().padLeft(2, '0');
    final m = value.month.toString().padLeft(2, '0');
    final h = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    return '$d/$m $h:$min';
  }

  Widget _emptyState(ThemeData theme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            Icon(Icons.verified_outlined, size: 52, color: Colors.grey[400]),
            const SizedBox(height: 10),
            Text(
              t('varNoLosses'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              t('varNoLossesHint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ]),
        ),
      );
}