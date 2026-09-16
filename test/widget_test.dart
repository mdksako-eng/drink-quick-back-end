// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/main.dart';
import 'package:drinks_calculator_fixed/screens/auth_screen.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Mock SharedPreferences so ThemeProvider.loadTheme() completes in tests
    SharedPreferences.setMockInitialValues({});

    // Build our app and trigger a frame
    await tester.pumpWidget(MyApp()); // Remove 'const' since MyApp doesn't have a const constructor

    // Verify that our app loads
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Splash screen shows while loading, then the sign-in screen',
      (WidgetTester tester) async {
    // Mock SharedPreferences so ThemeProvider.loadTheme() resolves
    // (otherwise it throws MissingPluginException and the splash is never built)
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(MyApp());

    // The splash is the only screen that renders this status label, so drive the
    // async startup frame-by-frame and record whether it appeared at all.
    var sawSplash = false;
    for (var i = 0; i < 15; i++) {
      final splashStatus = find.text('Checking authentication...');
      final loadingStatus = find.text('Loading app...');
      if (splashStatus.evaluate().isNotEmpty ||
          loadingStatus.evaluate().isNotEmpty) {
        sawSplash = true;
        // The branded splash must show its name, tagline and spinner.
        expect(find.text('Drinks Quick Cal'), findsWidgets);
        expect(find.text('Professional Drink Ordering & Management'),
            findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(sawSplash, isTrue,
        reason: 'The branded splash should be visible while the app initialises');

    // With no stored session the startup finishes on the sign-in screen.
    for (var i = 0;
        i < 20 && find.byType(AuthScreen).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The app arms a long inactivity (lock) timer while starting; stop it so the
    // test can finish without a pending timer.
    LockService().lock();
    await tester.pump();
  });
}
