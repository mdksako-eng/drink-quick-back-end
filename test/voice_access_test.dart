// test/voice_access_test.dart
// Voice used to be ON for everybody: a fresh install started talking, and the
// spoken notifications fired on the free plan. These tests pin the new rule —
// nothing is spoken until the plan grants it AND the user asks for it.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/voice_access.dart';

void main() {
  group('voiceAllowedForPlan', () {
    test('an unresolved plan never grants voice', () {
      expect(
        voiceAllowedForPlan(planResolved: false, grantsAiFeature: true),
        isFalse,
      );
    });

    test('a resolved plan that grants the AI feature grants voice', () {
      expect(
        voiceAllowedForPlan(planResolved: true, grantsAiFeature: true),
        isTrue,
      );
    });

    test('a resolved plan without the AI feature does not grant voice', () {
      expect(
        voiceAllowedForPlan(planResolved: true, grantsAiFeature: false),
        isFalse,
      );
    });

    test('the boot state (nothing known, nothing granted) is silent', () {
      expect(
        voiceAllowedForPlan(planResolved: false, grantsAiFeature: false),
        isFalse,
      );
    });
  });

  group('voiceOutputAllowed', () {
    test('needs the plan AND the user switch', () {
      expect(
        voiceOutputAllowed(allowedByPlan: true, userEnabled: true),
        isTrue,
      );
    });

    test('the user switch alone is not enough', () {
      expect(
        voiceOutputAllowed(allowedByPlan: false, userEnabled: true),
        isFalse,
      );
    });

    test('the plan alone is not enough — voice ships off', () {
      expect(
        voiceOutputAllowed(allowedByPlan: true, userEnabled: false),
        isFalse,
      );
    });

    test('neither condition grants voice', () {
      expect(
        voiceOutputAllowed(allowedByPlan: false, userEnabled: false),
        isFalse,
      );
    });
  });
}
