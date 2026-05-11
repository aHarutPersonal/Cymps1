import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../models/idol_models.dart';
import '../models/timeline_models.dart';

/// Idols repository provider.
final idolsRepositoryProvider = Provider<IdolsRepository>((ref) {
  return IdolsRepository(dioClient: ref.watch(dioClientProvider));
});

/// Repository for idol operations.
class IdolsRepository {
  IdolsRepository({required DioClient dioClient}) : _dioClient = dioClient;

  final DioClient _dioClient;

  /// Get idol suggestions based on user interests.
  ///
  /// [interests] - List of user interests to base suggestions on.
  /// [limit] - Maximum number of suggestions to return (default: 20).
  /// [source] - Source filter: "local", "llm", or "auto" (default: "auto").
  /// Returns an [ImportResponse] with job ID for tracking.
  Future<ImportResponse> suggest(
    List<String> interests, {
    int limit = 20,
    String source = 'auto',
  }) async {
    final response = await _dioClient.get(
      '/idols/suggest',
      queryParameters: {
        'interests': interests.join(','),
        'limit': limit,
        'source': source,
      },
      receiveTimeout: const Duration(minutes: 2),
    );
    // ignore: avoid_print
    print('📋 Suggest response: ${response.data}');
    return ImportResponse.fromJson(response.data);
  }

  /// Search/discover idols by query string.
  ///
  /// [query] - Search query (e.g., "Elon Musk", "Steve Jobs").
  /// Returns a [DiscoverResponse] with matching idol candidates.
  Future<DiscoverResponse> discover(String query) async {
    final response = await _dioClient.get(
      '/idols/discover',
      queryParameters: {'q': query},
    );
    // ignore: avoid_print
    print('🔍 Discover response: ${response.data}');
    return DiscoverResponse.fromJson(response.data);
  }

  /// Import an idol from external provider.
  ///
  /// [provider] - Data provider (e.g., "wikidata", "llm").
  /// [externalId] - External ID from the provider (e.g., Wikidata QID "Q317521", LLM ID "llm:ray_dalio").
  /// [name] - Required for LLM imports.
  /// [description] - Optional description.
  /// [birthDate] - Birth date (YYYY-MM-DD format) for LLM imports.
  /// [wikipediaUrl] - Wikipedia URL.
  /// [occupations] - List of occupations for LLM imports.
  /// Returns an [ImportResponse] with idol ID and job ID for tracking.
  Future<ImportResponse> importIdol({
    required String provider,
    required String externalId,
    String? name,
    String? description,
    String? birthDate,
    String? wikipediaUrl,
    List<String>? occupations,
  }) async {
    // Create the map with camelCase keys as backend expects
    final Map<String, dynamic> data = {
      'provider': provider,
      'externalId': externalId,
    };

    // For LLM imports, additional metadata is required
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;
    if (birthDate != null) data['birthDate'] = birthDate;
    if (wikipediaUrl != null) data['wikipediaUrl'] = wikipediaUrl;
    if (occupations != null && occupations.isNotEmpty) {
      data['occupations'] = occupations;
    }

    // ignore: avoid_print
    print(
      '🎭 Import request: provider=$provider, externalId=$externalId, name=$name',
    );
    // ignore: avoid_print
    print('🎭 Import JSON: $data');

    try {
      final response = await _dioClient.post('/idols/import', data: data);

      // ignore: avoid_print
      print('🎭 Import response: ${response.data}');

      final responseData = response.data as Map<String, dynamic>;

      // Check for error response with detail
      if (responseData.containsKey('detail')) {
        throw Exception(responseData['detail'].toString());
      }

      return ImportResponse.fromJson(responseData);
    } catch (e) {
      // ignore: avoid_print
      print('🎭 Import error: $e');
      rethrow;
    }
  }

  /// Get idol profile by ID.
  ///
  /// [idolId] - The idol's unique identifier.
  /// Returns the full [IdolProfile].
  Future<IdolProfile> getIdolProfile(String idolId) async {
    final response = await _dioClient.get('/idols/$idolId');
    return IdolProfile.fromJson(response.data);
  }

  /// Get idol timeline (milestones).
  ///
  /// [idolId] - The idol's unique identifier.
  /// [age] - Optional age limit to filter milestones (e.g., show only up to age 30).
  /// [mode] - Timeline mode ('full', 'summary', 'at_age').
  /// Returns a [TimelineResponse] with timeline items.
  Future<TimelineResponse> getIdolTimeline(
    String idolId, {
    int? age,
    String? mode,
  }) async {
    final queryParams = <String, dynamic>{};
    if (age != null) queryParams['age'] = age;
    if (mode != null) queryParams['mode'] = mode;

    final response = await _dioClient.get(
      '/idols/$idolId/timeline',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    // ignore: avoid_print
    print('📅 Timeline response: ${response.data}');

    final parsed = TimelineResponse.fromJson(response.data);
    // ignore: avoid_print
    print(
      '📅 Parsed timeline: events=${parsed.events.length}, timeline=${parsed.timeline.length}, milestones=${parsed.milestones.length}, items=${parsed.items.length}',
    );

    return parsed;
  }

  /// Get user's selected/imported idols.
  Future<List<IdolProfile>> getMyIdols() async {
    final response = await _dioClient.get('/idols/my');
    final list = response.data as List<dynamic>;
    return list
        .map((json) => IdolProfile.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Set an idol as the user's primary/current idol.
  Future<void> setCurrentIdol(String idolId) async {
    await _dioClient.post('/idols/$idolId/select');
  }

  /// Generate AI avatar for an idol.
  ///
  /// [idolId] - Idol ID.
  /// [age] - Optional age to depict (defaults to current age or 30).
  /// Returns the image URL.
  Future<String> generateAvatar(String idolId, {int? age}) async {
    final queryParams = <String, dynamic>{};
    if (age != null) queryParams['age'] = age;

    final response = await _dioClient.post(
      '/idols/$idolId/generate-image',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
      options: Options(
        receiveTimeout: const Duration(minutes: 2), // DALL-E can be slow
      ),
    );

    // ignore: avoid_print
    print('🎨 Generate avatar response: ${response.data}');

    final data = response.data as Map<String, dynamic>;
    return (data['imageUrl'] ?? data['image_url']).toString();
  }

  /// Remove an idol from user's list.
  Future<void> removeIdol(String idolId) async {
    await _dioClient.delete('/idols/$idolId');
  }
}
