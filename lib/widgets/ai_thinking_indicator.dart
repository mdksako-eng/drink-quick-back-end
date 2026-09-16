// widgets/ai_thinking_indicator.dart
// Professional "AI is thinking" animation: a pulsing gradient avatar with three
// animated dots. Dependency-free (plain AnimationController).
import 'package:flutter/material.dart';

class AiThinkingIndicator extends StatefulWidget {
  /// Localized label shown next to the animation (e.g. "AI is thinking…").
  final String label;
  final Color color;

  const AiThinkingIndicator({
    Key? key,
    required this.label,
    this.color = Colors.white,
  }) : super(key: key);

  @override
  State<AiThinkingIndicator> createState() => _AiThinkingIndicatorState();
}

class _AiThinkingIndicatorState extends State<AiThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingAvatar(controller: _controller, color: widget.color),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: widget.color,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Dots(controller: _controller, color: widget.color),
        ],
      ),
    );
  }
}

/// Softly scaling/glowing avatar so the wait feels alive but not busy.
class _PulsingAvatar extends StatelessWidget {
  final AnimationController controller;
  final Color color;

  const _PulsingAvatar({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(
            (controller.value <= 0.5 ? controller.value : 1 - controller.value) * 2);
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [
              Theme.of(context).primaryColor,
              Color.lerp(Theme.of(context).primaryColor, Colors.purple, t)!,
            ]),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context)
                    .primaryColor
                    .withValues(alpha: 0.25 + 0.35 * t),
                blurRadius: 6 + 8 * t,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Center(
            child: Text('AI',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }
}

/// Three dots filling in sequence — the classic "typing" affordance.
class _Dots extends StatelessWidget {
  final AnimationController controller;
  final Color color;

  const _Dots({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (controller.value + i * 0.18) % 1.0;
            final strength = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            return Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 4),
              child: Opacity(
                opacity: 0.35 + 0.65 * strength,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}