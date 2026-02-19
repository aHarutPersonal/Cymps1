// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'achievement_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Achievement {
  String get id => throw _privateConstructorUsedError;
  String get userId => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  AchievementCategory get category => throw _privateConstructorUsedError;
  DateTime? get achievementDate => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;
  String? get evidenceLink => throw _privateConstructorUsedError;
  DateTime? get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  /// Create a copy of Achievement
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AchievementCopyWith<Achievement> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AchievementCopyWith<$Res> {
  factory $AchievementCopyWith(
    Achievement value,
    $Res Function(Achievement) then,
  ) = _$AchievementCopyWithImpl<$Res, Achievement>;
  @useResult
  $Res call({
    String id,
    String userId,
    String title,
    AchievementCategory category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
}

/// @nodoc
class _$AchievementCopyWithImpl<$Res, $Val extends Achievement>
    implements $AchievementCopyWith<$Res> {
  _$AchievementCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Achievement
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = null,
    Object? title = null,
    Object? category = null,
    Object? achievementDate = freezed,
    Object? notes = freezed,
    Object? evidenceLink = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            userId: null == userId
                ? _value.userId
                : userId // ignore: cast_nullable_to_non_nullable
                      as String,
            title: null == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String,
            category: null == category
                ? _value.category
                : category // ignore: cast_nullable_to_non_nullable
                      as AchievementCategory,
            achievementDate: freezed == achievementDate
                ? _value.achievementDate
                : achievementDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            notes: freezed == notes
                ? _value.notes
                : notes // ignore: cast_nullable_to_non_nullable
                      as String?,
            evidenceLink: freezed == evidenceLink
                ? _value.evidenceLink
                : evidenceLink // ignore: cast_nullable_to_non_nullable
                      as String?,
            createdAt: freezed == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            updatedAt: freezed == updatedAt
                ? _value.updatedAt
                : updatedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$AchievementImplCopyWith<$Res>
    implements $AchievementCopyWith<$Res> {
  factory _$$AchievementImplCopyWith(
    _$AchievementImpl value,
    $Res Function(_$AchievementImpl) then,
  ) = __$$AchievementImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String userId,
    String title,
    AchievementCategory category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
}

/// @nodoc
class __$$AchievementImplCopyWithImpl<$Res>
    extends _$AchievementCopyWithImpl<$Res, _$AchievementImpl>
    implements _$$AchievementImplCopyWith<$Res> {
  __$$AchievementImplCopyWithImpl(
    _$AchievementImpl _value,
    $Res Function(_$AchievementImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Achievement
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = null,
    Object? title = null,
    Object? category = null,
    Object? achievementDate = freezed,
    Object? notes = freezed,
    Object? evidenceLink = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(
      _$AchievementImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        userId: null == userId
            ? _value.userId
            : userId // ignore: cast_nullable_to_non_nullable
                  as String,
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        category: null == category
            ? _value.category
            : category // ignore: cast_nullable_to_non_nullable
                  as AchievementCategory,
        achievementDate: freezed == achievementDate
            ? _value.achievementDate
            : achievementDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        notes: freezed == notes
            ? _value.notes
            : notes // ignore: cast_nullable_to_non_nullable
                  as String?,
        evidenceLink: freezed == evidenceLink
            ? _value.evidenceLink
            : evidenceLink // ignore: cast_nullable_to_non_nullable
                  as String?,
        createdAt: freezed == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        updatedAt: freezed == updatedAt
            ? _value.updatedAt
            : updatedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
      ),
    );
  }
}

/// @nodoc

class _$AchievementImpl extends _Achievement {
  const _$AchievementImpl({
    required this.id,
    required this.userId,
    required this.title,
    required this.category,
    this.achievementDate,
    this.notes,
    this.evidenceLink,
    this.createdAt,
    this.updatedAt,
  }) : super._();

  @override
  final String id;
  @override
  final String userId;
  @override
  final String title;
  @override
  final AchievementCategory category;
  @override
  final DateTime? achievementDate;
  @override
  final String? notes;
  @override
  final String? evidenceLink;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;

  @override
  String toString() {
    return 'Achievement(id: $id, userId: $userId, title: $title, category: $category, achievementDate: $achievementDate, notes: $notes, evidenceLink: $evidenceLink, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AchievementImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.achievementDate, achievementDate) ||
                other.achievementDate == achievementDate) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.evidenceLink, evidenceLink) ||
                other.evidenceLink == evidenceLink) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    userId,
    title,
    category,
    achievementDate,
    notes,
    evidenceLink,
    createdAt,
    updatedAt,
  );

  /// Create a copy of Achievement
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AchievementImplCopyWith<_$AchievementImpl> get copyWith =>
      __$$AchievementImplCopyWithImpl<_$AchievementImpl>(this, _$identity);
}

