// services/company_branding_service.dart
// The shop's logo: uploaded once by the owner/manager, then shown in the drawer,
// on invoices/receipts and in exported reports.
//
// The URL is kept in two places so it is always available:
//   * locally (SharedPreferences) for instant/offline display, and
//   * on the company record (`companies.logo_url`) so every user of the company
//     sees the same branding on every device.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'drink_image_service.dart';
import 'supabase_service.dart';

class CompanyBrandingService {
  CompanyBrandingService._();

  /// Legacy key (single global logo) — still read once for migration, then
  /// dropped by [clearLocal].
  static const String prefsKey = 'company_logo_url';

  /// Company-scoped cache key. Scoping is what stops a customer (or another
  /// shop's staff) from seeing the previous company's logo on a shared device.
  static String cacheKeyFor(int? companyId) => 'company_logo_url_$companyId';

  /// The locally cached logo URL for the current company (null for customers or
  /// when nothing was ever cached).
  static Future<String?> cached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString(cacheKeyFor(SupabaseService.currentCompanyId));
      return (url == null || url.trim().isEmpty) ? null : url.trim();
    } catch (_) {
      return null;
    }
  }

  /// Logo URL for the current company, preferring the stored value and falling
  /// back to the company record on the server — that is what makes the logo show
  /// up for every manager and staff member, on any device.
  static Future<String?> load({bool forceRefresh = false}) async {
    final companyId = SupabaseService.currentCompanyId;
    if (companyId == null) return null; // customers have no company branding

    final local = await cached();
    if (!forceRefresh && local != null) return local;

    try {
      final company = await SupabaseService.getCompany(companyId);
      final remote = company?['logo_url']?.toString().trim();
      if (remote != null && remote.isNotEmpty) {
        await _cache(remote, companyId);
        return remote;
      }
      // The company has no logo (or it was removed): drop a stale cache.
      await _cache(null, companyId);
      return null;
    } catch (e) {
      debugPrint('⚠️ Could not read the company logo: $e');
      return local;
    }
  }

  /// Uploads [bytes] (already cropped) as the company logo and saves the URL.
  ///
  /// Returns null on success, or a reason code/message on failure.
  static Future<String?> setLogoFromBytes(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final companyId = SupabaseService.currentCompanyId;
    final upload = await DrinkImageService.uploadLogo(
      bytes: bytes,
      companyId: companyId,
    );
    if (!upload.ok || upload.url == null) return upload.error ?? 'upload-failed';
    await save(upload.url!);
    return null;
  }

  /// Stores the URL locally and on the company record.
  static Future<void> save(String url) async {
    final companyId = SupabaseService.currentCompanyId;
    await _cache(url, companyId);
    try {
      await SupabaseService.saveCompanyLogo(url);
    } catch (e) {
      debugPrint('⚠️ Company logo saved locally only: $e');
    }
  }

  /// Removes the branding (locally AND on the company record).
  static Future<void> clear() async {
    await _cache(null, SupabaseService.currentCompanyId);
    try {
      await SupabaseService.saveCompanyLogo('');
    } catch (e) {
      debugPrint('⚠️ Company logo cleared locally only: $e');
    }
  }

  /// Removes only the local copy — used when signing out / switching company, so
  /// the next user cannot see this company's logo (the server value is kept).
  static Future<void> clearLocal({int? companyId}) async {
    await _cache(null, companyId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey); // legacy global key
    } catch (_) {}
  }

  static Future<void> _cache(String? url, int? companyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = cacheKeyFor(companyId);
      if (url == null || url.trim().isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, url.trim());
      }
    } catch (_) {}
  }
}