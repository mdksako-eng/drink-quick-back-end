// test/screens_layout_test.dart
// LAYOUT SMOKE TEST.
//
// Pumps the app's heaviest screens at phone and tablet sizes and fails if any of
// them reports a *layout* error — the class of bug behind
// "RenderBox was not laid out" (box.dart:2251) which repeats once per frame in
// debug builds and is otherwise very hard to pin down.
//
// Only layout failures are collected: the test environment has no plugins
// (secure storage, TTS, camera) and no network, so other exceptions are expected
// noise and are forwarded to the default handler untouched.
//
// When it fails, the assertion message contains the offending `file:line`
// (extracted by FlutterAssertionGuard) so the culprit is immediately obvious.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/providers/inventory_provider.dart';
import 'package:drinks_calculator_fixed/providers/plan_provider.dart';
import 'package:drinks_calculator_fixed/providers/order_provider.dart';
import 'package:drinks_calculator_fixed/screens/profile_screen.dart';
import 'package:drinks_calculator_fixed/screens/forecast_screen.dart';
import 'package:drinks_calculator_fixed/screens/drink_management_screen.dart';
import 'package:drinks_calculator_fixed/screens/inventory_report_screen.dart';
import 'package:drinks_calculator_fixed/screens/inventory_screen.dart';
import 'package:drinks_calculator_fixed/screens/manager_panel.dart';
import 'package:drinks_calculator_fixed/screens/notifications_screen.dart';
import 'package:drinks_calculator_fixed/screens/subscription_screen.dart';
import 'package:drinks_calculator_fixed/utils/flutter_assertion_guard.dart';
import 'package:drinks_calculator_fixed/widgets/upgrade_required.dart';

void main() {
  final layoutErrors = <String>[];
  late void Function(FlutterErrorDetails) defaultOnError;

  /// Errors that mean "this screen is wired up wrongly" and that a user would see
  /// as console spam:
  ///   * layout failures ("RenderBox was not laid out")
  ///   * provider notifications fired during build
  bool isScreenRenderBug(String text) =>
      FlutterAssertionGuard.isLayoutAssertion(text) ||
      text.contains('called during build') ||
      text.contains('was not laid out');

  setUp(() {
    layoutErrors.clear();
    SharedPreferences.setMockInitialValues({});
    defaultOnError = FlutterError.onError!;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (isScreenRenderBug(text)) {
        final where =
            FlutterAssertionGuard.widgetLocationOf(details) ?? '(unknown widget)';
        layoutErrors.add('  at $where\n  $text');
        return;
      }
      defaultOnError(details);
    };
  });

  tearDown(() {
    FlutterError.onError = defaultOnError;
  });

  /// Pumps [screen] inside a MaterialApp with the providers it reads.
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => PlanProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => DrinkProvider()),
          ChangeNotifierProvider(create: (_) => InventoryProvider()),
          ChangeNotifierProvider(create: (_) => OrderProvider()),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    // Let the initial async work settle (it fails gracefully offline).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  void expectNoLayoutError() {
    expect(
      layoutErrors,
      isEmpty,
      reason: 'Layout errors detected:\n${layoutErrors.join('\n')}',
    );
  }

  const phone = Size(390, 844);
  const tablet = Size(1100, 900);

  testWidgets('UpgradeRequiredView lays out on phone and tablet',
      (tester) async {
    await pumpScreen(tester, const UpgradeRequiredView(), size: phone);
    expectNoLayoutError();
    await pumpScreen(tester, const UpgradeRequiredView(), size: tablet);
    expectNoLayoutError();
  });

  testWidgets('ProfileScreen lays out on phone and tablet (no signed-in user)',
      (tester) async {
    // With no user the screen renders its safe empty state — the point is that it
    // must not throw or overflow while the session is being restored.
    await pumpScreen(tester, const ProfileScreen(), size: phone);
    expectNoLayoutError();
    await pumpScreen(tester, const ProfileScreen(), size: tablet);
    expectNoLayoutError();
  });

  testWidgets('SubscriptionScreen lays out on phone and tablet',
      (tester) async {
    await pumpScreen(tester, const SubscriptionScreen(), size: phone);
    expectNoLayoutError();
    await pumpScreen(tester, const SubscriptionScreen(), size: tablet);
    expectNoLayoutError();
  });

  testWidgets('SubscriptionScreen gate mode lays out (incl. Continue on Free)',
      (tester) async {
    await pumpScreen(
      tester,
      SubscriptionScreen(gate: true, onContinueFree: () {}),
      size: phone,
    );
    expectNoLayoutError();
    await pumpScreen(
      tester,
      SubscriptionScreen(gate: true, onContinueFree: () {}),
      size: tablet,
    );
    expectNoLayoutError();
  });

  testWidgets('NotificationsScreen lays out on phone and tablet',
      (tester) async {
    await pumpScreen(tester, const NotificationsScreen(), size: phone);
    expectNoLayoutError();
    await pumpScreen(tester, const NotificationsScreen(), size: tablet);
    expectNoLayoutError();
  });

  testWidgets('InventoryReportScreen lays out on phone and tablet',
      (tester) async {
    await pumpScreen(tester, const InventoryReportScreen(), size: phone);
    expectNoLayoutError();
    await pumpScreen(tester, const InventoryReportScreen(), size: tablet);
    expectNoLayoutError();
  });

  testWidgets('ForecastScreen lays out on phone and tablet', (tester) async {
    await pumpScreen(tester, const ForecastScreen(), size: phone);
    expectNoLayoutError();
    await pumpScreen(tester, const ForecastScreen(), size: tablet);
    expectNoLayoutError();
  });

  testWidgets('InventoryScreen lays out on phone and tablet', (tester) async {
    await pumpScreen(tester, const InventoryScreen(), size: phone);
    expectNoLayoutError();
    await pumpScreen(tester, const InventoryScreen(), size: tablet);
    expectNoLayoutError();
  });

  testWidgets('DrinkManagementScreen lays out on phone and tablet',
      (tester) async {
    await pumpScreen(tester, const DrinkManagementScreen(), size: phone);
    expectNoLayoutError();
    await pumpScreen(tester, const DrinkManagementScreen(), size: tablet);
    expectNoLayoutError();
  });

  testWidgets('ManagerPanel lays out on phone and tablet', (tester) async {
    await pumpScreen(tester, const ManagerPanel(), size: phone);
    expectNoLayoutError();
    await pumpScreen(tester, const ManagerPanel(), size: tablet);
    expectNoLayoutError();
  });
}