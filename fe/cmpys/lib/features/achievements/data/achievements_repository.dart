import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../models/achievement_models.dart';

/// Achievements repository provider.
final achievementsRepositoryProvider = Provider<AchievementsRepository>((ref) {
  return AchievementsRepository(dioClient: ref.watch(dioClientProvider));
});

/// Repository for achievements operations.
/// API Reference: /achievements endpoints
class AchievementsRepository {
  AchievementsRepository({required DioClient dioClient}) : _dioClient = dioClient;

  final DioClient _dioClient;

  /// Create a new user achievement.
  ///
  /// [title] - Achievement title (required).
  /// [category] - Category: career, learning, finance, impact, mindset, other.
  /// [achievementDate] - When the achievement occurred.
  /// [notes] - Optional notes about the achievement.
  /// [evidenceLink] - Optional link to evidence.
  ///
  /// API: POST /achievements
  Future<Achievement> createAchievement({
    required String title,
    required AchievementCategory category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
  }) async {
    final request = CreateAchievementRequest(
      title: title,
      category: category,
      achievementDate: achievementDate,
      notes: notes,
      evidenceLink: evidenceLink,
    );

    final response = await _dioClient.post(
      '/achievements',
      data: request.toJson(),
    );

    return Achievement.fromJson(response.data);
  }

  /// List user achievements with optional filters.
  ///
  /// [category] - Filter by category.
  /// [query] - Search in title/notes.
  /// [fromDate] - From date filter.
  /// [toDate] - To date filter.
  /// [limit] - Max results (1-200, default: 50).
  /// [offset] - Pagination offset.
  ///
  /// API: GET /achievements
  Future<AchievementsListResponse> listAchievements({
    AchievementCategory? category,
    String? query,
    DateTime? fromDate,
    DateTime? toDate,
    int? limit,
    int? offset,
  }) async {
    final queryParams = <String, dynamic>{};
    if (category != null) queryParams['category'] = category.toJson();
    if (query != null && query.isNotEmpty) queryParams['q'] = query;
    if (fromDate != null) queryParams['fromDate'] = fromDate.toIso8601String().split('T')[0];
    if (toDate != null) queryParams['toDate'] = toDate.toIso8601String().split('T')[0];
    if (limit != null) queryParams['limit'] = limit;
    if (offset != null) queryParams['offset'] = offset;

    final response = await _dioClient.get(
      '/achievements',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    // Handle both list and object responses
    if (response.data is List) {
      return AchievementsListResponse(
        achievements: (response.data as List)
            .map((json) => Achievement.fromJson(json as Map<String, dynamic>))
            .toList(),
      );
    }

    return AchievementsListResponse.fromJson(response.data);
  }

  /// Get a specific achievement.
  ///
  /// [achievementId] - The achievement's unique identifier.
  ///
  /// API: GET /achievements/{achievement_id}
  Future<Achievement> getAchievement(String achievementId) async {
    final response = await _dioClient.get('/achievements/$achievementId');
    return Achievement.fromJson(response.data);
  }

  /// Update an existing achievement.
  ///
  /// [achievementId] - The achievement's unique identifier.
  /// All other parameters are optional - only provided fields will be updated.
  ///
  /// API: PATCH /achievements/{achievement_id}
  Future<Achievement> updateAchievement(
    String achievementId, {
    String? title,
    AchievementCategory? category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
  }) async {
    final request = UpdateAchievementRequest(
      title: title,
      category: category,
      achievementDate: achievementDate,
      notes: notes,
      evidenceLink: evidenceLink,
    );

    final response = await _dioClient.patch(
      '/achievements/$achievementId',
      data: request.toJson(),
    );

    return Achievement.fromJson(response.data);
  }

  /// Delete an achievement.
  ///
  /// [achievementId] - The achievement's unique identifier.
  ///
  /// API: DELETE /achievements/{achievement_id}
  Future<void> deleteAchievement(String achievementId) async {
    await _dioClient.delete('/achievements/$achievementId');
  }

  /// Get all achievements (convenience method).
  Future<List<Achievement>> getAllAchievements() async {
    final response = await listAchievements(limit: 200);
    return response.achievements;
  }

  /// Get achievements by category.
  Future<List<Achievement>> getAchievementsByCategory(AchievementCategory category) async {
    final response = await listAchievements(category: category);
    return response.achievements;
  }

  /// Search achievements.
  Future<List<Achievement>> searchAchievements(String query) async {
    final response = await listAchievements(query: query);
    return response.achievements;
  }
}
