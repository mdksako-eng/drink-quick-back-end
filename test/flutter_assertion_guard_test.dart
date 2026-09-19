// test/flutter_assertion_guard_test.dart
// Guards the console-noise filter for the known Flutter MouseTracker assertion:
// it must swallow exactly that one assertion (and count it) while letting every
// other error through to the previous handler.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drinks_calculator_fixed/utils/flutter_assertion_guard.dart';

void main() {
  group('isMouseTrackerAssertion', () {
    const frameworkAssertion = 'Assertion failed: '
        'file:///C:/flutter/packages/flutter/lib/src/rendering/mouse_tracker.dart:199:12\n'
        "!_debugDuringDeviceUpdate";

    test('matches the framework mouse tracker assertion', () {
      expect(FlutterAssertionGuard.isMouseTrackerAssertion(frameworkAssertion),
          isTrue);
    });

    test('does not match other assertions', () {
      expect(
        FlutterAssertionGuard.isMouseTrackerAssertion(
            'Assertion failed: file:///.../render_object.dart:123:5'),
        isFalse,
      );
      expect(FlutterAssertionGuard.isMouseTrackerAssertion(''), isFalse);
    });

    test('needs both the file and the flag (not a partial match)', () {
      expect(
        FlutterAssertionGuard.isMouseTrackerAssertion(
            'file:///.../mouse_tracker.dart'),
        isFalse,
      );
      expect(
        FlutterAssertionGuard.isMouseTrackerAssertion('_debugDuringDeviceUpdate'),
        isFalse,
      );
    });
  });

  group('isLayoutAssertion', () {
    test('recognises the "RenderBox was not laid out" failure', () {
      expect(
        FlutterAssertionGuard.isLayoutAssertion(
            'RenderBox was not laid out: RenderRepaintBoundary#123 '
            'relayoutBoundary=up1 NEEDS-PAINT'),
        isTrue,
      );
    });

    test('recognises a debugNeedsLayout failure', () {
      expect(
        FlutterAssertionGuard.isLayoutAssertion(
            'assert(!debugNeedsLayout): is not true.'),
        isTrue,
      );
    });

    test('does not match unrelated errors', () {
      expect(FlutterAssertionGuard.isLayoutAssertion('Something else broke'),
          isFalse);
      expect(FlutterAssertionGuard.isLayoutAssertion(''), isFalse);
    });
  });

  group('extractDartLocation', () {
    test('pulls the widget creation location out of a diagnostics report', () {
      const report = 'The relevant error-causing widget was:\n'
          '  Column  file:///C:/proj/lib/screens/ai_assistant_screen.dart:1234:45\n'
          'When the exception was thrown, this was the stack:\n'
          '  #0      RenderBox.size (package:flutter/src/rendering/box.dart:2251:12)';
      expect(
        FlutterAssertionGuard.extractDartLocation(report),
        'file:///C:/proj/lib/screens/ai_assistant_screen.dart:1234:45',
      );
    });

    test('returns the first location when several are present', () {
      const report = 'first file:///a/b.dart:1:2 then file:///c/d.dart:3:4';
      expect(FlutterAssertionGuard.extractDartLocation(report),
          'file:///a/b.dart:1:2');
    });

    test('returns null when there is no location', () {
      expect(FlutterAssertionGuard.extractDartLocation('no path here'), isNull);
      expect(FlutterAssertionGuard.extractDartLocation(''), isNull);
    });

    test('does not swallow trailing punctuation', () {
      expect(
        FlutterAssertionGuard.extractDartLocation(
            'see file:///x/y_screen.dart:12:3).'),
        'file:///x/y_screen.dart:12:3',
      );
    });
  });

  group('install', () {
    late void Function(FlutterErrorDetails) original;

    setUp(() {
      original = FlutterError.onError!;
      FlutterAssertionGuard.resetCounters();
    });

    tearDown(() {
      FlutterError.onError = original;
    });

    test('swallows and counts the mouse tracker assertion', () {
      var reachedOriginal = 0;
      FlutterError.onError = (details) {
        reachedOriginal++;
        original(details);
      };
      FlutterAssertionGuard.install();

      final assertion = FlutterErrorDetails(
        exception: AssertionError(
            'file:///x/mouse_tracker.dart:199:12 !_debugDuringDeviceUpdate'),
      );
      FlutterError.onError!(assertion);
      FlutterError.onError!(assertion);

      expect(FlutterAssertionGuard.mouseTrackerAssertionsSeen, 2);
      expect(reachedOriginal, 0,
          reason: 'the framework assertion must be dropped, not reported');
    });

    test('forwards every other error', () {
      var reachedOriginal = 0;
      FlutterError.onError = (details) {
        reachedOriginal++;
        original(details);
      };
      FlutterAssertionGuard.install();

      FlutterError.onError!(FlutterErrorDetails(exception: Exception('boom')));

      expect(reachedOriginal, 1,
          reason: 'real errors must still reach the previous handler');
      expect(FlutterAssertionGuard.mouseTrackerAssertionsSeen, 0);
    });
  });
}