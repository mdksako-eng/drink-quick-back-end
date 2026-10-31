// test/drawer_menu_button_test.dart
// The drawer button on a screen that is NOT the till.
//
// Two things must hold, and both are easy to break later:
//   1. the screen keeps its BACK arrow — a Scaffold's own drawer would take the
//      leading slot and replace it (see Flutter's app_bar.dart: hasDrawer wins);
//   2. the button still opens the drawer, which is the trap it exists to avoid:
//      `Scaffold.of(context)` inside `appBar:` resolves ABOVE the Scaffold and
//      throws "No Scaffold widget found".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drinks_calculator_fixed/widgets/drawer_menu_button.dart';

/// A pushed screen shaped like the real ones: a Scaffold with a drawer, an AppBar
/// whose actions hold the menu button, and an implied back arrow.
class _PushedScreen extends StatelessWidget {
  const _PushedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const Drawer(child: Center(child: Text('DRAWER CONTENT'))),
      appBar: AppBar(
        // An EXPLICIT leading keeps the back arrow: a Scaffold's own drawer would
        // otherwise claim the leading slot (app_bar.dart: `if (hasDrawer) leading =
        // DrawerButton()`) and replace it. The menu button in `actions` opens the
        // drawer instead.
        leading: const BackButton(),
        title: const Text('Pushed'),
        actions: const [DrawerMenuButton()],
      ),
      body: const Center(child: Text('body')),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a pushed screen keeps its back arrow and its menu button works',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const _PushedScreen()),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // 1. The back arrow survived: the drawer did not claim the leading slot.
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('Pushed'), findsOneWidget);

    // 2. The menu button opens the drawer (the Scaffold.of trap is handled).
    expect(find.text('DRAWER CONTENT'), findsNothing);
    await tester.tap(find.byType(DrawerMenuButton));
    await tester.pumpAndSettle();
    expect(find.text('DRAWER CONTENT'), findsOneWidget);
  });
}
