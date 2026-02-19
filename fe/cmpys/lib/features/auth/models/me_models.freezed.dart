// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'me_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Me {
  String get id => throw _privateConstructorUsedError;
  String get email => throw _privateConstructorUsedError;
  String? get fullName => throw _privateConstructorUsedError;
  DateTime? get birthDate => throw _privateConstructorUsedError;

  /// Backend uses 'focusAreas', we map it to 'interests' internally
  List<String> get interests => throw _privateConstructorUsedError;
  String? get timezone => throw _privateConstructorUsedError;
  String? get avatarUrl => throw _privateConstructorUsedError;
  DateTime? get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  /// Create a copy of Me
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MeCopyWith<Me> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MeCopyWith<$Res> {
  factory $MeCopyWith(Me value, $Res Function(Me) then) =
      _$MeCopyWithImpl<$Res, Me>;
  @useResult
  $Res call({
    String id,
    String email,
    String? fullName,
    DateTime? birthDate,
    List<String> interests,
    String? timezone,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
}

/// @nodoc
class _$MeCopyWithImpl<$Res, $Val extends Me> implements $MeCopyWith<$Res> {
  _$MeCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Me
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? email = null,
    Object? fullName = freezed,
    Object? birthDate = freezed,
    Object? interests = null,
    Object? timezone = freezed,
    Object? avatarUrl = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            email: null == email
                ? _value.email
                : email // ignore: cast_nullable_to_non_nullable
                      as String,
            fullName: freezed == fullName
                ? _value.fullName
                : fullName // ignore: cast_nullable_to_non_nullable
                      as String?,
            birthDate: freezed == birthDate
                ? _value.birthDate
                : birthDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            interests: null == interests
                ? _value.interests
                : interests // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            timezone: freezed == timezone
                ? _value.timezone
                : timezone // ignore: cast_nullable_to_non_nullable
                      as String?,
            avatarUrl: freezed == avatarUrl
                ? _value.avatarUrl
                : avatarUrl // ignore: cast_nullable_to_non_nullable
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
abstract class _$$MeImplCopyWith<$Res> implements $MeCopyWith<$Res> {
  factory _$$MeImplCopyWith(_$MeImpl value, $Res Function(_$MeImpl) then) =
      __$$MeImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String email,
    String? fullName,
    DateTime? birthDate,
    List<String> interests,
    String? timezone,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
}

/// @nodoc
class __$$MeImplCopyWithImpl<$Res> extends _$MeCopyWithImpl<$Res, _$MeImpl>
    implements _$$MeImplCopyWith<$Res> {
  __$$MeImplCopyWithImpl(_$MeImpl _value, $Res Function(_$MeImpl) _then)
    : super(_value, _then);

  /// Create a copy of Me
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? email = null,
    Object? fullName = freezed,
    Object? birthDate = freezed,
    Object? interests = null,
    Object? timezone = freezed,
    Object? avatarUrl = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(
      _$MeImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        email: null == email
            ? _value.email
            : email // ignore: cast_nullable_to_non_nullable
                  as String,
        fullName: freezed == fullName
            ? _value.fullName
            : fullName // ignore: cast_nullable_to_non_nullable
                  as String?,
        birthDate: freezed == birthDate
            ? _value.birthDate
            : birthDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        interests: null == interests
            ? _value._interests
            : interests // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        timezone: freezed == timezone
            ? _value.timezone
            : timezone // ignore: cast_nullable_to_non_nullable
                  as String?,
        avatarUrl: freezed == avatarUrl
            ? _value.avatarUrl
            : avatarUrl // ignore: cast_nullable_to_non_nullable
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

class _$MeImpl extends _Me {
  const _$MeImpl({
    required this.id,
    required this.email,
    this.fullName,
    this.birthDate,
    final List<String> interests = const [],
    this.timezone,
    this.avatarUrl,
    this.createdAt,
    this.updatedAt,
  }) : _interests = interests,
       super._();

  @override
  final String id;
  @override
  final String email;
  @override
  final String? fullName;
  @override
  final DateTime? birthDate;

  /// Backend uses 'focusAreas', we map it to 'interests' internally
  final List<String> _interests;

  /// Backend uses 'focusAreas', we map it to 'interests' internally
  @override
  @JsonKey()
  List<String> get interests {
    if (_interests is EqualUnmodifiableListView) return _interests;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_interests);
  }

  @override
  final String? timezone;
  @override
  final String? avatarUrl;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;

  @override
  String toString() {
    return 'Me(id: $id, email: $email, fullName: $fullName, birthDate: $birthDate, interests: $interests, timezone: $timezone, avatarUrl: $avatarUrl, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MeImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.fullName, fullName) ||
                other.fullName == fullName) &&
            (identical(other.birthDate, birthDate) ||
                other.birthDate == birthDate) &&
            const DeepCollectionEquality().equals(
              other._interests,
              _interests,
            ) &&
            (identical(other.timezone, timezone) ||
                other.timezone == timezone) &&
            (identical(other.avatarUrl, avatarUrl) ||
                other.avatarUrl == avatarUrl) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    email,
    fullName,
    birthDate,
    const DeepCollectionEquality().hash(_interests),
    timezone,
    avatarUrl,
    createdAt,
    updatedAt,
  );

  /// Create a copy of Me
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MeImplCopyWith<_$MeImpl> get copyWith =>
      __$$MeImplCopyWithImpl<_$MeImpl>(this, _$identity);
}

abstract class _Me extends Me {
  const factory _Me({
    required final String id,
    required final String email,
    final String? fullName,
    final DateTime? birthDate,
    final List<String> interests,
    final String? timezone,
    final String? avatarUrl,
    final DateTime? createdAt,
    final DateTime? updatedAt,
  }) = _$MeImpl;
  const _Me._() : super._();

  @override
  String get id;
  @override
  String get email;
  @override
  String? get fullName;
  @override
  DateTime? get birthDate;

  /// Backend uses 'focusAreas', we map it to 'interests' internally
  @override
  List<String> get interests;
  @override
  String? get timezone;
  @override
  String? get avatarUrl;
  @override
  DateTime? get createdAt;
  @override
  DateTime? get updatedAt;

  /// Create a copy of Me
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MeImplCopyWith<_$MeImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$UpdateMeRequest {
  String? get fullName => throw _privateConstructorUsedError;
  DateTime? get birthDate => throw _privateConstructorUsedError;

  /// Internally called 'interests', sent to backend as 'focusAreas'
  List<String>? get interests => throw _privateConstructorUsedError;
  String? get timezone => throw _privateConstructorUsedError;

  /// Create a copy of UpdateMeRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UpdateMeRequestCopyWith<UpdateMeRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UpdateMeRequestCopyWith<$Res> {
  factory $UpdateMeRequestCopyWith(
    UpdateMeRequest value,
    $Res Function(UpdateMeRequest) then,
  ) = _$UpdateMeRequestCopyWithImpl<$Res, UpdateMeRequest>;
  @useResult
  $Res call({
    String? fullName,
    DateTime? birthDate,
    List<String>? interests,
    String? timezone,
  });
}

/// @nodoc
class _$UpdateMeRequestCopyWithImpl<$Res, $Val extends UpdateMeRequest>
    implements $UpdateMeRequestCopyWith<$Res> {
  _$UpdateMeRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UpdateMeRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? fullName = freezed,
    Object? birthDate = freezed,
    Object? interests = freezed,
    Object? timezone = freezed,
  }) {
    return _then(
      _value.copyWith(
            fullName: freezed == fullName
                ? _value.fullName
                : fullName // ignore: cast_nullable_to_non_nullable
                      as String?,
            birthDate: freezed == birthDate
                ? _value.birthDate
                : birthDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            interests: freezed == interests
                ? _value.interests
                : interests // ignore: cast_nullable_to_non_nullable
                      as List<String>?,
            timezone: freezed == timezone
                ? _value.timezone
                : timezone // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$UpdateMeRequestImplCopyWith<$Res>
    implements $UpdateMeRequestCopyWith<$Res> {
  factory _$$UpdateMeRequestImplCopyWith(
    _$UpdateMeRequestImpl value,
    $Res Function(_$UpdateMeRequestImpl) then,
  ) = __$$UpdateMeRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String? fullName,
    DateTime? birthDate,
    List<String>? interests,
    String? timezone,
  });
}

/// @nodoc
class __$$UpdateMeRequestImplCopyWithImpl<$Res>
    extends _$UpdateMeRequestCopyWithImpl<$Res, _$UpdateMeRequestImpl>
    implements _$$UpdateMeRequestImplCopyWith<$Res> {
  __$$UpdateMeRequestImplCopyWithImpl(
    _$UpdateMeRequestImpl _value,
    $Res Function(_$UpdateMeRequestImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of UpdateMeRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? fullName = freezed,
    Object? birthDate = freezed,
    Object? interests = freezed,
    Object? timezone = freezed,
  }) {
    return _then(
      _$UpdateMeRequestImpl(
        fullName: freezed == fullName
            ? _value.fullName
            : fullName // ignore: cast_nullable_to_non_nullable
                  as String?,
        birthDate: freezed == birthDate
            ? _value.birthDate
            : birthDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        interests: freezed == interests
            ? _value._interests
            : interests // ignore: cast_nullable_to_non_nullable
                  as List<String>?,
        timezone: freezed == timezone
            ? _value.timezone
            : timezone // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$UpdateMeRequestImpl extends _UpdateMeRequest {
  const _$UpdateMeRequestImpl({
    this.fullName,
    this.birthDate,
    final List<String>? interests,
    this.timezone,
  }) : _interests = interests,
       super._();

  @override
  final String? fullName;
  @override
  final DateTime? birthDate;

  /// Internally called 'interests', sent to backend as 'focusAreas'
  final List<String>? _interests;

  /// Internally called 'interests', sent to backend as 'focusAreas'
  @override
  List<String>? get interests {
    final value = _interests;
    if (value == null) return null;
    if (_interests is EqualUnmodifiableListView) return _interests;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  final String? timezone;

  @override
  String toString() {
    return 'UpdateMeRequest(fullName: $fullName, birthDate: $birthDate, interests: $interests, timezone: $timezone)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UpdateMeRequestImpl &&
            (identical(other.fullName, fullName) ||
                other.fullName == fullName) &&
            (identical(other.birthDate, birthDate) ||
                other.birthDate == birthDate) &&
            const DeepCollectionEquality().equals(
              other._interests,
              _interests,
            ) &&
            (identical(other.timezone, timezone) ||
                other.timezone == timezone));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    fullName,
    birthDate,
    const DeepCollectionEquality().hash(_interests),
    timezone,
  );

  /// Create a copy of UpdateMeRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UpdateMeRequestImplCopyWith<_$UpdateMeRequestImpl> get copyWith =>
      __$$UpdateMeRequestImplCopyWithImpl<_$UpdateMeRequestImpl>(
        this,
        _$identity,
      );
}

abstract class _UpdateMeRequest extends UpdateMeRequest {
  const factory _UpdateMeRequest({
    final String? fullName,
    final DateTime? birthDate,
    final List<String>? interests,
    final String? timezone,
  }) = _$UpdateMeRequestImpl;
  const _UpdateMeRequest._() : super._();

  @override
  String? get fullName;
  @override
  DateTime? get birthDate;

  /// Internally called 'interests', sent to backend as 'focusAreas'
  @override
  List<String>? get interests;
  @override
  String? get timezone;

  /// Create a copy of UpdateMeRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UpdateMeRequestImplCopyWith<_$UpdateMeRequestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
