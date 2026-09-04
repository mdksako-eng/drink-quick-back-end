import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';

/// Shows a one-time Terms & Privacy Policy consent dialog before the app
/// can be used. The user's acceptance is stored locally so they only see
/// it once (unless the consent version is bumped).
class LegalConsentGate extends StatefulWidget {
  final Widget child;
  const LegalConsentGate({super.key, required this.child});

  @override
  State<LegalConsentGate> createState() => _LegalConsentGateState();
}

class _LegalConsentGateState extends State<LegalConsentGate> {
  static const String _consentKey = 'legal_consent_accepted_v1';
  bool? _accepted;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _accepted = p.getBool(_consentKey) ?? false);
    });
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_consentKey, true);
    if (mounted) setState(() => _accepted = true);
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Unknown yet -> show child briefly then gate (avoids flash of dialog
    // for users who already accepted).
    if (_accepted == null || _accepted == true) return widget.child;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.verified_user_outlined,
                          size: 48, color: Color(0xFF667EEA)),
                      const SizedBox(height: 16),
                      const Text('Before you continue',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const Text(
                        'To use Drink Quick Cal you must review and accept '
                        'our Terms of Service and Privacy Policy, which '
                        'explain how your account, business and '
                        'transaction data are collected, stored and used.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => _open(ApiConfig.termsOfService),
                            child: const Text('View Terms'),
                          ),
                          TextButton(
                            onPressed: () => _open(ApiConfig.privacyPolicy),
                            child: const Text('View Privacy Policy'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _busy ? null : _accept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF667EEA),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle_outline),
                        label: const Text('I Accept'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
