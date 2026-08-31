// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Mock SharedPreferences so ThemeProvider.loadTheme() completes in tests
    SharedPreferences.setMockInitialValues({});

    // Build our app and trigger a frame
    await tester.pumpWidget(MyApp()); // Remove 'const' since MyApp doesn't have a const constructor

    // Verify that our app loads
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Splash screen shows while loading', (WidgetTester tester) async {
    // Mock SharedPreferences so ThemeProvider.loadTheme() resolves
    // (otherwise it throws MissingPluginException and the splash is never built)
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(MyApp());

    // First frame: MyApp shows a bare spinner while ThemeProvider loads.
    // Let the microtask queue flush so ThemeProvider finishes loading,
    // then AuthWrapper builds and renders the branded splash screen
    // (which shows while _isCheckingAuth is still true).
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    // Verify splash screen elements exist
    expect(find.text('Drinks Quick Cal'), findsOneWidget);
    expect(find.text('Professional Drink Ordering & Management'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
