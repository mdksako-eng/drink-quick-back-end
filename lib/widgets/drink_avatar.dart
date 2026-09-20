// widgets/drink_avatar.dart
// The little picture of a drink (or a company logo) used everywhere a drink is
// listed: the calculator's drink dropdown, the inventory list, the scan sheet and
// the order list. It shows the drink's real image when it has one and falls back
// to the previous generic icon when it does not (or when the URL fails to load).
import 'package:flutter/material.dart';

import '../models/drink_model.dart';
import '../utils/constants.dart';

class DrinkAvatar extends StatelessWidget {
  /// Preferred source: the drink itself.
  final Drink? drink;

  /// Explicit image URL (used when there is no [Drink], e.g. inventory rows).
  final String? imageUrl;

  /// Shown as a tooltip / semantic label.
  final String? name;

  final double size;

  /// Drawn when there is no usable image.
  final IconData fallbackIcon;

  /// Circle (lists, avatars) or rounded square (cards).
  final bool circular;

  final Color? background;
  final Color? foreground;

  const DrinkAvatar({
    super.key,
    this.drink,
    this.imageUrl,
    this.name,
    this.size = 40,
    this.fallbackIcon = Icons.local_drink,
    this.circular = true,
    this.background,
    this.foreground,
  });

  String get _url {
    final fromDrink = drink?.imageUrl.trim() ?? '';
    if (fromDrink.isNotEmpty) return fromDrink;
    return imageUrl?.trim() ?? '';
  }

  String get _label => name ?? drink?.name ?? '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = background ?? theme.primaryColor.withValues(alpha: 0.12);
    final fg = foreground ?? theme.primaryColor;
    final radius = circular ? size / 2 : size * 0.22;

    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Icon(fallbackIcon, size: size * 0.55, color: fg),
        );

    // An empty URL, or the placeholder every drink gets by default, means
    // "no picture" — those used to render as a broken image icon.
    final url = _url;
    final usable =
        url.isNotEmpty && url != AppConstants.defaultDrinkImage;

    final content = usable
        ? ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // A broken/removed picture must never break a list row.
              errorBuilder: (_, __, ___) => fallback(),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : fallback(),
            ),
          )
        : fallback();

    if (_label.isEmpty) return content;
    return Tooltip(message: _label, child: content);
  }
}