// providers/customer_provider.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer_model.dart';
import '../services/supabase_service.dart';
import '../utils/customer_ledger_helper.dart';

/// Customer accounts ("customer numbers") and their credit ledger (tabs).
///
/// STAFF enrol a customer; a MANAGER holds the final say on who is approved.
/// The backend enforces the rule — [canDecide] here only hides buttons the
/// server would refuse anyway.
///
/// The last known accounts + ledger are cached locally, so a till with no
/// network still shows who owes what (writing requires the server, because
/// credit is money).
class CustomerProvider extends ChangeNotifier {
  static const String _customersKey = 'customer_accounts';
  static const String _ledgerKey = 'customer_ledger';

  List<Customer> _customers = [];
  List<CustomerLedgerEntry> _entries = [];
  bool _loading = false;

  /// True when the last load had to fall back to the local cache.
  bool _offline = false;

  List<Customer> get customers => _customers;

  /// The whole company ledger, newest first.
  List<CustomerLedgerEntry> get entries =>
      CustomerLedgerHelper.newestFirst(_entries);

  bool get loading => _loading;
  bool get offline => _offline;

  /// Accounts that may hold a tab.
  List<Customer> get approved =>
      _customers.where((c) => c.status == CustomerLedgerHelper.statusApproved).toList();

  /// The manager's approval queue.
  List<Customer> get pending =>
      _customers.where((c) => c.status == CustomerLedgerHelper.statusPending).toList();

  int get pendingCount => CustomerLedgerHelper.pendingCount(_customers);

  /// Charged / paid / owed for the whole company.
  LedgerTotals get totals => CustomerLedgerHelper.totalsFor(_entries);

  LedgerTotals totalsFor(int customerId) =>
      CustomerLedgerHelper.totalsForCustomer(customerId, _entries);

  List<CustomerLedgerEntry> entriesFor(int customerId) =>
      CustomerLedgerHelper.newestFirst(
        _entries.where((e) => e.customerId == customerId).toList(),
      );

  /// "Who owes what", biggest debt first — what the owner asks for.
  List<Customer> get byDebt =>
      CustomerLedgerHelper.orderedByDebt(approved, _entries);

  /// Staff may enrol a customer; a customer account may not.
  bool canEnroll(String? role) => CustomerLedgerHelper.canEnroll(role);

  /// Only a manager approves, rejects, blocks or re-limits.
  bool canDecide(String? role) => CustomerLedgerHelper.canDecide(role);

  /// Loads the accounts + ledger from the backend, falling back to the cache.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();

    final rows = await SupabaseService.getCustomers();
    final ledger = await SupabaseService.getCustomerLedger();

    if (rows == null || ledger == null) {
      // Offline (or not signed in): keep the last known ledger on screen.
      _offline = true;
      await _loadCache();
    } else {
      _offline = false;
      _customers = rows.map(Customer.fromJson).toList();
      _entries = ledger.map(CustomerLedgerEntry.fromJson).toList();
      await _saveCache();
    }

    _loading = false;
    notifyListeners();
  }

  /// Enrols a customer. A staff enrolment waits as 'pending'; the manager's own
  /// enrolment is approved straight away — the backend decides, and the row it
  /// returns is the truth shown here.
  Future<Customer?> enroll({
    required String name,
    String? phone,
    String? notes,
  }) async {
    final row = await SupabaseService.enrollCustomer(
      name: name,
      phone: phone,
      notes: notes,
    );
    if (row == null) return null;
    final created = Customer.fromJson(row);
    _customers = [..._customers, created];
    await _saveCache();
    notifyListeners();
    return created;
  }

  /// Manager-only decision on an account (approve / reject / block / re-limit).
  Future<bool> decide(
    int customerId, {
    String? status,
    double? creditLimit,
    String? name,
    String? phone,
    String? notes,
  }) async {
    final row = await SupabaseService.decideCustomer(
      customerId,
      status: status,
      creditLimit: creditLimit,
      name: name,
      phone: phone,
      notes: notes,
    );
    if (row == null) return false;

    final updated = Customer.fromJson(row);
    final next = <Customer>[];
    for (final existing in _customers) {
      next.add(existing.id == updated.id ? updated : existing);
    }
    _customers = next;
    await _saveCache();
    notifyListeners();
    return true;
  }

  /// Charges a tab or records a payment against it. The raw result is returned
  /// so the caller can ask a manager when the credit limit is passed, then
  /// re-send with `overrideLimit: true`.
  Future<LedgerWriteResult> addEntry({
    required int customerId,
    required String kind,
    required double amount,
    String? reason,
    String? method,
    String? orderId,
    bool overrideLimit = false,
  }) async {
    final result = await SupabaseService.addCustomerEntry(
      customerId: customerId,
      kind: kind,
      amount: amount,
      reason: reason,
      method: method,
      orderId: orderId,
      overrideLimit: overrideLimit,
    );
    // Re-read the ledger so every balance on screen comes from the server.
    if (result.ok) await load();
    return result;
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _customersKey,
        jsonEncode(_customers.map((c) => c.toJson()).toList()),
      );
      await prefs.setString(
        _ledgerKey,
        jsonEncode(_entries.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Could not cache the customer ledger: $e');
    }
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedCustomers = prefs.getString(_customersKey);
      final cachedLedger = prefs.getString(_ledgerKey);
      if (cachedCustomers != null && cachedCustomers.isNotEmpty) {
        _customers = (jsonDecode(cachedCustomers) as List)
            .map((row) => Customer.fromJson(Map<String, dynamic>.from(row)))
            .toList();
      }
      if (cachedLedger != null && cachedLedger.isNotEmpty) {
        _entries = (jsonDecode(cachedLedger) as List)
            .map(
              (row) =>
                  CustomerLedgerEntry.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList();
      }
    } catch (e) {
      debugPrint('⚠️ Could not read the cached customer ledger: $e');
    }
  }
}
