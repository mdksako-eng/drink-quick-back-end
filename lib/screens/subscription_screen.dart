// screens/subscription_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/subscription_model.dart';
import '../providers/plan_provider.dart';
import '../utils/i18n.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({Key? key}) : super(key: key);

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlanProvider>().refresh();
    });
  }

  Future<void> _upgrade(String plan) async {
    final provider = context.read<PlanProvider>();
    setState(() => _busy = true);
    try {
      final result = await provider.initiate(plan);
      if (!mounted) return;

      final checkoutUrl = result?['checkoutUrl'] as String?;
      if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
        final uri = Uri.parse(checkoutUrl);
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok) await launchUrl(uri);

        // Poll for activation (the webhook activates it server-side).
        for (var i = 0; i < 6; i++) {
          await Future.delayed(const Duration(seconds: 3));
          if (!mounted) return;
          await provider.refresh();
          if (provider.info.isActive) {
            _showSnack(t('subscriptionActive'));
            return;
          }
        }
        _showSnack(t('payThenRefresh'));
      } else {
        _showSnack(t('payNotConfigured'));
      }
    } catch (e) {
      _showSnack('${t('error')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _momoPay(String plan, String provider) async {
    final phone = await _promptPhone(provider);
    if (phone == null || phone.isEmpty) return;

    final planProvider = context.read<PlanProvider>();
    setState(() => _busy = true);
    try {
      final data = await planProvider.momoInitiate(
        plan: plan,
        provider: provider,
        customerPhone: phone,
      );
      if (!mounted) return;
      if (data == null) {
        _showSnack(t('payNotConfigured'));
        return;
      }

      final reference = data['reference']?.toString() ?? '';
      final amount = data['amount']?.toString() ?? '';
      final currency = data['currency']?.toString() ?? 'XAF';
      final merchantPhone = data['merchantPhone']?.toString() ?? '';
      final auto = data['auto'] == true;
      final paymentUrl = data['paymentUrl']?.toString() ?? '';

      if (paymentUrl.isNotEmpty) {
        // Orange Money web payment: open the hosted checkout page, then poll
        // for activation (the webhook activates it server-side).
        final uri = Uri.parse(paymentUrl);
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok) await launchUrl(uri);
        await _autoVerifyPlan(planProvider);
      } else if (auto) {
        // Automatic verification via the MTN MoMo collection API.
        await _autoVerify(planProvider, reference);
      } else {
        // Manual confirmation fallback.
        final confirmed =
            await _promptConfirm(provider, amount, currency, merchantPhone);
        if (!confirmed || !mounted) return;

        final ok =
            await planProvider.momoConfirm(reference: reference, plan: plan);
        if (!mounted) return;
        _showSnack(ok ? t('subscriptionActive') : t('error'));
      }
    } catch (e) {
      if (mounted) _showSnack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _autoVerify(PlanProvider planProvider, String reference) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text(t('waitingForPayment'))),
        ]),
      ),
    );

    for (var i = 0; i < 12; i++) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;

      final status = await planProvider.momoStatus(reference: reference);
      if (status == null) continue;

      if (status['active'] == true) {
        if (mounted) Navigator.of(context).pop();
        if (mounted) _showSnack(t('subscriptionActive'));
        return;
      }
      if (status['status'] == 'failed') {
        if (mounted) Navigator.of(context).pop();
        if (mounted) _showSnack(t('error'));
        return;
      }
    }

    if (mounted) Navigator.of(context).pop();
    if (mounted) _showSnack(t('payThenRefresh'));
  }

  Future<void> _autoVerifyPlan(PlanProvider planProvider) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text(t('waitingForPayment'))),
        ]),
      ),
    );

    for (var i = 0; i < 12; i++) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      await planProvider.refresh();
      if (planProvider.info.isActive) {
        if (mounted) Navigator.of(context).pop();
        if (mounted) _showSnack(t('subscriptionActive'));
        return;
      }
    }

    if (mounted) Navigator.of(context).pop();
    if (mounted) _showSnack(t('payThenRefresh'));
  }

  Future<String?> _promptPhone(String provider) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(provider == 'mtn' ? t('payWithMomo') : t('payWithOrange')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(hintText: t('enterPhone')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(t('sendPayment')),
          ),
        ],
      ),
    );
  }

  Future<bool> _promptConfirm(
      String provider, String amount, String currency, String merchantPhone) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(provider == 'mtn' ? t('payWithMomo') : t('payWithOrange')),
        content: Text('${t('payToMerchant')} $merchantPhone\n$amount $currency'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('confirmPayment')),
          ),
        ],
      ),
    ).then((v) => v ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlanProvider>();
    final info = provider.info;

    return Scaffold(
      appBar: AppBar(title: Text(t('subscription'))),
      body: RefreshIndicator(
        onRefresh: provider.refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _currentPlanCard(info),
            const SizedBox(height: 28),
            Text(t('choosePlan'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _planCard('free', t('free'), 0, [
              t('calcFree1'),
              t('calcFree2'),
              t('calcFree3'),
            ], Icons.calculate_outlined),
            _planCard('starter', t('starter'), 1, [
              t('starterFeature1'),
              t('starterFeature2'),
            ], Icons.people_outline),
            _planCard('pro', t('pro'), 2, [
              t('proFeature1'),
              t('proFeature2'),
              t('proFeature3'),
              t('proFeature4'),
            ], Icons.workspace_premium),
          ],
        ),
      ),
    );
  }

  Widget _currentPlanCard(SubscriptionInfo info) {
    final primary = Theme.of(context).colorScheme.primary;
    final isActive = info.isActive;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withValues(alpha: 0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: Colors.white, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${t('currentPlan')}: ${_planLabel(info.plan)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isActive ? t('subscriptionActive') : t('subscriptionExpired'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (info.expiresAt != null) ...[
            const SizedBox(height: 8),
            Text(
              '${t('expiresOn')}: ${info.expiresAt.toString().split(' ').first}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _planLabel(String plan) {
    switch (plan) {
      case 'pro':
        return t('pro');
      case 'starter':
        return t('starter');
      default:
        return t('free');
    }
  }

  Widget _planCard(
      String plan, String title, int rank, List<String> features, IconData icon) {
    final provider = context.watch<PlanProvider>();
    final isCurrent = provider.plan == plan;
    final isPro = plan == 'pro';
    final canUpgrade = plan != 'free' && !isCurrent;
    final price = provider.priceLabel(plan);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPro ? primary : Colors.grey.withValues(alpha: 0.2),
          width: isPro ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(t('currentPlan'),
                        style:
                            const TextStyle(color: Colors.green, fontSize: 11)),
                  ),
              ],
            ),
            if (price.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(price,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: primary)),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(t('perMonth'),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            ...features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: primary),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(f, style: const TextStyle(fontSize: 14))),
                    ],
                  ),
                )),
            if (canUpgrade) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _upgrade(plan),
                  icon: const Icon(Icons.credit_card),
                  label: Text(t('payByCard')),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _momoPay(plan, 'mtn'),
                    icon: const Icon(Icons.phone_android, size: 18),
                    label: Text(t('payWithMomo'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _momoPay(plan, 'orange'),
                    icon: const Icon(Icons.phone_android, size: 18),
                    label: Text(t('payWithOrange'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
