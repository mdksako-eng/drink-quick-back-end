// widgets/skeleton.dart
// Lightweight loading skeletons (no external dependency).
import 'package:flutter/material.dart';

/// A subtle pulsing placeholder block.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A skeleton for a screen that loads a list of cards + a header row.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 84,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => SkeletonBox(height: itemHeight, radius: 12),
    );
  }
}
