import 'package:freezed_annotation/freezed_annotation.dart';

part 'timeline_models.freezed.dart';

/// Evidence for a timeline item.
@freezed
class Evidence with _$Evidence {
  const factory Evidence({
    String? sourceId,
    int? chunkIndex,
    String? sourceUrl,
    String? snippet,
    double? confidence,
  }) = _Evidence;

  factory Evidence.fromJson(Map<String, dynamic> json) {
    return Evidence(
      sourceId: (json['sourceId'] ?? json['source_id'])?.toString(),
      chunkIndex: (json['chunkIndex'] ?? json['chunk_index'] as num?)?.toInt(),
      sourceUrl: (json['sourceUrl'] ?? json['source_url'])?.toString(),
      snippet: json['snippet']?.toString(),
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }
}

/// A timeline item (milestone) for an idol.
@freezed
class TimelineItem with _$TimelineItem {
  const TimelineItem._();

  const factory TimelineItem({
    String? id,
    /// Title of the milestone (backend may use 'canonical_title' or 'title')
    String? canonicalTitle,
    String? title,
    String? description,
    int? ageAtEvent,
    String? category,
    double? importanceScore,
    double? confidence,
    @Default([]) List<Evidence> evidence,
    String? dateText,
    DateTime? date,
  }) = _TimelineItem;

  factory TimelineItem.fromJson(Map<String, dynamic> json) {
    return TimelineItem(
      id: json['id']?.toString(),
      canonicalTitle: (json['canonicalTitle'] ?? json['canonical_title'])?.toString(),
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      ageAtEvent: (json['ageAtEvent'] ?? json['age_at_event'] as num?)?.toInt(),
      category: json['category']?.toString(),
      importanceScore: (json['importanceScore'] ?? json['importance_score'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      evidence: _parseEvidence(json['evidence']) ?? [],
      dateText: (json['dateText'] ?? json['date_text'])?.toString(),
      date: _parseDate(json['date']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static List<Evidence>? _parseEvidence(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => Evidence.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get the display title (prefer canonicalTitle over title).
  String get displayTitle => canonicalTitle ?? title ?? 'Untitled';
}

/// Response from timeline endpoint.
@freezed
class TimelineResponse with _$TimelineResponse {
  const TimelineResponse._();

  const factory TimelineResponse({
    /// Backend returns 'events', but we also check 'timeline' and 'milestones' for compatibility
    @Default([]) List<TimelineItem> events,
    @Default([]) List<TimelineItem> timeline,
    @Default([]) List<TimelineItem> milestones,
    double? completenessEstimate,
    int? totalCount,
    int? totalEvents,
    String? idolId,
    String? idolName,
    String? mode,
    int? age,
    String? idol,
  }) = _TimelineResponse;

  factory TimelineResponse.fromJson(Map<String, dynamic> json) {
    return TimelineResponse(
      events: _parseItems(json['events']) ?? [],
      timeline: _parseItems(json['timeline']) ?? [],
      milestones: _parseItems(json['milestones']) ?? [],
      completenessEstimate: (json['completenessEstimate'] ?? json['completeness_estimate'] as num?)?.toDouble(),
      totalCount: (json['totalCount'] ?? json['total_count'] as num?)?.toInt(),
      totalEvents: (json['totalEvents'] ?? json['total_events'] as num?)?.toInt(),
      idolId: (json['idolId'] ?? json['idol_id'])?.toString(),
      idolName: (json['idolName'] ?? json['idol_name'])?.toString(),
      mode: json['mode']?.toString(),
      age: (json['age'] as num?)?.toInt(),
      idol: json['idol']?.toString(),
    );
  }

  static List<TimelineItem>? _parseItems(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => TimelineItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get timeline items from whichever field is populated.
  /// Priority: events (backend) > timeline > milestones
  List<TimelineItem> get items {
    if (events.isNotEmpty) return events;
    if (timeline.isNotEmpty) return timeline;
    return milestones;
  }
}
