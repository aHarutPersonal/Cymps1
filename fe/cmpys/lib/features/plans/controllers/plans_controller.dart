import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../auth/controllers/session_controller.dart';
import '../../idols/data/jobs_repository.dart';
import '../../idols/models/job_models.dart';
import '../data/plans_repository.dart';
import '../models/plan_models.dart';

/// Plans state.
sealed class PlansState {
  const PlansState();
}

class PlansInitial extends PlansState {
  const PlansInitial();
}

class PlansLoading extends PlansState {
  const PlansLoading();
}

class PlansNoPlan extends PlansState {
  const PlansNoPlan();
}

class PlansGenerating extends PlansState {
  const PlansGenerating({this.jobId, this.jobStatus});
  final String? jobId;
  final JobStatus? jobStatus;
}

class PlansLoaded extends PlansState {
  const PlansLoaded({
    required this.plan,
    this.weekSummaries = const {},
  });
  
  final Plan plan;
  
  /// Cached week summaries by week number
  final Map<int, WeekSummary> weekSummaries;

  /// Get completed items count
  int get completedCount => plan.items.where((i) => i.isCompleted).length;

  /// Get total items count
  int get totalCount => plan.items.length;

  /// Get overall progress (0-1)
  double get progress => totalCount > 0 ? completedCount / totalCount : 0;

  /// Get week summary for a specific week (from cache or calculate from items)
  WeekSummary? getWeekSummary(int week) {
    // Return cached summary if available
    if (weekSummaries.containsKey(week)) {
      return weekSummaries[week];
    }
    return null;
  }

  /// Calculate week progress from local items (fallback when no API data)
  (int completed, int total, double progress) calculateWeekProgress(int week) {
    final weekItems = plan.itemsForWeek(week);
    final completed = weekItems.where((i) => i.isCompleted).length;
    final total = weekItems.length;
    final progressPercent = total > 0 ? completed / total : 0.0;
    return (completed, total, progressPercent);
  }

  /// Create a copy with updated week summary
  PlansLoaded copyWithWeekSummary(int week, WeekSummary summary) {
    return PlansLoaded(
      plan: plan,
      weekSummaries: {...weekSummaries, week: summary},
    );
  }

  /// Create a copy with updated plan
  PlansLoaded copyWithPlan(Plan newPlan) {
    return PlansLoaded(
      plan: newPlan,
      weekSummaries: weekSummaries,
    );
  }
}

class PlansError extends PlansState {
  const PlansError({required this.message});
  final String message;
}

/// Plans controller provider.
final plansControllerProvider =
    StateNotifierProvider<PlansController, PlansState>((ref) {
  return PlansController(
    plansRepository: ref.watch(plansRepositoryProvider),
    jobsRepository: ref.watch(jobsRepositoryProvider),
    currentIdolId: ref.watch(currentIdolIdProvider),
    sessionController: ref.watch(sessionControllerProvider.notifier),
  );
});

/// Controller for plans screen.
class PlansController extends StateNotifier<PlansState> {
  PlansController({
    required PlansRepository plansRepository,
    required JobsRepository jobsRepository,
    required String? currentIdolId,
    required SessionController sessionController,
  })  : _plansRepository = plansRepository,
        _jobsRepository = jobsRepository,
        _currentIdolId = currentIdolId,
        _sessionController = sessionController,
        super(const PlansInitial());

  final PlansRepository _plansRepository;
  final JobsRepository _jobsRepository;
  final String? _currentIdolId;
  final SessionController _sessionController;

  /// Load current plan.
  /// Calls GET /plans/current
  Future<void> load() async {
    state = const PlansLoading();

    try {
      final plan = await _plansRepository.getCurrentPlan();

      if (plan == null) {
        state = const PlansNoPlan();
      } else {
        state = PlansLoaded(plan: plan);
      }
    } on ApiError catch (e) {
      // 404 means no plan exists
      if (e.statusCode == 404) {
        state = const PlansNoPlan();
      } else {
        state = PlansError(message: e.message);
      }
    } catch (e) {
      state = PlansError(message: e.toString());
    }
  }

  /// Generate a new plan.
  /// Calls POST /plans/generate
  Future<void> generatePlan({
    int durationWeeks = 12,
    double weeklyHours = 10,
    String? focus,
  }) async {
    if (_currentIdolId == null) {
      state = const PlansError(message: 'No idol selected');
      return;
    }

    final userAge = _sessionController.userAge;
    if (userAge == null) {
      state = const PlansError(message: 'User age not available. Please set your birth date in profile.');
      return;
    }

    state = const PlansGenerating();
    
    try {
      final response = await _plansRepository.generatePlan(
        idolId: _currentIdolId,
        targetAge: userAge,
        durationWeeks: durationWeeks,
        weeklyHours: weeklyHours,
        focus: focus,
      );

      final jobId = response.jobId;
      if (jobId == null) {
        // Fallback for instant generation
        await load();
        return;
      }

      // Start polling
      state = PlansGenerating(jobId: jobId);
      
      _jobsRepository.watchJob(jobId, pollInterval: const Duration(seconds: 1))
          .listen((status) {
            if (status.isCompleted) {
              load();
            } else if (status.isFailed) {
              state = PlansError(message: status.errorMessage ?? 'Generation failed');
            } else {
              state = PlansGenerating(jobId: jobId, jobStatus: status);
            }
          })
          .onError((error) {
            state = PlansError(message: error.toString());
          });

    } on ApiError catch (e) {
      state = PlansError(message: e.message);
    } catch (e) {
      state = PlansError(message: e.toString());
    }
  }

