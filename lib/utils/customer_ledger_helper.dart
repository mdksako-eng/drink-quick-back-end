// utils/customer_ledger_helper.dart
// Pure rules for customer accounts ("customer numbers") and their tab ledger.
//
// This mirrors drinks-calculator-backend/utils/customerApproval.js so the app
// hides what the server would refuse anyway — the server stays the authority.
//
// WHO DECIDES WHAT:
//   * STAFF enrol a customer -> the account waits as 'pending'
//   * a MANAGER holds the final say: approve / reject / block / re-limit
//   * only an approved account may hold credit

import '../models/customer_model.dart';

/// charged / paid / balance for one customer (or the whole shop).
class LedgerTotals {
  final double charged;
  final double paid;
  final double balance;

  const LedgerTotals({
    required this.charged,
    required this.paid,
    required this.balance,
  });

  /// True when the customer still owes money.
  bool get owes => balance > 0.005;

  /// True when they paid more than they took (a credit with the shop).
  bool get inCredit => balance < -0.005;

  @override
  String toString() =>
      'LedgerTotals(charged: $charged, paid: $paid, balance: $balance)';
}

class CustomerLedgerHelper {
  CustomerLedgerHelper._();

  static const List<String> statuses = [
    'pending',
    'approved',
    'rejected',
    'blocked',
  ];
  static const List<String> kinds = ['charge', 'payment'];

  static const String statusPending = 'pending';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';
  static const String statusBlocked = 'blocked';

  /// Manager, Administrator and Admin all "hold the final say".
  static bool isManagerRole(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return r == 'manager' || r == 'administrator' || r == 'admin';
  }

  /// Staff may enrol a customer; a customer account may not enrol anyone.
  static bool canEnroll(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return r == 'staff' || isManagerRole(r);
  }

  /// Only a manager approves, rejects, blocks or re-limits.
  static bool canDecide(String? role) => isManagerRole(role);

  /// A staff enrolment waits; a manager's own enrolment is final at once.
  static String initialStatusForRole(String? role) =>
      canDecide(role) ? statusApproved : statusPending;

  /// Only an approved account may hold a tab.
  static bool canHoldCredit(Customer? customer) =>
      customer != null && customer.status == statusApproved;

  /// True when a new charge would pass the manager's credit limit.
  static bool exceedsLimit({
    required double balance,
    required double amount,
    required double creditLimit,
  }) {
    if (creditLimit <= 0) return false; // no limit set -> nothing to exceed
    return balance + amount > creditLimit;
  }

  /// Totals for a list of ledger entries (charges count up, payments down).
  static LedgerTotals totalsFor(List<CustomerLedgerEntry> entries) {
    var charged = 0.0;
    var paid = 0.0;
    for (final entry in entries) {
      if (entry.isPayment) {
        paid += entry.amount;
      } else {
        charged += entry.amount;
      }
    }
    return LedgerTotals(
      charged: charged,
      paid: paid,
      balance: charged - paid,
    );
  }

  /// Totals for one customer, out of the whole shop's ledger.
  static LedgerTotals totalsForCustomer(
    int customerId,
    List<CustomerLedgerEntry> entries,
  ) =>
      totalsFor(entries.where((e) => e.customerId == customerId).toList());

  /// Newest first, ready for the ledger list.
  static List<CustomerLedgerEntry> newestFirst(
    List<CustomerLedgerEntry> entries,
  ) {
    final sorted = [...entries];
    sorted.sort((a, b) {
      final da = a.createdAt;
      final db = b.createdAt;
      if (da == null && db == null) return b.id.compareTo(a.id);
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return sorted;
  }

  /// "Who owes what", biggest debt first — the list the owner actually wants.
  static List<Customer> orderedByDebt(
    List<Customer> customers,
    List<CustomerLedgerEntry> entries,
  ) {
    final list = [...customers];
    list.sort((a, b) {
      final ba = totalsForCustomer(a.id, entries).balance;
      final bb = totalsForCustomer(b.id, entries).balance;
      final byDebt = bb.compareTo(ba);
      if (byDebt != 0) return byDebt;
      return a.customerNumber.compareTo(b.customerNumber);
    });
    return list;
  }

  /// How many accounts are waiting for the manager's decision.
  static int pendingCount(List<Customer> customers) =>
      customers.where((c) => c.status == statusPending).length;

  /// i18n key for a status badge.
  static String statusKey(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case statusApproved:
        return 'custStatusApproved';
      case statusRejected:
        return 'custStatusRejected';
      case statusBlocked:
        return 'custStatusBlocked';
      default:
        return 'custStatusPending';
    }
  }

  /// Digits only, so "6 77 12 34 56" matches "+237 677123456".
  static String normalizePhone(String? phone) =>
      (phone ?? '').replaceAll(RegExp(r'\D'), '');
}
