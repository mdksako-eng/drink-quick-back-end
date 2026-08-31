// widgets/floating_ai_button.dart
import 'package:flutter/material.dart';
import 'package:drinks_calculator_fixed/screens/ai_assistant_screen.dart';

class FloatingAIButton extends StatefulWidget {
  final VoidCallback? onPressed;

  const FloatingAIButton({super.key, this.onPressed});

  @override
  State<FloatingAIButton> createState() => _FloatingAIButtonState();
}

class _FloatingAIButtonState extends State<FloatingAIButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _navigateToAI() {
    if (widget.onPressed != null) {
      widget.onPressed!();
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AIAssistantScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final buttonSize = isMobile ? 60.0 : 70.0;

    return GestureDetector(
      onTap: _navigateToAI,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) => Container(
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF16A753), Color(0xFF764BA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF764BA2).withValues(alpha: 0.4),
                blurRadius: 15 * _pulseAnimation.value,
                spreadRadius: 2 * _pulseAnimation.value,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: RingsOnlyIcon(size: 55, isMobile: true),
          ),
        ),
      ),
    );
  }
}

class RingsOnlyIcon extends StatelessWidget {
  final double size;
  final bool isMobile;

  const RingsOnlyIcon({
    Key? key,
    this.size = 80,
    this.isMobile = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16A753), Color(0xFF764BA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.5,
            height: size * 0.5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
            ),
          ),
          Container(
            width: size * 0.68,
            height: size * 0.68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
            ),
          ),
          Container(
            width: size * 0.85,
            height: size * 0.85,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
            ),
          ),
          Text(
            'DQC',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              decoration: TextDecoration.none, // ADD THIS LINE - Removes underline
            ),
          ),
        ],
      ),
    );
  }
}