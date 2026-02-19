import 'package:freezed_annotation/freezed_annotation.dart';

part 'idol_models.freezed.dart';

/// A candidate idol from discovery/suggestion.
/// Handles both local suggestions (from DB) and web suggestions (from LLM/Wikidata).
@freezed
class IdolCandidate with _$IdolCandidate {
  const IdolCandidate._();
  
  const factory IdolCandidate({
    /// Source type: "local" (from DB) or "web" (from LLM/Wikidata)
    @Default('web') String source,
    /// For local suggestions: the idol's UUID in database
    String? id,
    /// For web suggestions: provider name (e.g., "wikidata", "llm")
    @Default('') String provider,
    /// For web suggestions: external ID from provider (e.g., "Q317521", "llm:ray_dalio")
    @Default('') String externalId,
    @Default('Unknown') String name,
    String? description,
    DateTime? birthDate,
    String? wikipediaUrl,
    @Default([]) List<String> occupations,
    /// For local suggestions: relevance score (0-1)
    double? relevanceScore,
    /// For web suggestions: confidence score (0-1)
    double? confidence,
    /// Domain/category (for local suggestions)
    String? domain,
    /// Aliases list (for local suggestions)
    @Default([]) List<IdolAlias> aliases,
    /// Tags list (for local suggestions)
    @Default([]) List<IdolTag> tags,
    String? avatarThumbUrl,
  }) = _IdolCandidate;

  /// Check if this is a local suggestion (from database)
  bool get isLocal => source == 'local';
  
  /// Check if this is a web suggestion (from external provider)
  bool get isWeb => source == 'web';

