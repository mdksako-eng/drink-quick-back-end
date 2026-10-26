// providers/purchasing_provider.dart
import 'package:flutter/foundation.dart';

import '../models/purchasing_model.dart';
import '../services/supabase_service.dart';

/// Buying stock: suppliers and purchase orders.
///
/// The forecast recommends what to reorder; this is where that becomes an
/// order. A MANAGER creates, sends and cancels (the backend refuses anyone else
/// with 403); ANY staff member may RECEIVE a delivery, because that is a
/// physical fact at the door like a restock. [canWrite] / [canReceive] here only
/// hide buttons the server would refuse anyway.
class PurchasingProvider extends ChangeNotifier {
  List<Supplier> _suppliers = [];
  List<PurchaseOrder> _orders = [];
  bool _loading = false;
  bool _offline = false;
  bool _hasLoaded = false;

  List<Supplier> get suppliers => _suppliers;
  List<PurchaseOrder> get orders => _orders;
  bool get loading => _loading;
  bool get offline => _offline;
  bool get hasLoaded => _hasLoaded;

  /// Orders still needing attention: a draft to send, a sent order to receive.
  List<PurchaseOrder> get open =>
      _orders.where((order) => order.isOpen).toList();

  /// Who a delivery is coming from (null when the order names nobody).
  Supplier? supplierOf(PurchaseOrder order) {
    for (final supplier in _suppliers) {
      if (supplier.id == order.supplierId) return supplier;
    }
    return null;
  }

  static bool _isManager(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return r == 'manager' || r == 'administrator' || r == 'admin';
  }

  /// A manager commits the shop's money.
  bool canWrite(String? role) => _isManager(role);

  /// Receiving is a physical fact: any role except the customer's own.
  bool canReceive(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return r.isNotEmpty && r != 'customer';
  }

  /// Loads suppliers and orders. The server is the authority; there is no local
  /// cache because an order list is only useful when it is current.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();

    final suppliers = await SupabaseService.getSuppliers();
    final orders = await SupabaseService.getPurchaseOrders();

    if (suppliers == null || orders == null) {
      _offline = true;
    } else {
      _offline = false;
      _suppliers = suppliers.map(Supplier.fromJson).toList();
      _orders = orders.map(PurchaseOrder.fromJson).toList();
    }

    _loading = false;
    _hasLoaded = true;
    notifyListeners();
  }

  /// Returns null on success, or a CODE the screen turns into text:
  /// 'offline' when the server could not be reached, 'refused' when it said no.
  Future<String?> _reloadAfter(Map<String, dynamic>? result) async {
    if (result == null) return 'offline';
    if (result['error'] != null) return 'refused';
    await load();
    return null;
  }

  /// Adds or updates a supplier (managers only).
  Future<String?> saveSupplier({
    required String name,
    String? phone,
    String? notes,
  }) async {
    final result = await SupabaseService.saveSupplier(
      name: name,
      phone: phone,
      notes: notes,
    );
    return _reloadAfter(result);
  }

  /// Creates a draft order from lines the screen built.
  Future<String?> createOrder({
    int? supplierId,
    required List<Map<String, dynamic>> lines,
    String? notes,
  }) async {
    final result = await SupabaseService.createPurchaseOrder(
      supplierId: supplierId,
      lines: lines,
      notes: notes,
    );
    return _reloadAfter(result);
  }

  /// Sends or cancels an order (managers only).
  Future<String?> setStatus(int id, String status) async {
    final result =
        await SupabaseService.setPurchaseOrderStatus(id: id, status: status);
    return _reloadAfter(result);
  }

  /// Receives a delivery: the backend adds the stock and freezes the order.
  Future<String?> receive(int id) async {
    final result = await SupabaseService.receivePurchaseOrder(id);
    return _reloadAfter(result);
  }
}
