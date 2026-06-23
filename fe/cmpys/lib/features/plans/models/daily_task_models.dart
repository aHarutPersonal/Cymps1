

/// A daily task for the home screen today view.
class DailyTask {
  const DailyTask({
    required this.id,
    required this.title,
    required this.type,
    this.estimatedHours,
    this.completedToday = false,
    this.dailyInstructions,
  });

  final String id;
  final String title;
  final String type; // 'habit' or 'practice'
  final double? estimatedHours;
  final bool completedToday;
  final String? dailyInstructions;

  /// Whether this is a daily-type task (habit or practice).
  bool get isDaily => type == 'habit' || type == 'practice';

  /// Display duration in minutes.
  String get durationLabel {
    final minutes = estimatedHours != null
        ? (estimatedHours! * 60).round()
        : 30;
    return '${minutes}m';
  }

  factory DailyTask.fromJson(Map<String, dynamic> json) {
    return DailyTask(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      type: (json['type'] ?? 'habit').toString(),
      estimatedHours:
          (json['estimatedHours'] ?? json['estimated_hours'] as num?)
              ?.toDouble(),
      completedToday: json['completedToday'] == true ||
          json['completed_today'] == true,
      dailyInstructions:
          (json['dailyInstructions'] ?? json['daily_instructions'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        if (estimatedHours != null) 'estimatedHours': estimatedHours,
        'completedToday': completedToday,
        if (dailyInstructions != null) 'dailyInstructions': dailyInstructions,
      };
}

/// Today's overview with tasks and streak.
class TodayOverview {
  const TodayOverview({
    required this.date,
    required this.items,
    this.streak = 0,
    this.totalToday = 0,
    this.completedToday = 0,
  });

  final String date;
  final List<DailyTask> items;
  final int streak;
  final int totalToday;
  final int completedToday;

  /// Whether there are any daily tasks for today.
  bool get hasDailyTasks => items.isNotEmpty;

  /// Whether all tasks are completed.
  bool get allCompleted => totalToday > 0 && completedToday >= totalToday;

  /// Remaining tasks count.
  int get remaining => totalToday - completedToday;

  factory TodayOverview.fromJson(Map<String, dynamic> json) {
    return TodayOverview(
      date: (json['date'] ?? '').toString(),
      items: _parseItems(json['items']),
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      totalToday:
          (json['totalToday'] ?? json['total_today'] as num?)?.toInt() ?? 0,
      completedToday:
          (json['completedToday'] ?? json['completed_today'] as num?)
              ?.toInt() ??
          0,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'items': items.map((i) => i.toJson()).toList(),
        'streak': streak,
        'totalToday': totalToday,
        'completedToday': completedToday,
      };

  static List<DailyTask> _parseItems(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value
        .map((e) => DailyTask.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// A single day dot in the weekly grid.
class DailyDot {
  const DailyDot({
    required this.date,
    required this.dayName,
    this.completed = false,
  });

  final String date;
  final String dayName;
  final bool completed;

  /// Whether this dot represents a future day.
  bool get isFuture {
    final dotDate = DateTime.tryParse(date);
    if (dotDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return dotDate.isAfter(today);
  }

  factory DailyDot.fromJson(Map<String, dynamic> json) {
    return DailyDot(
      date: (json['date'] ?? '').toString(),
      dayName: (json['dayName'] ?? json['day_name'] ?? '').toString(),
      completed: json['completed'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'dayName': dayName,
        'completed': completed,
      };
}

/// Weekly dot grid status for a daily task.
class DailyTaskWeekStatus {
  const DailyTaskWeekStatus({
    required this.itemId,
    required this.weekStart,
    required this.weekEnd,
    required this.days,
    this.completedCount = 0,
    this.totalDays = 7,
  });

  final String itemId;
  final String weekStart;
  final String weekEnd;
  final List<DailyDot> days;
  final int completedCount;
  final int totalDays;

  factory DailyTaskWeekStatus.fromJson(Map<String, dynamic> json) {
    return DailyTaskWeekStatus(
      itemId: (json['itemId'] ?? json['item_id'] ?? '').toString(),
      weekStart: (json['weekStart'] ?? json['week_start'] ?? '').toString(),
      weekEnd: (json['weekEnd'] ?? json['week_end'] ?? '').toString(),
      days: _parseDays(json['days']),
      completedCount:
          (json['completedCount'] ?? json['completed_count'] as num?)
              ?.toInt() ??
          0,
      totalDays:
          (json['totalDays'] ?? json['total_days'] as num?)?.toInt() ?? 7,
    );
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'weekStart': weekStart,
        'weekEnd': weekEnd,
        'days': days.map((d) => d.toJson()).toList(),
        'completedCount': completedCount,
        'totalDays': totalDays,
      };

  static List<DailyDot> _parseDays(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value
        .map((e) => DailyDot.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// User's streak information.
class StreakInfo {
  const StreakInfo({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastActiveDate,
  });

  final int currentStreak;
  final int longestStreak;
  final String? lastActiveDate;

  factory StreakInfo.fromJson(Map<String, dynamic> json) {
    return StreakInfo(
      currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
      longestStreak: (json['longest_streak'] as num?)?.toInt() ?? 0,
      lastActiveDate: (json['last_active_date'])?.toString(),
    );
  }
}

/// Today's focus item with reflection prompt.
class DailyFocusItem {
  const DailyFocusItem({
    required this.id,
    required this.title,
    required this.type,
    this.estimatedHours,
    this.dailyInstructions,
  });

  final String id;
  final String title;
  final String type;
  final int? estimatedHours;
  final String? dailyInstructions;

  factory DailyFocusItem.fromJson(Map<String, dynamic> json) {
    return DailyFocusItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      type: (json['type'] ?? 'habit').toString(),
      estimatedHours: (json['estimated_hours'] as num?)?.toInt(),
      dailyInstructions: (json['daily_instructions'])?.toString(),
    );
  }
}

/// Daily focus response with focus item, reflection prompt, and streak.
class DailyFocus {
  const DailyFocus({
    this.focusItem,
    this.reflectionPrompt,
    this.streak = 0,
  });

  final DailyFocusItem? focusItem;
  final String? reflectionPrompt;
  final int streak;

  factory DailyFocus.fromJson(Map<String, dynamic> json) {
    final focusData = json['focus_item'] as Map<String, dynamic>?;
    return DailyFocus(
      focusItem: focusData != null ? DailyFocusItem.fromJson(focusData) : null,
      reflectionPrompt: (json['reflection_prompt'])?.toString(),
      streak: (json['streak'] as num?)?.toInt() ?? 0,
    );
  }
}