  /// Custom fromJson to handle both camelCase and snake_case
  factory IdolCandidate.fromJson(Map<String, dynamic> json) {
    return IdolCandidate(
      source: _toString(json['source']) ?? 'web',
      id: _toString(json['id']),
      provider: _toString(json['provider']) ?? '',
      externalId: _toString(json['externalId'] ?? json['external_id']) ?? '',
      name: _toString(json['name']) ?? 'Unknown',
      description: _toString(json['description']),
      birthDate: _parseDate(json['birthDate'] ?? json['birth_date']),
      wikipediaUrl: _toString(json['wikipediaUrl'] ?? json['wikipedia_url']),
      occupations: (json['occupations'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      relevanceScore: (json['relevanceScore'] ?? json['relevance_score'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      domain: _toString(json['domain']),
      aliases: (json['aliases'] as List<dynamic>?)
              ?.map((e) => IdolAlias.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => IdolTag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      avatarThumbUrl:
          _toString(json['avatarThumbUrl'] ?? json['avatar_thumb_url']),
    );
  }
  
  /// Custom toJson for API requests
  Map<String, dynamic> toJson() => {
    'source': source,
    if (id != null) 'id': id,
    'provider': provider,
    'externalId': externalId,
    'name': name,
    if (description != null) 'description': description,
    if (birthDate != null) 'birthDate': birthDate!.toIso8601String().split('T')[0],
    if (wikipediaUrl != null) 'wikipediaUrl': wikipediaUrl,
    'occupations': occupations,
    if (relevanceScore != null) 'relevanceScore': relevanceScore,
    if (confidence != null) 'confidence': confidence,
    if (domain != null) 'domain': domain,
  };
  
  static String? _toString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }
  
  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Idol alias (alternative name).
@freezed
class IdolAlias with _$IdolAlias {
  const factory IdolAlias({
    String? id,
    String? aliasText,
  }) = _IdolAlias;

  factory IdolAlias.fromJson(Map<String, dynamic> json) {
    return IdolAlias(
      id: json['id']?.toString(),
      aliasText: (json['aliasText'] ?? json['alias_text'])?.toString(),
    );
  }
}

/// Idol tag (category/theme).
@freezed
class IdolTag with _$IdolTag {
  const factory IdolTag({
    String? id,
    String? name,
    String? type,
  }) = _IdolTag;

  factory IdolTag.fromJson(Map<String, dynamic> json) {
    return IdolTag(
      id: json['id']?.toString(),
      name: json['name']?.toString(),
      type: json['type']?.toString(),
    );
  }
}

/// Response from discover endpoint (search).
@freezed
class DiscoverResponse with _$DiscoverResponse {
  const factory DiscoverResponse({
    required String query,
    required List<IdolCandidate> candidates,
  }) = _DiscoverResponse;

  factory DiscoverResponse.fromJson(Map<String, dynamic> json) {
    return DiscoverResponse(
      query: (json['query'] ?? '').toString(),
      candidates: (json['candidates'] as List<dynamic>?)
              ?.map((e) => IdolCandidate.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Source mix statistics from suggest endpoint.
@freezed
class SourceMix with _$SourceMix {
  const factory SourceMix({
    @Default(0) int local,
    @Default(0) int web,
    @Default(0) int total,
  }) = _SourceMix;

  factory SourceMix.fromJson(Map<String, dynamic> json) {
    return SourceMix(
      local: (json['local'] as num?)?.toInt() ?? 0,
      web: (json['web'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Response from suggest endpoint.
@freezed
class SuggestResponse with _$SuggestResponse {
  const SuggestResponse._();
  
  const factory SuggestResponse({
    @Default([]) List<String> interests,
    SourceMix? sourceMix,
    @Default([]) List<IdolCandidate> candidates,
  }) = _SuggestResponse;

  /// Custom fromJson to handle both 'suggestions' and 'candidates' field names
  factory SuggestResponse.fromJson(Map<String, dynamic> json) {
    final candidatesList = json['suggestions'] ?? json['candidates'];
    final sourceMixData = json['sourceMix'] ?? json['source_mix'];
    
    return SuggestResponse(
      interests: (json['interests'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      sourceMix: sourceMixData is Map<String, dynamic> 
          ? SourceMix.fromJson(sourceMixData)
          : null,
      candidates: (candidatesList as List<dynamic>?)
              ?.map((e) => IdolCandidate.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Request to import an idol.
/// For LLM imports, additional metadata (name, description, birthDate, occupations) is required.
@freezed
class ImportRequest with _$ImportRequest {
  const ImportRequest._();
  
  const factory ImportRequest({
    required String provider,
    required String externalId,
    /// Required for LLM imports
    String? name,
    String? description,
    /// Date string in YYYY-MM-DD format
    String? birthDate,
    String? wikipediaUrl,
    /// List of occupations/roles
    List<String>? occupations,
  }) = _ImportRequest;

  factory ImportRequest.fromJson(Map<String, dynamic> json) {
    return ImportRequest(
      provider: (json['provider'] ?? '').toString(),
      externalId: (json['externalId'] ?? json['external_id'] ?? '').toString(),
      name: json['name']?.toString(),
      description: json['description']?.toString(),
      birthDate: (json['birthDate'] ?? json['birth_date'])?.toString(),
      wikipediaUrl: (json['wikipediaUrl'] ?? json['wikipedia_url'])?.toString(),
      occupations: (json['occupations'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }
  
  /// Custom toJson to send camelCase (as API expects)
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'provider': provider,
      'externalId': externalId,
    };
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;
    if (birthDate != null) data['birthDate'] = birthDate;
    if (wikipediaUrl != null) data['wikipediaUrl'] = wikipediaUrl;
    if (occupations != null && occupations!.isNotEmpty) data['occupations'] = occupations;
    return data;
  }
}

/// Response from import endpoint.
@freezed
class ImportResponse with _$ImportResponse {
  const factory ImportResponse({
    String? idolId,
    String? jobId,
    String? status,
    String? detail,
  }) = _ImportResponse;

  factory ImportResponse.fromJson(Map<String, dynamic> json) {
    return ImportResponse(
      idolId: (json['idolId'] ?? json['idol_id'])?.toString(),
      jobId: (json['jobId'] ?? json['job_id'])?.toString(),
      status: json['status']?.toString(),
      detail: json['detail']?.toString(),
    );
  }
}

/// Full idol profile.
@freezed
class IdolProfile with _$IdolProfile {
  const factory IdolProfile({
    required String id,
    required String name,
    String? description,
    DateTime? birthDate,
    DateTime? deathDate,
    String? wikipediaUrl,
    @Default([]) List<String> occupations,
    String? avatarUrl,
    String? avatarThumbUrl,
    List<String>? knownFor,
    String? nationality,
    String? birthPlace,
    String? summary,
    String? timelineStatus,
    double? timelineCompleteness,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _IdolProfile;

  factory IdolProfile.fromJson(Map<String, dynamic> json) {
    return IdolProfile(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      birthDate: _parseDate(json['birthDate'] ?? json['birth_date']),
      deathDate: _parseDate(json['deathDate'] ?? json['death_date']),
      wikipediaUrl: (json['wikipediaUrl'] ?? json['wikipedia_url'])?.toString(),
      occupations: (json['occupations'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      avatarUrl: (json['avatarUrl'] ?? json['avatar_url'] ?? json['imageUrl'] ?? json['image_url'])?.toString(),
      avatarThumbUrl:
          (json['avatarThumbUrl'] ?? json['avatar_thumb_url'])?.toString(),
      knownFor: (json['knownFor'] ?? json['known_for'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      nationality: json['nationality']?.toString(),
      birthPlace: (json['birthPlace'] ?? json['birth_place'])?.toString(),
      summary: json['summary']?.toString(),
      timelineStatus: (json['timelineStatus'] ?? json['timeline_status'])?.toString(),
      timelineCompleteness:
          (json['timelineCompleteness'] ?? json['timeline_completeness'] as num?)
              ?.toDouble(),
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
}
