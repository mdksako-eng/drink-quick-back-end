// config/api_config.dart
class ApiConfig {
  // Production backend URL (Render)
  static const String baseUrl = 'https://drink-quick-cal-kja1.onrender.com';

  // API Base
  static const String apiBase = '$baseUrl/api';

  // Auth Endpoints
  static const String register = '$apiBase/auth/register';
  static const String login = '$apiBase/auth/login';
  static const String logout = '$apiBase/auth/logout';
  static const String currentUser = '$apiBase/auth/me';
  static const String refreshToken = '$apiBase/auth/refresh';
  static const String resetPassword = '$apiBase/auth/reset-password';

  // User Management Endpoints
  static const String usersUrl = '$apiBase/users';
  static const String createStaff = '$apiBase/auth/create-staff';
  static String blockUser(dynamic id) => '$apiBase/auth/block-user/$id';
  static String unblockUser(dynamic id) => '$apiBase/auth/unblock-user/$id';
  static String deleteUser(dynamic id) => '$apiBase/auth/users/$id';
  static String updateUser(dynamic id) => '$apiBase/users/$id';

  // Admin Endpoints
  static const String adminUsers = '$apiBase/admin/users';
  static const String adminStats = '$apiBase/admin/stats';

  // Drinks
  static const String drinks = '$apiBase/drinks';

  // Health Check
  static const String health = '$baseUrl/health';
  static const String ping = '$apiBase/ping';
  static const String test = '$apiBase/test';

  // Legal pages (served as static files from the backend's public/ dir)
  static const String privacyPolicy = '$baseUrl/privacy.html';
  static const String termsOfService = '$baseUrl/terms.html';
  // ========== SUPABASE ==========
  // Replace these with your Supabase project details
  static const String supabaseUrl = 'https://hcfhnooabhxbdfgvtqhp.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_aTK59GscsMZuzeCx973mIw_SomssAXW';
  static const String supabaseRestUrl = '$supabaseUrl/rest/v1';
  static const String supabaseCompanies = '$supabaseRestUrl/companies';
  // Supabase Tables
  static const String supabaseDrinks = '$supabaseRestUrl/drinks';
  static const String supabaseOrders = '$supabaseRestUrl/orders';
  static const String supabaseInventory = '$supabaseRestUrl/inventory';
  static const String supabaseTransactions =
      '$supabaseRestUrl/inventory_transactions';
  static const String supabaseSettings = '$supabaseRestUrl/settings';
  static const String supabasePaymentTransactions = '$supabaseRestUrl/payment_transactions';

  // Get environment info
  static bool get isProduction => baseUrl.contains('onrender.com');
  static String get environment => isProduction ? 'Production' : 'Environment';
  // ========== BACKEND DATA ENDPOINTS (session-authenticated; replaces direct Supabase REST) ==========
  static const String dataDrinks = '$apiBase/data/drinks';
  static const String dataOrders = '$apiBase/data/orders';
  static const String dataInventory = '$apiBase/data/inventory';
  static const String dataInventoryUpsert = '$apiBase/data/inventory/upsert';
  static const String dataInventoryTransactions =
      '$apiBase/data/inventory-transactions';
  static const String dataSettings = '$apiBase/data/settings';
  static const String dataPaymentTransactions =
      '$apiBase/data/payment-transactions';
  static String dataCompany(dynamic id) => '$apiBase/data/company/$id';
  static String dataCompanyPaymentSettings(dynamic id) =>
      '$apiBase/data/company/$id/payment-settings';

  // Supabase headers (anon key) — legacy direct access only.
  static Map<String, String> get supabaseHeaders => {
    'apikey': supabaseAnonKey,
    'Authorization': 'Bearer $supabaseAnonKey',
    'Content-Type': 'application/json',
  };
}
