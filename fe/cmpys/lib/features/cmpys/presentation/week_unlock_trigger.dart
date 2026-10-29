// When the "Week unlocked" moment (`WeekUnlock` in `v3/app.jsx`, M1's
// `showWeekUnlock`) shows, shared by the Plan and Today tabs so both use one
// rule.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/v3/v3.dart';
import '../../plan/models/plan_models.dart';
import '../state/cmpys_store.dart';
import '../state/plan_data.dart';
import '../state/plan_providers.dart';
import '../state/today_data.dart';

/// The week of [plan] whose "Week n unlocked" moment is due, or null.
///
/// A week is due when it is the plan's current (focus) week, it is after
/// week 1, it has missions of its own, and the plan records finished
/// missions ending before it: the server's own week data says the learner
/// finished the weeks before and moved on. Null for week 1, for a plan
/// whose work is all done, and for a plan without week data (an older
/// server puts every item in week 1, so its focus week is never past 1).
///
/// This does not consult the per-account ledger; [maybeShowWeekUnlock] does.
int? weekUnlockDueWeek(BackendPlan plan) {
  if (plan.id.trim().isEmpty || plan.allMissionWorkComplete) return null;
  final week = plan.focusWeek;
  if (week <= 1 || week > plan.durationWeeks) return null;
  if (plan.missionsForWeek(week).isEmpty) return null;
  final finishedBefore = plan.items.any(
    (item) => !item.isDailyRhythm && item.isCompleted && item.weekEnd < week,
  );
  return finishedBefore ? week : null;
}

/// Whether the backend reports [week]'s missions ready, from data the app
/// has already loaded: some mission of the week has a written tutorial in a
/// detail read that already exists (Today's / Plan's read of the mission to
/// work on, or the Plan tab's peek of the others). Never starts a read (a
/// normal read can start generation); nothing loaded means not ready.
bool weekUnlockMissionsReady(WidgetRef ref, BackendPlan plan, int week) {
  for (final mission in plan.missionsForWeek(week)) {
    for (final provider in _detailReads(mission.id)) {
      if (!ref.exists(provider)) continue;
      final detail = ref.read(provider).valueOrNull;
      if (detail != null && detail.readyLessonCount > 0) return true;
    }
  }
  return false;
}

List<AutoDisposeFutureProvider<PlanItemDetailed>> _detailReads(String id) => [
  todayMissionDetailProvider(id),
  planMissionPeekProvider(id),
];

/// Set while one "Week unlocked" moment is being decided or shown, so the
/// Plan and Today tabs never show it twice at once.
bool _weekUnlockBusy = false;

/// Shows "Week n unlocked" for [plan] if it is due ([weekUnlockDueWeek])
/// and this account hasn't seen it for this plan (the store's ledger), and
/// returns the learner's choice; null when nothing was shown.
///
/// - Call it after a frame (e.g. from a post-frame callback) with the
///   plan the screen shows. Calling it on every build is fine: it returns
///   at once when nothing is due, and never shows the same week twice.
/// - It shows only while [context]'s route is current and its tab is on
///   screen (onboarding replaces the app shell, so it never shows there),
///   and only once the account's data has loaded.
/// - It waits up to [readyWait] for a mission read of the week that is
///   already loading, then says the missions are prepared only if one of
///   them has a written tutorial ([weekUnlockMissionsReady]).
/// - It records the week as shown as soon as the moment opens.
///
/// What "Start week n" leads to ([WeekUnlockResult.start]) is the caller's:
/// the Plan tab scrolls to the current week.
Future<WeekUnlockResult?> maybeShowWeekUnlock(
  BuildContext context,
  WidgetRef ref,
  BackendPlan plan, {
  Duration readyWait = const Duration(seconds: 3),
}) async {
  final week = weekUnlockDueWeek(plan);
  if (week == null || _weekUnlockBusy) return null;
  final store = ref.read(cmpysStoreProvider.notifier);
  if (!store.shouldShowWeekUnlock(plan.id, week)) return null;
  if (!_onScreen(context)) return null;

  _weekUnlockBusy = true;
  try {
    await _waitForLoadingReads(ref, plan, week, readyWait);
    if (!context.mounted ||
        !_onScreen(context) ||
        !store.shouldShowWeekUnlock(plan.id, week)) {
      return null;
    }
    final shown = showWeekUnlock(
      context,
      week: week,
      title: planWeekTitle(plan, week),
      totalWeeks: plan.durationWeeks,
      missionsReady: weekUnlockMissionsReady(ref, plan, week),
    );
    // Recorded as soon as it opens: it shows once even if the app closes
    // while it is up.
    unawaited(
      store
          .markWeekUnlockShown(plan.id, week)
          .then((_) {}, onError: (Object _) {}),
    );
    return await shown;
  } finally {
    _weekUnlockBusy = false;
  }
}

/// [context]'s route is the current one and its tab is on screen.
bool _onScreen(BuildContext context) =>
    context.mounted &&
    TickerMode.getNotifier(context).value &&
    (ModalRoute.of(context)?.isCurrent ?? true);

/// Waits (at most [limit]) for the week's mission reads that already exist
/// and are still loading.
Future<void> _waitForLoadingReads(
  WidgetRef ref,
  BackendPlan plan,
  int week,
  Duration limit,
) async {
  final pending = <Future<void>>[];
  for (final mission in plan.missionsForWeek(week)) {
    for (final provider in _detailReads(mission.id)) {
      if (!ref.exists(provider) || !ref.read(provider).isLoading) continue;
      pending.add(
        ref.read(provider.future).then((_) {}, onError: (Object _) {}),
      );
    }
  }
  if (pending.isEmpty) return;
  await Future.wait(pending).timeout(limit, onTimeout: () => const []);
}

/// Resets the one-at-a-time guard (for tests).
@visibleForTesting
void debugResetWeekUnlockTrigger() => _weekUnlockBusy = false;
