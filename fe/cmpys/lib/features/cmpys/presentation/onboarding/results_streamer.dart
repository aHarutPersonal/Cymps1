// Shared driver for the /generate-results SSE stream (comparison + blueprint).
// Used by the analysis step (primary) and the plan-gen step (blueprint retry).

import '../../../../core/network/coalesced_text.dart';
import '../../../session/data/session_repository.dart';

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
}) async {
  String section = '';
  final comparison = CoalescedText(
    onUpdate: (value) => onComparison?.call(value),
  );
  final blueprint = CoalescedText(
    onUpdate: (value) => onBlueprint?.call(value),
  );

  try {
    await for (final ev in repo.generateResults(sessionId)) {
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
        case 'error':
          throw StateError(ev['message']?.toString() ?? 'generation failed');
        case 'done':
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
