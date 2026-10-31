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

  group('elevation steps', () {
    test('grow flat -> soft -> raised -> floating', () {
      expect(AppElevation.flat, lessThan(AppElevation.soft));
      expect(AppElevation.soft, lessThan(AppElevation.raised));
      expect(AppElevation.raised, lessThan(AppElevation.floating));
      expect(AppElevation.flat, 0);
    });
  });

  group('the app-wide theme takes its shapes from the tokens', () {
    final main = File('lib/main.dart').readAsStringSync();

    test('the theme builders use the radius and elevation tokens', () {
      expect(main, contains('AppRadius.mediumAll'));
      expect(main, contains('AppRadius.largeAll'));
      expect(main, contains('AppElevation.raised'));
      expect(main, contains('AppElevation.floating'));
    });

    test('the hand-picked theme radii are gone', () {
      // These were the two numbers every screen had to guess at before.
      expect(main, isNot(contains('BorderRadius.circular(12)')));
      expect(main, isNot(contains('BorderRadius.circular(16)')));
    });

    test('dialogs, sheets and snackbars have one shared language', () {
      expect(main, contains('dialogTheme: DialogThemeData('));
      expect(main, contains('bottomSheetTheme: BottomSheetThemeData('));
      expect(main, contains('snackBarTheme: SnackBarThemeData('));
    });
  });

  group('the glass rule (static surfaces only)', () {
    test('the blur stays modest, so it cannot quietly become expensive', () {
      expect(AppGlass.blur, lessThanOrEqualTo(16));
    });

    test('no screen uses it — the backdrop there can move', () {
      // `BackdropFilter` re-blurs its region every frame, so glass behind a scrolling
      // list burns a low-end phone's frame budget. The lock overlay is the one place
      // whose backdrop is frozen; this test is what keeps it that way.
      final offenders = Directory('lib/screens')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('AppGlass'))
          .map((f) => f.path)
          .toList();

      expect(offenders, isEmpty);
    });

    test('it is applied exactly once, on the lock overlay', () {
      final main = File('lib/main.dart').readAsStringSync();
      // Count the CALL, not the name: the surrounding comment mentions AppGlass too.
      expect('AppGlass.surface('.allMatches(main).length, 1);
    });
  });
}
