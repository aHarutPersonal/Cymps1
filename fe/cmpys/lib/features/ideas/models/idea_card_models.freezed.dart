// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'idea_card_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

IdeaCardModel _$IdeaCardModelFromJson(Map<String, dynamic> json) {
  return _IdeaCardModel.fromJson(json);
}

/// @nodoc
mixin _$IdeaCardModel {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'idol_id')
  String get idolId => throw _privateConstructorUsedError;
  @JsonKey(name: 'category_tag')
  String get categoryTag => throw _privateConstructorUsedError;
  @JsonKey(name: 'content_markdown')
  String get contentMarkdown => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_locked')
  bool get isLocked => throw _privateConstructorUsedError;
  @JsonKey(name: 'sort_order')
  int get sortOrder => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime? get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_stashed')
  bool get isStashed => throw _privateConstructorUsedError;

  /// Serializes this IdeaCardModel to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of IdeaCardModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IdeaCardModelCopyWith<IdeaCardModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IdeaCardModelCopyWith<$Res> {
  factory $IdeaCardModelCopyWith(
    IdeaCardModel value,
    $Res Function(IdeaCardModel) then,
  ) = _$IdeaCardModelCopyWithImpl<$Res, IdeaCardModel>;
  @useResult
  $Res call({
    String id,
    @JsonKey(name: 'idol_id') String idolId,
    @JsonKey(name: 'category_tag') String categoryTag,
    @JsonKey(name: 'content_markdown') String contentMarkdown,
    @JsonKey(name: 'is_locked') bool isLocked,
    @JsonKey(name: 'sort_order') int sortOrder,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'is_stashed') bool isStashed,
  });
}

/// @nodoc
class _$IdeaCardModelCopyWithImpl<$Res, $Val extends IdeaCardModel>
    implements $IdeaCardModelCopyWith<$Res> {
  _$IdeaCardModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IdeaCardModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? idolId = null,
    Object? categoryTag = null,
    Object? contentMarkdown = null,
    Object? isLocked = null,
    Object? sortOrder = null,
    Object? createdAt = freezed,
    Object? isStashed = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            idolId: null == idolId
                ? _value.idolId
                : idolId // ignore: cast_nullable_to_non_nullable
                      as String,
            categoryTag: null == categoryTag
                ? _value.categoryTag
                : categoryTag // ignore: cast_nullable_to_non_nullable
                      as String,
            contentMarkdown: null == contentMarkdown
                ? _value.contentMarkdown
                : contentMarkdown // ignore: cast_nullable_to_non_nullable
                      as String,
            isLocked: null == isLocked
                ? _value.isLocked
                : isLocked // ignore: cast_nullable_to_non_nullable
                      as bool,
            sortOrder: null == sortOrder
                ? _value.sortOrder
                : sortOrder // ignore: cast_nullable_to_non_nullable
                      as int,
            createdAt: freezed == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            isStashed: null == isStashed
                ? _value.isStashed
                : isStashed // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$IdeaCardModelImplCopyWith<$Res>
    implements $IdeaCardModelCopyWith<$Res> {
  factory _$$IdeaCardModelImplCopyWith(
    _$IdeaCardModelImpl value,
    $Res Function(_$IdeaCardModelImpl) then,
  ) = __$$IdeaCardModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    @JsonKey(name: 'idol_id') String idolId,
    @JsonKey(name: 'category_tag') String categoryTag,
    @JsonKey(name: 'content_markdown') String contentMarkdown,
    @JsonKey(name: 'is_locked') bool isLocked,
    @JsonKey(name: 'sort_order') int sortOrder,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'is_stashed') bool isStashed,
  });
}