  /// Toggle item completion with optimistic update.
  /// Calls PATCH /plans/items/{id} then refreshes week summary
  Future<void> toggleItemCompletion(String itemId, {int? weekNumber}) async {
    final currentState = state;
    if (currentState is! PlansLoaded) return;

    final plan = currentState.plan;
    final itemIndex = plan.items.indexWhere((i) => i.id == itemId);
    if (itemIndex == -1) return;

    final item = plan.items[itemIndex];
    final newStatus = item.isCompleted ? 'pending' : 'completed';
    final newProgress = item.isCompleted ? 0 : 100;

    // Optimistic update - immediately update local state
    final optimisticItems = List<PlanItem>.from(plan.items);
    optimisticItems[itemIndex] = item.copyWith(
      status: newStatus,
      progressPercent: newProgress,
    );
    state = currentState.copyWithPlan(plan.copyWith(items: optimisticItems));

    try {
      // API call to toggle completion
      await _plansRepository.updatePlanItem(
        itemId,
        status: newStatus,
        progressPercent: newProgress,
      );

      // Refresh week summary if week is provided
      final week = weekNumber ?? item.weekStart;
      if (week != null) {
        await refreshWeekSummary(week);
      }
    } catch (e) {
      // Revert on error
      state = currentState;
    }
  }

  /// Fetch and update week summary from API
  Future<void> refreshWeekSummary(int week) async {
    final currentState = state;
    if (currentState is! PlansLoaded) return;

    try {
      final summary = await _plansRepository.getWeekSummary(
        currentState.plan.id,
        week,
      );
      
      if (state is PlansLoaded) {
        state = (state as PlansLoaded).copyWithWeekSummary(week, summary);
      }
    } catch (e) {
      // Silently fail - we still have optimistic local data
      // ignore: avoid_print
      print('Failed to refresh week summary: $e');
    }
  }

  /// Load week summary for a specific week (if not cached)
  Future<WeekSummary?> loadWeekSummary(int week) async {
    final currentState = state;
    if (currentState is! PlansLoaded) return null;

    // Return cached if available
    final cached = currentState.weekSummaries[week];
    if (cached != null) return cached;

    try {
      final summary = await _plansRepository.getWeekSummary(
        currentState.plan.id,
        week,
      );
      
      if (state is PlansLoaded) {
        state = (state as PlansLoaded).copyWithWeekSummary(week, summary);
      }
      
      return summary;
    } catch (e) {
      return null;
    }
  }

  /// Update item progress with optimistic update.
  /// Calls PATCH /plans/items/{id}
  Future<void> updateItemProgress(String itemId, int progressPercent) async {
    final currentState = state;
    if (currentState is! PlansLoaded) return;

    final plan = currentState.plan;
    final itemIndex = plan.items.indexWhere((i) => i.id == itemId);
    if (itemIndex == -1) return;

    final item = plan.items[itemIndex];

    // Determine status based on progress
    String newStatus;
    if (progressPercent >= 100) {
      newStatus = 'completed';
    } else if (progressPercent > 0) {
      newStatus = 'in_progress';
    } else {
      newStatus = 'pending';
    }

    // Optimistic update
    final optimisticItems = List<PlanItem>.from(plan.items);
    optimisticItems[itemIndex] = item.copyWith(
      progressPercent: progressPercent,
      status: newStatus,
    );
    state = PlansLoaded(plan: plan.copyWith(items: optimisticItems));

    try {
      // API call
      await _plansRepository.updatePlanItem(
        itemId,
        progressPercent: progressPercent,
        status: newStatus,
      );
    } catch (e) {
      // Revert on error
      state = currentState;
    }
  }

  /// Update item status with optimistic update.
  /// Calls PATCH /plans/items/{id}
  Future<void> updateItemStatus(String itemId, String status) async {
    final currentState = state;
    if (currentState is! PlansLoaded) return;

    final plan = currentState.plan;
    final itemIndex = plan.items.indexWhere((i) => i.id == itemId);
    if (itemIndex == -1) return;

    final item = plan.items[itemIndex];

    // Optimistic update
    final optimisticItems = List<PlanItem>.from(plan.items);
    optimisticItems[itemIndex] = item.copyWith(status: status);
    state = PlansLoaded(plan: plan.copyWith(items: optimisticItems));

    try {
      // API call
      await _plansRepository.updatePlanItem(itemId, status: status);
    } catch (e) {
      // Revert on error
      state = currentState;
    }
  }

  /// Create a new plan item.
  Future<void> createItem({
    required String title,
    required String description,
    int? week,
  }) async {
    final currentState = state;
    if (currentState is! PlansLoaded) return;
    
    try {
      final item = await _plansRepository.createPlanItem(
        planId: currentState.plan.id,
        title: title,
        description: description,
        weekStart: week ?? currentState.plan.currentWeek,
      );
      
      // Update state
      final updatedItems = [...currentState.plan.items, item];
      state = currentState.copyWithPlan(currentState.plan.copyWith(items: updatedItems));
      
      // Refresh summary if needed
      if (item.weekStart != null) {
        refreshWeekSummary(item.weekStart!);
      }
    } catch (e) {
      // Handle error
      print('Failed to create item: $e');
      rethrow;
    }
  }

  /// Refresh plan data.
  Future<void> refresh() async {
    await load();
  }
}
