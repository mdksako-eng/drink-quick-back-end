// test/app_info_test.dart
// One version, everywhere. The drawer, the lock screen, backup metadata and
// support reports must show the same number, and that number must be the one the
// build actually carries — pubspec.yaml. Before this guard the app said 1.1.0 in
// three places and 1.0.0 in a fourth.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/app_info_helper.dart';
import 'package:drinks_calculator_fixed/utils/constants.dart';

void main() {
  test('AppConstants.appVersion equals pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(versionFromPubspec(pubspec), AppConstants.appVersion,
        reason: 'bump AppConstants.appVersion together with pubspec.yaml');
  });

  test('versionFromPubspec strips the build number', () {
    expect(versionFromPubspec('name: x\nversion: 1.2.3+45\n'), '1.2.3');
    expect(versionFromPubspec('name: x\n'), isNull);
  });

  test('no other source file hardcodes a version', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      // The single declared source of truth.
      if (path.endsWith('utils/constants.dart')) continue;
      final found = hardcodedVersionsIn(entity.readAsStringSync());
      if (found.isNotEmpty) offenders.add('$path → ${found.join(', ')}');
    }
    expect(offenders, isEmpty,
        reason: 'use AppConstants.appVersion instead of a version literal');
  });
}
