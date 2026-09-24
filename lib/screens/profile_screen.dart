// screens/profile_screen.dart
// Role-aware profile: what a user sees here depends on whether they are a
// customer, staff, manager (co-manager or owner) or a platform administrator.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../providers/drink_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/order_provider.dart';
import '../services/company_branding_service.dart';
import '../services/secure_storage_service.dart';
import '../utils/helpers.dart';
import '../utils/i18n.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _companyName;
  String? _logoUrl;
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Read the providers before any await so no BuildContext is used across an
    // async gap (and the values cannot change mid-load).
    final user = context.read<AuthProvider>().user;
    final prefs = await SharedPreferences.getInstance();
    final logo = await CompanyBrandingService.load();
    final hasPin = user?.id != null
        ? await SecureStorageService.hasPin(userId: user!.id)
        : await SecureStorageService.hasPin();
    if (!mounted) return;
    setState(() {
      _companyName = prefs.getString('company_name');
      _logoUrl = logo;
      _hasPin = hasPin;
    });
  }

  /// Personalises the profile per role — the access card is the honest summary
  /// of what each role can actually do in the app.
  String _accessHint(String role, bool isOwner) {
    if (role == 'administrator' || role == 'admin') {
      return t('profileAdminHint');
    }
    if (role == 'manager') {
      return isOwner ? t('profileOwnerHint') : t('profileManagerHint');
    }
    if (role == 'staff') return t('profileStaffHint');
    return t('profileCustomerHint');
  }

  String _roleLabel(String role, bool isOwner) {
    if (role == 'manager') {
      return isOwner ? t('profileOwner') : t('role_Manager');
    }
    if (role == 'administrator' || role == 'admin') return t('role_Admin');
    if (role == 'staff') return t('role_Staff');
    if (role == 'customer') return t('role_Customer');
    return role.isEmpty ? t('profileRole') : role;
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'[\s._-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final first = parts.first;
      return first.substring(0, first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  /// 🔒 Asks for the password used to sign in on this device and returns true
  /// only when it verifies against the account currently logged in.
  Future<bool> _confirmDevicePassword() async {
    final auth = context.read<AuthProvider>();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final verified = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('profilePin')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('enterLoginPassword'),
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(labelText: t('password')),
                validator: (v) =>
                    (v ?? '').isEmpty ? t('passwordRequired') : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, auth.verifyPassword(passwordController.text));
              }
            },
            child: Text(t('verify')),
          ),
        ],
      ),
    );

    passwordController.dispose();
    if (verified == false && mounted) {
      Helpers.showToast(t('incorrectPassword'), isError: true);
    }
    return verified == true;
  }

  Future<void> _changePin(String userId) async {
    // 🔒 A new PIN takes over the lock screen, so prove it is the account owner
    // first: the device login password is required before the PIN can change.
    if (!await _confirmDevicePassword()) return;
    if (!mounted) return;

    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('profilePin')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: t('pin'),
                  counterText: '',
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.length < 4) return t('pinTooShort');
                  return null;
                },
              ),
              TextFormField(
                controller: confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: t('confirmPassword'),
                  counterText: '',
                ),
                validator: (v) {
                  if ((v ?? '').trim() != pinController.text.trim()) {
                    return t('auth_passwordsNoMatch');
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(t('save')),
          ),
        ],
      ),
    );

    pinController.dispose();
    confirmController.dispose();
    if (saved != true) return;

    await SecureStorageService.savePin(
      pinController.text.trim(),
      userId: userId,
    );
    if (mounted) {
      setState(() => _hasPin = true);
      Helpers.showToast(t('pinSaved'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final primary = theme.primaryColor;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t('profile')),
          backgroundColor: primary,
          foregroundColor: Colors.white,
        ),
        body: Center(child: Text(t('profile'))),
      );
    }

    final role = user.role.toLowerCase();
    final isOwner = user.isOwner;
    final isCustomer = role == 'customer';
    final isManager = role == 'manager';
    final isAdmin = role == 'administrator' || role == 'admin';

    // Company data is only meaningful for company users; a customer sees their
    // own device activity instead of the shop's catalogue.
    final drinkProvider = context.watch<DrinkProvider>();
    final inventoryProvider = context.watch<InventoryProvider>();
    final orderCount = context.watch<OrderProvider>().getTodaysOrders().length;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('profile')),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _headerCard(theme, primary, user.username, role, isOwner),
          const SizedBox(height: 14),
          _accessCard(theme, primary, _accessHint(role, isOwner)),
          const SizedBox(height: 14),
          _detailsCard(
            theme,
            primary,
            username: user.username,
            email: user.email,
            roleLabel: _roleLabel(role, isOwner),
            emailVerified: user.emailVerified,
            showCompany: !isCustomer,
            userId: user.id,
          ),
          const SizedBox(height: 14),
          _activityCard(
            theme,
            primary,
            showCompanyStats: !isCustomer,
            drinks: isCustomer ? null : drinkProvider.allDrinks.length,
            stockItems: isCustomer ? null : inventoryProvider.inventoryItems.length,
            lowStock: isCustomer ? null : inventoryProvider.lowStockCount,
            orders: orderCount,
            canSeeStaff: isManager || isAdmin,
          ),
          const SizedBox(height: 14),
          _securityCard(theme, primary, user.id, isCustomer: isCustomer),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, size: 20),
              label: Text(t('logout')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('logout')),
        content: Text(t('confirmLogout')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('logout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  Widget _headerCard(
    ThemeData theme,
    Color primary,
    String username,
    String role,
    bool isOwner,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final logo = _logoUrl;
    return Card(
      elevation: 2,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: (logo != null && logo.isNotEmpty)
                  ? Image.network(
                      logo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _initialsAvatar(primary),
                    )
                  : _initialsAvatar(primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _roleLabel(role, isOwner),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: primary),
                        ),
                      ),
                      if (isOwner)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified_user,
                                  size: 13, color: Colors.amber),
                              const SizedBox(width: 4),
                              Text(
                                t('profileOwner'),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.amber.shade200
                                        : Colors.amber.shade900),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accessCard(ThemeData theme, Color primary, String hint) {
    return Card(
      elevation: 1,
      color: primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 20, color: primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('profileAccess'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.hintColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value,
      {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: theme.hintColor,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 6,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodyLarge?.color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  trailing,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Company details are only shown to company users; a customer sees just
  /// their own account.
  Widget _detailsCard(
    ThemeData theme,
    Color primary, {
    required String username,
    required String email,
    required String roleLabel,
    required bool emailVerified,
    required bool showCompany,
    required String userId,
  }) {
    return Card(
      elevation: 1,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(theme, Icons.badge_outlined, t('profileAccount')),
            const SizedBox(height: 6),
            _infoRow(theme, t('username'), username),
            _infoRow(theme, t('email'), email,
                trailing: Icon(
                  emailVerified ? Icons.verified : Icons.error_outline,
                  size: 16,
                  color: emailVerified ? Colors.green : Colors.orange,
                )),
            _infoRow(theme, t('profileRole'), roleLabel),
            // The ID shown here is the signed-in user's account id (the one
            // support, approvals and the backend use) — not the company id.
            _infoRow(theme, t('profileUserId'), userId.isEmpty ? '-' : userId),
            if (showCompany)
              _infoRow(theme, t('profileCompany'),
                  (_companyName == null || _companyName!.isEmpty)
                      ? '-'
                      : _companyName!),
            const SizedBox(height: 4),
            Text(
              emailVerified
                  ? t('profileEmailVerified')
                  : t('profileEmailPending'),
              style: TextStyle(
                fontSize: 12,
                color: emailVerified ? Colors.green : Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initialsAvatar(Color primary) {
    return Center(
      child: Text(
        _initials(context.read<AuthProvider>().user?.username ?? ''),
        style: TextStyle(
            fontWeight: FontWeight.bold, fontSize: 20, color: primary),
      ),
    );
  }

  Widget _statTile(ThemeData theme, Color primary, IconData icon, String label,
      int? value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: primary),
          const SizedBox(height: 6),
          Text(
            value == null ? '-' : value.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  Widget _activityCard(
    ThemeData theme,
    Color primary, {
    required bool showCompanyStats,
    required int? drinks,
    required int? stockItems,
    required int? lowStock,
    required int orders,
    required bool canSeeStaff,
  }) {
    return Card(
      elevation: 1,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(theme, Icons.insights_outlined, t('profileActivity')),
            const SizedBox(height: 14),
            Row(
              children: [
                _statTile(theme, primary, Icons.receipt_long_outlined,
                    t('profileOrders'), orders),
                if (showCompanyStats) ...[
                  _statTile(theme, primary, Icons.local_bar_outlined,
                      t('profileDrinks'), drinks),
                  _statTile(theme, primary, Icons.inventory_2_outlined,
                      t('profileStock'), stockItems),
                ],
              ],
            ),
            if (showCompanyStats && lowStock != null && lowStock > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${t('lowStock')}: $lowStock',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ],
            if (canSeeStaff) ...[
              const SizedBox(height: 12),
              Text(
                t('profileStaffHint'),
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _securityCard(ThemeData theme, Color primary, String userId,
      {required bool isCustomer}) {
    return Card(
      elevation: 1,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(theme, Icons.lock_outline, t('profileSecurity')),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(_hasPin ? Icons.lock : Icons.lock_open,
                    size: 16, color: theme.hintColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _hasPin ? t('pinSet') : t('pinNotSet'),
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.textTheme.bodyMedium?.color),
                  ),
                ),
                TextButton(
                  onPressed: () => _changePin(userId),
                  child: Text(t('profilePin')),
                ),
              ],
            ),
            if (isCustomer)
              Text(
                t('profileCustomerHint'),
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
          ],
        ),
      ),
    );
  }

}
