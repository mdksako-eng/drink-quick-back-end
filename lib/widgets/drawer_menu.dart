// widgets/drawer_menu.dart
// The navigable part of the drawer: a search box, then the entries grouped by what
// you are trying to do (see utils/drawer_navigation.dart for the rule).
//
// Its own widget because the drawer shell also holds the account header, the logout
// button and the legal links, which are not navigation. This also keeps the search
// state away from the shell.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/plan_provider.dart';
import '../screens/admin_panel.dart';
import '../screens/ai_assistant_screen.dart';
import '../screens/containers_screen.dart';
import '../screens/customer_ledger_screen.dart';
import '../screens/forecast_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/manager_approval_screen.dart';
import '../screens/manager_dashboard.dart';
import '../screens/manager_panel.dart';
import '../screens/profile_screen.dart';
import '../screens/purchasing_screen.dart';
import '../screens/scanner_screen.dart';
import '../screens/shift_screen.dart';
import '../screens/storage_settings_screen.dart';
import '../screens/subscription_screen.dart';
import '../screens/support_report_screen.dart';
import '../screens/variance_screen.dart';
import '../utils/drawer_navigation.dart';
import '../utils/i18n.dart';
import '../utils/staff_permissions.dart';
import 'badge_icon.dart';

class DrawerMenu extends StatefulWidget {
  const DrawerMenu({
    super.key,
    required this.currentScreen,
    required this.primaryColor,
    required this.onDashboardTap,
    required this.onDrinkManagementTap,
    required this.onAboutTap,
    required this.onHelpTap,
    this.onInvoiceHistoryTap,
  });

  /// Which screen the drawer is open on top of — the highlight is derived from
  /// this, so it cannot go stale.
  final DrawerScreen currentScreen;
  final Color primaryColor;

  /// "Go home": the calculator owns its own route, so the shell provides this
  /// instead of the menu importing the screen that contains it.
  final VoidCallback onDashboardTap;

  /// Managing the drinks catalogue asks for the password first (the shell owns
  /// that dialog).
  final VoidCallback onDrinkManagementTap;

  /// About / Help are dialogs the shell owns.
  final VoidCallback onAboutTap;
  final VoidCallback onHelpTap;

  /// The invoice history is a panel inside the calculator, not a route.
  final VoidCallback? onInvoiceHistoryTap;

  @override
  State<DrawerMenu> createState() => _DrawerMenuState();
}

