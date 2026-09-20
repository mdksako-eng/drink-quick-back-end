// utils/image_crop_helper.dart
// Crops a picked picture to a centred square and scales it down using `dart:ui`
// only — no extra dependency, and the same code path on mobile, desktop and web.
//
// Why square: everywhere the app shows a drink or a logo (list leading icons,
// scan sheet, cards, avatars) the picture is drawn with BoxFit.cover, so a square
// source scales predictably instead of being cropped differently in each place.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

class ImageCropHelper {
  ImageCropHelper._();

  /// Default output size for drinks and company logos: crisp at 96 logical px on
  /// a 3x screen, and small enough to upload quickly.
  static const int defaultTargetSize = 512;

  /// Centre-crops [bytes] to a square of [targetSize] px and returns PNG bytes.
  ///
  /// Falls back to the original bytes when the platform cannot decode/encode the
  /// image (e.g. an exotic format), so an upload never fails just because of the
  /// crop step.
  static Future<Uint8List> cropToSquare(
    Uint8List bytes, {
    int targetSize = defaultTargetSize,
  }) async {
    if (bytes.isEmpty) return bytes;
    ui.Image? image;
    ui.Picture? picture;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      image = (await codec.getNextFrame()).image;

      final side = math.min(image.width, image.height);
      final left = (image.width - side) / 2;
      final top = (image.height - side) / 2;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(left, top, side.toDouble(), side.toDouble()),
        ui.Rect.fromLTWH(0, 0, targetSize.toDouble(), targetSize.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      picture = recorder.endRecording();

      final cropped = await picture.toImage(targetSize, targetSize);
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      cropped.dispose();
      if (data == null) return bytes;
      return data.buffer.asUint8List();
    } catch (e) {
      debugPrint('✂️ Crop skipped (uploading the original picture): $e');
      return bytes;
    } finally {
      picture?.dispose();
      image?.dispose();
    }
  }

  /// True when [bytes] already look like a square of [expectedSize].
  ///
  /// Cheap guard so a second pass over an already-cropped picture is skipped.
  static bool isSquarePng(Uint8List bytes,
      {int expectedSize = defaultTargetSize}) {
    // PNG header: \x89PNG\r\n\x1a\n then IHDR width/height as big-endian int32.
    if (bytes.length < 24) return false;
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    final width = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final height = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return width == height && width == expectedSize;
  }
}