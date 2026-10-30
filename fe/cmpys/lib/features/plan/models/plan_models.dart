// Backend 12-week plan models (GET /plans/current, /plan-items/{id}/detailed,
// /jobs/{id}). Hand-written fromJson, matching the backend's response schemas:
// plan/item payloads are camelCase, item-detail payloads are snake_case.

import 'dart:math' as math;

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
    this.estimatedMinutes,
    required this.status,
    required this.progressPercent,
    this.notes,
    this.resourceTitle,
    this.resourceUrl,
  });

  final String id;
  final String title;
  final String
  type; // habit | project | reading | course | practice | reflection
  final String description;
  final int weekStart;
  final int weekEnd;
  final String successMetric;
  final int estimatedHours;
  final int? estimatedMinutes;
  int get requiredMinutes => estimatedMinutes ?? estimatedHours * 60;
  String get durationLabel => formatMinutes(requiredMinutes);
  static String formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return '${remainder}m';
    return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
  }

  final String status; // not_started | in_progress | completed | skipped
  final int progressPercent;
  final String? notes;
  final String? resourceTitle;
  final String? resourceUrl;

  bool get isDailyRhythm => type == 'habit' || type == 'practice';
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
    estimatedMinutes: (j['estimatedMinutes'] as num?)?.toInt(),
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
    this.weeklyMinutes,
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

  /// Exact weekly capacity in minutes (half-hour steps); [weeklyHours] is the
  /// legacy whole-hour value. Null from servers that predate it.
  final int? weeklyMinutes;
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

  /// The first week that still contains unfinished finite work. Daily rhythm
  /// items intentionally do not gate progression because they reset and are
  /// meant to support the mission, not keep the user permanently locked.
  int get focusWeek {
    var firstIncompleteWeek = durationWeeks == 0 ? 1 : durationWeeks;
    var found = false;
    for (final item in items) {
      if (item.isDailyRhythm || item.isCompleted) continue;
      if (!found || item.weekStart < firstIncompleteWeek) {
        firstIncompleteWeek = item.weekStart;
        found = true;
      }
    }
    return found
        ? firstIncompleteWeek.clamp(1, durationWeeks == 0 ? 1 : durationWeeks)
        : (durationWeeks == 0 ? 1 : durationWeeks);
  }

  bool get allMissionWorkComplete => items
      .where((item) => !item.isDailyRhythm)
      .every((item) => item.isCompleted);

  /// Past weeks are reviewable, the focus week is actionable, and every
  /// future week stays locked until the current focus advances.
  bool isWeekUnlocked(int week) => allMissionWorkComplete || week <= focusWeek;

  BackendPlanItem? focusedItemForWeek(int week) {
    final remaining = missionsForWeek(
      week,
    ).where((item) => !item.isCompleted).toList(growable: false);
    if (remaining.isEmpty) return null;

    BackendPlanItem best = remaining.first;
    for (final item in remaining.skip(1)) {
      final itemInProgress = item.status == 'in_progress';
      final bestInProgress = best.status == 'in_progress';
      if ((itemInProgress && !bestInProgress) ||
          (itemInProgress == bestInProgress &&
              item.progressPercent > best.progressPercent)) {
        best = item;
      }
    }
    return best;
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
    weeklyMinutes: (j['weeklyMinutes'] as num?)?.toInt(),
    cycleNumber: (j['cycleNumber'] as num?)?.toInt() ?? 1,
    items:
        (j['items'] as List?)
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
    this.estimatedMinutes,
    this.sessionMinutes,
    this.dailyInstructions,
  });

  final String id;
  final String title;
  final String type; // habit | practice
  final int estimatedHours; // hours for the week
  final bool completedToday;

  /// Exact minutes for the week (`estimated_minutes`); null from servers that
  /// predate it, when [estimatedHours] is the only allocation.
  final int? estimatedMinutes;

  /// Minutes of one practice session (`session_minutes`): the weekly minutes
  /// over the rhythm's sessions per week. Null from servers that predate it.
  final int? sessionMinutes;
  final String? dailyInstructions;

  /// The week's allocation in minutes: exact when the server sends it, else
  /// the whole hours.
  int get weeklyMinutes {
    final minutes = estimatedMinutes;
    return minutes != null && minutes > 0 ? minutes : estimatedHours * 60;
  }

  factory TodayTaskItem.fromJson(Map<String, dynamic> j) => TodayTaskItem(
    id: j['id']?.toString() ?? '',
    title: j['title'] as String? ?? '',
    type: j['type'] as String? ?? 'habit',
    estimatedHours: (j['estimated_hours'] as num?)?.toInt() ?? 1,
    estimatedMinutes: (j['estimated_minutes'] as num?)?.toInt(),
    sessionMinutes: (j['session_minutes'] as num?)?.toInt(),
    completedToday: j['completed_today'] as bool? ?? false,
    dailyInstructions: j['daily_instructions'] as String?,
  );
}

