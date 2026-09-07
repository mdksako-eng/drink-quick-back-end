// screens/forecast_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/forecast_model.dart';
import '../providers/inventory_provider.dart';
import '../services/groq_service.dart';
import '../utils/forecast_helper.dart';
import '../utils/helpers.dart';
import '../utils/holidays.dart';
import '../utils/i18n.dart';

class ForecastScreen extends StatefulWidget {
  const ForecastScreen({Key? key}) : super(key: key);

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  int _horizonDays = 7;
  List<EventDay> _customEvents = [];
  ForecastResult? _result;
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final inv = Provider.of<InventoryProvider>(context, listen: false);
    await inv.loadInventory();
    await _loadEvents();
  }

  Future<void> _loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('forecast_custom_events');
    List<EventDay> events = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        events = list
            .map((e) => EventDay.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _customEvents = events;
        _result = _compute();
      });
    }
  }

  List<EventDay> _buildEvents() {
    final now = DateTime.now();
    final static = upcomingStaticEvents(now, _horizonDays, (k) => t(k));
    final map = <String, EventDay>{};
    for (final e in static) {
      map['${e.date.toIso8601String()}|${e.name}'] = e;
    }
    for (final e in _customEvents) {
      map['${e.date.toIso8601String()}|${e.name}'] = e;
    }
    final list = map.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  ForecastResult _compute() {
    final inv = Provider.of<InventoryProvider>(context, listen: false);
    return computeForecast(
      transactions: inv.transactions,
      inventory: inv.inventoryItems,
      horizonDays: _horizonDays,
      events: _buildEvents(),
    );
  }

  void _setHorizon(int days) {
    setState(() {
      _horizonDays = days;
      _result = _compute();
    });
  }

  Future<void> _refresh() async {
    final inv = Provider.of<InventoryProvider>(context, listen: false);
    await inv.loadInventory();
    if (mounted) setState(() => _result = _compute());
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('forecastTitle')),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: result == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildRangeSelector(),
                const SizedBox(height: 12),
                _buildAiButton(primary),
                const SizedBox(height: 16),
                _buildEventsSection(primary),
                const SizedBox(height: 16),
                _buildForecastList(result, primary),
              ],
            ),
    );
  }

  Widget _buildRangeSelector() {
    return Row(
      children: [7, 14, 30].map((d) {
        final selected = _horizonDays == d;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text('$d ${t('forecastDays')}'),
              selected: selected,
              onSelected: (_) => _setHorizon(d),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAiButton(Color primary) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.auto_awesome, color: primary),
        title: Text(t('forecastAiSummary')),
        subtitle: Text(t('forecastAiSummaryHint')),
        trailing: _aiLoading
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_right),
        onTap: _aiLoading ? null : _generateAiSummary,
      ),
    );
  }

  Widget _buildEventsSection(Color primary) {
    final events = _result?.events ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(t('forecastEvents'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold))),
              TextButton.icon(
                onPressed: _showAddEventDialog,
                icon: const Icon(Icons.add, size: 18),
                label: Text(t('forecastAddEvent')),
              ),
            ]),
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(t('forecastNoEvents'),
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              )
            else
              ...events.map(_buildEventTile),
          ],
        ),
      ),
    );
  }

  Widget _buildForecastList(ForecastResult result, Color primary) {
    if (result.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          Icon(Icons.insights, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(t('forecastNoData'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        ]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('forecastRecommendedOrder'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...result.items.map((i) => _buildForecastItem(i, primary)),
      ],
    );
  }

  Widget _buildForecastItem(ForecastItem item, Color primary) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(item.drinkName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold))),
              _trendBadge(item.trend),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _metric(t('forecastDemand'),
                  '${item.forecastDemand.toStringAsFixed(0)} ${t('forecastUnits')}'),
              _metric(t('forecastStock'), '${item.currentStock}'),
              _metric(t('forecastOrder'), '${item.recommendedOrder}',
                  highlight: item.recommendedOrder > 0),
            ]),
            const SizedBox(height: 8),
            _confidenceBar(item.confidence, primary),
          ],
        ),
      ),
    );
  }

  Widget _trendBadge(double trend) {
    final up = trend >= 0;
    final color = up ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14, color: color),
        const SizedBox(width: 2),
        Text('${trend.abs().toStringAsFixed(0)}%',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _metric(String label, String value, {bool highlight = false}) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: highlight ? Colors.green : null)),
      ]),
    );
  }

  Widget _confidenceBar(double confidence, Color primary) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(t('forecastConfidence'),
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const Spacer(),
        Text('${(confidence * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: confidence,
          minHeight: 6,
          backgroundColor: Colors.grey.withValues(alpha: 0.15),
          color: primary,
        ),
      ),
    ]);
  }

  Widget _buildEventTile(EventDay e) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event, color: Colors.orange),
      title: Text(e.name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(DateFormat('MMM d, y').format(e.date),
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('+${((e.multiplier - 1) * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
          onPressed: () => _deleteEvent(e),
        ),
      ]),
    );
  }

  Future<void> _deleteEvent(EventDay e) async {
    setState(() {
      _customEvents.removeWhere((x) =>
          x.date.toIso8601String() == e.date.toIso8601String() &&
          x.name == e.name);
    });
    await _saveEvents();
    if (mounted) setState(() => _result = _compute());
  }

  Future<void> _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('forecast_custom_events',
        jsonEncode(_customEvents.map((e) => e.toJson()).toList()));
  }

  Future<void> _showAddEventDialog() async {
    final nameController = TextEditingController();
    DateTime date = DateTime.now().add(const Duration(days: 1));
    double multiplier = 1.25;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Text(t('forecastAddEvent')),
              content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: nameController,
                    decoration:
                        InputDecoration(labelText: t('forecastEventName')),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('forecastEventDate')),
                    subtitle: Text(DateFormat('yyyy-MM-dd').format(date)),
                    trailing: const Icon(Icons.calendar_today, size: 20),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setModalState(() => date = picked);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<double>(
                    initialValue: multiplier,
                    decoration: InputDecoration(labelText: t('forecastBoost')),
                    items: const [
                      DropdownMenuItem(value: 1.1, child: Text('+10%')),
                      DropdownMenuItem(value: 1.25, child: Text('+25%')),
                      DropdownMenuItem(value: 1.5, child: Text('+50%')),
                      DropdownMenuItem(value: 2.0, child: Text('+100%')),
                    ],
                    onChanged: (v) =>
                        setModalState(() => multiplier = v ?? 1.25),
                  ),
                ]),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(t('forecastCancel'))),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(t('forecastSave'))),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      final name = nameController.text.trim();
      if (name.isEmpty) return;
      setState(() {
        _customEvents
            .add(EventDay(date: date, name: name, multiplier: multiplier));
        _result = _compute();
      });
      await _saveEvents();
    }
  }

  Future<void> _generateAiSummary() async {
    setState(() => _aiLoading = true);
    try {
      final groq = GroqService();
      final response = await groq.getResponse(_buildAiPrompt());
      if (mounted) {
        setState(() => _aiLoading = false);
        _showAiDialog(response);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _aiLoading = false);
        Helpers.showToast('$e');
      }
    }
  }

  String _buildAiPrompt() {
    final result = _result;
    final top = (result?.items.take(5) ?? const [])
        .map((i) =>
            '${i.drinkName}: ~${i.forecastDemand.toStringAsFixed(0)} units, order ${i.recommendedOrder}')
        .join('; ');
    final events = (result?.events ?? const [])
        .map((e) => '${e.name} (${DateFormat('MMM d').format(e.date)})')
        .join(', ');
    return 'You are a bar/restaurant inventory assistant. '
        '$_horizonDays-day demand forecast: $top. '
        'Upcoming events: ${events.isEmpty ? 'none' : events}. '
        'Give a concise restocking recommendation in 3-5 short bullet points.';
  }

  void _showAiDialog(String text) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.auto_awesome, color: Colors.orange),
          const SizedBox(width: 8),
          Text(t('forecastAiSummary')),
        ]),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('forecastCancel'))),
        ],
      ),
    );
  }
}



