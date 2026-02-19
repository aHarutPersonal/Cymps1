import 'package:freezed_annotation/freezed_annotation.dart';

part 'plan_models.freezed.dart';

/// A plan item (task/action).
@freezed
class PlanItem with _$PlanItem {
  const PlanItem._();

  const factory PlanItem({
    required String id,
    required String title,
    required String type,
    String? description,
    int? weekStart,
    int? weekEnd,
    @Default('pending') String status,
    @Default(0) int progressPercent,
    String? resourceTitle,
    String? resourceUrl,
    String? category,
    double? estimatedHours,
    String? successMetric,
    DateTime? dueDate,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _PlanItem;

  factory PlanItem.fromJson(Map<String, dynamic> json) {
    return PlanItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      type: (json['type'] ?? 'task').toString(),
      description: json['description']?.toString(),
      weekStart: (json['weekStart'] ?? json['week_start'] as num?)?.toInt(),
      weekEnd: (json['weekEnd'] ?? json['week_end'] as num?)?.toInt(),
      status: (json['status'] ?? 'pending').toString(),
      progressPercent: (json['progressPercent'] ?? json['progress_percent'] as num?)?.toInt() ?? 0,
      resourceTitle: (json['resourceTitle'] ?? json['resource_title'])?.toString(),
      resourceUrl: (json['resourceUrl'] ?? json['resource_url'])?.toString(),
      category: json['category']?.toString(),
      estimatedHours: (json['estimatedHours'] ?? json['estimated_hours'] as num?)?.toDouble(),
      successMetric: (json['successMetric'] ?? json['success_metric'])?.toString(),
      dueDate: _parseDate(json['dueDate'] ?? json['due_date']),
      completedAt: _parseDate(json['completedAt'] ?? json['completed_at']),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Check if item is completed.
  bool get isCompleted => status == 'completed' || status == 'done';

  /// Check if item is in progress.
  bool get isInProgress => status == 'in_progress' || status == 'active';

  /// Check if item is pending.
  bool get isPending => status == 'pending' || status == 'not_started' || status == 'todo';
}

/// A user's improvement plan.
@freezed
class Plan with _$Plan {
  const Plan._();

  const factory Plan({
    required String id,
    required int durationWeeks,
    required double weeklyHours,
    String? focus,
    @Default([]) List<PlanItem> items,
    String? idolId,
    String? idolName,
    int? targetAge,
    DateTime? startDate,
    DateTime? endDate,
    @Default('active') String status,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? totalItems,
    int? completedItems,
    double? overallProgress,
  }) = _Plan;

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      id: (json['id'] ?? '').toString(),
      durationWeeks: (json['durationWeeks'] ?? json['duration_weeks'] as num?)?.toInt() ?? 12,
      weeklyHours: (json['weeklyHours'] ?? json['weekly_hours'] as num?)?.toDouble() ?? 10.0,
      focus: json['focus']?.toString(),
      items: _parseItems(json['items']) ?? [],
      idolId: (json['idolId'] ?? json['idol_id'])?.toString(),
      idolName: (json['idolName'] ?? json['idol_name'])?.toString(),
      targetAge: (json['targetAge'] ?? json['target_age'] as num?)?.toInt(),
      startDate: _parseDate(json['startDate'] ?? json['start_date']),
      endDate: _parseDate(json['endDate'] ?? json['end_date']),
      status: (json['status'] ?? 'active').toString(),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
      totalItems: (json['totalItems'] ?? json['total_items'] as num?)?.toInt(),
      completedItems: (json['completedItems'] ?? json['completed_items'] as num?)?.toInt(),
      overallProgress: (json['overallProgress'] ?? json['overall_progress'] as num?)?.toDouble(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static List<PlanItem>? _parseItems(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => PlanItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get current week number (1-indexed).
  int get currentWeek {
    if (startDate == null) return 1;
    final daysSinceStart = DateTime.now().difference(startDate!).inDays;
    return (daysSinceStart ~/ 7) + 1;
  }

  /// Get items for a specific week.
  List<PlanItem> itemsForWeek(int week) {
    return items.where((item) {
      final start = item.weekStart ?? 1;
      final end = item.weekEnd ?? start;
      return week >= start && week <= end;
    }).toList();
  }

  /// Calculate overall progress percentage.
  double get calculatedProgress {
    if (items.isEmpty) return overallProgress ?? 0;
    final totalProgress = items.fold<int>(
      0,
      (sum, item) => sum + item.progressPercent,
    );
    return totalProgress / items.length;
  }
}

/// Request to create a plan.
@freezed
class CreatePlanRequest with _$CreatePlanRequest {
  const CreatePlanRequest._();

  const factory CreatePlanRequest({
    required int durationWeeks,
    required double weeklyHours,
    String? focus,
    String? idolId,
    int? targetAge,
    List<String>? gapIds,
  }) = _CreatePlanRequest;

  factory CreatePlanRequest.fromJson(Map<String, dynamic> json) {
    return CreatePlanRequest(
      durationWeeks: (json['durationWeeks'] ?? json['duration_weeks'] as num?)?.toInt() ?? 12,
      weeklyHours: (json['weeklyHours'] ?? json['weekly_hours'] as num?)?.toDouble() ?? 10.0,
      focus: json['focus']?.toString(),
      idolId: (json['idolId'] ?? json['idol_id'])?.toString(),
      targetAge: (json['targetAge'] ?? json['target_age'] as num?)?.toInt(),
      gapIds: _parseStringList(json['gapIds'] ?? json['gap_ids']),
    );
  }

  Map<String, dynamic> toJson() => {
    'durationWeeks': durationWeeks,
    'weeklyHours': weeklyHours,
    if (focus != null) 'focus': focus,
    if (idolId != null) 'idolId': idolId,
    if (targetAge != null) 'targetAge': targetAge,
    if (gapIds != null) 'gapIds': gapIds,
  };

  static List<String>? _parseStringList(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value.map((e) => e.toString()).toList();
  }
}

/// Request to update a plan item's progress.
@freezed
class UpdatePlanItemRequest with _$UpdatePlanItemRequest {
  const UpdatePlanItemRequest._();

  const factory UpdatePlanItemRequest({
    String? status,
    int? progressPercent,
    String? notes,
  }) = _UpdatePlanItemRequest;

  factory UpdatePlanItemRequest.fromJson(Map<String, dynamic> json) {
    return UpdatePlanItemRequest(
      status: json['status']?.toString(),
      progressPercent: (json['progressPercent'] ?? json['progress_percent'] as num?)?.toInt(),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (status != null) 'status': status,
    if (progressPercent != null) 'progressPercent': progressPercent,
    if (notes != null) 'notes': notes,
  };
}

/// Details status for plan item.
enum DetailsStatus {
  pending,
  generating,
  available,
  failed;

  static DetailsStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'pending':
        return DetailsStatus.pending;
      case 'generating':
        return DetailsStatus.generating;
      case 'available':
      case 'ready':
        return DetailsStatus.available;
      case 'failed':
        return DetailsStatus.failed;
      default:
        return DetailsStatus.pending;
    }
  }
}

/// Progress info returned by API.
@freezed
class ProgressInfo with _$ProgressInfo {
  const ProgressInfo._();

  const factory ProgressInfo({
    @Default(0) int completedSteps,
    @Default(0) int totalSteps,
    @Default(0.0) double percent,
  }) = _ProgressInfo;

  factory ProgressInfo.fromJson(Map<String, dynamic> json) {
    return ProgressInfo(
      completedSteps: (json['completed_steps'] ?? json['completedSteps'] as num?)?.toInt() ?? 0,
      totalSteps: (json['total_steps'] ?? json['totalSteps'] as num?)?.toInt() ?? 0,
      percent: (json['percent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'completed_steps': completedSteps,
    'total_steps': totalSteps,
    'percent': percent,
  };
}

/// Material type for plan materials.
enum PlanMaterialType {
  book,
  article,
  video,
  course,
  inAppLesson,
  search,
  link,
  other;

  static PlanMaterialType fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'book':
        return PlanMaterialType.book;
      case 'article':
        return PlanMaterialType.article;
      case 'video':
        return PlanMaterialType.video;
      case 'course':
        return PlanMaterialType.course;
      case 'in_app_lesson':
      case 'inapplesson':
        return PlanMaterialType.inAppLesson;
      case 'search':
        return PlanMaterialType.search;
      case 'link':
        return PlanMaterialType.link;
      default:
        return PlanMaterialType.other;
    }
  }

  String toJson() {
    switch (this) {
      case PlanMaterialType.book:
        return 'book';
      case PlanMaterialType.article:
        return 'article';
      case PlanMaterialType.video:
        return 'video';
      case PlanMaterialType.course:
        return 'course';
      case PlanMaterialType.inAppLesson:
        return 'in_app_lesson';
      case PlanMaterialType.search:
        return 'search';
      case PlanMaterialType.link:
        return 'link';
      case PlanMaterialType.other:
        return 'other';
    }
  }
}

/// A step within a plan item.
@freezed
class PlanStep with _$PlanStep {
  const PlanStep._();

  const factory PlanStep({
    required String id,
    required String title,
    String? description,
    String? instruction,
    String? expectedOutput,
    int? estimateMinutes,
    @Default(0) int order,
    @Default([]) List<String> resources,
    @Default(false) bool completed,
  }) = _PlanStep;

  factory PlanStep.fromJson(Map<String, dynamic> json) {
    return PlanStep(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: json['description']?.toString(),
      instruction: json['instruction']?.toString(),
      expectedOutput: (json['expectedOutput'] ?? json['expected_output'])?.toString(),
      estimateMinutes: (json['estimateMinutes'] ?? json['estimate_minutes'] as num?)?.toInt(),
      order: (json['order'] as num?)?.toInt() ?? 0,
      resources: _parseStringList(json['resources']) ?? [],
      completed: json['completed'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (description != null) 'description': description,
    if (instruction != null) 'instruction': instruction,
    if (expectedOutput != null) 'expectedOutput': expectedOutput,
    if (estimateMinutes != null) 'estimateMinutes': estimateMinutes,
    'order': order,
    'resources': resources,
    'completed': completed,
  };

  static List<String>? _parseStringList(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value.map((e) => e.toString()).toList();
  }

  /// Get displayable instruction (fallback to description).
  String get displayInstruction => instruction ?? description ?? '';
}

/// A material/resource for a plan item.
@freezed
class PlanMaterial with _$PlanMaterial {
  const PlanMaterial._();

  const factory PlanMaterial({
    String? id,
    required PlanMaterialType type,
    required String title,
    String? url,
    String? contentMarkdown,
    int? durationMinutes,
    String? reason,
  }) = _PlanMaterial;

  factory PlanMaterial.fromJson(Map<String, dynamic> json) {
    return PlanMaterial(
      id: json['id']?.toString(),
      type: PlanMaterialType.fromString(json['type']?.toString()),
      title: (json['title'] ?? '').toString(),
      url: json['url']?.toString(),
      contentMarkdown: (json['contentMarkdown'] ?? json['content_markdown'])?.toString(),
      durationMinutes: (json['durationMinutes'] ?? json['duration_minutes'] as num?)?.toInt(),
      reason: json['reason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'type': type.toJson(),
    'title': title,
    if (url != null) 'url': url,
    if (contentMarkdown != null) 'contentMarkdown': contentMarkdown,
    if (durationMinutes != null) 'durationMinutes': durationMinutes,
    if (reason != null) 'reason': reason,
  };

  /// Check if this is an in-app lesson.
  bool get isInAppLesson => type == PlanMaterialType.inAppLesson;

  /// Check if this is a search result.
  bool get isSearch => type == PlanMaterialType.search;

  /// Check if this is an external link.
  bool get isLink => type == PlanMaterialType.link || (url != null && type != PlanMaterialType.inAppLesson);

  /// Check if this is a book.
  bool get isBook => type == PlanMaterialType.book;

  /// Check if this is a video.
  bool get isVideo => type == PlanMaterialType.video;
}

/// Detailed information for a plan item.
@freezed
class PlanItemDetails with _$PlanItemDetails {
  const PlanItemDetails._();

  const factory PlanItemDetails({
    @Default([]) List<PlanStep> steps,
    @Default([]) List<PlanMaterial> materials,
  }) = _PlanItemDetails;

  factory PlanItemDetails.fromJson(Map<String, dynamic> json) {
    return PlanItemDetails(
      steps: _parseSteps(json['steps']) ?? [],
      materials: _parseMaterials(json['materials']) ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'steps': steps.map((s) => s.toJson()).toList(),
    'materials': materials.map((m) => m.toJson()).toList(),
  };

  static List<PlanStep>? _parseSteps(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => PlanStep.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<PlanMaterial>? _parseMaterials(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => PlanMaterial.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get total estimated time in minutes.
  int get totalEstimateMinutes {
    return steps.fold(0, (sum, step) => sum + (step.estimateMinutes ?? 0));
  }

  /// Get completed steps count.
  int get completedStepsCount {
    return steps.where((s) => s.completed).length;
  }

  /// Calculate progress percentage based on completed steps.
  double get progressPercent {
    if (steps.isEmpty) return 0;
    return (completedStepsCount / steps.length) * 100;
  }
}

/// Response for getting plan item with details.
/// API: GET /plan-items/{item_id}/detailed
@freezed
class PlanItemDetailsResponse with _$PlanItemDetailsResponse {
  const PlanItemDetailsResponse._();

  const factory PlanItemDetailsResponse({
    required PlanItem item,
    PlanItemDetails? details,
    ProgressInfo? progress,
    @Default(false) bool completed,
    DetailsStatus? detailsStatus,
    String? jobId,
  }) = _PlanItemDetailsResponse;

  factory PlanItemDetailsResponse.fromJson(Map<String, dynamic> json) {
    return PlanItemDetailsResponse(
      item: PlanItem.fromJson(json['item'] as Map<String, dynamic>),
      details: json['details'] != null
          ? PlanItemDetails.fromJson(json['details'] as Map<String, dynamic>)
          : null,
      progress: json['progress'] != null
          ? ProgressInfo.fromJson(json['progress'] as Map<String, dynamic>)
          : null,
      completed: json['completed'] == true,
      detailsStatus: json['detailsStatus'] != null || json['details_status'] != null
          ? DetailsStatus.fromString((json['detailsStatus'] ?? json['details_status'])?.toString())
          : null,
      jobId: (json['jobId'] ?? json['job_id'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'item': {
      'id': item.id,
      'title': item.title,
      'type': item.type,
      if (item.description != null) 'description': item.description,
      'status': item.status,
      'progressPercent': item.progressPercent,
    },
    if (details != null) 'details': details!.toJson(),
    if (progress != null) 'progress': progress!.toJson(),
    'completed': completed,
    if (detailsStatus != null) 'details_status': detailsStatus!.name,
    if (jobId != null) 'job_id': jobId,
  };

  /// Check if details are ready to display.
  bool get hasDetails => details != null && detailsStatus == DetailsStatus.available;

  /// Check if details are being generated.
  bool get isGenerating => detailsStatus == DetailsStatus.generating;

  /// Check if details generation failed.
  bool get hasFailed => detailsStatus == DetailsStatus.failed;

  /// Get progress percent for UI display.
  double get progressPercent => progress?.percent ?? 0.0;
}

/// Summary for a week in a plan.
/// API: GET /plans/{plan_id}/weeks/{week}/summary
@freezed
class WeekSummary with _$WeekSummary {
  const WeekSummary._();

  const factory WeekSummary({
    required int week,
    required int totalItems,
    required int completedItems,
    required double percent,
    @Default([]) List<PlanItem> items,
    String? theme,
    String? summary,
    int? totalMinutes,
    int? completedMinutes,
  }) = _WeekSummary;

  factory WeekSummary.fromJson(Map<String, dynamic> json) {
    return WeekSummary(
      week: (json['week'] as num?)?.toInt() ?? 1,
      totalItems: (json['total_items'] ?? json['totalItems'] as num?)?.toInt() ?? 0,
      completedItems: (json['completed_items'] ?? json['completedItems'] as num?)?.toInt() ?? 0,
      percent: (json['percent'] as num?)?.toDouble() ?? 0.0,
      items: _parseItems(json['items']) ?? [],
      theme: json['theme']?.toString(),
      summary: json['summary']?.toString(),
      totalMinutes: (json['total_minutes'] ?? json['totalMinutes'] as num?)?.toInt(),
      completedMinutes: (json['completed_minutes'] ?? json['completedMinutes'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'week': week,
    'total_items': totalItems,
    'completed_items': completedItems,
    'percent': percent,
    'items': items.map((i) => {
      'id': i.id,
      'title': i.title,
      'type': i.type,
      'status': i.status,
      'progressPercent': i.progressPercent,
    }).toList(),
    if (theme != null) 'theme': theme,
    if (summary != null) 'summary': summary,
    if (totalMinutes != null) 'total_minutes': totalMinutes,
    if (completedMinutes != null) 'completed_minutes': completedMinutes,
  };

  static List<PlanItem>? _parseItems(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => PlanItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Check if week is fully completed.
  bool get isCompleted => completedItems >= totalItems && totalItems > 0;

  /// Check if week has any progress.
  bool get hasProgress => completedItems > 0;

  /// Get remaining items count.
  int get remainingItems => totalItems - completedItems;

  /// Get progress as percent for UI display.
  double get progressPercent => percent;
}

/// Response for toggling plan item completion.
/// API: POST /plan-items/{item_id}/toggle-complete
@freezed
class ToggleCompleteResponse with _$ToggleCompleteResponse {
  const ToggleCompleteResponse._();

  const factory ToggleCompleteResponse({
    required bool completed,
    ProgressInfo? progress,
  }) = _ToggleCompleteResponse;

  factory ToggleCompleteResponse.fromJson(Map<String, dynamic> json) {
    return ToggleCompleteResponse(
      completed: json['completed'] == true,
      progress: json['progress'] != null
          ? ProgressInfo.fromJson(json['progress'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Get progress percent for UI display.
  double get progressPercent => progress?.percent ?? 0.0;
}

/// Response for toggling step completion.
/// API: POST /plan-items/{item_id}/steps/{step_id}/toggle
@freezed
class ToggleStepResponse with _$ToggleStepResponse {
  const ToggleStepResponse._();

  const factory ToggleStepResponse({
    required String stepId,
    required bool completed,
    ProgressInfo? progress,
    @Default(false) bool itemCompleted,
  }) = _ToggleStepResponse;

  factory ToggleStepResponse.fromJson(Map<String, dynamic> json) {
    return ToggleStepResponse(
      stepId: (json['step_id'] ?? json['stepId'] ?? '').toString(),
      completed: json['completed'] == true,
      progress: json['progress'] != null
          ? ProgressInfo.fromJson(json['progress'] as Map<String, dynamic>)
          : null,
      itemCompleted: json['item_completed'] == true || json['itemCompleted'] == true,
    );
  }

  /// Get progress percent for UI display.
  double get progressPercent => progress?.percent ?? 0.0;
}

/// Response for regenerating plan item details.
/// API: POST /plan-items/{item_id}/regenerate-details
@freezed
class RegenerateDetailsResponse with _$RegenerateDetailsResponse {
  const RegenerateDetailsResponse._();

  const factory RegenerateDetailsResponse({
    required String jobId,
  }) = _RegenerateDetailsResponse;

  factory RegenerateDetailsResponse.fromJson(Map<String, dynamic> json) {
    return RegenerateDetailsResponse(
      jobId: (json['job_id'] ?? json['jobId'] ?? '').toString(),
    );
  }
}
