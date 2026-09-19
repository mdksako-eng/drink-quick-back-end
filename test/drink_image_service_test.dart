// test/drink_image_service_test.dart
// Guards the drink-picture upload helpers: the file name/type/size rules, the
// collision-free storage path and the public URL that the Drink Management
// screen writes into the image field.
//
// The uploading itself is not exercised here (it needs a live Supabase project);
// the validation paths are, because they must reject bad input BEFORE any
// network call.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drinks_calculator_fixed/config/api_config.dart';
import 'package:drinks_calculator_fixed/services/drink_image_service.dart';

void main() {
  group('extensionOf', () {
    test('reads the extension in lower case', () {
      expect(DrinkImageService.extensionOf('Beer.PNG'), 'png');
      expect(DrinkImageService.extensionOf('photo.jpeg'), 'jpeg');
    });

    test('handles a path and a name with several dots', () {
      expect(DrinkImageService.extensionOf('/tmp/a/b/drink.v2.jpg'), 'jpg');
    });

    test('returns null when there is no extension', () {
      expect(DrinkImageService.extensionOf('beer'), isNull);
      expect(DrinkImageService.extensionOf('beer.'), isNull);
    });
  });

  group('isAllowedImage', () {
    test('accepts the supported picture formats', () {
      for (final name in ['a.png', 'b.jpg', 'c.jpeg', 'd.webp', 'e.gif']) {
        expect(DrinkImageService.isAllowedImage(name), isTrue,
            reason: '$name should be allowed');
      }
    });

    test('rejects anything else', () {
      expect(DrinkImageService.isAllowedImage('notes.txt'), isFalse);
      expect(DrinkImageService.isAllowedImage('invoice.pdf'), isFalse);
      expect(DrinkImageService.isAllowedImage('archive.zip'), isFalse);
      expect(DrinkImageService.isAllowedImage('noextension'), isFalse);
    });
  });

  group('contentTypeFor', () {
    test('maps the extension to a mime type', () {
      expect(DrinkImageService.contentTypeFor('png'), 'image/png');
      expect(DrinkImageService.contentTypeFor('JPG'), 'image/jpeg');
      expect(DrinkImageService.contentTypeFor('jpeg'), 'image/jpeg');
      expect(DrinkImageService.contentTypeFor('webp'), 'image/webp');
      expect(DrinkImageService.contentTypeFor('gif'), 'image/gif');
    });

    test('returns null for an unknown extension', () {
      expect(DrinkImageService.contentTypeFor('bmp'), isNull);
    });
  });

  group('sanitizeFileName', () {
    test('lower-cases and replaces unsafe characters', () {
      expect(DrinkImageService.sanitizeFileName('Beer Bottle 33cl!.PNG'),
          'beer-bottle-33cl-.png');
    });

    test('strips a path, keeping only the file name', () {
      expect(DrinkImageService.sanitizeFileName('/storage/emulated/0/Pics/a b.jpg'),
          'a-b.jpg');
    });

    test('collapses repeated dashes and drops leading dashes/dots', () {
      expect(DrinkImageService.sanitizeFileName('---beer---.png'), 'beer-.png');
    });

    test('never returns an empty name', () {
      expect(DrinkImageService.sanitizeFileName('///'), 'image');
      expect(DrinkImageService.sanitizeFileName('...'), 'image');
    });

    test('caps very long names', () {
      final long = '${'a' * 200}.png';
      expect(DrinkImageService.sanitizeFileName(long).length, 80);
    });
  });

  group('buildObjectPath', () {
    test('prefixes the company and stamps the upload', () {
      final path = DrinkImageService.buildObjectPath(
        companyId: 7,
        fileName: 'Beer.PNG',
        now: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(path, '7/1000-beer.png');
    });

    test('falls back to a shared prefix without a company', () {
      final path = DrinkImageService.buildObjectPath(
        companyId: null,
        fileName: 'beer.png',
        now: DateTime.fromMillisecondsSinceEpoch(5),
      );
      expect(path, startsWith('shared/'));
    });

    test('two uploads of the same file never collide', () {
      final first = DrinkImageService.buildObjectPath(
          companyId: 7,
          fileName: 'beer.png',
          now: DateTime.fromMillisecondsSinceEpoch(1));
      final second = DrinkImageService.buildObjectPath(
          companyId: 7,
          fileName: 'beer.png',
          now: DateTime.fromMillisecondsSinceEpoch(2));
      expect(first, isNot(second));
    });
  });

  group('publicUrlFor', () {
    test('points at the public bucket object', () {
      expect(
        DrinkImageService.publicUrlFor('7/1000-beer.png'),
        '${ApiConfig.supabaseUrl}/storage/v1/object/public/drink-images/7/1000-beer.png',
      );
    });

    test('uses the documented bucket name', () {
      expect(DrinkImageService.bucket, 'drink-images');
      expect(DrinkImageService.publicUrlFor('a.png'),
          contains('/storage/v1/object/public/drink-images/a.png'));
    });
  });

  group('upload validation (no network)', () {
    test('rejects a non-image before uploading', () async {
      final result = await DrinkImageService.upload(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'notes.txt',
      );
      expect(result.ok, isFalse);
      expect(result.error, 'unsupported-image-type');
      expect(result.url, isNull);
    });

    test('rejects an empty file', () async {
      final result = await DrinkImageService.upload(
        bytes: Uint8List(0),
        fileName: 'beer.png',
      );
      expect(result.ok, isFalse);
      expect(result.error, 'empty-file');
    });

    test('rejects a picture beyond the size limit', () async {
      final result = await DrinkImageService.upload(
        bytes: Uint8List(DrinkImageService.maxBytes + 1),
        fileName: 'beer.png',
      );
      expect(result.ok, isFalse);
      expect(result.error, 'file-too-large');
    });
  });
}