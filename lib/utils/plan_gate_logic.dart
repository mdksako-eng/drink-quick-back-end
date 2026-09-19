// utils/plan_gate_logic.dart
// Pure decision logic for the post-login subscription gate (imports only the
// plain data model, so it stays unit-testable without a widget tree).
import '../models/subscription_model.dart';

/// What the app should show right after login.
enum PlanGateDecision {
  /// Keep waiting: the plan has not been resolved yet and nothing is recorded.
  waiting,

  /// Show the subscription screen (plans, prices, payment sheets).
  showPlans,

  /// Go straight into the app.
  proceed,
}

/// Identifies the plan state a "Continue on Free" choice was made for.
///
/// Storing this (instead of a plain boolean) is what makes the gate re-open
/// when the situation changes: a company that acknowledged the gate while on
/// `free` is prompted again once their paid plan has expired
/// (`starter:active` -> `starter:expired`), and a brand-new company never skips
/// the gate on someone else's acknowledgement.
String planSignature(SubscriptionInfo info) => '${info.plan}:${info.status}';

/// Storage key for the per-company acknowledgement. Company-scoped, so switching
/// companies re-shows the gate, while every user of a company on this device
/// shares the choice.
String planGateAckKey(int? companyId) => 'plan_gate_ack_$companyId';

/// Decides whether the subscription screen must be shown before the app.
///
/// Rules, in order:
///   1. An active plan (starter/pro with time left) -> straight in.
///   2. A recorded choice that still matches the current plan state -> straight
///      in. This also means a returning user is never blocked by a failed
///      network call (the gate does not wait for the refetch).
///   3. The plan has not been resolved yet -> keep the loader up.
///   4. Otherwise -> show the plans (first login, free plan, expired plan).
PlanGateDecision planGateDecision({
  required bool hasLoaded,
  required bool planActive,
  required String signature,
  required String? ackSignature,
}) {
  if (planActive) return PlanGateDecision.proceed;
  if (ackSignature != null && ackSignature == signature) {
    return PlanGateDecision.proceed;
  }
  if (!hasLoaded) return PlanGateDecision.waiting;
  return PlanGateDecision.showPlans;
}