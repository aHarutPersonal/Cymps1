// The daily-habit toggle shared by the Today and Plan tabs (`useHabitToggle`
// in `v3/plan.jsx`, the toggle in `v3/today.jsx`).

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/v3/v3.dart';
import '../../plan/data/plan_repository.dart';
import '../../plan/models/plan_models.dart';
import '../../plan/state/current_plan_provider.dart';
import 'plan_providers.dart';
import 'today_data.dart';

/// Checking a habit is optimistic: the mark shows at once, then
/// `POST /plan-items/{id}/daily-toggle` runs.
///
/// - On failure the mark rolls back with the toast "Couldn’t update — try
///   again.".
/// - On success `todayViewProvider`, `todayStreakProvider` and the habit's
///   week are invalidated (also when the screen has closed meanwhile), and
///   the optimistic mark is dropped once fresh data arrives.
/// - A second tap on a habit while its toggle is in flight is ignored.
/// - Checking a habit that is not the last of the day toasts "Done for
///   today". Checking the last one celebrates the day once the server
///   confirms, at least 500 ms after the tap (the design's timeout).
///
/// Call [watchFreshHabits] from `build`, and read marks through
/// [isHabitDone].
mixin HabitToggleMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Habit id → shown completion while a toggle is in flight or until the
  /// next fresh today view arrives.
  final Map<String, bool> _optimisticHabits = {};
  final Set<String> _habitsInFlight = {};

  /// Whether [item] shows as done today, optimistic marks included.
  bool isHabitDone(TodayTaskItem item) =>
      _optimisticHabits[item.id] ?? item.completedToday;

  /// Whether a toggle of the habit [id] is waiting on the server (a tap now
  /// would be ignored).
  bool isHabitInFlight(String id) => _habitsInFlight.contains(id);

  /// Fresh habits from the server replace optimistic marks that are no
  /// longer in flight. Call from `build`.
  void watchFreshHabits() {
    ref.listen<AsyncValue<TodayView?>>(todayViewProvider, (previous, next) {
      if (next.isLoading || !next.hasValue || _optimisticHabits.isEmpty) return;
      setState(
        () => _optimisticHabits.removeWhere(
          (id, _) => !_habitsInFlight.contains(id),
        ),
      );
    });
  }

  /// Toggles [item] of [view]. With [toastOnUndo] un-checking toasts "Marked
  /// not done" (the Plan tab's wording); Today stays quiet.
  Future<void> toggleHabit(
    TodayView view,
    TodayTaskItem item, {
    bool toastOnUndo = false,
  }) async {
    if (_habitsInFlight.contains(item.id)) return;
    final nowDone = !isHabitDone(item);
    final allDoneAfter =
        nowDone && view.items.every((i) => i.id == item.id || isHabitDone(i));
    // The server streak already counts today once any habit is done today.
    final streakBeforeToday = view.completedToday > 0
        ? math.max(0, view.streak - 1)
        : view.streak;
    setState(() {
      _optimisticHabits[item.id] = nowDone;
      _habitsInFlight.add(item.id);
    });
    if (nowDone && !allDoneAfter) {
      showV3Toast(context, 'Done for today');
    } else if (!nowDone && toastOnUndo) {
      showV3Toast(
        context,
        'Marked not done',
        icon: V3Icons.refresh,
        tone: V3ToastTone.warn,
      );
    }
    // The design celebrates 500 ms after the last check.
    final celebrateAfter = Future<void>.delayed(
      const Duration(milliseconds: 500),
    );
    // Today, the streak and the week refresh even if this screen closes
    // before the server answers (the habit screen can be popped mid-toggle).
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final completed = await ref
          .read(planRepositoryProvider)
          .toggleDailyTask(item.id);
      container
        ..invalidate(todayViewProvider)
        ..invalidate(todayStreakProvider)
        ..invalidate(habitDailyStatusProvider(item.id));
      if (!mounted) return;
      setState(() {
        _habitsInFlight.remove(item.id);
        _optimisticHabits[item.id] = completed;
      });
      if (allDoneAfter && completed) {
        await celebrateAfter;
        if (!mounted) return;
        await showCelebration(context, Celebration.day(streakBeforeToday));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _habitsInFlight.remove(item.id);
        _optimisticHabits.remove(item.id);
      });
      showV3Toast(
        context,
        'Couldn’t update — try again.',
        icon: V3Icons.alert,
        tone: V3ToastTone.warn,
      );
    }
  }
}