class _DrawerMenuState extends State<DrawerMenu> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Every entry is filtered by the search box; a group with no visible entry is
  /// not rendered at all (see the build below).
  bool _shows(String label) => drawerSearchMatches(_query, label);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final role = authProvider.currentUser?.role;
    final isAdmin = StaffPermissions.isAdminRole(role);
    final isManager = StaffPermissions.isManagerRole(role);
    final isStaff = StaffPermissions.isStaffRole(role);
    final isCustomer = StaffPermissions.isCustomerRole(role);
    // Admin, Manager and Customer can manage drinks; everyone signed in can reach
    // the settings screen (staff included — they are the ones who set up a till).
    final canManageDrinks = isAdmin || isManager || isCustomer;
    final canManageSettings = isAdmin || isManager || isStaff || isCustomer;
    final theme = Theme.of(context);

    final groups = <DrawerGroup, List<Widget>>{
      DrawerGroup.daily: _dailyEntries(
        isAdmin: isAdmin,
        isManager: isManager,
        isStaff: isStaff,
        isCustomer: isCustomer,
      ),
      DrawerGroup.reports: _reportEntries(isAdmin: isAdmin, isManager: isManager),
      DrawerGroup.setup: _setupEntries(
        isAdmin: isAdmin,
        isManager: isManager,
        canManageDrinks: canManageDrinks,
        canManageSettings: canManageSettings,
      ),
      DrawerGroup.manager: _managerEntries(isManager: isManager),
      DrawerGroup.admin: _adminEntries(isAdmin: isAdmin),
      DrawerGroup.support: _supportEntries(),
    };

    final nothingMatches = groups.values.every((items) => items.isEmpty);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildSearchField(theme),
        if (nothingMatches) _buildNoResults(theme),
        for (final group in kDrawerGroupOrder)
          if ((groups[group] ?? const <Widget>[]).isNotEmpty) ...[
            _buildSectionTitle(context, t(drawerGroupLabelKey(group))),
            ...groups[group]!,
          ],
        const SizedBox(height: 8),
      ],
    );
  }

  /// On a 20-entry drawer, scrolling to "Variance" is the slowest part of using it.
  Widget _buildSearchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: t('clear'),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          hintText: t('drawerSearchHint'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildNoResults(ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(
          t('drawerNoResults'),
          style: TextStyle(fontSize: 13, color: theme.hintColor),
        ),
      );

  /// What you touch while serving.
  List<Widget> _dailyEntries({
    required bool isAdmin,
    required bool isManager,
    required bool isStaff,
    required bool isCustomer,
  }) =>
      [
        if (_shows(t('dashboard')))
          _buildItem(context, DrawerScreen.dashboard, Icons.dashboard,
              t('dashboard'), widget.onDashboardTap),
        if (_shows(t('profile')))
          _buildItem(context, DrawerScreen.profile, Icons.person_outline,
              t('profile'), () {
            Navigator.pop(context);
            Navigator.push(context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()));
          }),
        // Scan barcode/QR — a Pro feature. Managers/admins look up and manage
        // stock; staff send a scanned item straight to the calculator as an order.
        // Customers never see it.
        if ((isManager || isAdmin || isStaff) && _shows(t('scanMenu')))
          _buildItem(context, DrawerScreen.scan, Icons.qr_code_scanner,
              t('scanMenu'), () {
            Navigator.pop(context);
            _requireFeature(context, 'scanner', () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ScannerScreen()));
            });
          }),
        // 🕒 Shift / cash-up: the Z-report of this till.
        if (!isCustomer && _shows(t('shiftMenu')))
          _buildItem(context, DrawerScreen.shift, Icons.schedule,
              t('shiftMenu'), () {
            Navigator.pop(context);
            Navigator.push(context,
                MaterialPageRoute(builder: (context) => const ShiftScreen()));
          }),
        // 👥 Customer accounts ("customer numbers") — every staff member enrols,
        // the manager approves on the Approvals tab.
        if (!isCustomer && _shows(t('custMenu')))
          _buildItem(context, DrawerScreen.customers, Icons.people_outline,
              t('custMenu'), () {
            Navigator.pop(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const CustomerLedgerScreen()));
          }),
        // 🧺 Returnable containers: who is holding the shop's crates and bottles.
        if (!isCustomer && _shows(t('contMenu')))
          _buildItem(context, DrawerScreen.containers,
              Icons.inventory_2_outlined, t('contMenu'), () {
            Navigator.pop(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const ContainersScreen()));
          }),
        // 🛒 Buying stock: a manager sends the order, any staff member receives it.
        if (!isCustomer && _shows(t('purMenu')))
          _buildItem(context, DrawerScreen.purchasing,
              Icons.shopping_cart_outlined, t('purMenu'), () {
            Navigator.pop(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const PurchasingScreen()));
          }),
        if (_shows(t('invoiceHistoryDrawer')))
          _buildItem(context, DrawerScreen.invoices, Icons.history,
              t('invoiceHistoryDrawer'), () {
            Navigator.pop(context);
            if (widget.onInvoiceHistoryTap != null) widget.onInvoiceHistoryTap!();
          }),
        if (_shows(t('aiAssistantMenu')))
          _buildItem(context, DrawerScreen.aiAssistant, Icons.assistant,
              t('aiAssistantMenu'), () {
            Navigator.pop(context);
            _requireFeature(context, 'ai', () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AIAssistantScreen()));
            });
          }),
      ];

  /// Read-only analysis: what you open when you want an answer.
  List<Widget> _reportEntries({
    required bool isAdmin,
    required bool isManager,
  }) =>
      [
        if ((isManager || isAdmin) && _shows(t('analyticsMenu')))
          _buildItem(context, DrawerScreen.analytics,
              Icons.insert_chart_outlined, t('analyticsMenu'), () {
            Navigator.pop(context);
            _requireFeature(context, 'analytics', () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const ManagerDashboard()));
            });
          }),
        if ((isManager || isAdmin) && _shows(t('forecastMenu')))
          _buildItem(context, DrawerScreen.forecast, Icons.auto_graph,
              t('forecastMenu'), () {
            Navigator.pop(context);
            _requireFeature(context, 'forecast', () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const ForecastScreen()));
            });
          }),
        if ((isManager || isAdmin) && _shows(t('varMenu')))
          _buildItem(context, DrawerScreen.variance, Icons.trending_down,
              t('varMenu'), () {
            Navigator.pop(context);
            _requireFeature(context, 'reports', () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const VarianceScreen()));
            });
          }),
      ];

  /// Configuration and billing: what you change rarely.
  List<Widget> _setupEntries({
    required bool isAdmin,
    required bool isManager,
    required bool canManageDrinks,
    required bool canManageSettings,
  }) =>
      [
        if (canManageDrinks && _shows(t('drinkManagement')))
          _buildItem(context, DrawerScreen.drinks, Icons.local_drink,
              t('drinkManagement'), widget.onDrinkManagementTap),
        if (canManageDrinks && _shows(t('inventory')))
          _buildItem(context, DrawerScreen.inventory, Icons.inventory,
              t('inventory'), () {
            Navigator.pop(context);
            Navigator.push(context,
                MaterialPageRoute(builder: (context) => const InventoryScreen()));
          }),
        if (canManageSettings && _shows(t('settings')))
          _buildItem(context, DrawerScreen.settings, Icons.settings,
              t('settings'), () {
            Navigator.pop(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const StorageSettingsScreen()));
          }),
        if ((isManager || isAdmin) && _shows(t('subscription')))
          _buildItem(context, DrawerScreen.subscription,
              Icons.workspace_premium, t('subscription'), () {
            Navigator.pop(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SubscriptionScreen()));
          }),
      ];

  /// Who works here, and who is waiting to be approved.
  List<Widget> _managerEntries({required bool isManager}) => [
        if (isManager && _shows(t('staffManagement')))
          _buildItem(context, DrawerScreen.staff, Icons.business,
              t('staffManagement'), () {
            Navigator.pop(context);
            Navigator.push(context,
                MaterialPageRoute(builder: (context) => const ManagerPanel()));
          }),
        if (isManager && _shows(t('loginApprovalsMenu')))
          _buildItem(context, DrawerScreen.approvals, Icons.verified,
              t('loginApprovalsMenu'), () {
            Navigator.pop(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const ManagerApprovalScreen()));
          },
              iconColor: Colors.orange,
              badgeCount:
                  Provider.of<AuthProvider>(context).pendingApprovalsCount),
      ];

  List<Widget> _adminEntries({required bool isAdmin}) => [
        if (isAdmin && _shows(t('adminPanel')))
          _buildItem(context, DrawerScreen.adminPanel,
              Icons.admin_panel_settings, t('adminPanel'), () {
            Navigator.pop(context);
            Navigator.push(context,
                MaterialPageRoute(builder: (context) => const AdminPanel()));
          }, iconColor: Colors.purple),
      ];

  /// Anyone signed in can file a report — staff on the shop floor included, which
  /// is where most complaints start.
  List<Widget> _supportEntries() => [
        if (_shows(t('aboutMenu')))
          _buildItem(context, DrawerScreen.about, Icons.info_outline,
              t('aboutMenu'), widget.onAboutTap),
        if (_shows(t('helpSupportMenu')))
          _buildItem(context, DrawerScreen.help, Icons.help_outline,
              t('helpSupportMenu'), widget.onHelpTap),
        if (_shows(t('reportProblem')))
          _buildItem(context, DrawerScreen.reportProblem,
              Icons.bug_report_outlined, t('reportProblem'), () {
            Navigator.pop(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SupportReportScreen()));
          }),
      ];

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      child: Text(title,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: theme.hintColor)),
    );
  }

  /// Gate a premium feature behind the company's plan. Grants access when allowed,
  /// otherwise shows an upgrade prompt.
  void _requireFeature(
      BuildContext context, String feature, VoidCallback onGranted) {
    final plan = context.read<PlanProvider>();
    if (plan.canAccess(feature)) {
      onGranted();
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.workspace_premium, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(t('upgradeRequired'))),
        ]),
        content: Text('${t('upgradeTo')} ${t('pro')}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                  ctx,
                  MaterialPageRoute(
                      builder: (_) => const SubscriptionScreen()));
            },
            child: Text(t('upgrade')),
          ),
        ],
      ),
    );
  }

  /// One entry.
  ///
  /// The highlight is derived from [DrawerMenu.currentScreen], so it cannot claim
  /// you are somewhere you are not — which is exactly what the previous hardcoded
  /// `isActive: true` did.
  Widget _buildItem(
    BuildContext context,
    DrawerScreen screen,
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? iconColor,
    int badgeCount = 0,
  }) {
    final theme = Theme.of(context);
    final isSelected = screen == widget.currentScreen;
    final iconColorFinal =
        isSelected ? widget.primaryColor : iconColor ?? theme.hintColor;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? widget.primaryColor.withValues(alpha: 0.1) : null,
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
                    ? widget.primaryColor
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
                        fontWeight: FontWeight.bold),
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
                  color: widget.primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              )
            : null,
        onTap: () {
          // Tapping where you already are closes the drawer instead of pushing a
          // second copy of the same screen.
          if (isSelected) {
            Navigator.pop(context);
            return;
          }
          onTap();
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
