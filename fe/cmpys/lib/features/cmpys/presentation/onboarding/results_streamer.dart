// Shared driver for the /generate-results SSE stream (comparison + blueprint).
// Used by the analysis step (primary) and the plan-gen step (blueprint retry).

import '../../../../core/network/coalesced_text.dart';
import '../../../session/data/session_repository.dart';

/// A server-reported generation failure, distinct from a broken connection.
class ResultsGenerationException implements Exception {
  const ResultsGenerationException({
    required this.code,
    this.retryAfterSeconds = 0,
    this.section,
  });

  final String code;
  final int retryAfterSeconds;

  /// The pipeline section the server was working on (`comparison`,
  /// `blueprint` or `plan`), when it said so. The mentor lab uses it to mark
  /// the stage that failed.
  final String? section;

  String get message => switch (code) {
    'generation_unavailable' =>
      'Generation is unavailable right now. Your answers are saved. Please try again later.',
    'generation_rate_limited' =>
      'Generation is busy right now. Your answers are saved. Please wait before trying again.',
    _ =>
      'Generation could not finish. Your answers are saved. Please try again.',
  };

  @override
  String toString() => message;
}

/// Streams generate-results, invoking callbacks with the *accumulated* text of
/// each section as chunks arrive. Throws on stream error so callers can show
/// retry UI. Backend supports re-invocation from the comparison or blueprint
/// phase (retry semantics).
Future<void> streamGenerateResults({
  required AgenticSessionRepository repo,
  required String sessionId,
  void Function(String status)? onStatus,
  void Function(String section)? onSection,
  void Function(String accumulated)? onComparison,
  void Function(String accumulated)? onBlueprint,
  void Function(String jobId)? onPlanJob,
  void Function(bool ready)? onComparisonScores,
  void Function()? onDone,
}) async {
  String section = '';
  final comparison = CoalescedText(
    onUpdate: (value) => onComparison?.call(value),
  );
  final blueprint = CoalescedText(
    onUpdate: (value) => onBlueprint?.call(value),
  );

  try {
    // An abandoned connection must become recoverable instead of leaving the
    // user on a spinner forever. Heartbeats count as activity in this stream.
    await for (final ev
        in repo
            .generateResults(sessionId)
            .timeout(const Duration(seconds: 90))) {
      final type = ev['type'] as String? ?? '';
      switch (type) {
        case 'status':
          onStatus?.call(ev['message']?.toString() ?? '');
          break;
        case 'section':
          final nextSection = ev['section'] as String? ?? '';
          if (section == 'comparison' && nextSection != section) {
            comparison.flush();
          } else if (section == 'blueprint' && nextSection != section) {
            blueprint.flush();
          }
          section = nextSection;
          if (section.isNotEmpty) onSection?.call(section);
          break;
        case 'chunk':
          final content = ev['content'] as String? ?? '';
          if (section == 'blueprint') {
            blueprint.add(content);
          } else {
            comparison.add(content);
          }
          break;
        case 'plan_job':
          // The backend kicked off async 12-week plan generation (Celery).
          // Callers persist the job id so the app can poll GET /jobs/{id} and
          // surface the plan once it's ready.
          final jobId = ev['job_id']?.toString() ?? '';
          if (jobId.isNotEmpty) onPlanJob?.call(jobId);
          break;
        case 'comparison_scores':
          // The structured dimension scores behind the Compare screen. They
          // follow the blueprint, so this also marks the blueprint complete:
          // publish its pending text before telling the caller.
          comparison.flush();
          blueprint.flush();
          onComparisonScores?.call(ev['ready'] == true);
          break;
        case 'error':
          final delay = ev['retry_after_seconds'];
          final failedSection = ev['section']?.toString() ?? section;
          throw ResultsGenerationException(
            section: failedSection.isEmpty ? null : failedSection,
            code: ev['code']?.toString() ?? 'generation_failed',
            retryAfterSeconds: delay is num && delay.isFinite
                ? delay.toInt().clamp(0, 3600)
                : ev['retryable'] == false
                ? 60
                : 0,
          );
        case 'done':
          // The pipeline finished: publish any pending text first.
          comparison.flush();
          blueprint.flush();
          onDone?.call();
          break;
      }
    }
  } finally {
    // Completion, disconnect, and callback errors all flush any accumulated
    // partial document exactly once and cancel outstanding timers.
    comparison.close();
    blueprint.close();
  }
}
