

import '../../../core/network/dio_client.dart';
import '../models/daily_task_models.dart';

/// Repository for daily task operations.
class DailyTasksRepository {
  DailyTasksRepository({required DioClient dioClient})
    : _dioClient = dioClient;

  final DioClient _dioClient;

  /// Get today's tasks for a plan.
  ///
  /// [planId] - The plan's unique identifier.
  /// Returns [TodayOverview] with today's tasks and streak info.
  ///
  /// API: GET /plans/{plan_id}/today
  Future<TodayOverview> getTodayTasks(String planId) async {
    final response = await _dioClient.get('/plans/$planId/today');
    return TodayOverview.fromJson(response.data);
  }

  /// Toggle a daily task's completion for today.
  ///
  /// [itemId] - The plan item's unique identifier.
  /// Returns true if the task is now completed.
  ///
  /// API: POST /plan-items/{item_id}/daily-toggle
  Future<bool> toggleDailyTask(String itemId) async {
    final response = await _dioClient.post(
      '/plan-items/$itemId/daily-toggle',
    );
    final completed = response.data['completed'] == true ||
        response.data['completed_today'] == true;
    return completed;
  }

  /// Get weekly dot-grid status for a daily task.
  ///
  /// [itemId] - The plan item's unique identifier.
  /// Returns [DailyTaskWeekStatus] with 7-day completion dots.
  ///
  /// API: GET /plan-items/{item_id}/daily-status
  Future<DailyTaskWeekStatus> getDailyTaskWeekStatus(
    String itemId,
  ) async {
    final response = await _dioClient.get(
      '/plan-items/$itemId/daily-status',
    );
    return DailyTaskWeekStatus.fromJson(response.data);
  }

  /// Get the user's current and longest daily streak.
  ///
  /// API: GET /streak
  Future<StreakInfo> getStreak() async {
    final response = await _dioClient.get('/streak');
    return StreakInfo.fromJson(response.data);
  }

  /// Get today's focus item, reflection prompt, and streak.
  ///
  /// API: GET /daily-focus
  Future<DailyFocus> getDailyFocus() async {
    final response = await _dioClient.get('/daily-focus');
    return DailyFocus.fromJson(response.data);
  }
}
