// test/app_theme_test.dart
// The design tokens. Pure values, so the scale is checked here rather than by
// eyeballing 28 screens — and the guards keep the drawer from drifting back to
// hand-picked alphas and radii.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/theme/app_theme.dart';

void main() {
  group('the scales are ordered, so a layout cannot pick a nonsense value', () {
    test('radius grows small -> medium -> large', () {
      expect(AppRadius.small, lessThan(AppRadius.medium));
      expect(AppRadius.medium, lessThan(AppRadius.large));
      expect(AppRadius.pill, greaterThan(AppRadius.large));
    });

    test('spacing grows in steps', () {
      const steps = [
        AppSpace.xs,
        AppSpace.sm,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.xxl,
      ];
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThan(steps[i - 1]));
      }
    });

    test('alpha steps stay inside (0, 1)', () {
      for (final a in [
        AppAlpha.faint,
        AppAlpha.subtle,
        AppAlpha.medium,
        AppAlpha.strong,
      ]) {
        expect(a, greaterThan(0));
        expect(a, lessThan(1));
      }
      expect(AppAlpha.faint, lessThan(AppAlpha.strong));
    });
  });

  group('the brand surface', () {
    test('is a two-stop gradient that darkens, so white text stays legible', () {
      final gradient = AppBrand.surface(const Color(0xFF38B000));
      expect(gradient.colors.length, 2);
      final first = gradient.colors.first.computeLuminance();
      final second = gradient.colors.last.computeLuminance();
      expect(second, lessThanOrEqualTo(first));
    });

    test('its text colours are the light ones (the gradient is brand, not theme)',
        () {
      expect(AppBrand.onSurface, Colors.white);
      expect(AppBrand.onSurfaceMuted.a, lessThan(1));
    });
  });

  group('the role badge', () {
    test('is amber for an admin, orange for a manager, blue for staff', () {
      expect(AppRoleBadge.background('Administrator'), Colors.amber);
      expect(AppRoleBadge.background('admin'), Colors.amber);
      expect(AppRoleBadge.background('Manager'), Colors.orange);
      expect(AppRoleBadge.background('Owner'), Colors.orange);
      expect(AppRoleBadge.background('Staff'), Colors.blue);
    });

    test('an unknown role falls back to a neutral chip, never a crash', () {
      expect(AppRoleBadge.background(null), Colors.white24);
      expect(AppRoleBadge.background('barista'), Colors.white24);
      expect(AppRoleBadge.foreground('barista'), Colors.white);
    });

    test('only the amber chip needs dark text', () {
      expect(AppRoleBadge.foreground('Administrator'), Colors.black87);
      expect(AppRoleBadge.foreground('Manager'), Colors.white);
      expect(AppRoleBadge.foreground('Staff'), Colors.white);
    });
  });

  group('the drawer uses the tokens (no drift back to hand-picked values)', () {
    final menu = File('lib/widgets/drawer_menu.dart').readAsStringSync();
    final shell = File('lib/widgets/custom_drawer.dart').readAsStringSync();

    test('the selected row is styled by AppText, not an inline TextStyle', () {
      expect(menu, contains('AppText.itemLabel(context'));
      expect(menu, contains('AppText.sectionLabel(context'));
    });

    test('the drawer takes its radii and spacing from the tokens', () {
      expect(menu, contains('AppRadius.mediumAll'));
      expect(menu, contains('AppSpace.'));
      expect(shell, contains('AppBrand.surface('));
      expect(shell, contains('AppRoleBadge.background('));
      expect(shell, contains('AppShadow.soft('));
    });

    test('the old hand-picked selection tint is gone', () {
      // 10 % of the primary colour was the old highlight; it is nearly invisible in
      // dark mode, which is why the M3 secondaryContainer role replaced it.
      expect(menu, isNot(contains('withValues(alpha: 0.1)')));
    });
  });
}
