// utils/owner_permissions.dart
// Who may see/change what inside a company.
//
// The distinction that matters: a **co-manager** is a Manager whose user row is
// not the company's `owner_id`. Co-managers run the shop day to day but must not
// clear company data, re-brand it, or manage the subscription owner.
//
// Kept as pure functions so the rules are unit tested instead of being scattered
// as string comparisons across screens.
class OwnerPermissions {
  OwnerPermissions._();

  /// Platform administrator (any company).
  static bool isAdminRole(String? role) =>
      role == 'administrator' || role == 'admin';

  /// The company's owner manager.
  static bool isCompanyOwner(bool? isOwner) => isOwner == true;

  /// Owner manager or platform administrator.
  static bool isOwnerLevel({String? role, bool? isOwner}) =>
      isAdminRole(role) || isCompanyOwner(isOwner);

  /// Company data management (clear data, reset caches) — owner level only.
  static bool canManageCompanyData({String? role, bool? isOwner}) =>
      isOwnerLevel(role: role, isOwner: isOwner);

  /// Company branding (logo) — owner level only.
  static bool canManageBranding({String? role, bool? isOwner}) =>
      isOwnerLevel(role: role, isOwner: isOwner);

  /// The subscription/billing screen — managers and above.
  static bool canManageBilling({String? role, bool? isOwner}) =>
      isAdminRole(role) || role == 'manager';

  /// Company-wide settings (payments, currency) — everyone but staff/customers.
  static bool canManagePayments({String? role, bool? isOwner}) =>
      isAdminRole(role) || role == 'manager';
}
