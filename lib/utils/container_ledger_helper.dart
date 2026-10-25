// utils/container_ledger_helper.dart
// Pure rules for returnable containers (crates and bottles).
//
// This mirrors drinks-calculator-backend/utils/containerLedger.js so the app
// hides what the server would refuse anyway — the server stays the authority.
//
// The balance is ALWAYS summed from the movements, never stored:
//   outstanding = out - back - writeoff
// so it can never disagree with its own history.
//
// WHO DECIDES WHAT:
//   * STAFF hand a container out and take one back (a physical fact at the counter)
//   * a MANAGER alone writes one off (lost or broken) or changes the container list
//   * nobody gives back or writes off more than is actually outstanding
//
// Every refusal is returned as a CODE, never as English text, so the UI can show
// it through t('…') in both languages.

import '../models/container_model.dart';

/// out / back / writtenOff / outstanding for one customer (or the whole shop).
class ContainerTotals {
  final int out;
  final int back;
  final int writtenOff;
  final int outstanding;

  const ContainerTotals({
    required this.out,
    required this.back,
    required this.writtenOff,
    required this.outstanding,
  });

  /// True when this customer is still holding containers.
  bool get holdsAny => outstanding > 0;

  @override
  String toString() =>
      'ContainerTotals(out: $out, back: $back, writtenOff: $writtenOff, '
      'outstanding: $outstanding)';
}

/// One row of "who is holding my crates": a container type and what is out.
class ContainerOutstanding {
  final int containerTypeId;
  final String name;
  final double depositValue;
  final int outstanding;

  const ContainerOutstanding({
    required this.containerTypeId,
    required this.name,
    this.depositValue = 0,
    required this.outstanding,
  });

  /// Informational only — containers are goods, not cash.
  double get value => outstanding * depositValue;

  bool get holdsAny => outstanding != 0;
}

/// One row of "who is holding my containers": a customer and what they hold.
///
/// This comes from the BACKEND's aggregate (`GET /containers/outstanding`), not
/// from the movements the app happens to have loaded — the ledger endpoint is
/// capped at the newest 500 rows, so a shop with a long history must never have
/// its totals computed from a truncated list.
class ContainerHolder {
  final int customerId;
  final String customerNumber;
  final String name;
  final int outstanding;

  const ContainerHolder({
    required this.customerId,
    required this.customerNumber,
    required this.name,
    required this.outstanding,
  });

  bool get holdsAny => outstanding != 0;

  factory ContainerHolder.fromJson(Map<String, dynamic> json) => ContainerHolder(
        customerId:
            int.tryParse('${json['customer_id'] ?? ''}') ?? 0,
        customerNumber: (json['customer_number'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        outstanding: int.tryParse('${json['outstanding'] ?? '0'}') ?? 0,
      );
}

class ContainerLedgerHelper {
  ContainerLedgerHelper._();

  static const List<String> kinds = ['out', 'back', 'writeoff'];
  static const String kindOut = 'out';
  static const String kindBack = 'back';
  static const String kindWriteOff = 'writeoff';

  /// Manager, Administrator and Admin all "hold the final say".
  static bool isManagerRole(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return r == 'manager' || r == 'administrator' || r == 'admin';
  }

  /// Any role except the customer's own may record a movement at the counter.
  static bool canRecord(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return r.isNotEmpty && r != 'customer';
  }

  /// A write-off is stock disappearing, so a manager alone may do it.
  static bool canWriteOff(String? role) => isManagerRole(role);

  /// The container list itself (names, deposits) is shop setup.
  static bool canManageTypes(String? role) => isManagerRole(role);

  /// Totals for a list of movements.
  static ContainerTotals totalsFor(List<ContainerMovement> movements) {
    var out = 0;
    var back = 0;
    var writtenOff = 0;
    for (final movement in movements) {
      if (movement.isBack) {
        back += movement.quantity;
      } else if (movement.isWriteOff) {
        writtenOff += movement.quantity;
      } else if (movement.isOut) {
        out += movement.quantity;
      }
    }
    return ContainerTotals(
      out: out,
      back: back,
      writtenOff: writtenOff,
      outstanding: out - back - writtenOff,
    );
  }

  /// Totals for one customer, out of the whole shop's movements.
  static ContainerTotals totalsForCustomer(
    int customerId,
    List<ContainerMovement> movements,
  ) =>
      totalsFor(movements.where((m) => m.customerId == customerId).toList());

  /// What is still out for ONE container type (0 when they hold none).
  static int outstandingFor(
    List<ContainerMovement> movements,
    int containerTypeId,
  ) {
    final mine =
        movements.where((m) => m.containerTypeId == containerTypeId).toList();
    return totalsFor(mine).outstanding;
  }

  /// The whole ledger grouped by container type, biggest pile first.
  /// Types with nothing outstanding are dropped.
  static List<ContainerOutstanding> outstandingByType(
    List<ContainerType> types,
    List<ContainerMovement> movements,
  ) {
    final rows = types
        .map((type) => ContainerOutstanding(
              containerTypeId: type.id,
              name: type.name,
              depositValue: type.depositValue,
              outstanding: outstandingFor(movements, type.id),
            ))
        .where((row) => row.holdsAny)
        .toList();
    rows.sort((a, b) {
      final byPile = b.outstanding.compareTo(a.outstanding);
      if (byPile != 0) return byPile;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return rows;
  }

  /// Why a movement cannot be recorded, or null when it can.
  /// Codes, not sentences: the screen turns them into t('…') text.
  static String? movementProblem({
    required String? role,
    required String kind,
    required int quantity,
    required int outstanding,
  }) {
    if (!kinds.contains(kind)) return 'unknownKind';
    if (!canRecord(role)) return 'notAllowed';
    if (kind == kindWriteOff && !canWriteOff(role)) {
      return 'writeOffNeedsManager';
    }
    if (quantity <= 0) return 'quantityPositive';
    // Only 'out' adds to the pile; the other two take from it, and the pile can
    // never go below zero — the same rule the returns ceiling uses.
    if (kind != kindOut && quantity > outstanding) return 'exceedsOutstanding';
    return null;
  }

  /// Movements, newest first, ready for the ledger list.
  static List<ContainerMovement> newestFirst(
    List<ContainerMovement> movements,
  ) {
    final sorted = [...movements];
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

  /// i18n key for a movement kind.
  static String kindKey(String? kind) {
    switch ((kind ?? '').trim().toLowerCase()) {
      case kindBack:
        return 'contKindBack';
      case kindWriteOff:
        return 'contKindWriteoff';
      default:
        return 'contKindOut';
    }
  }

  /// i18n key for a refusal code from [movementProblem].
  static String problemKey(String? code) {
    switch (code) {
      case 'unknownKind':
        return 'contErrUnknownKind';
      case 'notAllowed':
        return 'contErrNotAllowed';
      case 'writeOffNeedsManager':
        return 'contErrWriteOffManager';
      case 'quantityPositive':
        return 'contErrQuantity';
      case 'exceedsOutstanding':
        return 'contErrTooMany';
      default:
        return 'contErrGeneric';
    }
  }
}
