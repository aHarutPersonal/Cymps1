import 'package:freezed_annotation/freezed_annotation.dart';

part 'comparison_models.freezed.dart';

// Helper functions for safe type conversion
int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Category breakdown in comparison.
@freezed
class CategoryBreakdown with _$CategoryBreakdown {
  const factory CategoryBreakdown({
    required String category,
    @Default(0) double userScore,
    @Default(0) double idolScore,
    @Default(0) int userCount,
    @Default(0) int idolCount,
    double? percentage,
    double? percent,
  }) = _CategoryBreakdown;

  factory CategoryBreakdown.fromJson(Map<String, dynamic> json) {
    return CategoryBreakdown(
      category: (json['category'] ?? '').toString(),
      userScore: _parseDouble(json['userScore'] ?? json['user_score']) ?? 0,
      idolScore: _parseDouble(json['idolScore'] ?? json['idol_score']) ?? 0,
      userCount: _parseInt(json['userCount'] ?? json['user_count']) ?? 0,
      idolCount: _parseInt(json['idolCount'] ?? json['idol_count']) ?? 0,
      percentage: _parseDouble(json['percentage']),
      percent: _parseDouble(json['percent']),
    );
  }
}

/// A strength identified in comparison.
@freezed
class ComparisonStrength with _$ComparisonStrength {
  const factory ComparisonStrength({
    required String category,
    required String description,
    String? achievementId,
    String? achievementTitle,
  }) = _ComparisonStrength;

  factory ComparisonStrength.fromJson(Map<String, dynamic> json) {
    return ComparisonStrength(
      category: (json['category'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      achievementId: (json['achievementId'] ?? json['achievement_id'])?.toString(),
      achievementTitle: (json['achievementTitle'] ?? json['achievement_title'])?.toString(),
    );
  }
}

/// A gap identified in comparison.
@freezed
class ComparisonGap with _$ComparisonGap {
  const factory ComparisonGap({
    required String category,
    required String description,
    String? milestoneId,
    String? milestoneTitle,
    int? idolAgeAtEvent,
    String? suggestion,
  }) = _ComparisonGap;

  factory ComparisonGap.fromJson(Map<String, dynamic> json) {
    return ComparisonGap(
      category: (json['category'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      milestoneId: (json['milestoneId'] ?? json['milestone_id'])?.toString(),
      milestoneTitle: (json['milestoneTitle'] ?? json['milestone_title'])?.toString(),
      idolAgeAtEvent: _parseInt(json['idolAgeAtEvent'] ?? json['idol_age_at_event']),
      suggestion: json['suggestion']?.toString(),
    );
  }
}

/// Missing vs idol item.
@freezed
class MissingMilestone with _$MissingMilestone {
  const factory MissingMilestone({
    String? id,
    String? title,
    String? description,
    String? category,
    int? ageAtEvent,
    String? eventDate,
    double? importanceScore,
  }) = _MissingMilestone;

  factory MissingMilestone.fromJson(Map<String, dynamic> json) {
    return MissingMilestone(
      id: json['id']?.toString(),
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      category: json['category']?.toString(),
      ageAtEvent: _parseInt(json['ageAtEvent'] ?? json['age_at_event']),
      eventDate: (json['eventDate'] ?? json['event_date'])?.toString(),
      importanceScore: _parseDouble(json['importanceScore'] ?? json['importance_score']),
    );
  }
}

/// Full comparison response.
@freezed
class ComparisonResponse with _$ComparisonResponse {
  const factory ComparisonResponse({
    required double overallScore,
    @Default([]) List<CategoryBreakdown> categoryBreakdown,
    @Default([]) List<ComparisonStrength> strengths,
    @Default([]) List<ComparisonGap> gaps,
    @Default([]) List<MissingMilestone> missingVsIdol,
    @Default(0) double completeness,
    @Default(0) int countedUserAchievements,
    @Default(0) int idolMilestonesAtAge,
    @Default(0) int totalIdolMilestones,
    @Default(0) int totalUserAchievements,
    @Default(0) int matchedCount,
    int? userAge,
    int? targetAge,
    String? mode,
    String? idolId,
    String? idolName,
    DateTime? generatedAt,
    // AI-enhanced fields
    String? overallAnalysis,
    String? realisticPerspective,
    String? encouragement,
    NextMilestone? nextMilestone,
    @Default(false) bool aiEnhanced,
  }) = _ComparisonResponse;

  factory ComparisonResponse.fromJson(Map<String, dynamic> json) {
    return ComparisonResponse(
      overallScore: _parseDouble(json['overallScore'] ?? json['overall_score']) ?? 0,
      categoryBreakdown: _parseCategoryBreakdown(json['categoryBreakdown'] ?? json['category_breakdown']) ?? [],
      strengths: _parseStrengths(json['strengths']) ?? [],
      gaps: _parseGaps(json['gaps']) ?? [],
      missingVsIdol: _parseMissingMilestones(json['missingVsIdol'] ?? json['missing_vs_idol']) ?? [],
      completeness: _parseDouble(json['completeness']) ?? 0,
      countedUserAchievements: _parseInt(json['countedUserAchievements'] ?? json['counted_user_achievements']) ?? 0,
      idolMilestonesAtAge: _parseInt(json['idolMilestonesAtAge'] ?? json['idol_milestones_at_age']) ?? 0,
      totalIdolMilestones: _parseInt(json['totalIdolMilestones'] ?? json['total_idol_milestones']) ?? 0,
      totalUserAchievements: _parseInt(json['totalUserAchievements'] ?? json['total_user_achievements']) ?? 0,
      matchedCount: _parseInt(json['matchedCount'] ?? json['matched_count']) ?? 0,
      userAge: _parseInt(json['userAge'] ?? json['user_age']),
      targetAge: _parseInt(json['targetAge'] ?? json['target_age']),
      mode: json['mode']?.toString(),
      idolId: (json['idolId'] ?? json['idol_id'])?.toString(),
      idolName: (json['idolName'] ?? json['idol_name'])?.toString(),
      generatedAt: _parseDate(json['generatedAt'] ?? json['generated_at']),
      // AI-enhanced fields
      overallAnalysis: (json['overallAnalysis'] ?? json['overall_analysis'])?.toString(),
      realisticPerspective: (json['realisticPerspective'] ?? json['realistic_perspective'])?.toString(),
      encouragement: json['encouragement']?.toString(),
      nextMilestone: json['nextMilestone'] != null || json['next_milestone'] != null
          ? NextMilestone.fromJson((json['nextMilestone'] ?? json['next_milestone']) as Map<String, dynamic>)
          : null,
      aiEnhanced: json['aiEnhanced'] == true || json['ai_enhanced'] == true,
    );
  }

  static List<CategoryBreakdown>? _parseCategoryBreakdown(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => CategoryBreakdown.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<ComparisonStrength>? _parseStrengths(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => ComparisonStrength.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<ComparisonGap>? _parseGaps(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => ComparisonGap.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<MissingMilestone>? _parseMissingMilestones(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => MissingMilestone.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Suggested next milestone from AI.
@freezed
class NextMilestone with _$NextMilestone {
  const factory NextMilestone({
    required String title,
    required String description,
    String? estimatedTimeframe,
  }) = _NextMilestone;

  factory NextMilestone.fromJson(Map<String, dynamic> json) {
    return NextMilestone(
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      estimatedTimeframe: (json['estimatedTimeframe'] ?? json['estimated_timeframe'])?.toString(),
    );
  }
}