/// The user's daily streak (GET /streak). The server keeps no per-day
/// history here: only the current run, the longest run and the last day with
/// a completion.
class StreakSummary {
  const StreakSummary({
    required this.current,
    required this.longest,
    this.lastActive,
  });

  final int current;
  final int longest;

  /// Last calendar day with a completion (a date, no time), if any.
  final DateTime? lastActive;

  factory StreakSummary.fromJson(Map<String, dynamic> j) {
    final raw = DateTime.tryParse(j['last_active_date']?.toString() ?? '');
    return StreakSummary(
      current: (j['current_streak'] as num?)?.toInt() ?? 0,
      longest: (j['longest_streak'] as num?)?.toInt() ?? 0,
      lastActive: raw == null ? null : DateTime(raw.year, raw.month, raw.day),
    );
  }
}

/// One day of a habit's week grid (GET /plan-items/{id}/daily-status).
class DailyStatusDay {
  const DailyStatusDay({required this.date, required this.completed});

  /// The calendar day (a UTC date, no time).
  final DateTime date;
  final bool completed;

  factory DailyStatusDay.fromJson(Map<String, dynamic> j) {
    final raw = DateTime.tryParse(j['date']?.toString() ?? '');
    return DailyStatusDay(
      date: raw == null
          ? DateTime.utc(1970)
          : DateTime.utc(raw.year, raw.month, raw.day),
      completed: j['completed'] as bool? ?? false,
    );
  }
}

/// A habit's own Monday-to-Sunday completions for the server's current week
/// (GET /plan-items/{id}/daily-status), the source of the Plan tab's
/// per-habit 7-day grid.
class DailyStatus {
  const DailyStatus({required this.itemId, required this.days});

  final String itemId;
  final List<DailyStatusDay> days;

  factory DailyStatus.fromJson(Map<String, dynamic> j) => DailyStatus(
    itemId: j['item_id']?.toString() ?? '',
    days:
        (j['days'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(DailyStatusDay.fromJson)
            .toList() ??
        const [],
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
    items:
        (j['items'] as List?)
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
    this.readyLessonCount,
    this.totalLessonCount,
  });

  final String id;
  final String status; // pending | queued | running | completed | failed
  final int progressPercent;
  final String? step;
  final String? errorMessage;

  /// Latest "AI thinking" line for progress UI.
  final String? thinkingLine;

  /// Persisted content count, independent of rounded job progress.
  final int? readyLessonCount;

  /// How many lessons the job will prepare, when its result says so.
  final int? totalLessonCount;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  factory PlanJobStatus.fromJson(Map<String, dynamic> j) => PlanJobStatus(
    id: j['id']?.toString() ?? '',
    status: j['status'] as String? ?? 'pending',
    progressPercent: (j['progressPercent'] as num?)?.toInt() ?? 0,
    step: j['step'] as String?,
    errorMessage: j['errorMessage'] as String?,
    thinkingLine: (j['thinkingStream'] as Map?)?['currentLine']?.toString(),
    readyLessonCount: ((j['results'] as Map?)?['ready_lesson_count'] as num?)
        ?.toInt(),
    totalLessonCount: ((j['results'] as Map?)?['total_lesson_count'] as num?)
        ?.toInt(),
  );
}

/// A tutorial's AI-generated hero image (backend `TutorialIllustration`):
/// [url] is usually relative (served from `/media/tutorials/`), [alt] is the
/// accessible description, and [aspect] is `w:h` (only "16:9" today).
class TutorialIllustration {
  const TutorialIllustration({
    required this.url,
    this.alt = '',
    this.provider = '',
    this.aspect = '16:9',
  });

