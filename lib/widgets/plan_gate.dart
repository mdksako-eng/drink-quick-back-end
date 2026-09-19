// widgets/plan_gate.dart
// Subscription gate: right after login the user lands on the subscription
// screen — before the rest of the app loads — so every screen is judged against
// a plan that has actually been resolved. "Continue on Free" is always offered,
// and choosing it is remembered per company so the gate does not nag on every
// launch (it comes back if a paid plan later lapses).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../providers/plan_provider.dart';
import '../screens/subscription_screen.dart';
import '../utils/plan_gate_logic.dart';

class PlanGate extends StatefulWidget {
  /// The app itself — only built once the plan is resolved (or acknowledged).
  final Widget child;

  const PlanGate({super.key, required this.child});

  @override
  State<PlanGate> createState() => _PlanGateState();
}

class _PlanGateState extends State<PlanGate> {
  PlanGateDecision _decision = PlanGateDecision.waiting;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Resolve after the first frame so the gate never calls notifyListeners()
    // during the parent's build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  int? get _companyId {
    try {
      return Provider.of<AuthProvider>(context, listen: false).user?.companyId;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readAck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(planGateAckKey(_companyId));
    } catch (_) {
      return null;
    }
  }

  Future<void> _resolve() async {
    if (_started || !mounted) return;
    _started = true;

    final plan = Provider.of<PlanProvider>(context, listen: false);
    String? ack = await _readAck();

    // A returning user who already chose a plan state is let straight through,
    // so a failed/slow fetch can never lock them out of the app.
    var decision = planGateDecision(
      hasLoaded: plan.hasLoaded,
      planActive: plan.info.isActive,
      signature: planSignature(plan.info),
      ackSignature: ack,
    );

    if (decision == PlanGateDecision.waiting) {
      await plan.refresh();
      ack = await _readAck();
      decision = planGateDecision(
        hasLoaded: plan.hasLoaded,
        planActive: plan.info.isActive,
        signature: planSignature(plan.info),
        ackSignature: ack,
      );
      // Still unresolved (offline and nothing recorded): let the user in rather
      // than trapping them on a spinner they cannot dismiss.
      if (decision == PlanGateDecision.waiting) {
        decision = PlanGateDecision.proceed;
      }
    }

    if (!mounted) return;
    setState(() => _decision = decision);
  }

  Future<void> _rememberFreeChoice() async {
    try {
      final info = Provider.of<PlanProvider>(context, listen: false).info;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(planGateAckKey(_companyId), planSignature(info));
    } catch (_) {}
  }

  Future<void> _continueFree() async {
    await _rememberFreeChoice();
    if (!mounted) return;
    setState(() => _decision = PlanGateDecision.proceed);
  }

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanProvider>();

    // A payment finished while the gate was open -> continue automatically.
    if (_decision == PlanGateDecision.showPlans && plan.info.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _decision == PlanGateDecision.showPlans) {
          setState(() => _decision = PlanGateDecision.proceed);
        }
      });
    }

    switch (_decision) {
      case PlanGateDecision.waiting:
        return const _PlanGateLoading();
      case PlanGateDecision.showPlans:
        return SubscriptionScreen(
          gate: true,
          onContinueFree: _continueFree,
        );
      case PlanGateDecision.proceed:
        return widget.child;
    }
  }
}

/// Branded loader shown while the plan is being resolved.
class _PlanGateLoading extends StatelessWidget {
  const _PlanGateLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
              SizedBox(height: 20),
              Text('Drinks Quick Cal',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}