abstract class _Achievement extends Achievement {
  const factory _Achievement({
    required final String id,
    required final String userId,
    required final String title,
    required final AchievementCategory category,
    final DateTime? achievementDate,
    final String? notes,
    final String? evidenceLink,
    final DateTime? createdAt,
    final DateTime? updatedAt,
  }) = _$AchievementImpl;
  const _Achievement._() : super._();

  @override
  String get id;
  @override
  String get userId;
  @override
  String get title;
  @override
  AchievementCategory get category;
  @override
  DateTime? get achievementDate;
  @override
  String? get notes;
  @override
  String? get evidenceLink;
  @override
  DateTime? get createdAt;
  @override
  DateTime? get updatedAt;

  /// Create a copy of Achievement
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AchievementImplCopyWith<_$AchievementImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$CreateAchievementRequest {
  String get title => throw _privateConstructorUsedError;
  AchievementCategory get category => throw _privateConstructorUsedError;
  DateTime? get achievementDate => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;
  String? get evidenceLink => throw _privateConstructorUsedError;

  /// Create a copy of CreateAchievementRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CreateAchievementRequestCopyWith<CreateAchievementRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CreateAchievementRequestCopyWith<$Res> {
  factory $CreateAchievementRequestCopyWith(
    CreateAchievementRequest value,
    $Res Function(CreateAchievementRequest) then,
  ) = _$CreateAchievementRequestCopyWithImpl<$Res, CreateAchievementRequest>;
  @useResult
  $Res call({
    String title,
    AchievementCategory category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
  });
}

/// @nodoc
class _$CreateAchievementRequestCopyWithImpl<
  $Res,
  $Val extends CreateAchievementRequest
>
    implements $CreateAchievementRequestCopyWith<$Res> {
  _$CreateAchievementRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CreateAchievementRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = null,
    Object? category = null,
    Object? achievementDate = freezed,
    Object? notes = freezed,
    Object? evidenceLink = freezed,
  }) {
    return _then(
      _value.copyWith(
            title: null == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String,
            category: null == category
                ? _value.category
                : category // ignore: cast_nullable_to_non_nullable
                      as AchievementCategory,
            achievementDate: freezed == achievementDate
                ? _value.achievementDate
                : achievementDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            notes: freezed == notes
                ? _value.notes
                : notes // ignore: cast_nullable_to_non_nullable
                      as String?,
            evidenceLink: freezed == evidenceLink
                ? _value.evidenceLink
                : evidenceLink // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$CreateAchievementRequestImplCopyWith<$Res>
    implements $CreateAchievementRequestCopyWith<$Res> {
  factory _$$CreateAchievementRequestImplCopyWith(
    _$CreateAchievementRequestImpl value,
    $Res Function(_$CreateAchievementRequestImpl) then,
  ) = __$$CreateAchievementRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String title,
    AchievementCategory category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
  });
}

/// @nodoc
class __$$CreateAchievementRequestImplCopyWithImpl<$Res>
    extends
        _$CreateAchievementRequestCopyWithImpl<
          $Res,
          _$CreateAchievementRequestImpl
        >
    implements _$$CreateAchievementRequestImplCopyWith<$Res> {
  __$$CreateAchievementRequestImplCopyWithImpl(
    _$CreateAchievementRequestImpl _value,
    $Res Function(_$CreateAchievementRequestImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of CreateAchievementRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = null,
    Object? category = null,
    Object? achievementDate = freezed,
    Object? notes = freezed,
    Object? evidenceLink = freezed,
  }) {
    return _then(
      _$CreateAchievementRequestImpl(
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        category: null == category
            ? _value.category
            : category // ignore: cast_nullable_to_non_nullable
                  as AchievementCategory,
        achievementDate: freezed == achievementDate
            ? _value.achievementDate
            : achievementDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        notes: freezed == notes
            ? _value.notes
            : notes // ignore: cast_nullable_to_non_nullable
                  as String?,
        evidenceLink: freezed == evidenceLink
            ? _value.evidenceLink
            : evidenceLink // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$CreateAchievementRequestImpl extends _CreateAchievementRequest {
  const _$CreateAchievementRequestImpl({
    required this.title,
    required this.category,
    this.achievementDate,
    this.notes,
    this.evidenceLink,
  }) : super._();

  @override
  final String title;
  @override
  final AchievementCategory category;
  @override
  final DateTime? achievementDate;
  @override
  final String? notes;
  @override
  final String? evidenceLink;

  @override
  String toString() {
    return 'CreateAchievementRequest(title: $title, category: $category, achievementDate: $achievementDate, notes: $notes, evidenceLink: $evidenceLink)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CreateAchievementRequestImpl &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.achievementDate, achievementDate) ||
                other.achievementDate == achievementDate) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.evidenceLink, evidenceLink) ||
                other.evidenceLink == evidenceLink));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    title,
    category,
    achievementDate,
    notes,
    evidenceLink,
  );

  /// Create a copy of CreateAchievementRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CreateAchievementRequestImplCopyWith<_$CreateAchievementRequestImpl>
  get copyWith =>
      __$$CreateAchievementRequestImplCopyWithImpl<
        _$CreateAchievementRequestImpl
      >(this, _$identity);
}

