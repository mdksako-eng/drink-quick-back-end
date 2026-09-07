// widgets/language_toggle.dart
// A compact, professional EN/FR segmented language switcher.
import 'package:flutter/material.dart';
import '../utils/i18n.dart';

class LanguageToggle extends StatelessWidget {
  final Color? activeColor;
  final Color? activeTextColor;
  final Color? inactiveTextColor;
  final Color? backgroundColor;

  const LanguageToggle({
    super.key,
    this.activeColor,
    this.activeTextColor,
    this.inactiveTextColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = activeColor ?? theme.primaryColor;
    final onActive = activeTextColor ?? Colors.white;
    final inactive = inactiveTextColor ?? theme.colorScheme.onSurface;

    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.instance.language,
      builder: (context, lang, _) {
        final isFr = lang == LanguageService.fr;
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: backgroundColor ?? theme.dividerColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _segment('EN', !isFr, active, onActive, inactive),
              _segment('FR', isFr, active, onActive, inactive),
            ],
          ),
        );
      },
    );
  }

  Widget _segment(String label, bool selected, Color active, Color onActive,
      Color inactive) {
    return GestureDetector(
      onTap: () {
        if (!selected) LanguageService.instance.toggle();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? active : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: selected ? onActive : inactive,
          ),
        ),
      ),
    );
  }
}
