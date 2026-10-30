// widgets/custom_drawer.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/screens/calculator_screen.dart';
import 'package:drinks_calculator_fixed/screens/drink_management_screen.dart';
import 'package:drinks_calculator_fixed/screens/auth_screen.dart';
import 'package:drinks_calculator_fixed/providers/sync_provider.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';
import 'package:drinks_calculator_fixed/services/company_branding_service.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../utils/i18n.dart';
import '../utils/constants.dart';
import 'language_toggle.dart';
import '../utils/drawer_navigation.dart';
import '../utils/staff_permissions.dart';
import '../theme/app_theme.dart';
import 'drawer_menu.dart';

class CustomDrawer extends StatelessWidget {
  final VoidCallback? onInvoiceHistoryTap;
  final VoidCallback? onCloseDrawer;

  /// Which screen the drawer is open on top of. The menu derives its highlight
  /// from this instead of hardcoding one entry.
  final DrawerScreen currentScreen;

  const CustomDrawer({
    super.key,
    this.onInvoiceHistoryTap,
    this.onCloseDrawer,
    this.currentScreen = DrawerScreen.dashboard,
  });

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;
    // Roles are normalised in ONE place (utils/staff_permissions.dart). The database
    // stores 'Manager', several screens lower-case it, and mixing the two conventions
    // is how a badge or an entry silently disappears.
    final isManager = StaffPermissions.isManagerRole(user?.role);
    final isStaff = StaffPermissions.isStaffRole(user?.role);
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Drawer(
      width: 280,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
            topRight: Radius.circular(0), bottomRight: Radius.circular(0)),
      ),
      backgroundColor: theme.cardColor,
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(
                top: 48,
                bottom: AppSpace.xl,
                left: AppSpace.xl,
                right: AppSpace.xl),
            decoration: BoxDecoration(
              // The ONE brand surface (theme/app_theme.dart), shared with the auth
              // hero — instead of a gradient invented per screen.
              gradient: AppBrand.surface(primaryColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // CircleAvatar
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: AppShadow.soft(context),
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    // 🏢 The shop's own logo when it has one, otherwise the
                    // app's drink icon.
                    child: ClipOval(
                      child: FutureBuilder<String?>(
                        // load() reads the cache the login flow warmed and only
                        // goes to the server when nothing is cached yet, so the
                        // logo is there on the first drawer open.
                        future: CompanyBrandingService.load(),
                        builder: (context, snapshot) {
                          final logo = snapshot.data;
                          if (logo == null || logo.isEmpty) {
                            return Icon(Icons.local_drink,
                                size: 36, color: primaryColor);
                          }
                          return Image.network(
                            logo,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.local_drink,
                                size: 36,
                                color: primaryColor),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(user?.username ?? 'User',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppBrand.onSurface),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                // Role and email row
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppRoleBadge.background(user?.role),
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Text(user?.role ?? 'Customer',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppRoleBadge.foreground(user?.role))),
                  ),
                  // 👑 Owner badge — distinguishes the company founder from
                  // managers who joined later via the invite code
                  if (user?.isOwner ?? false) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.yellow.shade700,
                        borderRadius: AppRadius.pillAll,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.workspace_premium,
                              size: 12, color: Colors.black87),
                          const SizedBox(width: 3),
                          Text(t('owner'),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  const Icon(Icons.email_outlined,
                      size: 12, color: AppBrand.onSurfaceMuted),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(user?.email ?? t('noEmail'),
                          style: const TextStyle(
                              fontSize: 11, color: AppBrand.onSurfaceMuted),
                          overflow: TextOverflow.ellipsis)),
                ]),
                // ✅ ADD COMPANY NAME (for Managers and Staff)
                if (isManager || isStaff) ...[
                  const SizedBox(height: 8),
                  _buildCompanyName(context),
                ],
                // ✅ ADD SYNC INDICATOR HERE (inside the Column, after the Row)
                const SizedBox(height: 12),

                if (isManager || isStaff)
                  Consumer<SyncProvider>(
                    builder: (context, syncProvider, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppBrand.onSurface
                              .withValues(alpha: AppAlpha.medium),
                          borderRadius: AppRadius.pillAll,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSyncIcon(syncProvider.status),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _getSyncStatusText(syncProvider),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (syncProvider.lastSyncTime != null)
                                  Text(
                                    _formatTimeAgo(syncProvider.lastSyncTime!),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            if (syncProvider.status == SyncStatus.error ||
                                syncProvider.status == SyncStatus.offline)
                              GestureDetector(
                                onTap: () {
                                  syncProvider.manualSync();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(t('syncStarted')),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.refresh,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ), // ✅ This closes the Container

          // Menu Items — grouped, searchable and honest about where you are.
          // The grouping rule and the filter live in utils/drawer_navigation.dart.
          Expanded(
            child: DrawerMenu(
              currentScreen: currentScreen,
              primaryColor: primaryColor,
              onDashboardTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const CalculatorScreen()));
              },
              onDrinkManagementTap: () {
                Navigator.pop(context);
                _showPasswordDialog(context);
              },
              onInvoiceHistoryTap: onInvoiceHistoryTap,
              onAboutTap: () => _showAboutDialog(context),
              onHelpTap: () => _showHelpDialog(context),
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor))),
            child: Column(
              children: [
                _buildLogoutButton(context, authProvider, primaryColor),
                const SizedBox(height: 12),
                // 🌐 Language toggle (EN/FR) — rebuilds the whole app via
                // the ValueListenableBuilder around MaterialApp.
                const LanguageToggle(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _openUrl(ApiConfig.privacyPolicyForLanguage),
                      child: Text(t('privacyPolicy'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Text('|', style: TextStyle(color: theme.hintColor)),
                    TextButton(
                      onPressed: () => _openUrl(ApiConfig.termsOfServiceForLanguage),
                      child: Text(t('termsOfService'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${t('version')} ${AppConstants.appVersion}',
                    style: TextStyle(fontSize: 11, color: theme.hintColor)),
                const SizedBox(height: 4),
                Text('© 2026 Drink Quick Cal',
                    style: TextStyle(
                        fontSize: 10,
                        color: theme.hintColor.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(
      BuildContext context, AuthProvider authProvider, Color primaryColor) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _showLogoutDialog(context, authProvider),
        icon: const Icon(Icons.logout, size: 18, color: Colors.white),
        label: Text(t('logout'),
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade400,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthProvider authProvider) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: theme.cardColor,
        title: Column(children: [
          const Icon(Icons.logout, size: 48, color: Colors.red),
          const SizedBox(height: 10),
          Text(t('confirmLogoutDialog'),
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color)),
        ]),
        content: Text(t('areYouSureLogout'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: theme.hintColor)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('cancel'))),
          ElevatedButton(
            onPressed: () async {
              // ✅ Save navigator BEFORE popping anything
              final rootNavigator = Navigator.of(context, rootNavigator: true);

              // Close the dialog
              Navigator.pop(dialogContext);

              // Close the drawer (if open)
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
              rootNavigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthScreen()),
                (route) => false,
              );
              // Logout
              await authProvider.logout();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: Text(t('logout')),
          ),
        ],
      ),
    );
  }

  void _showPasswordDialog(BuildContext context) {
    final passwordController = TextEditingController();
    bool obscureText = true;
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: theme.cardColor,
          title: Column(children: [
            Icon(Icons.lock, size: 48, color: primaryColor),
            const SizedBox(height: 10),
            Text(t('passwordRequiredDialog'),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyLarge?.color)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t('enterPasswordAccess'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: theme.hintColor)),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: obscureText,
              decoration: InputDecoration(
                hintText: t('enterPasswordHint'),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: Icon(Icons.password, color: primaryColor),
                suffixIcon: IconButton(
                    icon: Icon(
                        obscureText ? Icons.visibility_off : Icons.visibility,
                        size: 20),
                    onPressed: () =>
                        setState(() => obscureText = !obscureText)),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('cancel'))),
            ElevatedButton(
              onPressed: () {
                final authProvider =
                    Provider.of<AuthProvider>(context, listen: false);
                if (authProvider.verifyPassword(passwordController.text)) {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const DrinkManagementScreen()));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(t('incorrectPassword')),
                      backgroundColor: Colors.red));
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text(t('verify')),
            ),
          ],
        ),
      ),
    );
  }

  // Opens an external URL (privacy policy / terms) in the system browser.
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri,
          mode: LaunchMode.externalApplication);
      if (!ok) {
        // fallback: try in-app
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('⚠️ Could not open URL $url: $e');
    }
  }

  void _showAboutDialog(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: theme.cardColor,
        title: Row(children: [
          Icon(Icons.local_drink, color: primaryColor),
          const SizedBox(width: 10),
          Text(t('aboutTitle'),
              style: TextStyle(color: theme.textTheme.bodyLarge?.color))
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('aboutDesc'),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: theme.textTheme.bodyLarge?.color)),
              const SizedBox(height: 12),
              Text(t('aboutQuickSelection'),
                  style: TextStyle(color: theme.hintColor)),
              Text(t('aboutInvoiceGen'),
                  style: TextStyle(color: theme.hintColor)),
              Text(t('aboutOfflineStorage'),
                  style: TextStyle(color: theme.hintColor)),
              Text(t('aboutCloudSync'),
                  style: TextStyle(color: theme.hintColor)),
              Text(t('aboutAIAssistant'),
                  style: TextStyle(color: theme.hintColor)),
              const SizedBox(height: 16),
              Text('${t('versionLabel')} ${AppConstants.appVersion}',
                  style: TextStyle(fontSize: 12, color: theme.hintColor)),
              Text('© 2026 Drink Quick Cal',
                  style: TextStyle(fontSize: 12, color: theme.hintColor)),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('close')))
        ],
      ),
    );
  }

  // ✅ Company Name Widget
  // widgets/custom_drawer.dart - Fixed _buildCompanyName()

  Widget _buildCompanyName(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final user = authProvider.currentUser;

        // ✅ If user is null, show nothing
        if (user == null) {
          return const SizedBox.shrink();
        }

        // ✅ 🔴🔴🔴 ONLY SHOW FOR MANAGERS AND STAFF
        final isManagerOrStaff = user.role == 'Manager' || user.role == 'Staff';
        if (!isManagerOrStaff) {
          return const SizedBox.shrink();
        }

        // ✅ If no company ID, show nothing
        if (user.companyId == null) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.business, color: Colors.grey, size: 14),
                SizedBox(width: 6),
                Text(
                  t('noCompany'),
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        // ✅ Force a new FutureBuilder when user changes
        return FutureBuilder<Map<String, dynamic>?>(
          key: ValueKey('company_${user.id}_${user.companyId}'),
          future: _getCompanyInfo(context),
          builder: (context, snapshot) {
            // Loading state
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
              );
            }

            // Error or no data
            if (snapshot.hasError || snapshot.data == null) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.business, color: Colors.grey, size: 14),
                    SizedBox(width: 6),
                    Text(
                      t('noCompany'),
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }

            // ✅ Success - Show company data
            final companyData = snapshot.data!;
            final companyName = companyData['name'] ?? '';
            final companyCode = companyData['code'] ?? '';
            final isManager = user.role == 'Manager';

            // Double-check we have a name
            if (companyName.isEmpty) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.business, color: Colors.grey, size: 14),
                    SizedBox(width: 6),
                    Text(
                      t('noCompany'),
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }

            // ✅ Display company with green background
            // ✅ Name shows for both Manager and Staff
            // ✅ Code shows ONLY for Manager
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.business, color: Colors.green, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      companyName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // ✅ 🔴🔴🔴 Company Code - ONLY for Managers
                  if (isManager && companyCode.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        companyCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

// ✅ Get company info from Supabase - Query all and filter locally
  Future<Map<String, dynamic>?> _getCompanyInfo(BuildContext context) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;

      // If user is null, return null immediately
      if (user == null) {
        print('⚠️ _getCompanyInfo: User is null');
        return null;
      }

      print(
          '🔍 _getCompanyInfo - User: ${user.username}, CompanyId: ${user.companyId}');

      if (user.companyId == null) {
        print('❌ User ${user.username} has no companyId');
        return null;
      }

      final companyId = user.companyId!;
      print('🔍 Fetching company $companyId for user ${user.username}...');

      // Check cache first
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'company_data_$companyId';
      final cachedJson = prefs.getString(cacheKey);

      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final cachedData = jsonDecode(cachedJson) as Map<String, dynamic>;
          print('✅ Using cached company: ${cachedData['name']}');
          return cachedData;
        } catch (e) {
          print('⚠️ Failed to parse cached company data: $e');
        }
      }

      // ✅ Fetch via the session-authenticated backend data API.
      // (Never query companies directly with the anon key — payment
      // secrets must not leave the server.)
      final cid = int.tryParse(companyId.toString());
      if (cid == null) {
        print('❌ Invalid company ID: $companyId');
        return null;
      }

      final company = await SupabaseService.getCompany(cid);

      if (company != null) {
        // Cache the company data
        await prefs.setString(cacheKey, jsonEncode(company));
        await prefs.setString(
            'company_name_$companyId', company['name'] ?? '');
        await prefs.setString(
            'company_code_$companyId', company['code'] ?? '');

        print('✅ Found company: ${company['name']} (ID: ${company['id']})');
        return company;
      } else {
        print('❌ Company ID $companyId not found via backend');
        return null;
      }
    } catch (e, stackTrace) {
      print('❌ Error fetching company info: $e');
      print('📚 Stack trace: $stackTrace');
      return null;
    }
  }

  void _showHelpDialog(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: theme.cardColor,
        title: Row(children: [
          Icon(Icons.help, color: primaryColor),
          const SizedBox(width: 10),
          Text(t('helpSupport'),
              style: TextStyle(color: theme.textTheme.bodyLarge?.color))
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('quickTips'),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.bodyLarge?.color)),
              const SizedBox(height: 8),
              Text(t('tipSelectDrinks'),
                  style: TextStyle(color: theme.hintColor)),
              Text(t('tipEnterAmount'),
                  style: TextStyle(color: theme.hintColor)),
              Text(t('tapHistory'),
                  style: TextStyle(color: theme.hintColor)),
              Text(t('useAIForRecs'),
                  style: TextStyle(color: theme.hintColor)),
              Text(t('manageDrinksSettings'),
                  style: TextStyle(color: theme.hintColor)),
              const SizedBox(height: 16),
              Text(t('supportContact'),
                  style: TextStyle(fontSize: 12, color: theme.hintColor)),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('gotIt')))
        ],
      ),
    );
  }

  Widget _buildSyncIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.syncing:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        );
      case SyncStatus.success:
        return const Icon(Icons.cloud_done, color: Colors.white, size: 16);
      case SyncStatus.error:
        return const Icon(Icons.cloud_off, color: Colors.white, size: 16);
      case SyncStatus.offline:
        return const Icon(Icons.wifi_off, color: Colors.white, size: 16);
      case SyncStatus.idle:
        return const Icon(Icons.cloud_queue, color: Colors.white70, size: 16);
    }
  }

  String _getSyncStatusText(SyncProvider provider) {
    switch (provider.status) {
      case SyncStatus.syncing:
        return t('syncSyncing');
      case SyncStatus.success:
        return t('syncSynced');
      case SyncStatus.error:
        return t('syncFailed');
      case SyncStatus.offline:
        return t('syncOffline');
      case SyncStatus.idle:
        // Honest idle state: nothing has been synchronised yet.
        if (!provider.isOnline) return t('syncOffline');
        if (!provider.hasSynced) return t('syncNotYet');
        return t('syncCloudReady');
    }
  }

  String _formatTimeAgo(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return t('justNow');
    if (diff.inMinutes < 60) return '${diff.inMinutes}${t('mAgo')}';
    if (diff.inHours < 24) return '${diff.inHours}${t('hAgo')}';
    return '${diff.inDays}${t('dAgo')}';
  }
}