/// @nodoc
class __$$IdeaCardModelImplCopyWithImpl<$Res>
    extends _$IdeaCardModelCopyWithImpl<$Res, _$IdeaCardModelImpl>
    implements _$$IdeaCardModelImplCopyWith<$Res> {
  __$$IdeaCardModelImplCopyWithImpl(
    _$IdeaCardModelImpl _value,
    $Res Function(_$IdeaCardModelImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IdeaCardModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? idolId = null,
    Object? categoryTag = null,
    Object? contentMarkdown = null,
    Object? isLocked = null,
    Object? sortOrder = null,
    Object? createdAt = freezed,
    Object? isStashed = null,
  }) {
    return _then(
      _$IdeaCardModelImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        idolId: null == idolId
            ? _value.idolId
            : idolId // ignore: cast_nullable_to_non_nullable
                  as String,
        categoryTag: null == categoryTag
            ? _value.categoryTag
            : categoryTag // ignore: cast_nullable_to_non_nullable
                  as String,
        contentMarkdown: null == contentMarkdown
            ? _value.contentMarkdown
            : contentMarkdown // ignore: cast_nullable_to_non_nullable
                  as String,
        isLocked: null == isLocked
            ? _value.isLocked
            : isLocked // ignore: cast_nullable_to_non_nullable
                  as bool,
        sortOrder: null == sortOrder
            ? _value.sortOrder
            : sortOrder // ignore: cast_nullable_to_non_nullable
                  as int,
        createdAt: freezed == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        isStashed: null == isStashed
            ? _value.isStashed
            : isStashed // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$IdeaCardModelImpl implements _IdeaCardModel {
  const _$IdeaCardModelImpl({
    required this.id,
    @JsonKey(name: 'idol_id') required this.idolId,
    @JsonKey(name: 'category_tag') required this.categoryTag,
    @JsonKey(name: 'content_markdown') required this.contentMarkdown,
    @JsonKey(name: 'is_locked') this.isLocked = false,
    @JsonKey(name: 'sort_order') this.sortOrder = 0,
    @JsonKey(name: 'created_at') this.createdAt,
    @JsonKey(name: 'is_stashed') this.isStashed = false,
  });

  factory _$IdeaCardModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$IdeaCardModelImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'idol_id')
  final String idolId;
  @override
  @JsonKey(name: 'category_tag')
  final String categoryTag;
  @override
  @JsonKey(name: 'content_markdown')
  final String contentMarkdown;
  @override
  @JsonKey(name: 'is_locked')
  final bool isLocked;
  @override
  @JsonKey(name: 'sort_order')
  final int sortOrder;
  @override
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;
  @override
  @JsonKey(name: 'is_stashed')
  final bool isStashed;

  @override
  String toString() {
    return 'IdeaCardModel(id: $id, idolId: $idolId, categoryTag: $categoryTag, contentMarkdown: $contentMarkdown, isLocked: $isLocked, sortOrder: $sortOrder, createdAt: $createdAt, isStashed: $isStashed)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IdeaCardModelImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.idolId, idolId) || other.idolId == idolId) &&
            (identical(other.categoryTag, categoryTag) ||
                other.categoryTag == categoryTag) &&
            (identical(other.contentMarkdown, contentMarkdown) ||
                other.contentMarkdown == contentMarkdown) &&
            (identical(other.isLocked, isLocked) ||
                other.isLocked == isLocked) &&
            (identical(other.sortOrder, sortOrder) ||
                other.sortOrder == sortOrder) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.isStashed, isStashed) ||
                other.isStashed == isStashed));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    idolId,
    categoryTag,
    contentMarkdown,
    isLocked,
    sortOrder,
    createdAt,
    isStashed,
  );

  /// Create a copy of IdeaCardModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IdeaCardModelImplCopyWith<_$IdeaCardModelImpl> get copyWith =>
      __$$IdeaCardModelImplCopyWithImpl<_$IdeaCardModelImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$IdeaCardModelImplToJson(this);
  }
}

abstract class _IdeaCardModel implements IdeaCardModel {
  const factory _IdeaCardModel({
    required final String id,
    @JsonKey(name: 'idol_id') required final String idolId,
    @JsonKey(name: 'category_tag') required final String categoryTag,
    @JsonKey(name: 'content_markdown') required final String contentMarkdown,
    @JsonKey(name: 'is_locked') final bool isLocked,
    @JsonKey(name: 'sort_order') final int sortOrder,
    @JsonKey(name: 'created_at') final DateTime? createdAt,
    @JsonKey(name: 'is_stashed') final bool isStashed,
  }) = _$IdeaCardModelImpl;