abstract class _CreateAchievementRequest extends CreateAchievementRequest {
  const factory _CreateAchievementRequest({
    required final String title,
    required final AchievementCategory category,
    final DateTime? achievementDate,
    final String? notes,
    final String? evidenceLink,
  }) = _$CreateAchievementRequestImpl;
  const _CreateAchievementRequest._() : super._();

  @override
  String get title;
  @override
  AchievementCategory get category;
  @override
  DateTime? get achievementDate;
  @override
  String? get notes;
  @override
  String? get evidenceLink;

  /// Create a copy of CreateAchievementRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CreateAchievementRequestImplCopyWith<_$CreateAchievementRequestImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$UpdateAchievementRequest {
  String? get title => throw _privateConstructorUsedError;
  AchievementCategory? get category => throw _privateConstructorUsedError;
  DateTime? get achievementDate => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;
  String? get evidenceLink => throw _privateConstructorUsedError;

  /// Create a copy of UpdateAchievementRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UpdateAchievementRequestCopyWith<UpdateAchievementRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UpdateAchievementRequestCopyWith<$Res> {
  factory $UpdateAchievementRequestCopyWith(
    UpdateAchievementRequest value,
    $Res Function(UpdateAchievementRequest) then,
  ) = _$UpdateAchievementRequestCopyWithImpl<$Res, UpdateAchievementRequest>;
  @useResult
  $Res call({
    String? title,
    AchievementCategory? category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
  });
}

/// @nodoc
class _$UpdateAchievementRequestCopyWithImpl<
  $Res,
  $Val extends UpdateAchievementRequest
