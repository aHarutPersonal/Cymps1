import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../models/feed_models.dart';

/// Provider for the feed repository.
final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  return FeedRepository(dioClient: ref.watch(dioClientProvider));
});

/// Repository for the discover feed — includes social actions.
class FeedRepository {
  FeedRepository({required DioClient dioClient}) : _dioClient = dioClient;
  final DioClient _dioClient;

  /// Get the user's discover feed with pagination.
  Future<FeedResponse> getFeed({
    int page = 1,
    int pageSize = 10,
    int? seed,
  }) async {
    final params = <String, dynamic>{'page': page, 'page_size': pageSize};
    if (seed != null) params['seed'] = seed;

    final response = await _dioClient.get('/feed', queryParameters: params);
    return FeedResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Toggle like on a post. Returns {is_liked, like_count}.
  Future<Map<String, dynamic>> toggleLike(String postId) async {
    final response = await _dioClient.post('/feed/$postId/like');
    return response.data as Map<String, dynamic>;
  }

  /// Get comments for a post.
  Future<List<FeedComment>> getComments(String postId) async {
    final response = await _dioClient.get('/feed/$postId/comments');
    final list = response.data as List;
    return list
        .map((e) => FeedComment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Add a comment to a post.
  Future<FeedComment> addComment(String postId, String text) async {
    final response = await _dioClient.post(
      '/feed/$postId/comments',
      data: {'text': text},
    );
    return FeedComment.fromJson(response.data as Map<String, dynamic>);
  }
}
