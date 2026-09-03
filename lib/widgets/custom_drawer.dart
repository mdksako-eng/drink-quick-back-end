// widgets/custom_drawer.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/screens/calculator_screen.dart';
import 'package:drinks_calculator_fixed/screens/drink_management_screen.dart';
import 'package:drinks_calculator_fixed/screens/storage_settings_screen.dart';
import 'package:drinks_calculator_fixed/screens/admin_panel.dart';
import 'package:drinks_calculator_fixed/screens/manager_panel.dart';
import 'package:drinks_calculator_fixed/screens/ai_assistant_screen.dart';
import 'package:drinks_calculator_fixed/screens/auth_screen.dart';
import 'package:drinks_calculator_fixed/screens/inventory_screen.dart';
import 'package:drinks_calculator_fixed/providers/sync_provider.dart';
import 'package:drinks_calculator_fixed/screens/manager_approval_screen.dart';
import 'package:drinks_calculator_fixed/services/supabase_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../widgets/badge_icon.dart';

class CustomDrawer extends StatelessWidget {
  final VoidCallback? onInvoiceHistoryTap;
  final VoidCallback? onCloseDrawer;

  const CustomDrawer({
    super.key,
    this.onInvoiceHistoryTap,
    this.onCloseDrawer,
  });

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;
    final isAdmin = authProvider.isAdmin;
    final role = user?.role?.toLowerCase() ?? '';
    final isManager = role == 'manager';
    final isStaff = role == 'staff';
    final isCustomer = role == 'customer';

    // Admin, Manager, Customer can manage drinks
    final canManageDrinks = isAdmin || isManager || isCustomer;