>
    implements $UpdateAchievementRequestCopyWith<$Res> {
  _$UpdateAchievementRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UpdateAchievementRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = freezed,
    Object? category = freezed,
    Object? achievementDate = freezed,
    Object? notes = freezed,
    Object? evidenceLink = freezed,
  }) {
    return _then(
      _value.copyWith(
            title: freezed == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String?,
            category: freezed == category
                ? _value.category
                : category // ignore: cast_nullable_to_non_nullable
                      as AchievementCategory?,
            achievementDate: freezed == achievementDate
                ? _value.achievementDate
                : achievementDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            notes: freezed == notes
                ? _value.notes
                : notes // ignore: cast_nullable_to_non_nullable
                      as String?,
            evidenceLink: freezed == evidenceLink
                ? _value.evidenceLink
                : evidenceLink // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$UpdateAchievementRequestImplCopyWith<$Res>
    implements $UpdateAchievementRequestCopyWith<$Res> {
  factory _$$UpdateAchievementRequestImplCopyWith(
    _$UpdateAchievementRequestImpl value,
    $Res Function(_$UpdateAchievementRequestImpl) then,
  ) = __$$UpdateAchievementRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String? title,
    AchievementCategory? category,
    DateTime? achievementDate,
    String? notes,
    String? evidenceLink,
  });
}

/// @nodoc
class __$$UpdateAchievementRequestImplCopyWithImpl<$Res>
    extends
        _$UpdateAchievementRequestCopyWithImpl<
          $Res,
          _$UpdateAchievementRequestImpl
        >
    implements _$$UpdateAchievementRequestImplCopyWith<$Res> {
  __$$UpdateAchievementRequestImplCopyWithImpl(
    _$UpdateAchievementRequestImpl _value,
    $Res Function(_$UpdateAchievementRequestImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of UpdateAchievementRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = freezed,
    Object? category = freezed,
    Object? achievementDate = freezed,
    Object? notes = freezed,
    Object? evidenceLink = freezed,
  }) {
    return _then(
      _$UpdateAchievementRequestImpl(
        title: freezed == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String?,
        category: freezed == category
            ? _value.category
            : category // ignore: cast_nullable_to_non_nullable
                  as AchievementCategory?,
        achievementDate: freezed == achievementDate
            ? _value.achievementDate
            : achievementDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        notes: freezed == notes
            ? _value.notes
            : notes // ignore: cast_nullable_to_non_nullable
                  as String?,
        evidenceLink: freezed == evidenceLink
            ? _value.evidenceLink
            : evidenceLink // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$UpdateAchievementRequestImpl extends _UpdateAchievementRequest {
  const _$UpdateAchievementRequestImpl({
    this.title,
    this.category,
    this.achievementDate,
    this.notes,
    this.evidenceLink,
  }) : super._();

  @override
  final String? title;
  @override
  final AchievementCategory? category;
  @override
  final DateTime? achievementDate;
  @override
  final String? notes;
  @override
  final String? evidenceLink;

  @override
  String toString() {
    return 'UpdateAchievementRequest(title: $title, category: $category, achievementDate: $achievementDate, notes: $notes, evidenceLink: $evidenceLink)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UpdateAchievementRequestImpl &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.achievementDate, achievementDate) ||
                other.achievementDate == achievementDate) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.evidenceLink, evidenceLink) ||
                other.evidenceLink == evidenceLink));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    title,
    category,
    achievementDate,
    notes,
    evidenceLink,
  );

  /// Create a copy of UpdateAchievementRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UpdateAchievementRequestImplCopyWith<_$UpdateAchievementRequestImpl>
  get copyWith =>
      __$$UpdateAchievementRequestImplCopyWithImpl<
        _$UpdateAchievementRequestImpl
      >(this, _$identity);
}

abstract class _UpdateAchievementRequest extends UpdateAchievementRequest {
  const factory _UpdateAchievementRequest({
    final String? title,
    final AchievementCategory? category,
    final DateTime? achievementDate,
    final String? notes,
    final String? evidenceLink,
  }) = _$UpdateAchievementRequestImpl;
  const _UpdateAchievementRequest._() : super._();

  @override
  String? get title;
  @override
  AchievementCategory? get category;
  @override
  DateTime? get achievementDate;
  @override
  String? get notes;
  @override
  String? get evidenceLink;

