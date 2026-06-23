import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../data/daily_tasks_repository.dart';
import '../models/daily_task_models.dart';

/// Provider for the daily tasks repository.
final dailyTasksRepoProvider = Provider<DailyTasksRepository>((ref) {
  return DailyTasksRepository(dioClient: ref.watch(dioClientProvider));
});

/// State for the daily tasks notifier.
sealed class DailyTasksState {
  const DailyTasksState();
}

class DailyTasksInitial extends DailyTasksState {
  const DailyTasksInitial();
}

class DailyTasksLoading extends DailyTasksState {
  const DailyTasksLoading();
}

class DailyTasksLoaded extends DailyTasksState {
  const DailyTasksLoaded({required this.overview});
  final TodayOverview overview;
}

class DailyTasksError extends DailyTasksState {
  const DailyTasksError({this.message = ''});
  final String message;
}

/// Notifier for daily tasks.
class DailyTasksNotifier extends StateNotifier<DailyTasksState> {
  DailyTasksNotifier({
    required DailyTasksRepository repository,
  }) : _repository = repository, super(const DailyTasksInitial());

  final DailyTasksRepository _repository;

  String? _currentPlanId;

  /// Load today's tasks for a plan.
  Future<void> load(String planId) async {
    _currentPlanId = planId;
    state = const DailyTasksLoading();

    try {
      final overview = await _repository.getTodayTasks(planId);

      if (overview.hasDailyTasks) {
        state = DailyTasksLoaded(overview: overview);
      } else {
        // No daily tasks — use empty loaded state so UI knows to hide widget.
        state = DailyTasksLoaded(overview: overview);
      }
    } catch (e) {
      debugPrint('Failed to load daily tasks: $e');
      state = const DailyTasksError(message: 'Failed to load daily tasks');
    }
  }

  /// Toggle a daily task's completion.
  Future<void> toggleDailyTask(String itemId) async {
    final currentState = state;
    if (currentState is! DailyTasksLoaded) return;

    // Optimistic update
    final oldOverview = currentState.overview;
    final newItems = oldOverview.items.map((task) {
      if (task.id == itemId) {
        return DailyTask(
          id: task.id,
          title: task.title,
          type: task.type,
          estimatedHours: task.estimatedHours,
          completedToday: !task.completedToday,
          dailyInstructions: task.dailyInstructions,
        );
      }
      return task;
    }).toList();

    final newCompletedCount = newItems.where((t) => t.completedToday).length;
    state = DailyTasksLoaded(
      overview: TodayOverview(
        date: oldOverview.date,
        items: newItems,
        streak: oldOverview.streak,
        totalToday: oldOverview.totalToday,
        completedToday: newCompletedCount,
      ),
    );

    try {
      await _repository.toggleDailyTask(itemId);
      // Refresh to get accurate server state
      if (_currentPlanId != null) {
        final refreshed = await _repository.getTodayTasks(_currentPlanId!);
        state = DailyTasksLoaded(overview: refreshed);
      }
    } catch (e) {
      // Revert on error
      state = DailyTasksLoaded(overview: oldOverview);
    }
  }

  /// Refresh today's tasks.
  Future<void> refresh() async {
    if (_currentPlanId == null) return;
    await load(_currentPlanId!);
  }
}

/// Provider for daily tasks state.
final dailyTasksProvider =
    StateNotifierProvider<DailyTasksNotifier, DailyTasksState>((ref) {
      return DailyTasksNotifier(
        repository: ref.watch(dailyTasksRepoProvider),
      );
    });

/// Provider for streak info.
final streakProvider = FutureProvider<StreakInfo>((ref) {
  return ref.watch(dailyTasksRepoProvider).getStreak();
});

/// Provider for daily focus.
final dailyFocusProvider = FutureProvider<DailyFocus>((ref) {
  return ref.watch(dailyTasksRepoProvider).getDailyFocus();
});
