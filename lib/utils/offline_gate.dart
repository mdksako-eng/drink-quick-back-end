// utils/offline_gate.dart
// Can this sale be completed right now?
//
// SCOPE: this rule is for COMPANY tills only. A till that does not belong to a
// company (personal / customer use) is never restricted by it.
//
// For a company till the shop must keep selling when the internet drops — that is
// why the app is offline-first — but the books must not drift forever:
//   • electronic money (card / MTN / Orange) needs the server, so it cannot be
//     taken offline at all;
//   • cash may be sold offline and queued, but only until the unsynced queue hits
//     the cap — after that the operator must reconnect and sync;
//   • when the queue is full nothing completes, online or not: that is the
//     "not synced → cannot complete" rule.
//
// Pure and dependency-free, so the rule is unit tested rather than trusted.
enum OfflineSaleDecision {
  /// Not a company till, or online with a healthy queue: business as usual.
  allowed,

  /// Offline, cash: allowed, and the operator is warned it will sync later.
  allowedOfflineCash,

  /// Offline, electronic: refused — the provider cannot be reached.
  blockedOfflineElectronic,

  /// The unsynced queue reached its cap: refuse everything until a sync succeeds.
  blockedQueueFull,
}

class OfflineGate {
  /// How many unsynced sales a company till tolerates before selling is refused.
  static const int defaultMaxPending = 20;

  static OfflineSaleDecision decide({
    required bool isCompanyTill,
    required bool isOnline,
    required int pendingSync,
    required bool isElectronic,
    int maxPending = defaultMaxPending,
  }) {
    // The restriction exists for companies keeping shareable books; personal use
    // is never blocked by it.
    if (!isCompanyTill) return OfflineSaleDecision.allowed;

    final pending = pendingSync < 0 ? 0 : pendingSync;
    // The queue cap outranks connectivity: a stuck sync is the dangerous case, and
    // "not synced" must stop new sales even when the device believes it is online.
    if (pending >= maxPending) return OfflineSaleDecision.blockedQueueFull;
    if (!isOnline) {
      return isElectronic
          ? OfflineSaleDecision.blockedOfflineElectronic
          : OfflineSaleDecision.allowedOfflineCash;
    }
    return OfflineSaleDecision.allowed;
  }

  static bool isBlocked(OfflineSaleDecision decision) =>
      decision == OfflineSaleDecision.blockedOfflineElectronic ||
      decision == OfflineSaleDecision.blockedQueueFull;
}
