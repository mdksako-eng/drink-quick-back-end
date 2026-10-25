// providers/container_provider.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/container_model.dart';
import '../services/supabase_service.dart';
import '../utils/container_ledger_helper.dart';

/// Returnable containers (crates and bottles) and who is holding them.
///
/// The credit ledger answers "who owes me money"; this answers "who owes me
/// containers" — a crate in a customer's yard is money standing still. STAFF
/// record a container going out and coming back; only a MANAGER writes one off
/// or changes the container list. The backend enforces both
/// (utils/containerLedger.js); [canRecord] / [canWriteOff] here only hide
/// buttons the server would refuse anyway.
///
/// TOTALS COME FROM THE SERVER: the movements endpoint returns the newest 500
/// rows, so a shop with a long history would compute a wrong balance from the
/// local list. `GET /containers/outstanding` aggregates in SQL instead. The
/// local copy exists so the screen still shows something with no network.
class ContainerProvider extends ChangeNotifier {
  static const String _typesKey = 'container_types';
  static const String _movementsKey = 'container_movements';
  static const String _holdersKey = 'container_holders';

  List<ContainerType> _types = [];
  List<ContainerMovement> _movements = [];
  List<ContainerHolder> _holders = [];
  List<ContainerOutstanding> _byType = [];
  int _totalOutstanding = 0;
  bool _loading = false;
  bool _offline = false;

  List<ContainerType> get types => _types;

  /// The history we have loaded, newest first (display only — see the note above).
  List<ContainerMovement> get movements =>
      ContainerLedgerHelper.newestFirst(_movements);

  /// Who is holding containers, biggest holder first (server-computed).
  List<ContainerHolder> get holders => _holders;

  /// What is out of the shop, per container type (server-computed).
  List<ContainerOutstanding> get byType => _byType;

  /// Every container currently out of the shop, across all customers.
  int get totalOutstanding => _totalOutstanding;

  bool get loading => _loading;
  bool get offline => _offline;
  bool get hasTypes => _types.isNotEmpty;

  /// Any role except the customer's own records a movement at the counter.
  bool canRecord(String? role) => ContainerLedgerHelper.canRecord(role);

  /// A write-off is stock disappearing, so a manager alone may do it.
  bool canWriteOff(String? role) => ContainerLedgerHelper.canWriteOff(role);

  /// The container list itself is shop setup.
  bool canManageTypes(String? role) =>
      ContainerLedgerHelper.canManageTypes(role);

  /// What one customer holds of one container type, from the movements we have.
  /// The counter dialog uses this to cap the field; the server re-checks the
  /// ceiling when the movement is written.
  int heldBy(int customerId, int containerTypeId) =>
      ContainerLedgerHelper.outstandingFor(
        _movements.where((m) => m.customerId == customerId).toList(),
        containerTypeId,
      );

  /// One customer's movements, newest first.
  List<ContainerMovement> movementsFor(int customerId) =>
      ContainerLedgerHelper.newestFirst(
        _movements.where((m) => m.customerId == customerId).toList(),
      );

  /// Loads the list, the history and the server-side totals; falls back to the
  /// last known copy when there is no network.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();

    final types = await SupabaseService.getContainerTypes();
    final movements = await SupabaseService.getContainerLedger();
    final outstanding = await SupabaseService.getContainersOutstanding();

    if (types == null || movements == null || outstanding == null) {
      _offline = true;
      await _loadCache();
    } else {
      _offline = false;
      _types = types.map(ContainerType.fromJson).toList();
      _movements = movements.map(ContainerMovement.fromJson).toList();
      _holders = ((outstanding['customers'] as List?) ?? [])
          .whereType<Map>()
          .map((row) =>
              ContainerHolder.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      _byType = ((outstanding['byType'] as List?) ?? [])
          .whereType<Map>()
          .map((row) => ContainerOutstanding(
                containerTypeId:
                    int.tryParse('${row['containerTypeId'] ?? ''}') ?? 0,
                name: (row['name'] ?? '').toString(),
                depositValue:
                    double.tryParse('${row['depositValue'] ?? '0'}') ?? 0,
                outstanding: int.tryParse('${row['outstanding'] ?? '0'}') ?? 0,
              ))
          .toList();
      _totalOutstanding =
          int.tryParse('${outstanding['totalOutstanding'] ?? '0'}') ?? 0;
      await _saveCache();
    }

    _loading = false;
    notifyListeners();
  }

  /// Records one movement, then reloads so the totals come back from the server.
  /// Returns null on success, or a CODE the screen turns into text: 'offline'
  /// when the server could not be reached, 'refused' when it said no (nobody
  /// gives back more than went out, and only a manager writes off).
  Future<String?> record({
    required int customerId,
    required int containerTypeId,
    required String kind,
    required int quantity,
    String? reason,
  }) async {
    final result = await SupabaseService.recordContainerMovement(
      customerId: customerId,
      containerTypeId: containerTypeId,
      kind: kind,
      quantity: quantity,
      reason: reason,
    );
    if (result == null) return 'offline';
    if (result['error'] != null) return 'refused';
    await load();
    return null;
  }

  /// Adds or updates a container in the shop's list (managers only).
  Future<bool> saveType({required String name, double depositValue = 0}) async {
    final saved = await SupabaseService.saveContainerType(
      name: name,
      depositValue: depositValue,
    );
    if (saved == null) return false;
    await load();
    return true;
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final types = prefs.getString(_typesKey);
      if (types != null) {
        _types = (jsonDecode(types) as List)
            .whereType<Map>()
            .map((row) => ContainerType.fromJson(Map<String, dynamic>.from(row)))
            .toList();
      }
      final movements = prefs.getString(_movementsKey);
      if (movements != null) {
        _movements = (jsonDecode(movements) as List)
            .whereType<Map>()
            .map((row) =>
                ContainerMovement.fromJson(Map<String, dynamic>.from(row)))
            .toList();
      }
      final holders = prefs.getString(_holdersKey);
      if (holders != null) {
        _holders = (jsonDecode(holders) as List)
            .whereType<Map>()
            .map((row) =>
                ContainerHolder.fromJson(Map<String, dynamic>.from(row)))
            .toList();
      }
    } catch (e) {
      print('❌ container cache read failed: $e');
    }
  }

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setString(
        _typesKey,
        jsonEncode(_types.map((t) => t.toJson()).toList()),
      );
      await prefs.setString(
        _movementsKey,
        jsonEncode(_movements.map((m) => m.toJson()).toList()),
      );
      await prefs.setString(
        _holdersKey,
        jsonEncode(_holders
            .map((h) => {
                  'customer_id': h.customerId,
                  'customer_number': h.customerNumber,
                  'name': h.name,
                  'outstanding': h.outstanding,
                })
            .toList()),
      );
    } catch (e) {
      print('❌ container cache write failed: $e');
    }
  }
}
