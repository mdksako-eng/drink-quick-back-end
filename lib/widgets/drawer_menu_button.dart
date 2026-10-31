// widgets/drawer_menu_button.dart
// The app drawer's button for a screen that is NOT the till.
//
// WHY A WIDGET AND NOT AN INLINE IconButton: the obvious
//
//     appBar: AppBar(actions: [
//       IconButton(onPressed: () => Scaffold.of(context).openDrawer())
//     ])
//
// throws "No Scaffold widget found". The `context` there belongs to the enclosing
// build method, which sits ABOVE the Scaffold — the AppBar widget is *constructed*
// before the Scaffold exists in the element tree. A `Builder` would fix it, but the
// trap is easy to reintroduce, so the fix lives here once: this widget's own build
// context is a descendant of the Scaffold, so `Scaffold.of` resolves.
import 'package:flutter/material.dart';

import '../utils/i18n.dart';

class DrawerMenuButton extends StatelessWidget {
  const DrawerMenuButton({super.key, this.color});

  /// Overrides the icon colour (an AppBar on a coloured background, for example).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.menu, color: color),
      tooltip: t('menu'),
      // The context here is below the Scaffold, which is the whole point.
      onPressed: () => Scaffold.of(context).openDrawer(),
    );
  }
}
