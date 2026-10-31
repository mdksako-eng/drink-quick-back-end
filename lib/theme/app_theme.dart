// theme/app_theme.dart
// The app's visual tokens, in ONE place.
//
// WHY: the UI grew 27 gradients, 33 one-off box shadows and 194 hand-picked
// `withValues(alpha:)` values, so the drawer, the cards, the dialogs and the till
// each expressed "a surface" slightly differently. Consistency is what reads as
// polish — and unlike blur it costs nothing on the GPU.
//
// This is deliberately NOT a new style ("glass", "neumorphism"). The app is a till
// used in daylight on low-end Android phones: legibility and frame rate win over
// novelty. Widgets still take their colours from Theme.of(context), so both themes
// keep working; these tokens are the shared vocabulary around that.
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Corner radii. Three sizes and a pill, so a panel and a card cannot disagree.
class AppRadius {
  AppRadius._();
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double pill = 999;

  static BorderRadius get smallAll => BorderRadius.circular(small);
  static BorderRadius get mediumAll => BorderRadius.circular(medium);
  static BorderRadius get largeAll => BorderRadius.circular(large);
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}

/// Spacing steps. Named, so a layout reads as intent instead of magic numbers.
class AppSpace {
  AppSpace._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Opacity steps for translucent overlays. `withValues(alpha: 0.1)` sprinkled by
/// hand is how 194 slightly-different greys happened.
class AppAlpha {
  AppAlpha._();
  static const double faint = 0.06;
  static const double subtle = 0.10;
  static const double medium = 0.20;
  static const double strong = 0.32;
}

/// Elevation, in two levels. Theme-aware on purpose: a shadow that reads well on a
/// white surface is invisible on a dark one, so dark leans on the surface tint and
/// keeps only a hint of shadow.
class AppShadow {
  AppShadow._();

  /// Barely-there lift: cards, list panels, the drawer's own header.
  static List<BoxShadow> soft(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? AppAlpha.strong : 0.08),
        blurRadius: dark ? 12 : 16,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// A surface that floats above the page: dialogs, the bottom sheet.
  static List<BoxShadow> raised(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.5 : 0.14),
        blurRadius: dark ? 20 : 28,
        offset: const Offset(0, 8),
      ),
    ];
  }
}

/// The single brand surface: the gradient the drawer header and the auth hero
/// share. One deliberate brand moment per screen, instead of a gradient sprinkled
/// wherever a container happened to need a colour.
class AppBrand {
  AppBrand._();

  /// [primary] with a slightly darker second stop, so it works in both themes (a
  /// translucent stop lets the drawer's background bleed through).
  static LinearGradient surface(Color primary) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, Color.lerp(primary, Colors.black, 0.22)!],
      );

  /// Legible on [surface] in both themes — the gradient is the same colour either
  /// way, so its text is too.
  static const Color onSurface = Colors.white;
  static const Color onSurfaceMuted = Color.fromRGBO(255, 255, 255, 0.72);
}

/// Text styles the whole app can share.
class AppText {
  AppText._();

  /// A drawer entry: bold when it is the screen you are on.
  ///
  /// Selection is deliberately NOT colour-only (bold + the accent bar + the tinted
  /// panel), because colour alone fails for a colour-blind or hurried user.
  static TextStyle itemLabel(BuildContext context, {required bool selected}) {
    final scheme = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 14,
      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
    );
  }

  /// The small letter-spaced label above a group of entries.
  static TextStyle sectionLabel(BuildContext context) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
}

/// Elevation steps, so a card and a dialog cannot disagree about what "floating" is.
/// Material's own scale: 0 flat, 2 a card, 4 a bar, 8 something above the page.
class AppElevation {
  AppElevation._();
  static const double flat = 0;
  static const double soft = 2;
  static const double raised = 4;
  static const double floating = 8;
}

/// The app's ONE glass treatment, and it is opt-in on purpose.
///
/// WHERE IT IS ALLOWED: a surface whose backdrop does not move — today the lock
/// screen, which covers a frozen app. The rule is about cost, not taste:
/// `BackdropFilter` re-blurs its region every frame, so glass *behind a scrolling
/// list* would burn a low-end phone's frame budget while a cashier scrolls looking
/// for a bottle. That is the whole reason the rest of the app has none.
///
/// This is deliberately restrained glass — a small blur, a tint that keeps text
/// legible, and a hairline edge — not a full glassmorphism skin: the surface stays a
/// surface, and the money on it stays readable in daylight.
class AppGlass {
  AppGlass._();

  /// Enough to read as glass, small enough to stay cheap on the GPU.
  static const double blur = 12;

  /// A tint for a glass panel that carries text of its own.
  static Color fill(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? Colors.black.withValues(alpha: AppAlpha.medium)
        : Colors.white.withValues(alpha: AppAlpha.subtle);
  }

  /// A hairline edge, so a glass panel does not dissolve into what is behind it.
  static Border hairline(BuildContext context) => Border.all(
        color: Theme.of(context)
            .colorScheme
            .outlineVariant
            .withValues(alpha: AppAlpha.medium),
      );

  /// Wraps [child] in a blur. [child] is painted ON TOP of the blur, so pass the
  /// translucent gradient or tint there — an opaque child would simply hide it.
  static Widget surface({
    required Widget child,
    double blurRadius = blur,
    BorderRadius? radius,
    Color? tint,
  }) {
    return ClipRRect(
      borderRadius: radius ?? BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurRadius, sigmaY: blurRadius),
        child: tint == null
            ? child
            : Container(decoration: BoxDecoration(color: tint), child: child),
      ),
    );
  }
}

/// The role chip in the drawer header. Pure, so the colours are unit tested rather
/// than nested ternaries inside a build method.
class AppRoleBadge {
  AppRoleBadge._();

  /// Amber for a platform admin, orange for a manager/owner, blue for staff, and a
  /// neutral translucent white for anything else (a customer account).
  static Color background(String? role) {
    switch ((role ?? '').trim().toLowerCase()) {
      case 'admin':
      case 'administrator':
        return Colors.amber;
      case 'manager':
      case 'owner':
        return Colors.orange;
      case 'staff':
        return Colors.blue;
      default:
        return Colors.white24;
    }
  }

  /// Dark text on the light chips (amber), white on the rest.
  static Color foreground(String? role) {
    final normalised = (role ?? '').trim().toLowerCase();
    if (normalised == 'admin' || normalised == 'administrator') {
      return Colors.black87;
    }
    return Colors.white;
  }
}
