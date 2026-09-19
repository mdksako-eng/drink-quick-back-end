// test/plan_gate_test.dart
// Guards the post-login subscription gate: the plans must be shown before the
// app loads, "Continue on Free" must always let the user through, and a plan
// that lapses must bring the gate back.
import 'package:flutter_test/flutter_test.dart';

import 'package:drinks_calculator_fixed/models/subscription_model.dart';
import 'package:drinks_calculator_fixed/utils/plan_gate_logic.dart';

const _free = SubscriptionInfo(plan: 'free', status: 'none');
final _proActive = SubscriptionInfo(
  plan: 'pro',
  status: 'active',
  expiresAt: DateTime.now().add(const Duration(days: 30)),
);
final _proExpired = SubscriptionInfo(
  plan: 'pro',
  status: 'active',
  expiresAt: DateTime.now().subtract(const Duration(days: 1)),
);
const _starterCancelled =
    SubscriptionInfo(plan: 'starter', status: 'cancelled');

void main() {
  group('planSignature', () {
    test('combines the plan and the status', () {
      expect(planSignature(_free), 'free:none');
      expect(planSignature(_starterCancelled), 'starter:cancelled');
    });

    test('an expired paid plan no longer matches the signature it was acked for',
        () {
      expect(planSignature(_proActive), 'pro:active');
      expect(planSignature(_proExpired), 'pro:active');
      expect(planSignature(_proActive), planSignature(_proExpired));
    });
  });

  group('planGateDecision', () {
    test('an active plan goes straight into the app', () {
      expect(
        planGateDecision(
          hasLoaded: true,
          planActive: _proActive.isActive,
          signature: planSignature(_proActive),
          ackSignature: null,
        ),
        PlanGateDecision.proceed,
      );
    });

    test('an expired paid plan is NOT active', () {
      expect(
        planGateDecision(
          hasLoaded: true,
          planActive: _proExpired.isActive,
          signature: planSignature(_proExpired),
          ackSignature: null,
        ),
        PlanGateDecision.showPlans,
      );
    });

    test('first login on the free plan shows the plans', () {
      expect(
        planGateDecision(
          hasLoaded: true,
          planActive: _free.isActive,
          signature: planSignature(_free),
          ackSignature: null,
        ),
        PlanGateDecision.showPlans,
      );
    });

    test('"Continue on Free" is remembered for that plan state', () {
      expect(
        planGateDecision(
          hasLoaded: true,
          planActive: _free.isActive,
          signature: planSignature(_free),
          ackSignature: planSignature(_free),
        ),
        PlanGateDecision.proceed,
      );
    });

    test('a lapsed plan re-opens the gate despite an old acknowledgement', () {
      // Acknowledged while on 'free', now holding a cancelled subscription.
      expect(
        planGateDecision(
          hasLoaded: true,
          planActive: _starterCancelled.isActive,
          signature: planSignature(_starterCancelled),
          ackSignature: 'free:none',
        ),
        PlanGateDecision.showPlans,
      );
    });

    test('waits while the plan is unresolved and nothing was acknowledged', () {
      expect(
        planGateDecision(
          hasLoaded: false,
          planActive: false,
          signature: planSignature(_free),
          ackSignature: null,
        ),
        PlanGateDecision.waiting,
      );
    });

    test('a returning acknowledged user is never blocked by a failed fetch', () {
      expect(
        planGateDecision(
          hasLoaded: false,
          planActive: false,
          signature: planSignature(_free),
          ackSignature: planSignature(_free),
        ),
        PlanGateDecision.proceed,
      );
    });
  });

  group('planGateAckKey', () {
    test('is scoped per company so a switch re-shows the gate', () {
      expect(planGateAckKey(7), isNot(planGateAckKey(8)));
      expect(planGateAckKey(7), 'plan_gate_ack_7');
    });

    test('handles a missing company id', () {
      expect(planGateAckKey(null), 'plan_gate_ack_null');
    });
  });
}