  final String url;
  final String alt;
  final String provider;
  final String aspect;

  /// Width over height from [aspect]; 16:9 when it is missing or invalid.
  double get aspectRatio {
    final parts = aspect.split(':');
    if (parts.length == 2) {
      final w = double.tryParse(parts[0].trim());
      final h = double.tryParse(parts[1].trim());
      if (w != null && h != null && w > 0 && h > 0) return w / h;
    }
    return 16 / 9;
  }

  /// Null unless [json] is a map with a non-empty `url`; the field is
  /// optional, so older payloads read without an image.
  static TutorialIllustration? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url']?.toString().trim() ?? '';
    if (url.isEmpty) return null;
    return TutorialIllustration(
      url: url,
      alt: json['alt']?.toString().trim() ?? '',
      provider: json['provider']?.toString() ?? '',
      aspect: json['aspect']?.toString() ?? '16:9',
    );
  }
}

/// One teach-first step inside a plan item's generated lesson details.
class PlanStepDetail {
  const PlanStepDetail({
    required this.id,
    required this.title,
    this.description,
    this.expectedOutput,
    this.estimateMinutes,
    this.readingMinutes,
    this.practiceMinutes,
    this.resources = const [],
    this.substeps = const [],
    this.lessonContent,
    this.lessonFormat,
    this.illustration,
  });

  final String id;
  final String title;
  final String? description;
  final String? expectedOutput;
  final int? estimateMinutes;
  final int? readingMinutes;
  final int? practiceMinutes;
  final List<String> resources;
  final List<String> substeps;

  /// Full markdown lesson for this step.
  final String? lessonContent;
  final String? lessonFormat;

  /// Optional hero image for a tutorial (absent when disabled or failed).
  final TutorialIllustration? illustration;

  bool get isTutorial => lessonFormat == 'tutorial_v1';
  bool get hasContent => lessonContent?.trim().isNotEmpty ?? false;

  /// Pending steps have no inferred reading time. Published content can use a
  /// word-count estimate when older payloads omit explicit timing metadata.
  int? get effectiveReadingMinutes {
    final minutes = readingMinutes;
    if (minutes != null && minutes > 0) return minutes;
    if (!hasContent) return null;
    final words = lessonContent!.trim().split(RegExp(r'\s+')).length;
    return (words / 200).ceil().clamp(1, 60);
  }

  int? get effectivePracticeMinutes {
    final minutes = practiceMinutes;
    return minutes != null && minutes > 0 ? minutes : null;
  }

  int? get totalMinutes {
    final reading = readingMinutes;
    final practice = effectivePracticeMinutes;
    if (reading != null && reading > 0 && practice != null) {
      return reading + practice;
    }
    final estimate = estimateMinutes;
    return estimate != null && estimate > 0 ? estimate : null;
  }

