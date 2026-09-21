// services/session_data_cleaner.dart
// Wipes every trace of the previous company from this device.
//
// Company-scoped caches (name, logo, address, currency, payment switches) live in
// SharedPreferences, which is NOT scoped per company. Without this cleanup the
// next person to sign in on the device — a customer, or staff of another shop —
// would still see the previous company's name, logo and currency.
//
// Called on logout / forced logout and again when a customer signs in, so the two
// paths cannot leak into each other.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'company_branding_service.dart';
import 'secure_storage_service.dart';

class SessionDataCleaner {
  SessionDataCleaner._();

  /// Preferences that describe the signed-in company (never a user preference:
  /// theme, language and compact mode are deliberately kept).
  static const List<String> companyScopedKeys = [
    'last_company_id',
    'company_name',
    'company_email',
    'company_phone',
    'company_address',
    'currency_symbol',
    'currency_position',
    'decimal_separator',
    'thousands_separator',
    'decimal_places',
    'business_payments_enabled',
    'mtn_enabled',
    'orange_enabled',
    'auto_sync',
    // Legacy single-key logo cache (now stored per company).
    'company_logo_url',
  ];

  /// Clears the company caches. Pass [companyId] to also delete that company's
  /// encrypted local blob before its id is forgotten.
  static Future<void> clearCompanyData({int? companyId}) async {
    try {
      final id = companyId ?? await _lastCompanyId();
      if (id != null) {
        try {
          await SecureStorageService.clearCompanyData(id);
        } catch (e) {
          debugPrint('⚠️ Could not clear company storage for $id: $e');
        }
      }

      await CompanyBrandingService.clearLocal(companyId: id);

      final prefs = await SharedPreferences.getInstance();
      for (final key in companyScopedKeys) {
        await prefs.remove(key);
      }
      debugPrint('🧹 Company-scoped caches cleared (company=$id)');
    } catch (e) {
      debugPrint('⚠️ Company cache cleanup failed: $e');
    }
  }

  static Future<int?> _lastCompanyId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('last_company_id');
    } catch (_) {
      return null;
    }
  }
}