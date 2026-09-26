// services/whatsapp_service.dart
// Hands a prepared message over to WhatsApp. The message text is built by
// utils/whatsapp_helper.dart; this service only does the I/O (the launch), so
// screens never touch url_launcher themselves.
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:url_launcher/url_launcher.dart';

import '../utils/whatsapp_helper.dart';

class WhatsAppService {
  WhatsAppService._();

  /// Opens WhatsApp with [message] ready to send to [phone].
  ///
  /// Returns false when there is no usable number (ask for a phone number) or
  /// when WhatsApp is not installed (the caller shows a toast).
  static Future<bool> send({
    required String? phone,
    required String message,
  }) async {
    final link = WhatsAppHelper.link(phone, message);
    if (link.isEmpty) return false;
    try {
      return await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('⚠️ Could not open WhatsApp: $e');
      return false;
    }
  }

  /// Opens WhatsApp's contact picker with [message] ready to send — used when
  /// the shop has no phone on file for the recipient (the Z-report to an owner).
  static Future<bool> share({required String message}) async {
    try {
      return await launchUrl(
        Uri.parse(WhatsAppHelper.shareLink(message)),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('⚠️ Could not open WhatsApp: $e');
      return false;
    }
  }

  /// True when a number is on file, so the UI can hide/disable the button
  /// instead of failing after the tap.
  static bool hasNumber(String? phone) =>
      WhatsAppHelper.normalizeNumber(phone).isNotEmpty;
}
