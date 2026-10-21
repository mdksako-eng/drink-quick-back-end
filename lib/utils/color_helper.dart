// utils/color_helper.dart
// Reading a colour that came from company settings or SharedPreferences.
//
// WHY THIS EXISTS: the app did `Color(int.parse(hex.replaceFirst('#', '0xFF')))`
// in eight places. One empty or corrupted value (a failed save, an older build, a
// hand-edited preference) throws a FormatException **inside build()** — the screen
// dies with no way back. This parser never throws: anything it cannot read falls
// back to the brand colour.
import 'package:flutter/material.dart';

/// Used when a stored value is missing or unreadable.
const Color kFallbackPrimaryColor = Color(0xFF667EEA);

/// Parse `#RRGGBB`, `RRGGBB`, `#RGB`, `#AARRGGBB`, `AARRGGBB` or `0xAARRGGBB`.
///
/// Never throws: returns [fallback] for null, empty, wrong-length or non-hex input.
Color parseHexColor(String? value, {Color fallback = kFallbackPrimaryColor}) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return fallback;

  var hex = raw;
  if (hex.startsWith('#')) {
    hex = hex.substring(1);
  } else if (hex.toLowerCase().startsWith('0x')) {
    hex = hex.substring(2);
  }

  // #RGB shorthand → #RRGGBB
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length != 6 && hex.length != 8) return fallback;
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return fallback;

  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return fallback;

  // Six digits mean an opaque colour; eight already carry their alpha.
  return Color(hex.length == 8 ? parsed : (0xFF000000 | parsed));
}
