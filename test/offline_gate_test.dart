// test/offline_gate_test.dart
// Option C, scoped to company tills: cash keeps the shop open during an outage, but
// the unsynced queue has a hard cap, and electronic money never pretends to work
// offline. Personal (non-company) use is never blocked.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/offline_gate.dart';

OfflineSaleDecision decide({
  bool isCompanyTill = true,
  bool isOnline = true,
  int pendingSync = 0,
  bool isElectronic = false,
  int maxPending = OfflineGate.defaultMaxPending,
}) =>
    OfflineGate.decide(
      isCompanyTill: isCompanyTill,
      isOnline: isOnline,
      pendingSync: pendingSync,
      isElectronic: isElectronic,
      maxPending: maxPending,
    );

void main() {
  group('online company till', () {
    test('cash and electronic sales complete while the queue is healthy', () {
      expect(decide(), OfflineSaleDecision.allowed);
      expect(decide(isElectronic: true), OfflineSaleDecision.allowed);
    });

    test('a full queue stops everything, even when the device says it is online', () {
      expect(decide(pendingSync: 20), OfflineSaleDecision.blockedQueueFull);
      expect(decide(pendingSync: 25, isElectronic: true),
          OfflineSaleDecision.blockedQueueFull);
    });

    test('just below the cap still sells', () {
      expect(decide(pendingSync: 19), OfflineSaleDecision.allowed);
    });
  });

  group('offline company till', () {
    test('cash is allowed and flagged for a later sync', () {
      expect(decide(isOnline: false), OfflineSaleDecision.allowedOfflineCash);
    });

    test('electronic money is refused', () {
      expect(decide(isOnline: false, isElectronic: true),
          OfflineSaleDecision.blockedOfflineElectronic);
    });

    test('the queue cap outranks the payment method', () {
      expect(decide(isOnline: false, pendingSync: 20),
          OfflineSaleDecision.blockedQueueFull);
      expect(decide(isOnline: false, pendingSync: 20, isElectronic: true),
          OfflineSaleDecision.blockedQueueFull);
    });
  });

  group('not a company till', () {
    test('never blocked, offline or with a full queue', () {
      expect(decide(isCompanyTill: false, isOnline: false),
          OfflineSaleDecision.allowed);
      expect(decide(isCompanyTill: false, isOnline: false, pendingSync: 99),
          OfflineSaleDecision.allowed);
      expect(
          decide(
              isCompanyTill: false,
              isOnline: false,
              pendingSync: 99,
              isElectronic: true),
          OfflineSaleDecision.allowed);
    });
  });

  group('edges', () {
    test('a negative or zero pending count is harmless', () {
      expect(decide(pendingSync: -3), OfflineSaleDecision.allowed);
      expect(decide(pendingSync: 0), OfflineSaleDecision.allowed);
    });

    test('a custom cap is honoured', () {
      expect(decide(pendingSync: 5, maxPending: 5),
          OfflineSaleDecision.blockedQueueFull);
      expect(decide(pendingSync: 4, maxPending: 5), OfflineSaleDecision.allowed);
    });

    test('isBlocked matches the decision', () {
      expect(OfflineGate.isBlocked(OfflineSaleDecision.allowed), isFalse);
      expect(OfflineGate.isBlocked(OfflineSaleDecision.allowedOfflineCash), isFalse);
      expect(OfflineGate.isBlocked(OfflineSaleDecision.blockedOfflineElectronic), isTrue);
      expect(OfflineGate.isBlocked(OfflineSaleDecision.blockedQueueFull), isTrue);
    });
  });
}
