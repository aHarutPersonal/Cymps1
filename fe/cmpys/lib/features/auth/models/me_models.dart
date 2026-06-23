import 'package:freezed_annotation/freezed_annotation.dart';

part 'me_models.freezed.dart';

/// Current user profile.
/// Backend returns nested structure: { id, email, profile: { fullName, birthDate, focusAreas, timezone } }
@freezed
class Me with _$Me {
  const Me._();
  const factory Me({
    required String id,
    required String email,
    String? fullName,
    DateTime? birthDate,

    /// Backend uses 'focusAreas', we map it to 'interests' internally
    @Default([]) List<String> interests,
    String? timezone,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _Me;

  factory Me.fromJson(Map<String, dynamic> json) {
    // Backend returns nested profile structure
    final profile = json['profile'] as Map<String, dynamic>?;

    return Me(
      id: (json['id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      // Try profile nested fields first, then flat fields for backwards compatibility
      fullName: _toString(
        profile?['fullName'] ??
            profile?['full_name'] ??
            json['fullName'] ??
            json['full_name'],
      ),
      birthDate: _parseDate(
        profile?['birthDate'] ??
            profile?['birth_date'] ??
            json['birthDate'] ??
            json['birth_date'],
      ),
      // Backend uses 'focusAreas', we also support 'interests' for backwards compatibility
      interests:
          _parseStringList(
            profile?['focusAreas'] ??
                profile?['focus_areas'] ??
                json['focusAreas'] ??
                json['focus_areas'] ??
                json['interests'],
          ) ??
          [],
      timezone: _toString(profile?['timezone'] ?? json['timezone']),
      avatarUrl: _toString(
        profile?['avatarUrl'] ??
            profile?['avatar_url'] ??
            json['avatarUrl'] ??
            json['avatar_url'],
      ),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
    );
  }

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

  static List<String>? _parseStringList(dynamic value) {
    if (value == null) return null;
    if (value is List) return value.map((e) => e.toString()).toList();
    return null;
  }
}

/// Request to update user profile.
/// Backend expects: { fullName, birthDate, focusAreas, timezone } (camelCase)
@freezed
class UpdateMeRequest with _$UpdateMeRequest {
  const UpdateMeRequest._();
  const factory UpdateMeRequest({
    String? fullName,
    DateTime? birthDate,

    /// Internally called 'interests', sent to backend as 'focusAreas'
    List<String>? interests,
    String? timezone,
  }) = _UpdateMeRequest;

  factory UpdateMeRequest.fromJson(Map<String, dynamic> json) {
    return UpdateMeRequest(
      fullName: (json['fullName'] ?? json['full_name'])?.toString(),
      birthDate: _parseDate(json['birthDate'] ?? json['birth_date']),
      interests:
          (json['focusAreas'] ??
                  json['focus_areas'] ??
                  json['interests'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList(),
      timezone: json['timezone']?.toString(),
    );
  }

  /// toJson sends camelCase keys and uses 'focusAreas' as per backend spec
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (fullName != null) data['fullName'] = fullName;
    if (birthDate != null) {
      data['birthDate'] = birthDate!.toIso8601String().split(
        'T',
      )[0]; // YYYY-MM-DD
    }
    if (interests != null) {
      data['focusAreas'] = interests; // Map to focusAreas for backend
    }
    if (timezone != null) data['timezone'] = timezone;
    return data;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
