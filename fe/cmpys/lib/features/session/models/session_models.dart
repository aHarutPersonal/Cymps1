import 'package:freezed_annotation/freezed_annotation.dart';

part 'session_models.freezed.dart';

/// Phase of the 5-state agentic workflow.
enum SessionPhase {
  @JsonValue('intake')
  intake,
  @JsonValue('idol_selection')
  idolSelection,
  @JsonValue('interview')
  interview,
  @JsonValue('comparison')
  comparison,
  @JsonValue('blueprint')
  blueprint,
  @JsonValue('guided_learning')
  guidedLearning,
  @JsonValue('completed')
  completed;

  /// Parse from backend snake_case string.
  static SessionPhase fromString(String value) {
    switch (value) {
      case 'intake':
        return SessionPhase.intake;
      case 'idol_selection':
        return SessionPhase.idolSelection;
      case 'interview':
        return SessionPhase.interview;
      case 'comparison':
        return SessionPhase.comparison;
      case 'blueprint':
        return SessionPhase.blueprint;
      case 'guided_learning':
        return SessionPhase.guidedLearning;
      case 'completed':
        return SessionPhase.completed;
      default:
        return SessionPhase.intake;
    }
  }

  /// Serialize to backend snake_case string.
  String toJson() {
    switch (this) {
      case SessionPhase.intake:
        return 'intake';
      case SessionPhase.idolSelection:
        return 'idol_selection';
      case SessionPhase.interview:
        return 'interview';
      case SessionPhase.comparison:
        return 'comparison';
      case SessionPhase.blueprint:
        return 'blueprint';
      case SessionPhase.guidedLearning:
        return 'guided_learning';
      case SessionPhase.completed:
        return 'completed';
    }
  }
}

/// Idol info embedded in session response.
@freezed
class SelectedIdolInfo with _$SelectedIdolInfo {
  const SelectedIdolInfo._();

  const factory SelectedIdolInfo({
    required String id,
    required String name,
    String? era,
  }) = _SelectedIdolInfo;

  factory SelectedIdolInfo.fromJson(Map<String, dynamic> json) {
    return SelectedIdolInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      era: json['era']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (era != null) 'era': era,
  };
}

/// Full session state from GET /sessions/{id}.
@freezed
class Session with _$Session {
  const Session._();

