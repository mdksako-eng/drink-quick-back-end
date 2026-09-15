// widgets/upgrade_required.dart
// Full-screen placeholder shown when a premium feature is opened without an
// adequate subscription plan.
import 'package:flutter/material.dart';
import '../screens/subscription_screen.dart';
import '../utils/i18n.dart';

class UpgradeRequiredView extends StatelessWidget {
  const UpgradeRequiredView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('upgradeRequired'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.workspace_premium,
                  size: 72, color: Colors.orange),
              const SizedBox(height: 16),
              Text(t('upgradeRequired'),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(t('upgradeRequiredBody'), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SubscriptionScreen())),
                icon: const Icon(Icons.upgrade),
                label: Text(t('upgradeTo')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
