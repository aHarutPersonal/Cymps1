// Loads the user's generated 12-week plan and, while the backend Celery job
// is still writing it, polls GET /jobs/{id} until it completes.
//
// The plan-generation job id arrives over the onboarding `plan_job` SSE event
// and is persisted in the CMPYS store; users who reinstalled (or never got the
// event) still resolve via GET /plans/current alone.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../cmpys/state/cmpys_store.dart';
import '../../session/data/session_repository.dart';
import '../../session/models/session_models.dart';
import '../data/plan_repository.dart';
import '../models/plan_models.dart';

enum CurrentPlanStatus {
  /// First fetch in flight.
  loading,

  /// No plan yet, but a generation job is running — `jobProgress`/`jobLine`
  /// carry live progress for the UI.
  generating,

  /// Plan loaded.
  ready,

  /// No plan and no job to wait on (e.g. onboarding not finished).
  empty,

  /// Fetch or generation failed; `error` has the message.
  failed,
}

@immutable
class CurrentPlanState {
  const CurrentPlanState({
    required this.status,
    this.plan,
    this.jobProgress = 0,
    this.jobLine = '',
    this.error,
  });

  final CurrentPlanStatus status;
  final BackendPlan? plan;
  final int jobProgress;
  final String jobLine;
  final String? error;
}

class CurrentPlanController extends StateNotifier<CurrentPlanState> {
  CurrentPlanController({
    required PlanRepository repo,
    required String? Function() readJobId,
    String? Function()? readIdolName,
    Future<String?> Function()? requestGeneration,
  })  : _repo = repo,
        _readJobId = readJobId,
        _readIdolName = readIdolName,
        _requestGeneration = requestGeneration,
        super(const CurrentPlanState(status: CurrentPlanStatus.loading)) {
    refresh();
  }

  final PlanRepository _repo;
  final String? Function() _readJobId;

  /// Name of the idol the user is currently working with (from the latest
  /// session). Used to reject a cached plan that belongs to a previous idol.
  final String? Function()? _readIdolName;
  String? _lastIdol;

  /// Recovery hook: enqueue plan generation for an account whose onboarding
  /// finished without a stored job id (older app build, lost SSE event).
  /// Returns the new job id, or null when generation can't be requested.
  final Future<String?> Function()? _requestGeneration;
  bool _autoGenerateTried = false;
  Timer? _poll;

  static const _pollInterval = Duration(seconds: 3);

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Re-fetch the plan; falls back to job polling while it's generating.
  Future<void> refresh() async {
    _poll?.cancel();
    try {
      // Check the stored job FIRST. A running job means a newer plan is being
      // generated — we must not show the stale old plan during that window.
      final jobId = _readJobId();
      if (jobId != null && jobId.isNotEmpty) {
        try {
          final job = await _repo.getJobStatus(jobId);
          if (!mounted) return;
          if (!job.isCompleted && !job.isFailed) {
            state = CurrentPlanState(
              status: CurrentPlanStatus.generating,
              jobProgress: job.progressPercent,
              jobLine: job.thinkingLine ?? '',
            );
            _startPolling(jobId);
            return;
          }
          // Completed or failed → fall through to fetch the (new) plan.
        } catch (e) {
          if (e is ApiError && e.statusCode == 404) {
            // Stale job id → ignore, fall through to existing plan.
          } else {
            rethrow;
          }
        }
      }

      final plan = await _repo.getCurrentPlan();
      if (!mounted) return;
      // Guard against showing a plan that belongs to a previously-selected
      // idol. /plans/current returns the user's newest plan globally; if the
      // user has since switched idols and that idol's plan isn't the newest
      // yet, the returned plan is stale and must not be presented as current.
      // Compare normalised names, matching CmpysStore.syncFromSession, since
      // both names originate from the backend idol record.
      final wantIdol = _readIdolName?.call()?.toLowerCase().trim();
      final planIdol = plan?.idolName?.toLowerCase().trim();
      final matchesActiveIdol = plan == null ||
          wantIdol == null ||
          wantIdol.isEmpty ||
          planIdol == null ||
          planIdol.isEmpty ||
          planIdol == wantIdol;
      if (plan != null && plan.items.isNotEmpty && matchesActiveIdol) {
        state = CurrentPlanState(status: CurrentPlanStatus.ready, plan: plan);
        return;
      }
      if (jobId != null && jobId.isNotEmpty) {
        // Job completed but plan not yet visible — keep polling briefly.
        state = const CurrentPlanState(status: CurrentPlanStatus.generating);
        _startPolling(jobId);
      } else {
        await _tryAutoGenerate();
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('📋 Plan fetch failed: $e');
      state = CurrentPlanState(
          status: CurrentPlanStatus.failed, error: e.toString());
    }
  }

  /// No plan and no job id: if a completed onboarding session exists, enqueue
  /// generation ourselves so the user still ends up with an AI plan. Tried at
  /// most once per controller lifetime.
  Future<void> _tryAutoGenerate() async {
    if (_autoGenerateTried || _requestGeneration == null) {
      if (state.status != CurrentPlanStatus.generating) {
        state = const CurrentPlanState(status: CurrentPlanStatus.empty);
      }
      return;
    }
    _autoGenerateTried = true;
    try {
      final jobId = await _requestGeneration();
      if (!mounted) return;
      if (jobId != null && jobId.isNotEmpty) {
        debugPrint('📋 Auto-enqueued plan generation: $jobId');
        state = const CurrentPlanState(status: CurrentPlanStatus.generating);
        _startPolling(jobId);
        return;
      }
    } catch (e) {
      debugPrint('📋 Plan auto-generation failed: $e');
    }
    if (mounted) {
      state = const CurrentPlanState(status: CurrentPlanStatus.empty);
    }
  }

  /// Called when the onboarding flow stores a fresh plan-generation job id.
  void onJobIdChanged(String? jobId) {
    if (jobId == null || jobId.isEmpty) return;
    // If already polling this exact cycle, skip — but NEVER skip when showing
    // an older plan (ready state): the new job means a fresh plan is coming.
    if (state.status == CurrentPlanStatus.generating) return;
    state = const CurrentPlanState(status: CurrentPlanStatus.generating);
    _startPolling(jobId);
  }

  /// The user switched to a different idol (a new session). The cached plan is
  /// for the previous idol, so re-fetch — `/plans/current` will return the new
  /// idol's plan once generated, and the idol guard in [refresh] keeps the old
  /// plan from showing in the meantime.
  void onIdolChanged(String? idolName) {
    if (idolName == null || idolName.isEmpty) return;
    if (idolName == _lastIdol) return;
    _lastIdol = idolName;
    refresh();
  }

  void _startPolling(String jobId) {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => _checkJob(jobId));
    _checkJob(jobId);
  }

