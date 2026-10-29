// Providers behind the Plan tab, next to `today_data.dart`'s.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../plan/data/plan_repository.dart';
import '../../plan/models/plan_models.dart';
import 'plan_data.dart';
import 'today_data.dart';

/// A mission's tutorials read with `?peek=true`: a pure read that never
/// promotes a prefetch job or enqueues generation. The Plan tab reads every
/// mission of the week this way except the one in front of the learner, so
/// opening the tab can never start paid work.
final planMissionPeekProvider = FutureProvider.autoDispose
    .family<PlanItemDetailed, String>((ref, itemId) {
      return ref.watch(planRepositoryProvider).peekPlanItemDetailed(itemId);
    });

/// Whether the server behind [plan] honours `?peek=true`. Peek shipped with
/// the plan's `weeklyMinutes`; an older server ignores the flag and runs the
/// normal read, which can start paid generation. So on a plan without
/// `weeklyMinutes` the app reads only the mission to work on.
bool planSupportsPeek(BackendPlan plan) => plan.weeklyMinutes != null;

/// The provider that reads a week mission's tutorials: the mission to work
/// on now through the normal read (shared with Today, exactly as it reads
/// it), every other mission through [planMissionPeekProvider]. Null when the
/// mission must not be read at all: a peek on a server that cannot peek
/// ([planSupportsPeek]); its card then shows the header only.
AutoDisposeFutureProvider<PlanItemDetailed>? planMissionDetailProvider(
  String itemId, {
  required bool peek,
  bool peekSupported = true,
}) => !peek
    ? todayMissionDetailProvider(itemId)
    : peekSupported
    ? planMissionPeekProvider(itemId)
    : null;

/// A habit's completions for each day of this week
/// (GET /plan-items/{id}/daily-status): the Plan tab's per-habit 7-day grid.
/// Invalidated after a toggle.
final habitDailyStatusProvider = FutureProvider.autoDispose
    .family<DailyStatus, String>((ref, itemId) {
      return ref.watch(planRepositoryProvider).getDailyStatus(itemId);
    });

/// A habit's Monday-to-Sunday grid as the Plan tab and the habit screen show
/// it: its own week from [habitDailyStatusProvider], with today null (the
/// screen fills it from the live habit). While that loads no day shows done;
/// if it fails, the days of the streak run stand in.
List<bool?> watchHabitWeek(WidgetRef ref, String itemId, DateTime today) {
  final status = ref.watch(habitDailyStatusProvider(itemId));
  if (status.hasValue) return habitWeekFromStatus(status.value, today);
  if (status.hasError) {
    return streakWeek(ref.watch(todayStreakProvider).valueOrNull, today);
  }
  return habitWeekFromStatus(null, today);
}