  factory PlanStepDetail.fromJson(
    Map<String, dynamic> j, {
    String? defaultLessonFormat,
  }) => PlanStepDetail(
    id: j['id']?.toString() ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String?,
    expectedOutput: j['expected_output'] as String?,
    estimateMinutes: (j['estimate_minutes'] as num?)?.toInt(),
    readingMinutes: ((j['reading_minutes'] ?? j['readingMinutes']) as num?)
        ?.toInt(),
    practiceMinutes: ((j['practice_minutes'] ?? j['practiceMinutes']) as num?)
        ?.toInt(),
    resources:
        (j['resources'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    substeps:
        (j['substeps'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    lessonContent: j['lesson_content'] as String?,
    lessonFormat: j['lesson_format'] as String? ?? defaultLessonFormat,
    illustration: TutorialIllustration.fromJson(j['illustration']),
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
    this.canonicalKey,
    this.urlResolutionStatus,
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
  final String? canonicalKey;
  final String? urlResolutionStatus;
  final List<BookIdea> ideas;

  /// A backend-provided exact destination after rejecting search pages and
  /// unsafe schemes. Kept defensive here so legacy rows cannot reopen them.
  String? get directUrl => safeDirectMaterialUrl(url);

  bool get exactLinkUnavailable =>
      urlResolutionStatus == 'unresolved' && directUrl == null;

  /// YouTube video id when [url] points at YouTube, else null.
  String? get youtubeVideoId {
    final u = directUrl;
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

  bool get hasInlineContent =>
      (contentMarkdown != null && contentMarkdown!.trim().isNotEmpty) ||
      ideas.isNotEmpty;

  /// External courses/tools/templates are recommendations, not reading
  /// lessons. Legacy rows may still carry a metadata-only resource id, so a
  /// real external link must win unless genuine inline content exists.
  bool get prefersExternalLink =>
      directUrl != null &&
      const {'course', 'tool', 'template'}.contains(type) &&
      !hasInlineContent;

  bool get hasInAppContent =>
      hasInlineContent ||
      ((contentResourceId != null && contentResourceId!.isNotEmpty) &&
          const {'book', 'article', 'in_app_lesson'}.contains(type));

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
        canonicalKey: (j['canonical_key'] ?? j['canonicalKey'])?.toString(),
        urlResolutionStatus:
            (j['url_resolution_status'] ?? j['urlResolutionStatus'])
                ?.toString(),
        ideas:
            (j['ideas'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(BookIdea.fromJson)
                .toList() ??
            const [],
      );
}

String? safeDirectMaterialUrl(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  final host = uri.host.toLowerCase();
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '').toLowerCase();
  final queryKeys = uri.queryParameters.keys
      .map((key) => key.toLowerCase())
      .toSet();
  if (host == 'localhost' ||
      host == '::1' ||
      host == '0.0.0.0' ||
      host.startsWith('127.') ||
      host.startsWith('10.') ||
      host.startsWith('192.168.') ||
      host.startsWith('169.254.') ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      (host.contains('google.') && path == '/search') ||
      (host.endsWith('bing.com') && path == '/search') ||
      host.endsWith('search.yahoo.com') ||
      (host.endsWith('duckduckgo.com') && queryKeys.contains('q')) ||
      ((host.startsWith('amazon.') || host.contains('.amazon.')) &&
          path == '/s') ||
      (host.endsWith('coursera.org') && path == '/search') ||
      (host.endsWith('youtube.com') && path == '/results')) {
    return null;
  }
  if (const {'/search', '/find', '/results'}.contains(path) &&
      queryKeys.intersection(const {
        'q',
        'query',
        'keyword',
        'search',
        'search_query',
      }).isNotEmpty) {
    return null;
  }
  return raw;
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
        ideas:
            ((j['summaryJson'] as Map?)?['ideas'] as List?)
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
      parts.add(
        BookChapter(
          title: 'Part ${parts.length + 1}',
          markdown: part.toString().trim(),
        ),
      );
      part.clear();
      words = 0;
    }
  }
  if (part.toString().trim().isNotEmpty) {
    parts.add(
      BookChapter(
        title: 'Part ${parts.length + 1}',
        markdown: part.toString().trim(),
      ),
    );
  }
  if (parts.length <= 1) {
    return [BookChapter(title: 'Full text', markdown: text)];
  }
  return parts;
}

/// `generation_window` on `GET /plan-items/{id}/detailed`: the tutorials the
/// backend keeps written (one ahead). [currentStepId] is the first step
/// without a completion, [nextStepId] the one after it (null at the end).
/// [waitingForLearner] is true when both are written, nothing is running and
/// the remaining steps wait, by design, for the learner to move on.
class GenerationWindow {
  const GenerationWindow({
    this.currentStepId,
    this.nextStepId,
    this.waitingForLearner = false,
  });

  final String? currentStepId;
  final String? nextStepId;
  final bool waitingForLearner;

  /// Null when [raw] is not an object (an older backend sends none).
  static GenerationWindow? tryParse(Object? raw) {
    if (raw is! Map) return null;
    String? id(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    return GenerationWindow(
      currentStepId: id(raw['current_step_id']),
      nextStepId: id(raw['next_step_id']),
      waitingForLearner: raw['waiting_for_learner'] == true,
    );
  }
}

/// GET /plan-items/{id}/detailed — item + lesson details + progress.
/// While lessons are still being generated, `detailsStatus` is `pending` or
/// `partial` and `jobId` points at the generation job to poll. A partial
/// response contains every outline step plus any lessons already ready.
class PlanItemDetailed {
  const PlanItemDetailed({
    required this.item,
    required this.detailsStatus,
    this.steps = const [],
    this.materials = const [],
    this.completed = false,
    this.completedStepIds = const {},
    this.completedSteps = 0,
    this.totalSteps = 0,
    this.jobId,
    this.artifactJobId,
    this.detailsError,
    this.detailsProgress = 0,
    this.detailsStep,
    this.dailyInstructions,
    this.dailyReflection = '',
    this.completedToday = false,
    this.lessonFormat,
    this.definitionOfDone,
    this.mentalModel,
    this.sessionMinutes,
    this.generationWindow,
  });

  final BackendPlanItem item;
  final String detailsStatus;
  // available | partial | pending | generating | failed
  final List<PlanStepDetail> steps;
  final List<PlanMaterialDetail> materials;
  final bool completed;
  final Set<String> completedStepIds;
  final int completedSteps;
  final int totalSteps;
  final String? jobId;

  /// Optimistic-concurrency token for completion mutations. This is distinct
  /// from [jobId], which is only the operational job currently being polled.
  final String? artifactJobId;
  final String? detailsError;
  final int detailsProgress;
  final String? detailsStep;
  final String? dailyInstructions;
  final String dailyReflection;
  final bool completedToday;
  final String? lessonFormat;

  /// Mission outcome copy from `details.definition_of_done` /
  /// `details.mental_model`. Absent on older lessons.
  final String? definitionOfDone;
  final String? mentalModel;

  /// A daily habit's minutes for one session (`session_minutes`, the value
  /// Today shows). Null from servers that predate it; then use
  /// [sessionMinutesOrWeekShare].
  final int? sessionMinutes;

  /// The one-ahead window; null from servers that predate it, where
  /// [windowCurrentIndex] and [windowNextIndex] fall back to the next
  /// uncompleted step and the one after it.
  final GenerationWindow? generationWindow;

  /// The habit's minutes for one session: [sessionMinutes] when the server
  /// sends it, else about a seventh of the week's allocation, at least one
  /// minute (what `habitSessionMinutes` does for Today's items).
  int get sessionMinutesOrWeekShare {
    final session = sessionMinutes;
    if (session != null && session > 0) return session;
    final weekly = item.estimatedMinutes;
    final week = weekly != null && weekly > 0
        ? weekly
        : item.estimatedHours * 60;
    return math.max(1, (week / 7).round());
  }

  bool get isTutorialSequence =>
      lessonFormat == 'tutorial_v1' ||
      (steps.isNotEmpty && steps.every((step) => step.isTutorial));
  int get readyLessonCount => steps.where((step) => step.hasContent).length;

  bool get detailsReady => detailsStatus == 'available';
  bool get detailsPartial => detailsStatus == 'partial';
  bool get hasReadyLesson =>
      steps.any((step) => step.lessonContent?.trim().isNotEmpty ?? false);
  bool get detailsFailed =>
      detailsStatus == 'failed' ||
      (detailsPartial && detailsError != null) ||
      (!detailsReady && !detailsPartial && !detailsLoading) ||
      generationStalled;

  /// The learner's tutorial is not written, nothing is writing it and
  /// generation is not parked: it stopped (a lost re-queue, say) and must
  /// offer "Generate again" rather than wait quietly.
  bool get generationStalled {
    if (completed || detailsReady || !isTutorialSequence || steps.isEmpty) {
      return false;
    }
    // Only a one-ahead server promises that a missing current tutorial with
    // no job is stuck; an older server batches and may sit idle between runs.
    if (generationWindow == null) return false;
    if (detailsLoading || generationParked) return false;
    final step = steps[activeStepIndex];
    return !step.hasContent && !isStepCompleted(step.id);
  }

  bool get detailsLoading =>
      detailsStatus == 'pending' ||
      detailsStatus == 'generating' ||
      (detailsPartial &&
          detailsError == null &&
          jobId != null &&
          !generationParked);

  /// Both window tutorials are written and generation waits for the learner
  /// to move on: not loading, not failed, nothing to poll. The window's
  /// `waiting_for_learner` is authoritative; `details_step` stands in only
  /// for a server that sends no window.
  bool get generationParked {
    if (detailsError != null) return false;
    final window = generationWindow;
    if (window != null) return window.waitingForLearner;
    return detailsStep == 'waiting_for_learner' && jobId == null;
  }

  /// The index of the step the learner is on, per the window.
  int get windowCurrentIndex {
    final index = _stepIndexOf(generationWindow?.currentStepId);
    return index ?? activeStepIndex;
  }

  /// The index of the step after it, or null at the end.
  int? get windowNextIndex {
    final window = generationWindow;
    if (window != null) {
      if (window.nextStepId == null) return null;
      final index = _stepIndexOf(window.nextStepId);
      if (index != null) return index;
    }
    final next = windowCurrentIndex + 1;
    return next < steps.length ? next : null;
  }

  int? _stepIndexOf(String? stepId) {
    if (stepId == null) return null;
    final index = steps.indexWhere((step) => step.id == stepId);
    return index < 0 ? null : index;
  }

  /// The first unwritten, unfinished step inside the window: the one a
  /// running job writes (one at a time). Null when both are written.
  int? get unwrittenWindowStepIndex {
    if (steps.isEmpty) return null;
    for (final index in [windowCurrentIndex, ?windowNextIndex]) {
      if (index < 0 || index >= steps.length) continue;
      final step = steps[index];
      if (!step.hasContent && !isStepCompleted(step.id)) return index;
    }
    return null;
  }

  /// The step being written right now, or null when no job is running.
  int? get preparingStepIndex =>
      detailsLoading ? unwrittenWindowStepIndex : null;

  /// Tutorial 1 is being written: nothing is started and it has no lesson
  /// yet (or there is no outline yet), and generation has not stopped.
  bool get firstTutorialPreparing =>
      !completed &&
      !detailsFailed &&
      completedStepIds.isEmpty &&
      (steps.isEmpty || !steps.first.hasContent);

  /// Tutorial 1 has its lesson and the learner has not finished it.
  bool get firstTutorialReadable =>
      !completed &&
      isTutorialSequence &&
      steps.isNotEmpty &&
      steps.first.hasContent &&
      !isStepCompleted(steps.first.id);

  bool isStepCompleted(String stepId) => completedStepIds.contains(stepId);

  /// The learner's next uncompleted step is published and can be read now.
  bool get currentStepReadable {
    if (steps.isEmpty) return false;
    final step = steps[activeStepIndex];
    return step.hasContent && !isStepCompleted(step.id);
  }

  int get activeStepIndex {
    for (var index = 0; index < steps.length; index++) {
      if (!isStepCompleted(steps[index].id)) return index;
    }
    return steps.isEmpty ? 0 : steps.length - 1;
  }

  bool isStepUnlocked(int index) =>
      completed || index <= activeStepIndex || isStepCompleted(steps[index].id);

  factory PlanItemDetailed.fromJson(Map<String, dynamic> j) {
    final details = j['details'] as Map<String, dynamic>?;
    final progress = j['progress'] as Map<String, dynamic>?;
    final lessonFormat = details?['lesson_format'] as String?;
    return PlanItemDetailed(
      item: BackendPlanItem.fromJson(
        (j['item'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      detailsStatus: j['details_status'] as String? ?? 'available',
      lessonFormat: lessonFormat,
      steps:
          (details?['steps'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(
                (step) => PlanStepDetail.fromJson(
                  step,
                  defaultLessonFormat: lessonFormat,
                ),
              )
              .toList() ??
          const [],
      materials:
          (details?['materials'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(PlanMaterialDetail.fromJson)
              .toList() ??
          const [],
      completed: j['completed'] as bool? ?? false,
      completedStepIds:
          ((j['completed_step_ids'] ?? j['completedStepIds']) as List? ??
                  const [])
              .map((e) => e.toString())
              .toSet(),
      completedSteps: (progress?['completed_steps'] as num?)?.toInt() ?? 0,
      totalSteps: (progress?['total_steps'] as num?)?.toInt() ?? 0,
      jobId: j['job_id']?.toString(),
      artifactJobId: (j['artifact_job_id'] ?? j['artifactJobId'])?.toString(),
      detailsError: j['details_error']?.toString(),
      detailsProgress: (j['details_progress'] as num?)?.toInt() ?? 0,
      detailsStep: j['details_step']?.toString(),
      dailyInstructions: j['daily_instructions']?.toString(),
      dailyReflection: j['daily_reflection']?.toString() ?? '',
      completedToday: j['completed_today'] as bool? ?? false,
      definitionOfDone: _optionalText(details?['definition_of_done']),
      mentalModel: _optionalText(details?['mental_model']),
      sessionMinutes: _sessionMinutes(j),
      generationWindow: GenerationWindow.tryParse(j['generation_window']),
    );
  }

  /// `session_minutes` on the response, or on its item payload.
  static int? _sessionMinutes(Map<String, dynamic> j) {
    final item = j['item'] as Map?;
    final value =
        j['session_minutes'] ??
        item?['session_minutes'] ??
        item?['sessionMinutes'];
    return value is num ? value.toInt() : null;
  }

  static String? _optionalText(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}

/// One of the user's achievements on the server (`GET /achievements`,
/// `AchievementResponse`): what the Record restores on sign-in.
class ServerAchievement {
  const ServerAchievement({
    required this.id,
    required this.title,
    required this.category,
    required this.source,
    this.notes,
    this.achievementDate,
    this.createdAt,
  });

  final String id;
  final String title;

  /// `career`, `learning`, `finance`, `impact`, `mindset` or `other`.
  final String category;

  /// `manual`, `plan_item` or `plan_cycle`.
  final String source;
  final String? notes;

  /// The date the user gave (a calendar date), when they gave one.
  final DateTime? achievementDate;

  /// When the server saved it.
  final DateTime? createdAt;

  /// A row from the list, or null when it has no id (it can't be matched or
  /// deleted later).
  static ServerAchievement? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.trim().isEmpty) return null;
    String? text(Object? v) => v is String ? v : null;
    DateTime? when(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return ServerAchievement(
      id: id,
      title: text(raw['title']) ?? '',
      category: text(raw['category']) ?? 'other',
      source: text(raw['source']) ?? 'manual',
      notes: text(raw['notes']),
      achievementDate: when(raw['achievementDate']),
      createdAt: when(raw['createdAt']),
    );
  }
}
