// widgets/activity_detector.dart
import 'package:flutter/material.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';

class ActivityDetector extends StatelessWidget {
  final Widget child;

  const ActivityDetector({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => LockService().resetTimer(),
      onPanDown: (_) => LockService().resetTimer(),
      onScaleStart: (_) => LockService().resetTimer(),
      onLongPress: () => LockService().resetTimer(),
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}