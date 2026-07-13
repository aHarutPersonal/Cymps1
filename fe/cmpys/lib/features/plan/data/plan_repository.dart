import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/dio_client.dart';
import '../models/plan_models.dart';

/// Plan repository provider.
final planRepositoryProvider = Provider<PlanRepository>((ref) {
  return PlanRepository(dioClient: ref.watch(dioClientProvider));
});

/// API access for the generated 12-week plan: current plan, generation-job
/// polling, and per-item lesson details.
class PlanRepository {
  PlanRepository({required DioClient dioClient}) : _dioClient = dioClient;

  final DioClient _dioClient;

  /// The user's most recent plan, or null if none has been generated yet.
  Future<BackendPlan?> getCurrentPlan() async {
    final response = await _dioClient.get('/plans/current');
    if (response.data == null) return null;
    return BackendPlan.fromJson(response.data as Map<String, dynamic>);
  }

  /// Poll target for async jobs (plan generation, item-detail generation).
  Future<PlanJobStatus> getJobStatus(String jobId) async {
    final response = await _dioClient.get(
      '/jobs/$jobId',
      queryParameters: const {'type': 'plan'},
    );
    return PlanJobStatus.fromJson(response.data as Map<String, dynamic>);
  }

  /// Lightweight polling target for a mission's lesson-generation job.
  /// Keeping this separate from [getJobStatus] prevents detail jobs from being
  /// looked up as plan jobs and avoids repeatedly downloading the full item.
  Future<PlanJobStatus> getPlanDetailJobStatus(String jobId) async {
    final response = await _dioClient.get(
      '/jobs/$jobId',
      queryParameters: const {'type': 'plan_detail'},
    );
    return PlanJobStatus.fromJson(response.data as Map<String, dynamic>);
  }

  /// Item + lesson details (steps, materials). If details aren't generated
  /// yet the backend enqueues a job and returns `details_status: pending`
  /// with a `job_id` to poll.
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async {
    final response = await _dioClient.get('/plan-items/$itemId/detailed');
    return PlanItemDetailed.fromJson(response.data as Map<String, dynamic>);
  }

  /// Explicitly retry a mission lesson after the backend reports generation
  /// failure. Failed jobs are not auto-requeued on every poll, preventing an
  /// endless loading/cost loop.
  Future<String> regeneratePlanItemDetails(String itemId) async {
    final response = await _dioClient.post(
      '/plan-items/$itemId/regenerate-details',
    );
    final data = response.data as Map<String, dynamic>;
    return (data['job_id'] ?? data['jobId'])?.toString() ?? '';
  }

