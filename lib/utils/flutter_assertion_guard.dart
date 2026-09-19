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

  /// How many layout assertions ("RenderBox was not laid out", …) were seen.
  static int layoutAssertionsSeen = 0;

  /// Locations already reported, so a per-frame failure prints once.
  static final Set<String> _reportedLayoutLocations = {};

  /// True when [exceptionText] is the known MouseTracker re-entrancy assertion.
  static bool isMouseTrackerAssertion(String exceptionText) =>
      exceptionText.contains('mouse_tracker.dart') &&
      exceptionText.contains('_debugDuringDeviceUpdate');

  /// True when [exceptionText] looks like a layout failure that usually means an
  /// unbounded / badly nested layout somewhere in a screen.
  static bool isLayoutAssertion(String exceptionText) =>
      exceptionText.contains('RenderBox was not laid out') ||
      exceptionText.contains('debugNeedsLayout');

  /// First `file:///....dart:line:column` reference in [diagnosticsText].
  ///
  /// Flutter's error report embeds the offending widget's creation location, so
  /// pulling it out gives a copy-pasteable pointer to the buggy line.
  static String? extractDartLocation(String diagnosticsText) {
    final match = RegExp(r'file:///[^\s()]+\.dart:\d+:\d+')
        .firstMatch(diagnosticsText);
    return match?.group(0);
  }

  /// Collects the widget location from a Flutter error's information collector.
  static String? widgetLocationOf(FlutterErrorDetails details) {
    final collector = details.informationCollector;
    if (collector == null) return null;
    try {
      for (final node in collector()) {
        final text = node.toStringDeep(minLevel: DiagnosticLevel.info);
        final location = extractDartLocation(text);
        if (location != null) return location;
      }
    } catch (_) {
      // Diagnostics are best-effort: never let reporting break error handling.
    }
    return null;
  }

  /// Installs the filter. Safe to call once at startup.
  static void install() {
    final previous = FlutterError.onError;
    var reportedMouseTracker = false;

    FlutterError.onError = (FlutterErrorDetails details) {
      final text = details.exceptionAsString();

      if (isMouseTrackerAssertion(text)) {
        mouseTrackerAssertionsSeen++;
        if (!reportedMouseTracker) {
          reportedMouseTracker = true;
          debugPrint('🖱️ Ignoring Flutter MouseTracker debug assertion '
              '(framework re-entrancy, harmless in release builds — see '
              'flutter/flutter#137938). Further occurrences are counted only.');
        }
        return;
      }

      if (isLayoutAssertion(text)) {
        layoutAssertionsSeen++;
        final location = widgetLocationOf(details);
        final key = location ??
            text.substring(0, text.length < 90 ? text.length : 90);
        if (_reportedLayoutLocations.add(key)) {
          // A layout failure repeats every frame; print the pointer once so the
          // console stays readable (the full report still follows below).
          debugPrint('🧱 LAYOUT ERROR — send this line to get it fixed:');
          debugPrint('   location: ${location ?? '(unknown - see report below)'}');
          debugPrint('   $text');
        }
        // NOT filtered: a layout bug is real and must remain visible.
      }

      (previous ?? FlutterError.presentError)(details);
    };
  }

  @visibleForTesting
  static void resetCounters() {
    mouseTrackerAssertionsSeen = 0;
    layoutAssertionsSeen = 0;
    _reportedLayoutLocations.clear();
  }
}