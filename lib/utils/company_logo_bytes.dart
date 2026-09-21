// utils/company_logo_bytes.dart
// Fetches the company logo as bytes so it can be drawn inside PDF exports.
//
// The PDF engine cannot load a URL by itself, and exports must never fail just
// because the logo is missing/offline — every getter here returns null instead
// of throwing, and the report simply prints without the logo.
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/company_branding_service.dart';

class CompanyLogoBytes {
  CompanyLogoBytes._();

  static Uint8List? _cache;
  static String? _cachedFor;

  /// Logo bytes for the current company (null when there is none or offline).
  static Future<Uint8List?> load({bool forceRefresh = false}) async {
    if (forceRefresh) resetCache();
    final url = await CompanyBrandingService.load(forceRefresh: forceRefresh);
    return fromUrl(url);
  }

  /// Downloads [url] as bytes, caching the last successful download per URL so a
  /// multi-section export does not re-download the same image.
  static Future<Uint8List?> fromUrl(String? url) async {
    final trimmed = (url ?? '').trim();
    if (trimmed.isEmpty) return null;
    if (!isFetchableUrl(trimmed)) return null;
    if (_cache != null && _cachedFor == trimmed) return _cache;

    try {
      final response = await http
          .get(Uri.parse(trimmed))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('⚠️ Logo download failed: HTTP ${response.statusCode}');
        return null;
      }
      if (response.bodyBytes.isEmpty) return null;
      _cache = response.bodyBytes;
      _cachedFor = trimmed;
      return _cache;
    } catch (e) {
      debugPrint('⚠️ Logo download error: $e');
      return null;
    }
  }

  /// Only real http(s) image URLs are fetched (data URIs and local paths are
  /// not usable inside a PDF).
  static bool isFetchableUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.startsWith('data:')) return false;
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  /// Test seam.
  @visibleForTesting
  static void resetCache() {
    _cache = null;
    _cachedFor = null;
  }
}