  factory _IdeaCardModel.fromJson(Map<String, dynamic> json) =
      _$IdeaCardModelImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'idol_id')
  String get idolId;
  @override
  @JsonKey(name: 'category_tag')
  String get categoryTag;
  @override
  @JsonKey(name: 'content_markdown')
  String get contentMarkdown;
  @override
  @JsonKey(name: 'is_locked')
  bool get isLocked;
  @override
  @JsonKey(name: 'sort_order')
  int get sortOrder;
  @override
  @JsonKey(name: 'created_at')
  DateTime? get createdAt;
  @override
  @JsonKey(name: 'is_stashed')
  bool get isStashed;

  /// Create a copy of IdeaCardModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IdeaCardModelImplCopyWith<_$IdeaCardModelImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

IdeaCardListResponse _$IdeaCardListResponseFromJson(Map<String, dynamic> json) {
  return _IdeaCardListResponse.fromJson(json);
}

/// @nodoc
mixin _$IdeaCardListResponse {
  @JsonKey(name: 'idea_cards')
  List<IdeaCardModel> get ideaCards => throw _privateConstructorUsedError;
  int get total => throw _privateConstructorUsedError;
  int get page => throw _privateConstructorUsedError;
  @JsonKey(name: 'page_size')
  int get pageSize => throw _privateConstructorUsedError;

  /// Serializes this IdeaCardListResponse to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of IdeaCardListResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IdeaCardListResponseCopyWith<IdeaCardListResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IdeaCardListResponseCopyWith<$Res> {
  factory $IdeaCardListResponseCopyWith(
    IdeaCardListResponse value,
    $Res Function(IdeaCardListResponse) then,
  ) = _$IdeaCardListResponseCopyWithImpl<$Res, IdeaCardListResponse>;
  @useResult
  $Res call({
    @JsonKey(name: 'idea_cards') List<IdeaCardModel> ideaCards,
    int total,
    int page,
    @JsonKey(name: 'page_size') int pageSize,
  });
}

/// @nodoc
class _$IdeaCardListResponseCopyWithImpl<
  $Res,
  $Val extends IdeaCardListResponse
>
    implements $IdeaCardListResponseCopyWith<$Res> {
  _$IdeaCardListResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IdeaCardListResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ideaCards = null,
    Object? total = null,
    Object? page = null,
    Object? pageSize = null,
  }) {
    return _then(
      _value.copyWith(
            ideaCards: null == ideaCards
                ? _value.ideaCards
                : ideaCards // ignore: cast_nullable_to_non_nullable
                      as List<IdeaCardModel>,
            total: null == total
                ? _value.total
                : total // ignore: cast_nullable_to_non_nullable
                      as int,
            page: null == page
                ? _value.page
                : page // ignore: cast_nullable_to_non_nullable
                      as int,
            pageSize: null == pageSize
                ? _value.pageSize
                : pageSize // ignore: cast_nullable_to_non_nullable
                      as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$IdeaCardListResponseImplCopyWith<$Res>
    implements $IdeaCardListResponseCopyWith<$Res> {
  factory _$$IdeaCardListResponseImplCopyWith(
    _$IdeaCardListResponseImpl value,
    $Res Function(_$IdeaCardListResponseImpl) then,
  ) = __$$IdeaCardListResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'idea_cards') List<IdeaCardModel> ideaCards,
    int total,
    int page,
    @JsonKey(name: 'page_size') int pageSize,
  });
}

