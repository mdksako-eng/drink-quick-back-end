// utils/app_info_helper.dart
//
// The version is declared once, as `AppConstants.appVersion`, and must equal the
// `version:` field of pubspec.yaml. Letting the two drift is how the drawer came
// to say 1.1.0 while the lock screen said 1.0.0 and support reports said a third
// thing. The helpers below are pure so the guard test can check both the constant
// and every file on disk.

/// The version declared in pubspec.yaml: `version: 1.0.0+1` → `1.0.0`.
/// Returns null when the file carries no version line.
String? versionFromPubspec(String pubspecContents) {
  final match = RegExp(r'^\s*version:\s*([^\s#]+)', multiLine: true)
      .firstMatch(pubspecContents);
  if (match == null) return null;
  return match.group(1)!.split('+').first.trim();
}

/// Every version-looking literal (`x.y.z`) **inside a string literal** in
/// [source]. A non-empty result means someone hardcoded a version instead of
/// reading `AppConstants.appVersion`. Comments are ignored on purpose: this file
/// and the changelog may talk about versions.
List<String> hardcodedVersionsIn(String source) {
  final pattern = RegExp("'[^'\n]*\\b\\d+\\.\\d+\\.\\d+\\b[^'\n]*'");
  return pattern.allMatches(source).map((m) => m.group(0)!).toList();
}
