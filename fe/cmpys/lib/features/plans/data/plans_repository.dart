import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../idols/models/idol_models.dart';
import '../models/plan_models.dart';

/// Plans repository provider.
final plansRepositoryProvider = Provider<PlansRepository>((ref) {
  return PlansRepository(dioClient: ref.watch(dioClientProvider));
});

/// Repository for plans operations.
class PlansRepository {
  PlansRepository({required DioClient dioClient}) : _dioClient = dioClient;

  final DioClient _dioClient;

  /// Add a new item to the plan.
  Future<PlanItem> createPlanItem({
    required String planId,
    required String title,
    required String description,
    String type = 'project',
    int estimatedHours = 1,
    int? weekStart,
  }) async {
    final response = await _dioClient.post(
      '/plans/$planId/items',
      data: {
        'title': title,
        'description': description,
        'type': type,
        'estimatedHours': estimatedHours,
        if (weekStart != null) 'weekStart': weekStart,
      },
    );
    return PlanItem.fromJson(response.data);
  }

  /// Generate a new improvement plan.
  ///
  /// [idolId] - The idol to base the plan on.
  /// [targetAge] - User's target age for comparison (required by backend).
  /// [durationWeeks] - Plan duration in weeks (default: 12).
  /// [weeklyHours] - Available hours per week (default: 10).
  /// [focus] - Optional focus area.
  /// [gapIds] - Optional specific gaps to address.
  /// Returns the [ImportResponse] containing the jobId.
  Future<ImportResponse> generatePlan({
    required String idolId,
    required int targetAge,
    int durationWeeks = 12,
    double weeklyHours = 10,
    String? focus,
    List<String>? gapIds,
  }) async {
    // Build request body with all required fields in camelCase
    final Map<String, dynamic> data = {
      'idolId': idolId,
      'targetAge': targetAge,
      'durationWeeks': durationWeeks,
      'weeklyHours': weeklyHours,
    };

    if (focus != null) data['focus'] = focus;
    if (gapIds != null && gapIds.isNotEmpty) data['gapIds'] = gapIds;

    final response = await _dioClient.post('/plans/generate', data: data);

    return ImportResponse.fromJson(response.data);
  }

  /// Get user's current active plan.
  ///
  /// Returns the current [Plan] or null if no active plan.
  Future<Plan?> getCurrentPlan() async {
    try {
      final response = await _dioClient.get('/plans/current');
      return Plan.fromJson(response.data);
    } catch (e) {
      // Return null if no plan exists (404)
      return null;
    }
  }

  /// Get a specific plan by ID.
  Future<Plan> getPlan(String planId) async {
    final response = await _dioClient.get('/plans/$planId');
    return Plan.fromJson(response.data);
  }

  /// List all user's plans.
  Future<List<Plan>> listPlans() async {
    final response = await _dioClient.get('/plans');
    final list = response.data as List<dynamic>;
    return list
        .map((json) => Plan.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Update a plan item's progress.
  ///
  /// [planItemId] - The plan item's unique identifier.
  /// [status] - New status ('pending', 'in_progress', 'completed').
  /// [progressPercent] - Progress percentage (0-100).
  /// [notes] - Optional notes about progress.
  /// Returns the updated [PlanItem].
  Future<PlanItem> updatePlanItem(
    String planItemId, {
    String? status,
    int? progressPercent,
    String? notes,
  }) async {
    final data = <String, dynamic>{};
    if (status != null) data['status'] = status;
    if (progressPercent != null) data['progress_percent'] = progressPercent;
    if (notes != null) data['notes'] = notes;

    final response = await _dioClient.patch(
      '/plans/items/$planItemId',
      data: data,
    );

    return PlanItem.fromJson(response.data);
  }

  /// Mark a plan item as completed.
  Future<PlanItem> completePlanItem(String planItemId) async {
    return updatePlanItem(
      planItemId,
      status: 'completed',
      progressPercent: 100,
    );
  }

  /// Mark a plan item as in progress.
  Future<PlanItem> startPlanItem(String planItemId) async {
    return updatePlanItem(planItemId, status: 'in_progress');
  }

  /// Update plan item progress percentage.
  Future<PlanItem> updateProgress(String planItemId, int percent) async {
    return updatePlanItem(planItemId, progressPercent: percent);
  }

  /// Delete/cancel a plan.
  Future<void> deletePlan(String planId) async {
    await _dioClient.delete('/plans/$planId');
  }

  /// Activate a plan (set as current).
  Future<Plan> activatePlan(String planId) async {
    final response = await _dioClient.post('/plans/$planId/activate');
    return Plan.fromJson(response.data);
  }

  /// Get a specific plan item with its details.
  ///
  /// [itemId] - The plan item's unique identifier.
  /// Returns [PlanItemDetailsResponse] containing the item, details, and progress.
  ///
  /// API: GET /plan-items/{item_id}/detailed
  Future<PlanItemDetailsResponse> getPlanItem(String itemId) async {
    final response = await _dioClient.get('/plan-items/$itemId/detailed');
    return PlanItemDetailsResponse.fromJson(response.data);
  }

  /// Toggle a plan item's completion status.
  ///
  /// [itemId] - The plan item's unique identifier.
  /// Returns [ToggleCompleteResponse] with new completion state and progress.
  ///
  /// API: POST /plan-items/{item_id}/toggle-complete
  Future<ToggleCompleteResponse> togglePlanItemComplete(String itemId) async {
    final response = await _dioClient.post(
      '/plan-items/$itemId/toggle-complete',
    );
    return ToggleCompleteResponse.fromJson(response.data);
  }

  /// Toggle a step's completion status within a plan item.
  ///
  /// [itemId] - The plan item's unique identifier.
  /// [stepId] - The step's unique identifier.
  /// Returns [ToggleStepResponse] with new completion state and progress.
  ///
  /// API: POST /plan-items/{item_id}/steps/{step_id}/toggle
  Future<ToggleStepResponse> togglePlanStep(
    String itemId,
    String stepId,
  ) async {
    final response = await _dioClient.post(
      '/plan-items/$itemId/steps/$stepId/toggle',
    );
    return ToggleStepResponse.fromJson(response.data);
  }

  /// Regenerate details for a plan item.
  ///
  /// [itemId] - The plan item's unique identifier.
  /// Returns [RegenerateDetailsResponse] with the job ID to poll for status.
  ///
  /// API: POST /plan-items/{item_id}/regenerate-details
  Future<RegenerateDetailsResponse> regeneratePlanItemDetails(
    String itemId,
  ) async {
    final response = await _dioClient.post(
      '/plan-items/$itemId/regenerate-details',
    );
    return RegenerateDetailsResponse.fromJson(response.data);
  }

  /// Get summary for a specific week in a plan.
  ///
  /// [planId] - The plan's unique identifier.
  /// [week] - The week number (1-indexed).
  /// Returns [WeekSummary] with week statistics and items.
  ///
  /// API: GET /plans/{plan_id}/weeks/{week}/summary
  Future<WeekSummary> getWeekSummary(String planId, int week) async {
    final response = await _dioClient.get('/plans/$planId/weeks/$week/summary');
    return WeekSummary.fromJson(response.data);
  }
}