/// @nodoc
class __$$IdeaCardListResponseImplCopyWithImpl<$Res>
    extends _$IdeaCardListResponseCopyWithImpl<$Res, _$IdeaCardListResponseImpl>
    implements _$$IdeaCardListResponseImplCopyWith<$Res> {
  __$$IdeaCardListResponseImplCopyWithImpl(
    _$IdeaCardListResponseImpl _value,
    $Res Function(_$IdeaCardListResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IdeaCardListResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ideaCards = null,
    Object? total = null,
    Object? page = null,
    Object? pageSize = null,
  }) {
    return _then(
      _$IdeaCardListResponseImpl(
        ideaCards: null == ideaCards
            ? _value._ideaCards
            : ideaCards // ignore: cast_nullable_to_non_nullable
                  as List<IdeaCardModel>,
        total: null == total
            ? _value.total
            : total // ignore: cast_nullable_to_non_nullable
                  as int,
        page: null == page
            ? _value.page
            : page // ignore: cast_nullable_to_non_nullable
                  as int,
        pageSize: null == pageSize
            ? _value.pageSize
            : pageSize // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$IdeaCardListResponseImpl implements _IdeaCardListResponse {
  const _$IdeaCardListResponseImpl({
    @JsonKey(name: 'idea_cards') required final List<IdeaCardModel> ideaCards,
    required this.total,
    required this.page,
    @JsonKey(name: 'page_size') required this.pageSize,
  }) : _ideaCards = ideaCards;

  factory _$IdeaCardListResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$IdeaCardListResponseImplFromJson(json);

  final List<IdeaCardModel> _ideaCards;
  @override
  @JsonKey(name: 'idea_cards')
  List<IdeaCardModel> get ideaCards {
    if (_ideaCards is EqualUnmodifiableListView) return _ideaCards;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_ideaCards);
  }

  @override
  final int total;
  @override
  final int page;
  @override
  @JsonKey(name: 'page_size')
  final int pageSize;

  @override
  String toString() {
    return 'IdeaCardListResponse(ideaCards: $ideaCards, total: $total, page: $page, pageSize: $pageSize)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IdeaCardListResponseImpl &&
            const DeepCollectionEquality().equals(
              other._ideaCards,
              _ideaCards,
            ) &&
            (identical(other.total, total) || other.total == total) &&
            (identical(other.page, page) || other.page == page) &&
            (identical(other.pageSize, pageSize) ||
                other.pageSize == pageSize));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_ideaCards),
    total,
    page,
    pageSize,
  );

  /// Create a copy of IdeaCardListResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IdeaCardListResponseImplCopyWith<_$IdeaCardListResponseImpl>
  get copyWith =>
      __$$IdeaCardListResponseImplCopyWithImpl<_$IdeaCardListResponseImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$IdeaCardListResponseImplToJson(this);
  }
}

abstract class _IdeaCardListResponse implements IdeaCardListResponse {
  const factory _IdeaCardListResponse({
    @JsonKey(name: 'idea_cards') required final List<IdeaCardModel> ideaCards,
    required final int total,
    required final int page,
    @JsonKey(name: 'page_size') required final int pageSize,
  }) = _$IdeaCardListResponseImpl;

  factory _IdeaCardListResponse.fromJson(Map<String, dynamic> json) =
      _$IdeaCardListResponseImpl.fromJson;

  @override
  @JsonKey(name: 'idea_cards')
  List<IdeaCardModel> get ideaCards;
  @override
  int get total;
  @override
  int get page;
  @override
  @JsonKey(name: 'page_size')
  int get pageSize;

  /// Create a copy of IdeaCardListResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IdeaCardListResponseImplCopyWith<_$IdeaCardListResponseImpl>
  get copyWith => throw _privateConstructorUsedError;
}

SyllabusCategory _$SyllabusCategoryFromJson(Map<String, dynamic> json) {
  return _SyllabusCategory.fromJson(json);
}