  /// Create a copy of UpdateAchievementRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UpdateAchievementRequestImplCopyWith<_$UpdateAchievementRequestImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$AchievementsListResponse {
  List<Achievement> get achievements => throw _privateConstructorUsedError;
  int get total => throw _privateConstructorUsedError;

  /// Create a copy of AchievementsListResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AchievementsListResponseCopyWith<AchievementsListResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AchievementsListResponseCopyWith<$Res> {
  factory $AchievementsListResponseCopyWith(
    AchievementsListResponse value,
    $Res Function(AchievementsListResponse) then,
  ) = _$AchievementsListResponseCopyWithImpl<$Res, AchievementsListResponse>;
  @useResult
  $Res call({List<Achievement> achievements, int total});
}

/// @nodoc
class _$AchievementsListResponseCopyWithImpl<
  $Res,
  $Val extends AchievementsListResponse
>
    implements $AchievementsListResponseCopyWith<$Res> {
  _$AchievementsListResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AchievementsListResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? achievements = null, Object? total = null}) {
    return _then(
      _value.copyWith(
            achievements: null == achievements
                ? _value.achievements
                : achievements // ignore: cast_nullable_to_non_nullable
                      as List<Achievement>,
            total: null == total
                ? _value.total
                : total // ignore: cast_nullable_to_non_nullable
                      as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$AchievementsListResponseImplCopyWith<$Res>
    implements $AchievementsListResponseCopyWith<$Res> {
  factory _$$AchievementsListResponseImplCopyWith(
    _$AchievementsListResponseImpl value,
    $Res Function(_$AchievementsListResponseImpl) then,
  ) = __$$AchievementsListResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<Achievement> achievements, int total});
}

/// @nodoc
class __$$AchievementsListResponseImplCopyWithImpl<$Res>
    extends
        _$AchievementsListResponseCopyWithImpl<
          $Res,
          _$AchievementsListResponseImpl
        >
    implements _$$AchievementsListResponseImplCopyWith<$Res> {
  __$$AchievementsListResponseImplCopyWithImpl(
    _$AchievementsListResponseImpl _value,
    $Res Function(_$AchievementsListResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AchievementsListResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? achievements = null, Object? total = null}) {
    return _then(
      _$AchievementsListResponseImpl(
        achievements: null == achievements
            ? _value._achievements
            : achievements // ignore: cast_nullable_to_non_nullable
                  as List<Achievement>,
        total: null == total
            ? _value.total
            : total // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc

class _$AchievementsListResponseImpl implements _AchievementsListResponse {
  const _$AchievementsListResponseImpl({
    final List<Achievement> achievements = const [],
    this.total = 0,
  }) : _achievements = achievements;

  final List<Achievement> _achievements;
  @override
  @JsonKey()
  List<Achievement> get achievements {
    if (_achievements is EqualUnmodifiableListView) return _achievements;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_achievements);
  }

  @override
  @JsonKey()
  final int total;

  @override
  String toString() {
    return 'AchievementsListResponse(achievements: $achievements, total: $total)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AchievementsListResponseImpl &&
            const DeepCollectionEquality().equals(
              other._achievements,
              _achievements,
            ) &&
            (identical(other.total, total) || other.total == total));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_achievements),
    total,
  );

  /// Create a copy of AchievementsListResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AchievementsListResponseImplCopyWith<_$AchievementsListResponseImpl>
  get copyWith =>
      __$$AchievementsListResponseImplCopyWithImpl<
        _$AchievementsListResponseImpl
      >(this, _$identity);
}

abstract class _AchievementsListResponse implements AchievementsListResponse {
  const factory _AchievementsListResponse({
    final List<Achievement> achievements,
    final int total,
  }) = _$AchievementsListResponseImpl;

  @override
  List<Achievement> get achievements;
  @override
  int get total;

  /// Create a copy of AchievementsListResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AchievementsListResponseImplCopyWith<_$AchievementsListResponseImpl>
  get copyWith => throw _privateConstructorUsedError;
}
