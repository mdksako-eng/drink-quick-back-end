// utils/voice_access.dart
//
// Voice (spoken AI replies, order announcements, spoken notifications) is a PAID
// capability that ships OFF.
//
// Two independent conditions must both hold before a single word is spoken:
//   1. the company's plan grants it — resolved from PlanProvider, and
//   2. the user switched the global voice switch on.
//
// Both default to "no", so a fresh install, a free plan and a plan we could not
// read all stay silent. Pure on purpose: the rule is unit tested without pumping
// widgets (see test/voice_access_test.dart).

/// Does the current plan grant voice output?
///
/// [planResolved] is false until a plan fetch has completed. Until then we do not
/// know what the company pays for, and an unknown entitlement is never granted —
/// a failed or unfinished fetch must not hand out a paid feature.
bool voiceAllowedForPlan({
  required bool planResolved,
  required bool grantsAiFeature,
}) {
  if (!planResolved) return false;
  return grantsAiFeature;
}

/// The effective switch: the plan must grant voice AND the user must want it.
///
/// A downgrade silences the app without touching the user's saved preference, so
/// re-subscribing brings the voice back exactly as they left it.
bool voiceOutputAllowed({
  required bool allowedByPlan,
  required bool userEnabled,
}) =>
    allowedByPlan && userEnabled;