/// @nodoc
mixin _$SyllabusCategory {
  String get tag => throw _privateConstructorUsedError;
  int get count => throw _privateConstructorUsedError;
  int get unlocked => throw _privateConstructorUsedError;
  int get locked => throw _privateConstructorUsedError;

  /// Serializes this SyllabusCategory to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SyllabusCategory
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SyllabusCategoryCopyWith<SyllabusCategory> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SyllabusCategoryCopyWith<$Res> {
  factory $SyllabusCategoryCopyWith(
    SyllabusCategory value,
    $Res Function(SyllabusCategory) then,
  ) = _$SyllabusCategoryCopyWithImpl<$Res, SyllabusCategory>;
  @useResult
  $Res call({String tag, int count, int unlocked, int locked});
}

/// @nodoc
class _$SyllabusCategoryCopyWithImpl<$Res, $Val extends SyllabusCategory>
    implements $SyllabusCategoryCopyWith<$Res> {
  _$SyllabusCategoryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SyllabusCategory
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? tag = null,
    Object? count = null,
    Object? unlocked = null,
    Object? locked = null,
  }) {
    return _then(
      _value.copyWith(
            tag: null == tag
                ? _value.tag
                : tag // ignore: cast_nullable_to_non_nullable
                      as String,
            count: null == count
                ? _value.count
                : count // ignore: cast_nullable_to_non_nullable
                      as int,
            unlocked: null == unlocked
                ? _value.unlocked
                : unlocked // ignore: cast_nullable_to_non_nullable
                      as int,
            locked: null == locked
                ? _value.locked
                : locked // ignore: cast_nullable_to_non_nullable
                      as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SyllabusCategoryImplCopyWith<$Res>
    implements $SyllabusCategoryCopyWith<$Res> {
  factory _$$SyllabusCategoryImplCopyWith(
    _$SyllabusCategoryImpl value,
    $Res Function(_$SyllabusCategoryImpl) then,
  ) = __$$SyllabusCategoryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String tag, int count, int unlocked, int locked});
}

/// @nodoc
class __$$SyllabusCategoryImplCopyWithImpl<$Res>
    extends _$SyllabusCategoryCopyWithImpl<$Res, _$SyllabusCategoryImpl>
    implements _$$SyllabusCategoryImplCopyWith<$Res> {
  __$$SyllabusCategoryImplCopyWithImpl(
    _$SyllabusCategoryImpl _value,
    $Res Function(_$SyllabusCategoryImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SyllabusCategory
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? tag = null,
    Object? count = null,
    Object? unlocked = null,
    Object? locked = null,
  }) {
    return _then(
      _$SyllabusCategoryImpl(
        tag: null == tag
            ? _value.tag
            : tag // ignore: cast_nullable_to_non_nullable
                  as String,
        count: null == count
            ? _value.count
            : count // ignore: cast_nullable_to_non_nullable
                  as int,
        unlocked: null == unlocked
            ? _value.unlocked
            : unlocked // ignore: cast_nullable_to_non_nullable
                  as int,
        locked: null == locked
            ? _value.locked
            : locked // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SyllabusCategoryImpl implements _SyllabusCategory {
  const _$SyllabusCategoryImpl({
    required this.tag,
    required this.count,
    required this.unlocked,
    required this.locked,
  });

  factory _$SyllabusCategoryImpl.fromJson(Map<String, dynamic> json) =>
      _$$SyllabusCategoryImplFromJson(json);

  @override
  final String tag;
  @override
  final int count;
  @override
  final int unlocked;
  @override
  final int locked;

  @override
  String toString() {
    return 'SyllabusCategory(tag: $tag, count: $count, unlocked: $unlocked, locked: $locked)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SyllabusCategoryImpl &&
            (identical(other.tag, tag) || other.tag == tag) &&
            (identical(other.count, count) || other.count == count) &&
            (identical(other.unlocked, unlocked) ||
                other.unlocked == unlocked) &&
            (identical(other.locked, locked) || other.locked == locked));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, tag, count, unlocked, locked);

  /// Create a copy of SyllabusCategory
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SyllabusCategoryImplCopyWith<_$SyllabusCategoryImpl> get copyWith =>
      __$$SyllabusCategoryImplCopyWithImpl<_$SyllabusCategoryImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$SyllabusCategoryImplToJson(this);
  }
}

abstract class _SyllabusCategory implements SyllabusCategory {
  const factory _SyllabusCategory({
    required final String tag,
    required final int count,
    required final int unlocked,
    required final int locked,
  }) = _$SyllabusCategoryImpl;

  factory _SyllabusCategory.fromJson(Map<String, dynamic> json) =
      _$SyllabusCategoryImpl.fromJson;

  @override
  String get tag;
  @override
  int get count;
  @override
  int get unlocked;
  @override
  int get locked;

  /// Create a copy of SyllabusCategory
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SyllabusCategoryImplCopyWith<_$SyllabusCategoryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SyllabusResponse _$SyllabusResponseFromJson(Map<String, dynamic> json) {
  return _SyllabusResponse.fromJson(json);
}

/// @nodoc
mixin _$SyllabusResponse {
  @JsonKey(name: 'idol_id')
  String get idolId => throw _privateConstructorUsedError;
  @JsonKey(name: 'idol_name')
  String get idolName => throw _privateConstructorUsedError;
  List<SyllabusCategory> get categories => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_cards')
  int get totalCards => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_stashed')
  int get totalStashed => throw _privateConstructorUsedError;

  /// Serializes this SyllabusResponse to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SyllabusResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SyllabusResponseCopyWith<SyllabusResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SyllabusResponseCopyWith<$Res> {
  factory $SyllabusResponseCopyWith(
    SyllabusResponse value,
    $Res Function(SyllabusResponse) then,
  ) = _$SyllabusResponseCopyWithImpl<$Res, SyllabusResponse>;
  @useResult
  $Res call({
    @JsonKey(name: 'idol_id') String idolId,
    @JsonKey(name: 'idol_name') String idolName,
    List<SyllabusCategory> categories,
    @JsonKey(name: 'total_cards') int totalCards,
    @JsonKey(name: 'total_stashed') int totalStashed,
  });
}

/// @nodoc
class _$SyllabusResponseCopyWithImpl<$Res, $Val extends SyllabusResponse>
    implements $SyllabusResponseCopyWith<$Res> {
  _$SyllabusResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SyllabusResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? idolId = null,
    Object? idolName = null,
    Object? categories = null,
    Object? totalCards = null,
    Object? totalStashed = null,
  }) {
    return _then(
      _value.copyWith(
            idolId: null == idolId
                ? _value.idolId
                : idolId // ignore: cast_nullable_to_non_nullable
                      as String,
            idolName: null == idolName
                ? _value.idolName
                : idolName // ignore: cast_nullable_to_non_nullable
                      as String,
            categories: null == categories
                ? _value.categories
                : categories // ignore: cast_nullable_to_non_nullable
                      as List<SyllabusCategory>,
            totalCards: null == totalCards
                ? _value.totalCards
                : totalCards // ignore: cast_nullable_to_non_nullable
                      as int,
            totalStashed: null == totalStashed
                ? _value.totalStashed
                : totalStashed // ignore: cast_nullable_to_non_nullable
                      as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SyllabusResponseImplCopyWith<$Res>
    implements $SyllabusResponseCopyWith<$Res> {
  factory _$$SyllabusResponseImplCopyWith(
    _$SyllabusResponseImpl value,
    $Res Function(_$SyllabusResponseImpl) then,
  ) = __$$SyllabusResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(name: 'idol_id') String idolId,
    @JsonKey(name: 'idol_name') String idolName,
    List<SyllabusCategory> categories,
    @JsonKey(name: 'total_cards') int totalCards,
    @JsonKey(name: 'total_stashed') int totalStashed,
  });
}

/// @nodoc
class __$$SyllabusResponseImplCopyWithImpl<$Res>
    extends _$SyllabusResponseCopyWithImpl<$Res, _$SyllabusResponseImpl>
    implements _$$SyllabusResponseImplCopyWith<$Res> {
  __$$SyllabusResponseImplCopyWithImpl(
    _$SyllabusResponseImpl _value,
    $Res Function(_$SyllabusResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SyllabusResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? idolId = null,
    Object? idolName = null,
    Object? categories = null,
    Object? totalCards = null,
    Object? totalStashed = null,
  }) {
    return _then(
      _$SyllabusResponseImpl(
        idolId: null == idolId
            ? _value.idolId
            : idolId // ignore: cast_nullable_to_non_nullable
                  as String,
        idolName: null == idolName
            ? _value.idolName
            : idolName // ignore: cast_nullable_to_non_nullable
                  as String,
        categories: null == categories
            ? _value._categories
            : categories // ignore: cast_nullable_to_non_nullable
                  as List<SyllabusCategory>,
        totalCards: null == totalCards
            ? _value.totalCards
            : totalCards // ignore: cast_nullable_to_non_nullable
                  as int,
        totalStashed: null == totalStashed
            ? _value.totalStashed
            : totalStashed // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SyllabusResponseImpl implements _SyllabusResponse {
  const _$SyllabusResponseImpl({
    @JsonKey(name: 'idol_id') required this.idolId,
    @JsonKey(name: 'idol_name') required this.idolName,
    required final List<SyllabusCategory> categories,
    @JsonKey(name: 'total_cards') required this.totalCards,
    @JsonKey(name: 'total_stashed') required this.totalStashed,
  }) : _categories = categories;

  factory _$SyllabusResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$SyllabusResponseImplFromJson(json);

  @override
  @JsonKey(name: 'idol_id')
  final String idolId;
  @override
  @JsonKey(name: 'idol_name')
  final String idolName;
  final List<SyllabusCategory> _categories;
  @override
  List<SyllabusCategory> get categories {
    if (_categories is EqualUnmodifiableListView) return _categories;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_categories);
  }

  @override
  @JsonKey(name: 'total_cards')
  final int totalCards;
  @override
  @JsonKey(name: 'total_stashed')
  final int totalStashed;

  @override
  String toString() {
    return 'SyllabusResponse(idolId: $idolId, idolName: $idolName, categories: $categories, totalCards: $totalCards, totalStashed: $totalStashed)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SyllabusResponseImpl &&
            (identical(other.idolId, idolId) || other.idolId == idolId) &&
            (identical(other.idolName, idolName) ||
                other.idolName == idolName) &&
            const DeepCollectionEquality().equals(
              other._categories,
              _categories,
            ) &&
            (identical(other.totalCards, totalCards) ||
                other.totalCards == totalCards) &&
            (identical(other.totalStashed, totalStashed) ||
                other.totalStashed == totalStashed));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    idolId,
    idolName,
    const DeepCollectionEquality().hash(_categories),
    totalCards,
    totalStashed,
  );

  /// Create a copy of SyllabusResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SyllabusResponseImplCopyWith<_$SyllabusResponseImpl> get copyWith =>
      __$$SyllabusResponseImplCopyWithImpl<_$SyllabusResponseImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$SyllabusResponseImplToJson(this);
  }
}

abstract class _SyllabusResponse implements SyllabusResponse {
  const factory _SyllabusResponse({
    @JsonKey(name: 'idol_id') required final String idolId,
    @JsonKey(name: 'idol_name') required final String idolName,
    required final List<SyllabusCategory> categories,
    @JsonKey(name: 'total_cards') required final int totalCards,
    @JsonKey(name: 'total_stashed') required final int totalStashed,
  }) = _$SyllabusResponseImpl;

  factory _SyllabusResponse.fromJson(Map<String, dynamic> json) =
      _$SyllabusResponseImpl.fromJson;

  @override
  @JsonKey(name: 'idol_id')
  String get idolId;
  @override
  @JsonKey(name: 'idol_name')
  String get idolName;
  @override
  List<SyllabusCategory> get categories;
  @override
  @JsonKey(name: 'total_cards')
  int get totalCards;
  @override
  @JsonKey(name: 'total_stashed')
  int get totalStashed;

  /// Create a copy of SyllabusResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SyllabusResponseImplCopyWith<_$SyllabusResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

StashActionResponse _$StashActionResponseFromJson(Map<String, dynamic> json) {
  return _StashActionResponse.fromJson(json);
}

/// @nodoc
mixin _$StashActionResponse {
  bool get success => throw _privateConstructorUsedError;
  String get action =>
      throw _privateConstructorUsedError; // "stashed" | "unstashed"
  @JsonKey(name: 'idea_card_id')
  String get ideaCardId => throw _privateConstructorUsedError;

  /// Serializes this StashActionResponse to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of StashActionResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $StashActionResponseCopyWith<StashActionResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $StashActionResponseCopyWith<$Res> {
  factory $StashActionResponseCopyWith(
    StashActionResponse value,
    $Res Function(StashActionResponse) then,
  ) = _$StashActionResponseCopyWithImpl<$Res, StashActionResponse>;
  @useResult
  $Res call({
    bool success,
    String action,
    @JsonKey(name: 'idea_card_id') String ideaCardId,
  });
}

/// @nodoc
class _$StashActionResponseCopyWithImpl<$Res, $Val extends StashActionResponse>
    implements $StashActionResponseCopyWith<$Res> {
  _$StashActionResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of StashActionResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? action = null,
    Object? ideaCardId = null,
  }) {
    return _then(
      _value.copyWith(
            success: null == success
                ? _value.success
                : success // ignore: cast_nullable_to_non_nullable
                      as bool,
            action: null == action
                ? _value.action
                : action // ignore: cast_nullable_to_non_nullable
                      as String,
            ideaCardId: null == ideaCardId
                ? _value.ideaCardId
                : ideaCardId // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$StashActionResponseImplCopyWith<$Res>
    implements $StashActionResponseCopyWith<$Res> {
  factory _$$StashActionResponseImplCopyWith(
    _$StashActionResponseImpl value,
    $Res Function(_$StashActionResponseImpl) then,
  ) = __$$StashActionResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    bool success,
    String action,
    @JsonKey(name: 'idea_card_id') String ideaCardId,
  });
}

/// @nodoc
class __$$StashActionResponseImplCopyWithImpl<$Res>
    extends _$StashActionResponseCopyWithImpl<$Res, _$StashActionResponseImpl>
    implements _$$StashActionResponseImplCopyWith<$Res> {
  __$$StashActionResponseImplCopyWithImpl(
    _$StashActionResponseImpl _value,
    $Res Function(_$StashActionResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of StashActionResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? action = null,
    Object? ideaCardId = null,
  }) {
    return _then(
      _$StashActionResponseImpl(
        success: null == success
            ? _value.success
            : success // ignore: cast_nullable_to_non_nullable
                  as bool,
        action: null == action
            ? _value.action
            : action // ignore: cast_nullable_to_non_nullable
                  as String,
        ideaCardId: null == ideaCardId
            ? _value.ideaCardId
            : ideaCardId // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$StashActionResponseImpl implements _StashActionResponse {
  const _$StashActionResponseImpl({
    required this.success,
    required this.action,
    @JsonKey(name: 'idea_card_id') required this.ideaCardId,
  });

  factory _$StashActionResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$StashActionResponseImplFromJson(json);

  @override
  final bool success;
  @override
  final String action;
  // "stashed" | "unstashed"
  @override
  @JsonKey(name: 'idea_card_id')
  final String ideaCardId;

  @override
  String toString() {
    return 'StashActionResponse(success: $success, action: $action, ideaCardId: $ideaCardId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StashActionResponseImpl &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.action, action) || other.action == action) &&
            (identical(other.ideaCardId, ideaCardId) ||
                other.ideaCardId == ideaCardId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, success, action, ideaCardId);

  /// Create a copy of StashActionResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StashActionResponseImplCopyWith<_$StashActionResponseImpl> get copyWith =>
      __$$StashActionResponseImplCopyWithImpl<_$StashActionResponseImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$StashActionResponseImplToJson(this);
  }
}

abstract class _StashActionResponse implements StashActionResponse {
  const factory _StashActionResponse({
    required final bool success,
    required final String action,
    @JsonKey(name: 'idea_card_id') required final String ideaCardId,
  }) = _$StashActionResponseImpl;

  factory _StashActionResponse.fromJson(Map<String, dynamic> json) =
      _$StashActionResponseImpl.fromJson;

  @override
  bool get success;
  @override
  String get action; // "stashed" | "unstashed"
  @override
  @JsonKey(name: 'idea_card_id')
  String get ideaCardId;

  /// Create a copy of StashActionResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StashActionResponseImplCopyWith<_$StashActionResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
