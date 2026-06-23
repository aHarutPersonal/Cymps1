// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'feed_models.freezed.dart';
part 'feed_models.g.dart';

/// A single item in the discover feed.
@freezed
class FeedItem with _$FeedItem {
  const factory FeedItem({
    required String id,
    required String type, // "quote" | "video"
    required String title,
    String? content,
    String? category,
    String? url,
    String? source,
    String? reason,
    @JsonKey(name: 'like_count') @Default(0) int likeCount,
    @JsonKey(name: 'comment_count') @Default(0) int commentCount,
    @JsonKey(name: 'is_liked') @Default(false) bool isLiked,
  }) = _FeedItem;

  factory FeedItem.fromJson(Map<String, dynamic> json) =>
      _$FeedItemFromJson(json);
}

/// Response from the feed endpoint with pagination.
@freezed
class FeedResponse with _$FeedResponse {
  const factory FeedResponse({
    required List<FeedItem> items,
    required int total,
    required int page,
    @JsonKey(name: 'page_size') required int pageSize,
    @JsonKey(name: 'has_more') required bool hasMore,
  }) = _FeedResponse;

  factory FeedResponse.fromJson(Map<String, dynamic> json) =>
      _$FeedResponseFromJson(json);
}

/// A comment on a feed post.
@freezed
class FeedComment with _$FeedComment {
  const factory FeedComment({
    required String id,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'user_name') String? userName,
    required String text,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _FeedComment;

  factory FeedComment.fromJson(Map<String, dynamic> json) =>
      _$FeedCommentFromJson(json);
}
