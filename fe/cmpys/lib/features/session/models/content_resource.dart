class ContentResource {
  const ContentResource({
    required this.id,
    required this.kind,
    required this.canonicalKey,
    required this.title,
    required this.licenseStatus,
    required this.isSaved,
    required this.progressPercent,
    this.authorOrCreator,
    this.sourceUrl,
    this.thumbnailUrl,
    this.contentMarkdown,
    this.summaryJson,
    this.durationMinutes,
    this.metadataJson,
    this.savedAt,
    this.cursorJson,
    this.completedAt,
  });

  final String id;
  final String kind;
  final String canonicalKey;
  final String title;
  final String? authorOrCreator;
  final String? sourceUrl;
  final String? thumbnailUrl;
  final String licenseStatus;
  final String? contentMarkdown;
  final Map<String, dynamic>? summaryJson;
  final int? durationMinutes;
  final Map<String, dynamic>? metadataJson;
  final bool isSaved;
  final int progressPercent;
  final DateTime? savedAt;
  final Map<String, dynamic>? cursorJson;
  final DateTime? completedAt;

  factory ContentResource.fromJson(Map<String, dynamic> json) {
    return ContentResource(
      id: (json['id'] ?? '').toString(),
      kind: (json['kind'] ?? 'article').toString(),
      canonicalKey: (json['canonicalKey'] ?? json['canonical_key'] ?? '')
          .toString(),
      title: (json['title'] ?? '').toString(),
      authorOrCreator: (json['authorOrCreator'] ?? json['author_or_creator'])
          ?.toString(),
      sourceUrl: (json['sourceUrl'] ?? json['source_url'])?.toString(),
      thumbnailUrl: (json['thumbnailUrl'] ?? json['thumbnail_url'])?.toString(),
      licenseStatus: (json['licenseStatus'] ?? json['license_status'] ?? '')
          .toString(),
      contentMarkdown: (json['contentMarkdown'] ?? json['content_markdown'])
          ?.toString(),
      summaryJson: _mapOrNull(json['summaryJson'] ?? json['summary_json']),
      durationMinutes:
          (json['durationMinutes'] ?? json['duration_minutes'] as num?)
              ?.toInt(),
      metadataJson: _mapOrNull(json['metadataJson'] ?? json['metadata_json']),
      isSaved: json['isSaved'] == true || json['is_saved'] == true,
      progressPercent:
          (json['progressPercent'] ?? json['progress_percent'] as num?)
              ?.toInt() ??
          0,
      savedAt: _dateOrNull(json['savedAt'] ?? json['saved_at']),
      cursorJson: _mapOrNull(json['cursorJson'] ?? json['cursor_json']),
      completedAt: _dateOrNull(json['completedAt'] ?? json['completed_at']),
    );
  }

  bool get isBook => kind == 'public_domain_book' || kind == 'llm_book_summary';

  bool get isVideo => kind == 'video';

  bool get isCompleted => completedAt != null || progressPercent >= 100;

  bool get isUnavailable => metadataJson?['unavailable'] == true;

  bool get canReadInApp =>
      contentMarkdown != null && contentMarkdown!.isNotEmpty;

  String get kindLabel {
    switch (kind) {
      case 'public_domain_book':
      case 'llm_book_summary':
        return 'Book';
      case 'video':
        return 'Video';
      case 'in_app_lesson':
        return 'Lesson';
      case 'article':
        return 'Article';
      default:
        return 'Resource';
    }
  }

  String get metaLabel {
    final creator = authorOrCreator?.trim();
    final duration = durationMinutes != null ? '$durationMinutes min' : null;
    return [
      if (creator != null && creator.isNotEmpty) creator,
      if (duration != null) duration,
    ].join(' • ');
  }

  static Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static DateTime? _dateOrNull(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }
}

class ContentHighlight {
  const ContentHighlight({
    required this.id,
    required this.contentResourceId,
    required this.createdAt,
    required this.updatedAt,
    this.locatorJson,
    this.quoteText,
    this.noteText,
  });

  final String id;
  final String contentResourceId;
  final Map<String, dynamic>? locatorJson;
  final String? quoteText;
  final String? noteText;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayText {
    final note = noteText?.trim();
    if (note != null && note.isNotEmpty) return note;
    return quoteText?.trim() ?? '';
  }

  factory ContentHighlight.fromJson(Map<String, dynamic> json) {
    return ContentHighlight(
      id: (json['id'] ?? '').toString(),
      contentResourceId:
          (json['contentResourceId'] ?? json['content_resource_id'] ?? '')
              .toString(),
      locatorJson: ContentResource._mapOrNull(
        json['locatorJson'] ?? json['locator_json'],
      ),
      quoteText: (json['quoteText'] ?? json['quote_text'])?.toString(),
      noteText: (json['noteText'] ?? json['note_text'])?.toString(),
      createdAt: _dateOrEpoch(json['createdAt'] ?? json['created_at']),
      updatedAt: _dateOrEpoch(json['updatedAt'] ?? json['updated_at']),
    );
  }

  static DateTime _dateOrEpoch(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}