  const factory Session({
    required String id,
    required SessionPhase phase,
    required int userAge,
    required String userFinancialStatus,
    required List<String> userInterests,
    SelectedIdolInfo? selectedIdol,
    @Default(0) int interviewTurnCount,
    String? comparisonOutput,
    String? blueprintOutput,
    Map<String, dynamic>? comparisonScores,
    String? interviewThreadId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _Session;

  factory Session.fromJson(Map<String, dynamic> json) {
    final rawComparisonScores =
        json['comparisonScores'] ?? json['comparison_scores'];
    return Session(
      id: json['id']?.toString() ?? '',
      phase: SessionPhase.fromString(json['phase']?.toString() ?? 'intake'),
      userAge: _parseInt(json['user_age']) ?? 0,
      userFinancialStatus: (json['user_financial_status'] ?? '').toString(),
      userInterests: _parseStringList(json['user_interests']),
      selectedIdol: json['selected_idol'] != null
          ? SelectedIdolInfo.fromJson(
              json['selected_idol'] as Map<String, dynamic>,
            )
          : null,
      interviewTurnCount: _parseInt(json['interview_turn_count']) ?? 0,
      comparisonOutput: json['comparison_output']?.toString(),
      blueprintOutput: json['blueprint_output']?.toString(),
      comparisonScores: rawComparisonScores is Map
          ? rawComparisonScores.cast<String, dynamic>()
          : null,
      interviewThreadId: json['interview_thread_id']?.toString(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'phase': phase.toJson(),
    'user_age': userAge,
    'user_financial_status': userFinancialStatus,
    'user_interests': userInterests,
    if (selectedIdol != null) 'selected_idol': selectedIdol!.toJson(),
    'interview_turn_count': interviewTurnCount,
    if (comparisonOutput != null) 'comparison_output': comparisonOutput,
    if (blueprintOutput != null) 'blueprint_output': blueprintOutput,
    if (comparisonScores != null) 'comparisonScores': comparisonScores,
    if (interviewThreadId != null) 'interview_thread_id': interviewThreadId,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
  };

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value.map((e) => e.toString()).toList();
  }
}

/// A single idol suggestion for the session flow.
@freezed
class IdolSuggestion with _$IdolSuggestion {
  const IdolSuggestion._();

  const factory IdolSuggestion({
    required String name,
    required String era,
    required String relevanceSummary,
    String? wikidataId,
    String? imageUrl,
    @Default([]) List<String> domains,
    @Default(0.8) double confidence,
  }) = _IdolSuggestion;

  factory IdolSuggestion.fromJson(Map<String, dynamic> json) {
    return IdolSuggestion(
      name: json['name']?.toString() ?? '',
      era: json['era']?.toString() ?? '',
      relevanceSummary:
          (json['relevance_summary'] ?? json['relevanceSummary'] ?? '')
              .toString(),
      wikidataId: (json['wikidata_id'] ?? json['wikidataId'])?.toString(),
      imageUrl: (json['image_url'] ?? json['imageUrl'])?.toString(),
      domains: Session._parseStringList(json['domains']),
      confidence: _parseDouble(json['confidence']) ?? 0.8,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'era': era,
    'relevance_summary': relevanceSummary,
    if (wikidataId != null) 'wikidata_id': wikidataId,
    if (imageUrl != null) 'image_url': imageUrl,
    'domains': domains,
    'confidence': confidence,
  };

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// Request to create a new session.
@freezed
class SessionCreateRequest with _$SessionCreateRequest {
  const SessionCreateRequest._();

  const factory SessionCreateRequest({
    required int age,
    required String financialStatus,
    required List<String> interests,
    String? goal,
  }) = _SessionCreateRequest;

  Map<String, dynamic> toJson() => {
    'age': age,
    'financial_status': financialStatus,
    'interests': interests,
    if (goal != null) 'goal': goal,
  };
}

/// Request to choose the session mentor.
@freezed
class SelectIdolRequest with _$SelectIdolRequest {
  const SelectIdolRequest._();

  const factory SelectIdolRequest({
    required String idolName,
    String? wikidataId,
  }) = _SelectIdolRequest;

  Map<String, dynamic> toJson() => {
    'idol_name': idolName,
    if (wikidataId != null) 'wikidata_id': wikidataId,
  };
}

/// A fetched learning resource (article or video).
@freezed
class LearningMaterial with _$LearningMaterial {
  const LearningMaterial._();

  const factory LearningMaterial({
    required String title,
    required String url,
    required String type,
    required String summary,
    String? contentResourceId,
    String? canonicalKey,
    String? licenseStatus,
    String? thumbnailUrl,
    int? durationMinutes,
  }) = _LearningMaterial;

  factory LearningMaterial.fromJson(Map<String, dynamic> json) {
    return LearningMaterial(
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      type: json['type']?.toString() ?? 'article',
      summary: json['summary']?.toString() ?? '',
      contentResourceId:
          (json['content_resource_id'] ?? json['contentResourceId'])
              ?.toString(),
      canonicalKey: (json['canonical_key'] ?? json['canonicalKey'])?.toString(),
      licenseStatus: (json['license_status'] ?? json['licenseStatus'])
          ?.toString(),
      thumbnailUrl: (json['thumbnail_url'] ?? json['thumbnailUrl'])?.toString(),
      durationMinutes:
          (json['duration_minutes'] ?? json['durationMinutes'] as num?)
              ?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'type': type,
    'summary': summary,
    if (contentResourceId != null) 'content_resource_id': contentResourceId,
    if (canonicalKey != null) 'canonical_key': canonicalKey,
    if (licenseStatus != null) 'license_status': licenseStatus,
    if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
    if (durationMinutes != null) 'duration_minutes': durationMinutes,
  };
}

/// A bite-sized daily insight.
@freezed
class DailyInsight with _$DailyInsight {
  const DailyInsight._();

  const factory DailyInsight({
    required String title,
    required String content,
    required String category,
  }) = _DailyInsight;

  factory DailyInsight.fromJson(Map<String, dynamic> json) {
    return DailyInsight(
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Learning',
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    'category': category,
  };
}

/// Response containing the daily feed of insights.
@freezed
class DailyFeedResponse with _$DailyFeedResponse {
  const DailyFeedResponse._();

  const factory DailyFeedResponse({@Default([]) List<DailyInsight> insights}) =
      _DailyFeedResponse;

  factory DailyFeedResponse.fromJson(Map<String, dynamic> json) {
    return DailyFeedResponse(
      insights: (json['insights'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((e) => DailyInsight.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'insights': insights.map((e) => e.toJson()).toList(),
  };
}
