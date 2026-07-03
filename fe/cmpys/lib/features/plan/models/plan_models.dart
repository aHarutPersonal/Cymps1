// Backend 12-week plan models (GET /plans/current, /plan-items/{id}/detailed,
// /jobs/{id}). Hand-written fromJson, matching the backend's response schemas:
// plan/item payloads are camelCase, item-detail payloads are snake_case.

/// Result of toggling a plan item's completion state. Contains the new
/// completed flag plus plan-level signals used by the achievement cycle flow.
class ToggleResult {
  const ToggleResult({
    required this.completed,
    this.planComplete = false,
    this.missionTasksRemaining,
  });

  final bool completed;
  final bool planComplete;
  final int? missionTasksRemaining;

  factory ToggleResult.fromJson(Map<String, dynamic> j) => ToggleResult(
        completed: j['completed'] as bool? ?? false,
        planComplete: j['planComplete'] as bool? ?? false,
        missionTasksRemaining: (j['missionTasksRemaining'] as num?)?.toInt(),
      );
}

/// One generated plan item. `type == 'habit'` items are the week's daily
/// rhythm tasks; every other type is a primary mission task.
class BackendPlanItem {
  const BackendPlanItem({
    required this.id,
    required this.title,
    required this.type,
    required this.description,
    required this.weekStart,
    required this.weekEnd,
    required this.successMetric,
    required this.estimatedHours,
    required this.status,
    required this.progressPercent,
    this.notes,
    this.resourceTitle,
    this.resourceUrl,
  });

  final String id;
  final String title;
  final String type; // habit | project | reading | course | practice | reflection
  final String description;
  final int weekStart;
  final int weekEnd;
  final String successMetric;
  final int estimatedHours;
  final String status; // not_started | in_progress | completed | skipped
  final int progressPercent;
  final String? notes;
  final String? resourceTitle;
  final String? resourceUrl;

  bool get isDailyRhythm => type == 'habit';
  bool get isMissionTask =>
      type == 'project' || type == 'course' || type == 'reading';
  bool get isCompleted => status == 'completed';

  factory BackendPlanItem.fromJson(Map<String, dynamic> j) => BackendPlanItem(
        id: j['id']?.toString() ?? '',
        title: j['title'] as String? ?? '',
        type: j['type'] as String? ?? 'project',
        description: j['description'] as String? ?? '',
        weekStart: (j['weekStart'] as num?)?.toInt() ?? 1,
        weekEnd: (j['weekEnd'] as num?)?.toInt() ?? 1,
        successMetric: j['successMetric'] as String? ?? '',
        estimatedHours: (j['estimatedHours'] as num?)?.toInt() ?? 1,
        status: j['status'] as String? ?? 'not_started',
        progressPercent: (j['progressPercent'] as num?)?.toInt() ?? 0,
        notes: j['notes'] as String?,
        resourceTitle: j['resourceTitle'] as String?,
        resourceUrl: j['resourceUrl'] as String?,
      );
}

/// The user's generated 12-week plan.
class BackendPlan {
  // Non-const: carries a lazily-built week index (see [_weekIndex]).
  BackendPlan({
    required this.id,
    required this.durationWeeks,
    required this.weeklyHours,
    required this.items,
    this.cycleNumber = 1,
    this.idolName,
    this.roadmapThesis,
    this.antiGoals = const [],
    this.totalItems = 0,
    this.completedItems = 0,
    this.overallProgress = 0,
    this.createdAt,
  });

  final String id;
  final int durationWeeks;
  final int weeklyHours;
  final int cycleNumber;
  final List<BackendPlanItem> items;
  final String? idolName;
  final String? roadmapThesis;
  final List<String> antiGoals;
  final int totalItems;
  final int completedItems;
  final double overallProgress;
  final DateTime? createdAt;

  // week → items covering it, precomputed once per plan instance so the
  // roadmap doesn't re-filter the full item list per week on every rebuild.
  Map<int, List<BackendPlanItem>>? _missionsByWeek;
  Map<int, List<BackendPlanItem>>? _rhythmByWeek;

  void _buildWeekIndex() {
    final missions = <int, List<BackendPlanItem>>{};
    final rhythm = <int, List<BackendPlanItem>>{};
    for (final item in items) {
      final byWeek = item.isDailyRhythm ? rhythm : missions;
      for (var week = item.weekStart; week <= item.weekEnd; week++) {
        (byWeek[week] ??= []).add(item);
      }
    }
    _missionsByWeek = missions;
    _rhythmByWeek = rhythm;
  }

