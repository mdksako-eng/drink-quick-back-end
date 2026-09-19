// utils/flutter_assertion_guard.dart
// Drops ONE well-known Flutter framework debug assertion so it cannot flood the
// console, without hiding any real error.
//
// What it filters
// ---------------
// `mouse_tracker.dart` asserts that a mouse "device update" is never entered
// recursively (`assert(!_debugDuringDeviceUpdate)`). On web and desktop a hover
// that arrives while the tree is being rebuilt can re-enter it, and the framework
// then prints "Another exception was thrown: Assertion failed: ... mouse_tracker
// .dart" on every mouse move.
//
// It is a known framework-side issue — flutter/flutter#137938, #137939 and
// #138811 were all closed without a fix — and it only exists in debug builds
// (assertions are stripped in release), so the app's state is unaffected. The
// only real damage is console spam that hides genuine errors.
//
// Everything else is forwarded to the previous handler untouched.
import 'package:flutter/foundation.dart';

class FlutterAssertionGuard {
  FlutterAssertionGuard._();

  /// How many MouseTracker assertions were swallowed this session.
  static int mouseTrackerAssertionsSeen = 0;

  /// True when [exceptionText] is the known MouseTracker re-entrancy assertion.
  static bool isMouseTrackerAssertion(String exceptionText) =>
      exceptionText.contains('mouse_tracker.dart') &&
      exceptionText.contains('_debugDuringDeviceUpdate');

  /// Installs the filter. Safe to call once at startup.
  static void install() {
    final previous = FlutterError.onError;
    var reported = false;

    FlutterError.onError = (FlutterErrorDetails details) {
      if (isMouseTrackerAssertion(details.exceptionAsString())) {
        mouseTrackerAssertionsSeen++;
        if (!reported) {
          reported = true;
          debugPrint('🖱️ Ignoring Flutter MouseTracker debug assertion '
              '(framework re-entrancy, harmless in release builds — see '
              'flutter/flutter#137938). Further occurrences are counted only.');
        }
        return;
      }
      (previous ?? FlutterError.presentError)(details);
    };
  }

  @visibleForTesting
  static void resetCounter() => mouseTrackerAssertionsSeen = 0;
}