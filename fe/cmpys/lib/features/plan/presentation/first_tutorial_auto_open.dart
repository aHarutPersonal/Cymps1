// Tutorial 1 opens by itself once: when the learner waits on the "preparing
// your first tutorial" state (the mission screen or Today) and it becomes
// readable. Per mission, per app session; never after the learner opened it.

import 'package:flutter/widgets.dart';

/// The missions whose first tutorial has been opened in this app session,
/// by the learner or automatically.
abstract final class FirstTutorialAutoOpen {
  static final Set<String> _opened = {};

  /// Records that tutorial 1 of [missionId] was opened.
  static void markOpened(String missionId) => _opened.add(missionId);

  /// Whether tutorial 1 of [missionId] may open by itself now; true at most
  /// once per mission, and never after [markOpened].
  static bool claim(String missionId) => _opened.add(missionId);

  @visibleForTesting
  static void resetForTest() => _opened.clear();
}

/// Whether [context]'s page is the top route of its navigator and of every
/// navigator above it: nothing (a page, a sheet, a dialog) covers it, even on
/// the root navigator over a shell branch, whose own route stays current.
bool routeIsOnTop(BuildContext context) {
  var scope = context;
  var navigator = Navigator.maybeOf(context);
  while (true) {
    final route = ModalRoute.of(scope);
    if (route != null && !route.isCurrent) return false;
    if (navigator == null) return true;
    final parent = navigator.context.findAncestorStateOfType<NavigatorState>();
    if (parent == null) return true;
    // The route of the parent navigator that hosts this navigator.
    scope = navigator.context;
    navigator = parent;
  }
}
