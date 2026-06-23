// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'idea_card_models.freezed.dart';
part 'idea_card_models.g.dart';

/// A single atomic insight card from the backend.
@freezed
class IdeaCardModel with _$IdeaCardModel {
  const factory IdeaCardModel({
    required String id,
    @JsonKey(name: 'idol_id') required String idolId,
    @JsonKey(name: 'category_tag') required String categoryTag,
    @JsonKey(name: 'content_markdown') required String contentMarkdown,
    @JsonKey(name: 'is_locked') @Default(false) bool isLocked,
    @JsonKey(name: 'sort_order') @Default(0) int sortOrder,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'is_stashed') @Default(false) bool isStashed,
  }) = _IdeaCardModel;

  factory IdeaCardModel.fromJson(Map<String, dynamic> json) =>
      _$IdeaCardModelFromJson(json);
}

/// Paginated response for IdeaCards.
@freezed
class IdeaCardListResponse with _$IdeaCardListResponse {
  const factory IdeaCardListResponse({
    @JsonKey(name: 'idea_cards') required List<IdeaCardModel> ideaCards,
    required int total,
    required int page,
    @JsonKey(name: 'page_size') required int pageSize,
  }) = _IdeaCardListResponse;

  factory IdeaCardListResponse.fromJson(Map<String, dynamic> json) =>
      _$IdeaCardListResponseFromJson(json);
}

/// Syllabus category item.
@freezed
class SyllabusCategory with _$SyllabusCategory {
  const factory SyllabusCategory({
    required String tag,
    required int count,
    required int unlocked,
    required int locked,
  }) = _SyllabusCategory;

  factory SyllabusCategory.fromJson(Map<String, dynamic> json) =>
      _$SyllabusCategoryFromJson(json);
}

/// Syllabus response for an idol.
@freezed
class SyllabusResponse with _$SyllabusResponse {
  const factory SyllabusResponse({
    @JsonKey(name: 'idol_id') required String idolId,
    @JsonKey(name: 'idol_name') required String idolName,
    required List<SyllabusCategory> categories,
    @JsonKey(name: 'total_cards') required int totalCards,
    @JsonKey(name: 'total_stashed') required int totalStashed,
  }) = _SyllabusResponse;

  factory SyllabusResponse.fromJson(Map<String, dynamic> json) =>
      _$SyllabusResponseFromJson(json);
}

/// Stash toggle action response.
@freezed
class StashActionResponse with _$StashActionResponse {
  const factory StashActionResponse({
    required bool success,
    required String action, // "stashed" | "unstashed"
    @JsonKey(name: 'idea_card_id') required String ideaCardId,
  }) = _StashActionResponse;

  factory StashActionResponse.fromJson(Map<String, dynamic> json) =>
      _$StashActionResponseFromJson(json);
}
