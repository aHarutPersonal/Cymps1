import 'package:freezed_annotation/freezed_annotation.dart';

part 'job_models.freezed.dart';

/// AI thinking stream during idol import.
/// Shows dynamic text that appears progressively like a typewriter.
@freezed
class ThinkingStream with _$ThinkingStream {
  const ThinkingStream._();

  const factory ThinkingStream({
    /// The line currently being "typed" - animate with typewriter effect
    required String currentLine,

    /// Lines already shown - display immediately with checkmark
    required List<String> completedLines,

    /// Optional insight/tip - show as subtle aside
    String? insight,

    /// Current processing step name
    required String step,

    /// Progress within current step (0-100)
    required int stepProgress,
  }) = _ThinkingStream;

  factory ThinkingStream.fromJson(Map<String, dynamic> json) {
    return ThinkingStream(
      currentLine:
          (json['currentLine'] ?? json['current_line'])?.toString() ?? '',
      completedLines:
          ((json['completedLines'] ?? json['completed_lines'])
                  as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      insight: json['insight']?.toString(),
      step: json['step']?.toString() ?? '',
      stepProgress:
          ((json['stepProgress'] ?? json['step_progress']) as num?)?.toInt() ??
          0,
    );
  }
}

/// Status of an async job (e.g., idol enrichment).
///
/// Job statuses: queued, running, completed, failed
/// Job steps: collecting_sources, extracting_profile, extracting_achievements,
///            normalizing_timeline, generating_persona, storing_data, done
@freezed
class JobStatus with _$JobStatus {
  const JobStatus._();

  const factory JobStatus({
    String? id,

    /// The idol ID this job is processing
    String? idolId,

    /// The idol's name
    String? idolName,
    required String status,

    /// Current processing step (e.g., "extracting_achievements")
    String? step,
    @Default(0) int progressPercent,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,

    /// AI thinking stream - shows dynamic text during import
    ThinkingStream? thinkingStream,

    /// Top achievements found (available after 60%)
    List<String>? previewAchievements,

    /// Idol's domains (available after 25%)
    List<String>? previewDomains,

    /// Final job results (e.g., suggestions)
    Map<String, dynamic>? results,
  }) = _JobStatus;

  factory JobStatus.fromJson(Map<String, dynamic> json) {
    return JobStatus(
      id: json['id']?.toString(),
      idolId: (json['idolId'] ?? json['idol_id'])?.toString(),
      idolName: (json['idolName'] ?? json['idol_name'])?.toString(),
      status: json['status']?.toString() ?? 'pending',
      step: json['step']?.toString(),
      progressPercent:
          (json['progressPercent'] ?? json['progress_percent'] as num?)
              ?.toInt() ??
          0,
      errorMessage: (json['errorMessage'] ?? json['error_message'])?.toString(),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
      completedAt: _parseDate(json['completedAt'] ?? json['completed_at']),
      thinkingStream:
          (json['thinkingStream'] ?? json['thinking_stream']) != null
          ? ThinkingStream.fromJson(
              (json['thinkingStream'] ?? json['thinking_stream'])
                  as Map<String, dynamic>,
            )
          : null,
      previewAchievements:
          ((json['previewAchievements'] ?? json['preview_achievements'])
                  as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList(),
      previewDomains:
          ((json['previewDomains'] ?? json['preview_domains'])
                  as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList(),
      results: json['results'] as Map<String, dynamic>?,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Check if job is still running.
  bool get isRunning =>
      status == 'queued' ||
      status == 'pending' ||
      status == 'running' ||
      status == 'in_progress';

  /// Check if job completed successfully.
  bool get isCompleted => status == 'completed' || status == 'done';

  /// Check if job failed.
  bool get isFailed => status == 'failed' || status == 'error';

  /// Check if job is in a terminal state.
  bool get isTerminal => isCompleted || isFailed;
}

/// Enum for job status values.
enum JobStatusType {
  @JsonValue('pending')
  pending,
  @JsonValue('running')
  running,
  @JsonValue('in_progress')
  inProgress,
  @JsonValue('completed')
  completed,
  @JsonValue('done')
  done,
  @JsonValue('failed')
  failed,
  @JsonValue('error')
  error,
}
