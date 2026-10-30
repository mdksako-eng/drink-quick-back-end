// test/drawer_menu_test.dart
// The drawer menu as a user meets it: the sections it shows, the search box, and the
// highlight — which must tell the truth about where you are, because the previous
// version hardcoded "Dashboard" as active from every screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drinks_calculator_fixed/providers/auth_provider.dart';
import 'package:drinks_calculator_fixed/providers/plan_provider.dart';
import 'package:drinks_calculator_fixed/utils/drawer_navigation.dart';
import 'package:drinks_calculator_fixed/utils/i18n.dart';
import 'package:drinks_calculator_fixed/widgets/drawer_menu.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpMenu(WidgetTester tester, DrawerScreen current) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PlanProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DrawerMenu(
              currentScreen: current,
              primaryColor: Colors.blue,
              onDashboardTap: () {},
              onDrinkManagementTap: () {},
              onAboutTap: () {},
              onHelpTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The style the menu gave a label — the highlight is a bold, coloured Text.
  TextStyle styleOf(WidgetTester tester, String label) {
    final text = tester.widget<Text>(find.descendant(
      of: find.widgetWithText(ListTile, label),
      matching: find.text(label),
    ));
    return text.style!;
  }

  testWidgets('the menu is searchable and grouped', (tester) async {
    await pumpMenu(tester, DrawerScreen.dashboard);

    expect(find.text(t('drawerSearchHint')), findsOneWidget);
    expect(find.text(t('menuMain')), findsOneWidget);
    expect(find.text(t('dashboard')), findsOneWidget);
    expect(find.text(t('shiftMenu')), findsOneWidget);
  });

  testWidgets('sections that need a role are not offered to someone without it',
      (tester) async {
    await pumpMenu(tester, DrawerScreen.dashboard);

    // A user with no role at all: no manager entries, no admin panel, no reports.
    expect(find.text(t('menuManager')), findsNothing);
    expect(find.text(t('menuAdmin')), findsNothing);
    expect(find.text(t('analyticsMenu')), findsNothing);
    expect(find.text(t('staffManagement')), findsNothing);
  });

  testWidgets('the highlight follows the screen the drawer was opened from',
      (tester) async {
    await pumpMenu(tester, DrawerScreen.dashboard);
    expect(styleOf(tester, t('dashboard')).fontWeight, FontWeight.w600);
    expect(styleOf(tester, t('shiftMenu')).fontWeight, FontWeight.normal);

    // Same menu, opened from another screen: the highlight moves with it instead of
    // staying on Dashboard.
    await pumpMenu(tester, DrawerScreen.shift);
    expect(styleOf(tester, t('shiftMenu')).fontWeight, FontWeight.w600);
    expect(styleOf(tester, t('dashboard')).fontWeight, FontWeight.normal);
  });

  testWidgets('typing in the search box filters the menu', (tester) async {
    await pumpMenu(tester, DrawerScreen.dashboard);

    await tester.enterText(find.byType(TextField), 'shift');
    await tester.pump();

    expect(find.text(t('shiftMenu')), findsOneWidget);
    expect(find.text(t('dashboard')), findsNothing);
    expect(find.text(t('aboutMenu')), findsNothing);
  });

  testWidgets('a query that matches nothing says so, and drops the headers',
      (tester) async {
    await pumpMenu(tester, DrawerScreen.dashboard);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();

    expect(find.text(t('drawerNoResults')), findsOneWidget);
    expect(find.text(t('menuMain')), findsNothing);
  });
}
