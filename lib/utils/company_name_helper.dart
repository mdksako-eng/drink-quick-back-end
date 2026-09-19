// utils/company_name_helper.dart
// Resolves the business name that every exported report must carry.
//
// Order: the cached setting -> the live company record on the server (which is
// then cached) -> null. Shared by the inventory report and the manager
// dashboard so both exports always show the same header.
import 'package:shared_preferences/shared_preferences.dart';

import '../services/supabase_service.dart';

class CompanyNameHelper {
  CompanyNameHelper._();

  /// The real business name, or null when it is not known yet.
  static Future<String?> resolve() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('company_name')?.trim();
      if (cached != null &&
          cached.isNotEmpty &&
          cached != 'Drink Quick Cal') {
        return cached;
      }

      final companyId = SupabaseService.currentCompanyId;
      if (companyId != null) {
        final company = await SupabaseService.getCompany(companyId);
        final name = company?['name']?.toString().trim();
        if (name != null && name.isNotEmpty) {
          await prefs.setString('company_name', name);
          return name;
        }
      }

      return (cached == null || cached.isEmpty) ? null : cached;
    } catch (_) {
      return null;
    }
  }
}