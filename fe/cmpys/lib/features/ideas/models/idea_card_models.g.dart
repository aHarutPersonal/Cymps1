// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'idea_card_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$IdeaCardModelImpl _$$IdeaCardModelImplFromJson(Map<String, dynamic> json) =>
    _$IdeaCardModelImpl(
      id: json['id'] as String,
      idolId: json['idol_id'] as String,
      categoryTag: json['category_tag'] as String,
      contentMarkdown: json['content_markdown'] as String,
      isLocked: json['is_locked'] as bool? ?? false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      isStashed: json['is_stashed'] as bool? ?? false,
    );

Map<String, dynamic> _$$IdeaCardModelImplToJson(_$IdeaCardModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'idol_id': instance.idolId,
      'category_tag': instance.categoryTag,
      'content_markdown': instance.contentMarkdown,
      'is_locked': instance.isLocked,
      'sort_order': instance.sortOrder,
      'created_at': instance.createdAt?.toIso8601String(),
      'is_stashed': instance.isStashed,
    };

_$IdeaCardListResponseImpl _$$IdeaCardListResponseImplFromJson(
  Map<String, dynamic> json,
) => _$IdeaCardListResponseImpl(
  ideaCards: (json['idea_cards'] as List<dynamic>)
      .map((e) => IdeaCardModel.fromJson(e as Map<String, dynamic>))
      .toList(),
  total: (json['total'] as num).toInt(),
  page: (json['page'] as num).toInt(),
  pageSize: (json['page_size'] as num).toInt(),
);

Map<String, dynamic> _$$IdeaCardListResponseImplToJson(
  _$IdeaCardListResponseImpl instance,
) => <String, dynamic>{
  'idea_cards': instance.ideaCards,
  'total': instance.total,
  'page': instance.page,
  'page_size': instance.pageSize,
};

_$SyllabusCategoryImpl _$$SyllabusCategoryImplFromJson(
  Map<String, dynamic> json,
) => _$SyllabusCategoryImpl(
  tag: json['tag'] as String,
  count: (json['count'] as num).toInt(),
  unlocked: (json['unlocked'] as num).toInt(),
  locked: (json['locked'] as num).toInt(),
);

Map<String, dynamic> _$$SyllabusCategoryImplToJson(
  _$SyllabusCategoryImpl instance,
) => <String, dynamic>{
  'tag': instance.tag,
  'count': instance.count,
  'unlocked': instance.unlocked,
  'locked': instance.locked,
};

_$SyllabusResponseImpl _$$SyllabusResponseImplFromJson(
  Map<String, dynamic> json,
) => _$SyllabusResponseImpl(
  idolId: json['idol_id'] as String,
  idolName: json['idol_name'] as String,
  categories: (json['categories'] as List<dynamic>)
      .map((e) => SyllabusCategory.fromJson(e as Map<String, dynamic>))
      .toList(),
  totalCards: (json['total_cards'] as num).toInt(),
  totalStashed: (json['total_stashed'] as num).toInt(),
);

Map<String, dynamic> _$$SyllabusResponseImplToJson(
  _$SyllabusResponseImpl instance,
) => <String, dynamic>{
  'idol_id': instance.idolId,
  'idol_name': instance.idolName,
  'categories': instance.categories,
  'total_cards': instance.totalCards,
  'total_stashed': instance.totalStashed,
};

_$StashActionResponseImpl _$$StashActionResponseImplFromJson(
  Map<String, dynamic> json,
) => _$StashActionResponseImpl(
  success: json['success'] as bool,
  action: json['action'] as String,
  ideaCardId: json['idea_card_id'] as String,
);

Map<String, dynamic> _$$StashActionResponseImplToJson(
  _$StashActionResponseImpl instance,
) => <String, dynamic>{
  'success': instance.success,
  'action': instance.action,
  'idea_card_id': instance.ideaCardId,
};
