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

  /// Clears the company caches that are visible to whoever signs in next.
  ///
  /// Note: the *encrypted* company blobs (drinks/orders keyed
  /// `*_company_<id>`) are deliberately kept on a plain logout — they are
  /// company-scoped and encrypted, a customer session cannot read them, and
  /// keeping them means staff can still open the catalogue offline right after
  /// signing back in. They are cleared where the company actually changes (see
  /// `clearEncryptedBlobs`) or by the providers' own `clearAll*` calls.
  static Future<void> clearCompanyData({int? companyId}) async {
    try {
      final id = companyId ?? await _lastCompanyId();

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

  /// Deletes the company's encrypted local data too. Used when the device moves
  /// to a **different** company (or when a customer takes over the device), where
  /// keeping the previous shop's blobs has no upside.
  static Future<void> clearEncryptedBlobs(int companyId) async {
    try {
      await SecureStorageService.clearCompanyData(companyId);
      debugPrint('🧹 Encrypted company blobs cleared for $companyId');
    } catch (e) {
      debugPrint('⚠️ Could not clear encrypted blobs: $e');
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