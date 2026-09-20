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

  static const String prefsKey = 'company_logo_url';

  /// The locally cached logo URL (null when none was ever set).
  static Future<String?> cached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString(prefsKey);
      return (url == null || url.trim().isEmpty) ? null : url.trim();
    } catch (_) {
      return null;
    }
  }

  /// Logo URL, preferring the server record (so a logo set on another device
  /// shows up) and falling back to the cached copy when offline.
  static Future<String?> load({bool forceRefresh = false}) async {
    final local = await cached();
    if (!forceRefresh && local != null) return local;

    try {
      final companyId = SupabaseService.currentCompanyId;
      if (companyId != null) {
        final company = await SupabaseService.getCompany(companyId);
        final remote = company?['logo_url']?.toString().trim();
        if (remote != null && remote.isNotEmpty) {
          await _cache(remote);
          return remote;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Could not read the company logo: $e');
    }
    return local;
  }

  /// Uploads [bytes] (already cropped) as the company logo and saves the URL.
  ///
  /// Returns null on success, or a reason code/message on failure.
  static Future<String?> setLogoFromBytes(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final upload = await DrinkImageService.uploadLogo(
      bytes: bytes,
      companyId: SupabaseService.currentCompanyId,
    );
    if (!upload.ok || upload.url == null) return upload.error ?? 'upload-failed';
    await save(upload.url!);
    return null;
  }

  /// Stores the URL locally and on the company record.
  static Future<void> save(String url) async {
    await _cache(url);
    try {
      await SupabaseService.saveCompanyLogo(url);
    } catch (e) {
      debugPrint('⚠️ Company logo saved locally only: $e');
    }
  }

  /// Removes the branding (locally and on the company record).
  static Future<void> clear() async {
    await _cache(null);
    try {
      await SupabaseService.saveCompanyLogo('');
    } catch (e) {
      debugPrint('⚠️ Company logo cleared locally only: $e');
    }
  }

  static Future<void> _cache(String? url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (url == null || url.trim().isEmpty) {
        await prefs.remove(prefsKey);
      } else {
        await prefs.setString(prefsKey, url.trim());
      }
    } catch (_) {}
  }
}