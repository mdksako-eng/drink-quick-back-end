// services/drink_image_service.dart
// Uploads drink pictures to the public Supabase Storage bucket `drink-images`
// and returns the public URL that the Drink Management screen puts in the image
// field (the drink card renders it with Image.network).
//
// Setup (one SQL run) is documented in
// drinks-calculator-backend/sql/storage_drink_images.sql.
//
// The parsing/validation helpers are pure so they are unit tested; the upload
// itself degrades gracefully: when the bucket or the policy is missing the
// caller gets a readable message instead of an exception.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_config.dart';

/// Outcome of an upload attempt.
class ImageUploadResult {
  final bool ok;

  /// Public URL of the uploaded file (null on failure).
  final String? url;

  /// Human-readable reason when [ok] is false.
  final String? error;

  const ImageUploadResult.success(this.url)
      : ok = true,
        error = null;

  const ImageUploadResult.failure(this.error)
      : ok = false,
        url = null;
}

class DrinkImageService {
  DrinkImageService._();

  /// Bucket name — keep in sync with sql/storage_drink_images.sql.
  static const String bucket = 'drink-images';

  /// Maximum accepted size (the bucket enforces the same limit server-side).
  static const int maxBytes = 5 * 1024 * 1024;

  static const List<String> allowedExtensions = [
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
  ];

  /// mime type per extension (Storage stores it with the object).
  static String? contentTypeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return null;
    }
  }

  /// Extension of [fileName] (without the dot), or null when there is none.
  static String? extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) return null;
    return fileName.substring(dot + 1).toLowerCase();
  }

  /// True when the file looks like an image we accept.
  static bool isAllowedImage(String fileName) =>
      allowedExtensions.contains(extensionOf(fileName));

  /// A collision-free storage path: `<companyId>/<timestamp>-<safe name>`.
  ///
  /// Keeping the company prefix makes the bucket browsable per business and
  /// stops two shops from clashing on "beer.png".
  static String buildObjectPath({
    required int? companyId,
    required String fileName,
    DateTime? now,
  }) {
    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final safe = sanitizeFileName(fileName);
    return '${companyId ?? 'shared'}/$stamp-$safe';
  }

  /// Turns any name into something safe for a URL / storage key.
  static String sanitizeFileName(String fileName) {
    final base = fileName.split(RegExp(r'[/\\]')).last;
    final cleaned = base
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^[-.]+'), '');
    if (cleaned.isEmpty) return 'image';
    return cleaned.length > 80 ? cleaned.substring(cleaned.length - 80) : cleaned;
  }

  /// Public URL for an object path.
  ///
  /// Built from the project URL (not from the live client) so it stays pure and
  /// unit testable — it is the exact pattern Supabase Storage serves:
  /// `{SUPABASE_URL}/storage/v1/object/public/<bucket>/<path>`.
  static String publicUrlFor(String objectPath) =>
      '${ApiConfig.supabaseUrl}/storage/v1/object/public/$bucket/$objectPath';

  /// Uploads [bytes] and returns the public URL.
  ///
  /// [fileName] only supplies the extension/name; the stored key is generated
  /// from it so an upload never overwrites an existing picture.
  static Future<ImageUploadResult> upload({
    required Uint8List bytes,
    required String fileName,
    int? companyId,
  }) async {
    if (!isAllowedImage(fileName)) {
      return const ImageUploadResult.failure('unsupported-image-type');
    }
    if (bytes.isEmpty) {
      return const ImageUploadResult.failure('empty-file');
    }
    if (bytes.length > maxBytes) {
      return const ImageUploadResult.failure('file-too-large');
    }

    final extension = extensionOf(fileName)!;
    final objectPath =
        buildObjectPath(companyId: companyId, fileName: fileName);

    try {
      final storage = Supabase.instance.client.storage.from(bucket);
      await storage.uploadBinary(
        objectPath,
        bytes,
        fileOptions: FileOptions(
          contentType: contentTypeFor(extension),
          upsert: false,
        ),
      );
      return ImageUploadResult.success(storage.getPublicUrl(objectPath));
    } catch (e) {
      debugPrint('🖼️ Drink image upload failed: $e');
      final message = e.toString();
      if (message.contains('Bucket not found') ||
          message.contains('bucket') && message.contains('not found')) {
        return const ImageUploadResult.failure('bucket-missing');
      }
      if (message.contains('row-level security') ||
          message.contains('Unauthorized') ||
          message.contains('403')) {
        return const ImageUploadResult.failure('policy-denied');
      }
      return ImageUploadResult.failure(message);
    }
  }

  /// Uploads a company logo into the same public bucket and returns its URL.
  ///
  /// Stored as `<companyId>/logo-<timestamp>.png` so the bucket stays organised
  /// (drink pictures live beside it) and a new logo never overwrites the old one.
  static Future<ImageUploadResult> uploadLogo({
    required Uint8List bytes,
    int? companyId,
    DateTime? now,
  }) async {
    if (bytes.isEmpty) {
      return const ImageUploadResult.failure('empty-file');
    }
    if (bytes.length > maxBytes) {
      return const ImageUploadResult.failure('file-too-large');
    }

    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final objectPath = '${companyId ?? 'shared'}/logo-$stamp.png';

    try {
      await Supabase.instance.client.storage.from(bucket).uploadBinary(
            objectPath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: false,
            ),
          );
      return ImageUploadResult.success(publicUrlFor(objectPath));
    } catch (e) {
      debugPrint('🏢 Logo upload failed: $e');
      final message = e.toString();
      if (message.contains('Bucket not found') ||
          (message.contains('bucket') && message.contains('not found'))) {
        return const ImageUploadResult.failure('bucket-missing');
      }
      if (message.contains('row-level security') ||
          message.contains('Unauthorized') ||
          message.contains('403')) {
        return const ImageUploadResult.failure('policy-denied');
      }
      return ImageUploadResult.failure(message);
    }
  }
}