  /// Mission tasks (non-habit) covering [week].
  List<BackendPlanItem> missionsForWeek(int week) {
    if (_missionsByWeek == null) _buildWeekIndex();
    return _missionsByWeek![week] ?? const [];
  }

  /// Daily rhythm (habit) tasks covering [week].
  List<BackendPlanItem> dailyRhythmForWeek(int week) {
    if (_rhythmByWeek == null) _buildWeekIndex();
    return _rhythmByWeek![week] ?? const [];
  }

  /// Week the user is in right now (1-based, clamped to the plan length).
  /// A freshly generated plan is in week 1.
  int currentWeek([DateTime? now]) {
    final created = createdAt;
    if (created == null) return 1;
    final days = (now ?? DateTime.now()).difference(created).inDays;
    return (days ~/ 7 + 1).clamp(1, durationWeeks == 0 ? 1 : durationWeeks);
  }

  factory BackendPlan.fromJson(Map<String, dynamic> j) => BackendPlan(
        id: j['id']?.toString() ?? '',
        durationWeeks: (j['durationWeeks'] as num?)?.toInt() ?? 12,
        weeklyHours: (j['weeklyHours'] as num?)?.toInt() ?? 10,
        cycleNumber: (j['cycleNumber'] as num?)?.toInt() ?? 1,
        items: (j['items'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(BackendPlanItem.fromJson)
                .toList() ??
            const [],
        idolName: j['idolName'] as String?,
        roadmapThesis: j['roadmapThesis'] as String?,
        antiGoals:
            (j['antiGoals'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        totalItems: (j['totalItems'] as num?)?.toInt() ?? 0,
        completedItems: (j['completedItems'] as num?)?.toInt() ?? 0,
        overallProgress: (j['overallProgress'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? ''),
      );
}

/// One habit/practice item in today's view (GET /plans/{id}/today) with its
/// per-day completion state. Daily completions reset every day server-side.
class TodayTaskItem {
  const TodayTaskItem({
    required this.id,
    required this.title,
    required this.type,
    required this.estimatedHours,
    required this.completedToday,
    this.dailyInstructions,
  });

  final String id;
  final String title;
  final String type; // habit | practice
  final int estimatedHours; // hours for the week
  final bool completedToday;
  final String? dailyInstructions;

  factory TodayTaskItem.fromJson(Map<String, dynamic> j) => TodayTaskItem(
        id: j['id']?.toString() ?? '',
        title: j['title'] as String? ?? '',
        type: j['type'] as String? ?? 'habit',
        estimatedHours: (j['estimated_hours'] as num?)?.toInt() ?? 1,
        completedToday: j['completed_today'] as bool? ?? false,
        dailyInstructions: j['daily_instructions'] as String?,
      );
}

/// Today's daily rhythm for the current plan week, plus streak.
class TodayView {
  const TodayView({
    required this.items,
    required this.streak,
    required this.completedToday,
    required this.totalToday,
  });

  final List<TodayTaskItem> items;
  final int streak;
  final int completedToday;
  final int totalToday;

  factory TodayView.fromJson(Map<String, dynamic> j) => TodayView(
        items: (j['items'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(TodayTaskItem.fromJson)
                .toList() ??
            const [],
        streak: (j['streak'] as num?)?.toInt() ?? 0,
        completedToday: (j['completed_today'] as num?)?.toInt() ?? 0,
        totalToday: (j['total_today'] as num?)?.toInt() ?? 0,
      );
}

/// Status of an async backend job (GET /jobs/{id}).
class PlanJobStatus {
  const PlanJobStatus({
    required this.id,
    required this.status,
    required this.progressPercent,
    this.step,
    this.errorMessage,
    this.thinkingLine,
  });

  final String id;
  final String status; // pending | queued | running | completed | failed
  final int progressPercent;
  final String? step;
  final String? errorMessage;

  /// Latest "AI thinking" line for progress UI.
  final String? thinkingLine;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  factory PlanJobStatus.fromJson(Map<String, dynamic> j) => PlanJobStatus(
        id: j['id']?.toString() ?? '',
        status: j['status'] as String? ?? 'pending',
        progressPercent: (j['progressPercent'] as num?)?.toInt() ?? 0,
        step: j['step'] as String?,
        errorMessage: j['errorMessage'] as String?,
        thinkingLine:
            (j['thinkingStream'] as Map?)?['currentLine']?.toString(),
      );
}

/// One teach-first step inside a plan item's generated lesson details.
class PlanStepDetail {
  const PlanStepDetail({
    required this.id,
    required this.title,
    this.description,
    this.expectedOutput,
    this.estimateMinutes,
    this.substeps = const [],
    this.lessonContent,
  });

  final String id;
  final String title;
  final String? description;
  final String? expectedOutput;
  final int? estimateMinutes;
  final List<String> substeps;

  /// Full markdown lesson for this step.
  final String? lessonContent;

  factory PlanStepDetail.fromJson(Map<String, dynamic> j) => PlanStepDetail(
        id: j['id']?.toString() ?? '',
        title: j['title'] as String? ?? '',
        description: j['description'] as String?,
        expectedOutput: j['expected_output'] as String?,
        estimateMinutes: (j['estimate_minutes'] as num?)?.toInt(),
        substeps:
            (j['substeps'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        lessonContent: j['lesson_content'] as String?,
      );
}

/// A Deepstash-style idea card extracted from a book material.
class BookIdea {
  const BookIdea({
    required this.title,
    required this.content,
    this.category = 'Mindset',
  });

  final String title;
  final String content;
  final String category;

  factory BookIdea.fromJson(Map<String, dynamic> j) => BookIdea(
        title: j['title'] as String? ?? '',
        content: j['content'] as String? ?? '',
        category: j['category'] as String? ?? 'Mindset',
      );
}

/// A material/resource attached to a plan item (book, video, in-app lesson…).
class PlanMaterialDetail {
  const PlanMaterialDetail({
    required this.title,
    this.url,
    this.type,
    this.authorOrCreator,
    this.durationMinutes,
    this.reason,
    this.contentMarkdown,
    this.contentResourceId,
    this.ideas = const [],
  });

  final String title;
  final String? url;
  final String? type;
  final String? authorOrCreator;
  final int? durationMinutes;
  final String? reason;
  final String? contentMarkdown;

  /// Shared content_resources.id — the full lesson text may live there
  /// instead of inline in [contentMarkdown].
  final String? contentResourceId;
  final List<BookIdea> ideas;

  /// YouTube video id when [url] points at YouTube, else null.
  String? get youtubeVideoId {
    final u = url;
    if (u == null || u.isEmpty) return null;
    final uri = Uri.tryParse(u);
    if (uri == null) return null;
    final host = uri.host.replaceFirst('www.', '');
    if (host == 'youtu.be') {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    if (host.endsWith('youtube.com')) {
      final v = uri.queryParameters['v'];
      if (v != null && v.isNotEmpty) return v;
      // /embed/<id>, /shorts/<id>, /live/<id>
      final segs = uri.pathSegments;
      if (segs.length >= 2 &&
          const {'embed', 'shorts', 'live'}.contains(segs.first)) {
        return segs[1];
      }
    }
    return null;
  }

  bool get hasInAppContent =>
      (contentMarkdown != null && contentMarkdown!.trim().isNotEmpty) ||
      (contentResourceId != null && contentResourceId!.isNotEmpty) ||
      ideas.isNotEmpty;

  factory PlanMaterialDetail.fromJson(Map<String, dynamic> j) =>
      PlanMaterialDetail(
        title: j['title'] as String? ?? '',
        url: j['url'] as String?,
        type: j['type'] as String?,
        authorOrCreator: j['author_or_creator'] as String?,
        durationMinutes: (j['duration_minutes'] as num?)?.toInt(),
        reason: j['reason'] as String?,
        contentMarkdown: j['content_markdown'] as String?,
        contentResourceId: j['content_resource_id']?.toString(),
        ideas: (j['ideas'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(BookIdea.fromJson)
                .toList() ??
            const [],
      );
}

/// Shared content resource (GET /content-resources/{id}) — holds the full
/// in-app lesson/article/book text when the plan material only references
/// it, plus this user's reading progress.
class ContentResourceDetail {
  const ContentResourceDetail({
    required this.id,
    required this.title,
    this.authorOrCreator,
    this.contentMarkdown,
    this.durationMinutes,
    this.kind,
    this.progressPercent = 0,
    this.cursorJson,
    this.ideas = const [],
  });

  final String id;
  final String title;
  final String? authorOrCreator;
  final String? contentMarkdown;
  final int? durationMinutes;
  final String? kind;
  final int progressPercent;
  final Map<String, dynamic>? cursorJson;
  final List<BookIdea> ideas;

  /// Last chapter the user had open (from cursorJson), or 0.
  int get cursorChapter => (cursorJson?['chapter'] as num?)?.toInt() ?? 0;

  factory ContentResourceDetail.fromJson(Map<String, dynamic> j) =>
      ContentResourceDetail(
        id: j['id']?.toString() ?? '',
        title: j['title'] as String? ?? '',
        authorOrCreator: j['authorOrCreator'] as String?,
        contentMarkdown: j['contentMarkdown'] as String?,
        durationMinutes: (j['durationMinutes'] as num?)?.toInt(),
        kind: j['kind'] as String?,
        progressPercent: (j['progressPercent'] as num?)?.toInt() ?? 0,
        cursorJson: (j['cursorJson'] as Map?)?.cast<String, dynamic>(),
        ideas: ((j['summaryJson'] as Map?)?['ideas'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(BookIdea.fromJson)
                .toList() ??
            const [],
      );
}

/// One chapter/section of a book resource, split from its markdown.
class BookChapter {
  const BookChapter({required this.title, required this.markdown});

  final String title;
  final String markdown;
}

/// Split a book's markdown into chapters on `## ` headings. Falls back to
/// fixed-size parts for texts without chapter markers, so even unstructured
/// books stay readable page by page.
List<BookChapter> splitBookChapters(String markdown) {
  final lines = markdown.split('\n');
  final chapters = <BookChapter>[];
  String currentTitle = 'Beginning';
  final buffer = StringBuffer();

  void flush() {
    final body = buffer.toString().trim();
    if (body.isNotEmpty) {
      chapters.add(BookChapter(title: currentTitle, markdown: body));
    }
    buffer.clear();
  }

  for (final line in lines) {
    if (line.startsWith('## ')) {
      flush();
      currentTitle = line.substring(3).trim();
    } else if (line.startsWith('# ')) {
      // Book title line — skip, the reader shows it in the header.
      continue;
    } else {
      buffer.writeln(line);
    }
  }
  flush();

  if (chapters.length > 1) return chapters;

  // No chapter markers: split into ~2500-word parts.
  final text = chapters.isEmpty ? markdown : chapters.first.markdown;
  final paragraphs = text.split('\n\n');
  final parts = <BookChapter>[];
  final part = StringBuffer();
  var words = 0;
  for (final p in paragraphs) {
    part.writeln(p);
    part.writeln();
    words += p.split(' ').length;
    if (words >= 2500) {
      parts.add(BookChapter(
          title: 'Part ${parts.length + 1}', markdown: part.toString().trim()));
      part.clear();
      words = 0;
    }
  }
  if (part.toString().trim().isNotEmpty) {
    parts.add(BookChapter(
        title: 'Part ${parts.length + 1}', markdown: part.toString().trim()));
  }
  if (parts.length <= 1) {
    return [BookChapter(title: 'Full text', markdown: text)];
  }
  return parts;
}

/// GET /plan-items/{id}/detailed — item + lesson details + progress.
/// While the lesson is still being generated, `detailsStatus` is `pending`
/// and `jobId` points at the generation job to poll.
class PlanItemDetailed {
  const PlanItemDetailed({
    required this.item,
    required this.detailsStatus,
    this.steps = const [],
    this.materials = const [],
    this.completed = false,
    this.jobId,
  });

  final BackendPlanItem item;
  final String detailsStatus; // available | pending | generating | failed
  final List<PlanStepDetail> steps;
  final List<PlanMaterialDetail> materials;
  final bool completed;
  final String? jobId;

  bool get detailsReady => detailsStatus == 'available';

  factory PlanItemDetailed.fromJson(Map<String, dynamic> j) {
    final details = j['details'] as Map<String, dynamic>?;
    return PlanItemDetailed(
      item: BackendPlanItem.fromJson(
          (j['item'] as Map?)?.cast<String, dynamic>() ?? const {}),
      detailsStatus: j['details_status'] as String? ?? 'available',
      steps: (details?['steps'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(PlanStepDetail.fromJson)
              .toList() ??
          const [],
      materials: (details?['materials'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(PlanMaterialDetail.fromJson)
              .toList() ??
          const [],
      completed: j['completed'] as bool? ?? false,
      jobId: j['job_id']?.toString(),
    );
  }
}