  bool _checking = false;

  Future<void> _checkJob(String jobId) async {
    if (_checking) return;
    _checking = true;
    try {
      final job = await _repo.getJobStatus(jobId);
      if (!mounted) return;
      if (job.isCompleted) {
        _poll?.cancel();
        await refresh();
      } else if (job.isFailed) {
        _poll?.cancel();
        state = CurrentPlanState(
          status: CurrentPlanStatus.failed,
          error: job.errorMessage ?? 'Plan generation failed.',
        );
      } else {
        state = CurrentPlanState(
          status: CurrentPlanStatus.generating,
          jobProgress: job.progressPercent,
          jobLine: job.thinkingLine ?? '',
        );
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('📋 Plan job poll failed: $e');
      // A stale job id (backend reset) 404s forever — stop and show "no
      // plan". Transient network errors just wait for the next tick.
      if (e is ApiError && e.statusCode == 404) {
        _poll?.cancel();
        state = const CurrentPlanState(status: CurrentPlanStatus.empty);
      }
    } finally {
      _checking = false;
    }
  }
}

final currentPlanProvider =
    StateNotifierProvider<CurrentPlanController, CurrentPlanState>((ref) {
  final controller = CurrentPlanController(
    repo: ref.watch(planRepositoryProvider),
    readJobId: () => ref.read(cmpysStoreProvider).planJobId,
    readIdolName: () => ref.read(cmpysStoreProvider).idol.name,
    requestGeneration: () async {
      // Recovery path: a completed onboarding session with a chosen idol but
      // no plan and no job id (older app build / lost SSE event). Enqueue
      // generation via POST /plans/generate and persist the job id.
      final session =
          await ref.read(sessionRepositoryProvider).getLatestSession();
      final idolId = session?.selectedIdol?.id;
      final hasResults = session?.blueprintOutput?.trim().isNotEmpty == true ||
          session?.phase == SessionPhase.completed;
      if (session == null || idolId == null || idolId.isEmpty || !hasResults) {
        return null;
      }
      final jobId = await ref.read(planRepositoryProvider).generatePlan(
            idolId: idolId,
            targetAge: session.userAge > 0 ? session.userAge : 24,
          );
      if (jobId.isNotEmpty) {
        ref.read(cmpysStoreProvider.notifier).setPlanJobId(jobId);
      }
      return jobId;
    },
  );
  // When onboarding finishes and persists the job id, start polling without
  // waiting for a manual refresh.
  ref.listen<String?>(
    cmpysStoreProvider.select((s) => s.planJobId),
    (_, next) => controller.onJobIdChanged(next),
  );
  // When the user switches idols (new session), re-fetch so the Plan tab shows
  // the new idol's plan instead of the previous idol's cached one.
  ref.listen<String>(
    cmpysStoreProvider.select((s) => s.idol.name),
    (_, next) => controller.onIdolChanged(next),
  );
  return controller;
});

/// Today's daily rhythm (current plan week's habit/practice items with
/// per-day completion + streak). Null until the plan is ready. Invalidate
/// after a daily-toggle to refresh counts; previous data is kept while
/// refreshing so the list doesn't flicker.
final todayViewProvider = FutureProvider<TodayView?>((ref) async {
  final planState = ref.watch(currentPlanProvider);
  final plan = planState.plan;
  if (planState.status != CurrentPlanStatus.ready || plan == null) return null;
  return ref.watch(planRepositoryProvider).getTodayView(plan.id);
});
