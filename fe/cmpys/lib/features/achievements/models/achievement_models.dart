import 'package:freezed_annotation/freezed_annotation.dart';

part 'achievement_models.freezed.dart';

/// Achievement category enum.
enum AchievementCategory {
  career,
  learning,
  finance,
  impact,
  mindset,
  other;

  static AchievementCategory fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'career':
        return AchievementCategory.career;
      case 'learning':
        return AchievementCategory.learning;
      case 'finance':
        return AchievementCategory.finance;
      case 'impact':
        return AchievementCategory.impact;
      case 'mindset':
        return AchievementCategory.mindset;
      default:
        return AchievementCategory.other;
    }
  }

  String toJson() => name;
}

/// A user achievement.
/// API: GET /achievements, POST /achievements, etc.
@freezed
class Achievement with _$Achievement {
  const Achievement._();

  const factory Achievement({
    required String id,
    required String userId,
    required String title,
    required AchievementCategory category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _Achievement;

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? json['user_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      category: AchievementCategory.fromString(json['category']?.toString()),
      achievementDate: _parseDate(
        json['achievementDate'] ?? json['achievement_date'],
      ),
      notes: json['notes']?.toString(),
      evidenceLink: (json['evidenceLink'] ?? json['evidence_link'])?.toString(),
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'title': title,
    'category': category.toJson(),
    if (achievementDate != null)
      'achievementDate': achievementDate!.toIso8601String().split('T')[0],
    if (notes != null) 'notes': notes,
    if (evidenceLink != null) 'evidenceLink': evidenceLink,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };
}

/// Request to create an achievement.
/// API: POST /achievements
@freezed
class CreateAchievementRequest with _$CreateAchievementRequest {
  const CreateAchievementRequest._();

  const factory CreateAchievementRequest({
    required String title,
    required AchievementCategory category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
  }) = _CreateAchievementRequest;

  factory CreateAchievementRequest.fromJson(Map<String, dynamic> json) {
    return CreateAchievementRequest(
      title: (json['title'] ?? '').toString(),
      category: AchievementCategory.fromString(json['category']?.toString()),
      achievementDate: _parseDate(
        json['achievementDate'] ?? json['achievement_date'],
      ),
      notes: json['notes']?.toString(),
      evidenceLink: (json['evidenceLink'] ?? json['evidence_link'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'category': category.toJson(),
    if (achievementDate != null)
      'achievementDate': achievementDate!.toIso8601String().split('T')[0],
    if (notes != null) 'notes': notes,
    if (evidenceLink != null) 'evidenceLink': evidenceLink,
  };

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Request to update an achievement.
/// API: PATCH /achievements/{achievement_id}
@freezed
class UpdateAchievementRequest with _$UpdateAchievementRequest {
  const UpdateAchievementRequest._();

  const factory UpdateAchievementRequest({
    String? title,
    AchievementCategory? category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
  }) = _UpdateAchievementRequest;

  factory UpdateAchievementRequest.fromJson(Map<String, dynamic> json) {
    return UpdateAchievementRequest(
      title: json['title']?.toString(),
      category: json['category'] != null
          ? AchievementCategory.fromString(json['category']?.toString())
          : null,
      achievementDate: _parseDate(
        json['achievementDate'] ?? json['achievement_date'],
      ),
      notes: json['notes']?.toString(),
      evidenceLink: (json['evidenceLink'] ?? json['evidence_link'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (title != null) data['title'] = title;
    if (category != null) data['category'] = category!.toJson();
    if (achievementDate != null) {
      data['achievementDate'] = achievementDate!.toIso8601String().split(
        'T',
      )[0];
    }
    if (notes != null) data['notes'] = notes;
    if (evidenceLink != null) data['evidenceLink'] = evidenceLink;
    return data;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Response for listing achievements.
/// API: GET /achievements
@freezed
class AchievementsListResponse with _$AchievementsListResponse {
  const factory AchievementsListResponse({
    @Default([]) List<Achievement> achievements,
    @Default(0) int total,
  }) = _AchievementsListResponse;

  factory AchievementsListResponse.fromJson(Map<String, dynamic> json) {
    return AchievementsListResponse(
      achievements: _parseAchievements(json['achievements']) ?? [],
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }

  static List<Achievement>? _parseAchievements(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => Achievement.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
