import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../models/idea_card_models.dart';

/// Provider for the idea card repository.
final ideaCardRepositoryProvider = Provider<IdeaCardRepository>((ref) {
  return IdeaCardRepository(dioClient: ref.watch(dioClientProvider));
});

/// Repository for IdeaCard API interactions.
class IdeaCardRepository {
  IdeaCardRepository({required DioClient dioClient}) : _dioClient = dioClient;
  final DioClient _dioClient;

  /// Get syllabus (category breakdown) for an idol.
  Future<SyllabusResponse> getSyllabus(String idolId) async {
    final response = await _dioClient.get('/idols/$idolId/syllabus');
    return SyllabusResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get paginated daily ideas for an idol.
  Future<IdeaCardListResponse> getDailyIdeas({
    required String idolId,
    int page = 1,
    int pageSize = 10,
    String? category,
    bool refresh = false,
  }) async {
    final params = <String, dynamic>{'page': page, 'page_size': pageSize};
    if (category != null) params['category'] = category;
    if (refresh) params['refresh'] = true;

    final response = await _dioClient.get(
      '/idols/$idolId/daily-ideas',
      queryParameters: params,
    );
    return IdeaCardListResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Toggle stash on an IdeaCard. Returns stash action result.
  Future<StashActionResponse> toggleStash(String ideaCardId) async {
    final response = await _dioClient.post('/stash/$ideaCardId');
    return StashActionResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get user's stashed IdeaCards.
  Future<IdeaCardListResponse> getStash({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dioClient.get(
      '/stash',
      queryParameters: {'page': page, 'page_size': pageSize},
    );
    return IdeaCardListResponse.fromJson(response.data as Map<String, dynamic>);
  }
}
