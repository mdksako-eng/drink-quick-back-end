// utils/drawer_navigation.dart
// Where each drawer entry belongs, and whether a search query matches it. Pure —
// unit tested — so the grouping and the filter are decisions a test can check
// instead of something you eyeball in a 1200-line widget.
//
// The three main groups answer three different questions, in the order a person
// asks them during a shift:
//   daily   - what do I touch while serving? (sell, scan, cash up, customers)
//   reports - what do I open when I want an answer? (read-only analysis)
//   setup   - what do I change rarely? (catalogue, stock, settings, billing)
// Manager / admin / support keep their own groups.

/// A drawer destination.
///
/// The drawer is told which one is currently on screen, so the highlight is
/// derived from the truth instead of being hardcoded to one entry.
enum DrawerScreen {
  dashboard,
  profile,
  scan,
  shift,
  customers,
  containers,
  purchasing,
  invoices,
  aiAssistant,
  analytics,
  forecast,
  variance,
  drinks,
  inventory,
  settings,
  subscription,
  staff,
  approvals,
  adminPanel,
  about,
  help,
  reportProblem,
}

/// The sections the drawer renders, in order.
enum DrawerGroup { daily, reports, setup, manager, admin, support }

/// Section order: what you use while serving comes first, the rarely-touched
/// configuration comes last.
const List<DrawerGroup> kDrawerGroupOrder = [
  DrawerGroup.daily,
  DrawerGroup.reports,
  DrawerGroup.setup,
  DrawerGroup.manager,
  DrawerGroup.admin,
  DrawerGroup.support,
];

/// i18n key of a group's header.
String drawerGroupLabelKey(DrawerGroup group) {
  switch (group) {
    case DrawerGroup.daily:
      return 'menuMain';
    case DrawerGroup.reports:
      return 'menuManagement';
    case DrawerGroup.setup:
      return 'menuSetup';
    case DrawerGroup.manager:
      return 'menuManager';
    case DrawerGroup.admin:
      return 'menuAdmin';
    case DrawerGroup.support:
      return 'menuSupport';
  }
}

/// Does [label] match what the user typed? An empty query matches everything.
///
/// Case- and accent-insensitive: the two languages disagree about accents
/// ("Réapprovisionnement") and nobody types them into a search box.
bool drawerSearchMatches(String query, String label) {
  final needle = foldForSearch(query);
  if (needle.isEmpty) return true;
  return foldForSearch(label).contains(needle);
}

/// Lower-cased, accent-folded text, for comparing a typed query with a label.
String foldForSearch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll('ç', 'c')
    .trim();