    // Everyone can manage settings
    final canManageSettings = isAdmin || isManager || isStaff || isCustomer;

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
            padding:
                const EdgeInsets.only(top: 48, bottom: 24, left: 20, right: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [primaryColor, primaryColor.withValues(alpha: 0.7)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // CircleAvatar
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    child:
                        Icon(Icons.local_drink, size: 36, color: primaryColor),
                  ),
                ),
                const SizedBox(height: 16),
                Text(user?.username ?? 'User',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                // Role and email row
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isAdmin
                          ? Colors.amber
                          : isManager
                              ? Colors.orange
                              : isStaff
                                  ? Colors.blue
                                  : Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(user?.role ?? 'Customer',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isAdmin ? Colors.black87 : Colors.white)),
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.workspace_premium,
                              size: 12, color: Colors.black87),
                          SizedBox(width: 3),
                          Text('Owner',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  const Icon(Icons.email_outlined,
                      size: 12, color: Colors.white70),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(user?.email ?? 'No email',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color.fromRGBO(255, 255, 255, 0.702)),
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
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(30),
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
                                  _getSyncStatusText(syncProvider.status),
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
                                    const SnackBar(
                                      content: Text('Manual sync started...'),
                                      duration: Duration(seconds: 2),
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

          // Menu Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 8),

                // ========== MAIN SECTION ==========
                _buildDrawerSectionTitle(context, 'MAIN'),

                _buildDrawerItem(context, Icons.dashboard, 'Dashboard', () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const CalculatorScreen()));
                }, isActive: true, primaryColor: primaryColor),

                _buildDrawerItem(context, Icons.history, 'Invoice History', () {
                  Navigator.pop(context);
                  if (onInvoiceHistoryTap != null) onInvoiceHistoryTap!();
                }, primaryColor: primaryColor),

                _buildDrawerItem(context, Icons.assistant, 'AI Assistant', () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const AIAssistantScreen()));
                }, primaryColor: primaryColor),

                // ========== MANAGEMENT SECTION ==========
                Divider(
                    height: 16,
                    thickness: 1,
                    indent: 16,
                    endIndent: 16,
                    color: theme.dividerColor),
                _buildDrawerSectionTitle(context, 'MANAGEMENT'),

                // Manage Drinks (Admin, Manager, Customer)
                if (canManageDrinks)
                  _buildDrawerItem(context, Icons.local_drink, 'Manage Drinks',
                      () {
                    Navigator.pop(context);
                    _showPasswordDialog(context);
                  }, primaryColor: primaryColor),
                // Inventory (Admin, Manager, Customer)
                if (canManageDrinks)
                  _buildDrawerItem(context, Icons.inventory, 'Inventory', () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const InventoryScreen()));
                  }, primaryColor: primaryColor),
                // Settings (Everyone)
                if (canManageSettings)
                  _buildDrawerItem(context, Icons.settings, 'Settings', () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                const StorageSettingsScreen()));
                  }, primaryColor: primaryColor),

                // ========== MANAGER SECTION ==========
                if (isManager) ...[
                  Divider(
                      height: 16,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                      color: theme.dividerColor),
                  _buildDrawerSectionTitle(context, 'MANAGER',
                      color: Colors.orange),
                  _buildDrawerItem(context, Icons.business, 'Staff Management',
                      () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ManagerPanel()));
                  }, iconColor: Colors.orange, primaryColor: primaryColor),
                  if (isManager || isAdmin)
                    _buildDrawerItem(
                      context,
                      Icons.verified,
                      'Login Approvals',
                      () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ManagerApprovalScreen(),
                          ),
                        );
                      },
                      iconColor: Colors.orange,
                      primaryColor: primaryColor,
                      badgeCount: Provider.of<AuthProvider>(context)
                          .pendingApprovalsCount,
                    ),
                ],

                // ========== ADMIN SECTION ==========
                if (isAdmin) ...[
                  Divider(
                      height: 16,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                      color: theme.dividerColor),
                  _buildDrawerSectionTitle(context, 'ADMIN',
                      color: Colors.purple),
                  _buildDrawerItem(
                      context, Icons.admin_panel_settings, 'Admin Panel', () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const AdminPanel()));
                  }, iconColor: Colors.purple, primaryColor: primaryColor),
                ],

                Divider(
                    height: 16,
                    thickness: 1,
                    indent: 16,
                    endIndent: 16,
                    color: theme.dividerColor),

                // ========== SUPPORT SECTION ==========
                _buildDrawerSectionTitle(context, 'SUPPORT'),

                _buildDrawerItem(context, Icons.info_outline, 'About', () {
                  _showAboutDialog(context);
                }, primaryColor: primaryColor),
                _buildDrawerItem(context, Icons.help_outline, 'Help & Support',
                    () {
                  _showHelpDialog(context);
                }, primaryColor: primaryColor),
              ],
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _openUrl(ApiConfig.privacyPolicy),
                      child: const Text('Privacy Policy',
                          style: TextStyle(fontSize: 12)),
                    ),
                    Text('|', style: TextStyle(color: theme.hintColor)),
                    TextButton(
                      onPressed: () => _openUrl(ApiConfig.termsOfService),
                      child: const Text('Terms',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Version 1.1.0',
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

  Widget _buildDrawerSectionTitle(BuildContext context, String title,
      {Color? color}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      child: Text(title,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: color ?? theme.hintColor)),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool isActive = false,
    Color? iconColor,
    required Color primaryColor,
    int badgeCount = 0,
  }) {
    final theme = Theme.of(context);
    final isSelected = isActive;
    final iconColorFinal =
        isSelected ? primaryColor : iconColor ?? theme.hintColor;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? primaryColor.withValues(alpha: 0.1) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: BadgeIcon(
          icon: icon,
          count: badgeCount,
          iconColor: iconColorFinal,
          iconSize: 22,
          badgeColor: Colors.red,
          textColor: Colors.white,
        ),
        title: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? primaryColor
                    : theme.textTheme.bodyLarge?.color,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
            if (badgeCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : badgeCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        trailing: isSelected
            ? Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              )
            : null,
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        label: const Text('Logout',
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
          Text('Confirm Logout',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color)),
        ]),
        content: Text('Are you sure you want to logout?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: theme.hintColor)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
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
            child: const Text('Logout'),
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
            Text('Password Required',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyLarge?.color)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Enter your password to access drink management:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: theme.hintColor)),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: obscureText,
              decoration: InputDecoration(
                hintText: 'Enter password',
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
                child: const Text('Cancel')),
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Incorrect password!'),
                      backgroundColor: Colors.red));
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('Verify'),
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
          Text('About Drink Quick',
              style: TextStyle(color: theme.textTheme.bodyLarge?.color))
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Professional Drink Calculator & Management System',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: theme.textTheme.bodyLarge?.color)),
              const SizedBox(height: 12),
              Text('• Quick drink selection and ordering',
                  style: TextStyle(color: theme.hintColor)),
              Text('• Invoice generation with PDF support',
                  style: TextStyle(color: theme.hintColor)),
              Text('• Offline data storage',
                  style: TextStyle(color: theme.hintColor)),
              Text('• Cloud sync capabilities',
                  style: TextStyle(color: theme.hintColor)),
              Text('• AI-powered drink assistant',
                  style: TextStyle(color: theme.hintColor)),
              const SizedBox(height: 16),
              Text('Version: 1.1.0',
                  style: TextStyle(fontSize: 12, color: theme.hintColor)),
              Text('© 2026 Drink Quick Cal',
                  style: TextStyle(fontSize: 12, color: theme.hintColor)),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
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
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.business, color: Colors.grey, size: 14),
                SizedBox(width: 6),
                Text(
                  'No Company',
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
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.business, color: Colors.grey, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'No Company',
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
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.business, color: Colors.grey, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'No Company',
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
          Text('Help & Support',
              style: TextStyle(color: theme.textTheme.bodyLarge?.color))
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quick Tips:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.bodyLarge?.color)),
              const SizedBox(height: 8),
              Text('• Select drinks from dropdown and add to order',
                  style: TextStyle(color: theme.hintColor)),
              Text('• Enter amount received to calculate change',
                  style: TextStyle(color: theme.hintColor)),
              Text('• Tap History to view past invoices',
                  style: TextStyle(color: theme.hintColor)),
              Text('• Use AI Assistant for recommendations',
                  style: TextStyle(color: theme.hintColor)),
              Text('• Manage drinks from Settings',
                  style: TextStyle(color: theme.hintColor)),
              const SizedBox(height: 16),
              Text('For support, contact: mbundaderick@gmail.com',
                  style: TextStyle(fontSize: 12, color: theme.hintColor)),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'))
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

  String _getSyncStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.success:
        return 'Synced';
      case SyncStatus.error:
        return 'Sync failed';
      case SyncStatus.offline:
        return 'Offline';
      case SyncStatus.idle:
        return 'Cloud ready';
    }
  }

  String _formatTimeAgo(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