  /// Resolve a deferred canonical resource after background generation.
  /// Returns null while its quality-gated module is still being prepared.
  Future<String?> resolveContentResourceId(String canonicalKey) async {
    try {
      final response = await _dioClient.get(
        '/content-resources/resolve',
        queryParameters: {'canonicalKey': canonicalKey},
      );
      final data = response.data as Map<String, dynamic>;
      return data['id']?.toString();
    } on ApiError catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Complete or uncomplete one lesson step. The backend enforces sequential
  /// progression and auto-completes the mission after its final lesson.
  Future<({bool completed, bool itemCompleted})> toggleStepComplete(
    String itemId,
    String stepId,
  ) async {
    final response = await _dioClient.post(
      '/plan-items/$itemId/steps/$stepId/toggle',
    );
    final data = response.data as Map<String, dynamic>;
    return (
      completed: data['completed'] as bool? ?? false,
      itemCompleted: data['item_completed'] as bool? ?? false,
    );
  }

  /// Toggle item-level completion. Returns a [ToggleResult] with the new
  /// completed state plus plan-level signals (planComplete,
  /// missionTasksRemaining) used by the achievement cycle flow.
  Future<ToggleResult> toggleItemComplete(String itemId) async {
    final response = await _dioClient.post(
      '/plan-items/$itemId/toggle-complete',
    );
    final data = response.data as Map<String, dynamic>;
    debugPrint('✅ Toggled plan item $itemId → ${data['completed']}');
    return ToggleResult.fromJson(data);
  }

  /// Fetch an AI-suggested achievement title + category for a completed item.
  Future<({String title, String category})> fetchAchievementSuggestion(
    String itemId,
  ) async {
    final r = await _dioClient.post(
      '/plan-items/$itemId/achievement-suggestion',
    );
    final d = r.data as Map<String, dynamic>;
    return (
      title: d['title'] as String? ?? '',
      category: d['category'] as String? ?? 'other',
    );
  }

  /// Persist a user achievement (auto-generated or manually edited).
  Future<void> saveAchievement({
    required String title,
    required String category,
    String? notes,
    String? evidenceLink,
    required String source,
    String? planId,
    String? planItemId,
    int cycleNumber = 1,
  }) async {
    await _dioClient.post(
      '/achievements',
      data: {
        'title': title,
        'category': category,
        'source': source,
        if (planId != null) 'planId': planId,
        if (planItemId != null) 'planItemId': planItemId,
        'cycleNumber': cycleNumber,
        if (notes != null) 'notes': notes,
        if (evidenceLink != null) 'evidenceLink': evidenceLink,
      },
    );
  }

  /// Generate a narrative summary of the completed plan cycle.
  Future<({String narrative, String? capstoneTitle})> fetchCycleSummary(
    String planId,
  ) async {
    final r = await _dioClient.post('/plans/$planId/cycle-summary');
    final d = r.data as Map<String, dynamic>;
    return (
      narrative: d['narrative'] as String? ?? '',
      capstoneTitle: d['capstoneTitle'] as String?,
    );
  }

  /// Enqueue generation of the next 12-week plan cycle. Returns the job id.
  Future<String> generateNext(String planId) async {
    final r = await _dioClient.post('/plans/$planId/generate-next');
    return (r.data as Map<String, dynamic>)['jobId'] as String? ?? '';
  }

  /// Today's habit/practice items for the plan's current week, with per-day
  /// completion state and the user's streak.
  Future<TodayView> getTodayView(String planId) async {
    final response = await _dioClient.get('/plans/$planId/today');
    return TodayView.fromJson(response.data as Map<String, dynamic>);
  }

  /// Toggle *today's* completion for a habit/practice item (resets daily,
  /// unlike [toggleItemComplete]). Returns the new completed-today state.
  Future<bool> toggleDailyTask(String itemId) async {
    final response = await _dioClient.post('/plan-items/$itemId/daily-toggle');
    final data = response.data as Map<String, dynamic>;
    debugPrint('📅 Daily-toggled $itemId → ${data['completed']}');
    return data['completed'] as bool? ?? false;
  }

  /// Full shared content resource — the in-app lesson/article/book text for
  /// materials that reference one by id. For public-domain books the backend
  /// hydrates the full text on first access, so this call can take a moment.
  Future<ContentResourceDetail> getContentResource(String resourceId) async {
    final response = await _dioClient.get('/content-resources/$resourceId');
    return ContentResourceDetail.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Persist reading/watch progress for a shared resource.
  Future<void> updateContentProgress(
    String resourceId, {
    required int progressPercent,
    Map<String, dynamic>? cursorJson,
    bool? completed,
  }) async {
    await _dioClient.patch(
      '/content-resources/$resourceId/progress',
      data: {
        'progressPercent': progressPercent,
        if (cursorJson != null) 'cursorJson': cursorJson,
        if (completed != null) 'completed': completed,
      },
    );
  }

  /// Enqueue 12-week plan generation (POST /plans/generate). Returns the job
  /// id to poll. Used as a recovery path when a completed onboarding session
  /// exists but no plan was ever generated (e.g. the `plan_job` SSE event
  /// predates this app version); the normal path is the session-linked job
  /// the backend enqueues itself during generate-results.
  Future<String> generatePlan({
    required String idolId,
    required int targetAge,
    String? sessionId,
    int durationWeeks = 12,
    int weeklyHours = 10,
  }) async {
    final response = await _dioClient.post(
      '/plans/generate',
      data: {
        'idolId': idolId,
        'targetAge': targetAge,
        'durationWeeks': durationWeeks,
        'weeklyHours': weeklyHours,
        if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final jobId = data['jobId']?.toString() ?? '';
    debugPrint('🛠️ Enqueued plan generation, job: $jobId');
    return jobId;
  }
}
