// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'daily_insight.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

DailyInsight _$DailyInsightFromJson(Map<String, dynamic> json) {
  return _DailyInsight.fromJson(json);
}

/// @nodoc
mixin _$DailyInsight {
  String get title => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  String get category => throw _privateConstructorUsedError;
  String? get idolName => throw _privateConstructorUsedError;

  /// Serializes this DailyInsight to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DailyInsight
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DailyInsightCopyWith<DailyInsight> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DailyInsightCopyWith<$Res> {
  factory $DailyInsightCopyWith(
    DailyInsight value,
    $Res Function(DailyInsight) then,
  ) = _$DailyInsightCopyWithImpl<$Res, DailyInsight>;
  @useResult
  $Res call({String title, String content, String category, String? idolName});
}

/// @nodoc
class _$DailyInsightCopyWithImpl<$Res, $Val extends DailyInsight>
    implements $DailyInsightCopyWith<$Res> {
  _$DailyInsightCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DailyInsight
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = null,
    Object? content = null,
    Object? category = null,
    Object? idolName = freezed,
  }) {
    return _then(
      _value.copyWith(
            title: null == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String,
            content: null == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                      as String,
            category: null == category
                ? _value.category
                : category // ignore: cast_nullable_to_non_nullable
                      as String,
            idolName: freezed == idolName
                ? _value.idolName
                : idolName // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$DailyInsightImplCopyWith<$Res>
    implements $DailyInsightCopyWith<$Res> {
  factory _$$DailyInsightImplCopyWith(
    _$DailyInsightImpl value,
    $Res Function(_$DailyInsightImpl) then,
  ) = __$$DailyInsightImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String title, String content, String category, String? idolName});
}

/// @nodoc
class __$$DailyInsightImplCopyWithImpl<$Res>
    extends _$DailyInsightCopyWithImpl<$Res, _$DailyInsightImpl>
    implements _$$DailyInsightImplCopyWith<$Res> {
  __$$DailyInsightImplCopyWithImpl(
    _$DailyInsightImpl _value,
    $Res Function(_$DailyInsightImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of DailyInsight
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = null,
    Object? content = null,
    Object? category = null,
    Object? idolName = freezed,
  }) {
    return _then(
      _$DailyInsightImpl(
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        content: null == content
            ? _value.content
            : content // ignore: cast_nullable_to_non_nullable
                  as String,
        category: null == category
            ? _value.category
            : category // ignore: cast_nullable_to_non_nullable
                  as String,
        idolName: freezed == idolName
            ? _value.idolName
            : idolName // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$DailyInsightImpl implements _DailyInsight {
  const _$DailyInsightImpl({
    required this.title,
    required this.content,
    required this.category,
    this.idolName,
  });

  factory _$DailyInsightImpl.fromJson(Map<String, dynamic> json) =>
      _$$DailyInsightImplFromJson(json);

  @override
  final String title;
  @override
  final String content;
  @override
  final String category;
  @override
  final String? idolName;

  @override
  String toString() {
    return 'DailyInsight(title: $title, content: $content, category: $category, idolName: $idolName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DailyInsightImpl &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.idolName, idolName) ||
                other.idolName == idolName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, title, content, category, idolName);

  /// Create a copy of DailyInsight
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DailyInsightImplCopyWith<_$DailyInsightImpl> get copyWith =>
      __$$DailyInsightImplCopyWithImpl<_$DailyInsightImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DailyInsightImplToJson(this);
  }
}

abstract class _DailyInsight implements DailyInsight {
  const factory _DailyInsight({
    required final String title,
    required final String content,
    required final String category,
    final String? idolName,
  }) = _$DailyInsightImpl;

  factory _DailyInsight.fromJson(Map<String, dynamic> json) =
      _$DailyInsightImpl.fromJson;

  @override
  String get title;
  @override
  String get content;
  @override
  String get category;
  @override
  String? get idolName;

  /// Create a copy of DailyInsight
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DailyInsightImplCopyWith<_$DailyInsightImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
