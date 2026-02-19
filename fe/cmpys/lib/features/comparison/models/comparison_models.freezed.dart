// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'comparison_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$CategoryBreakdown {
  String get category => throw _privateConstructorUsedError;
  double get userScore => throw _privateConstructorUsedError;
  double get idolScore => throw _privateConstructorUsedError;
  int get userCount => throw _privateConstructorUsedError;
  int get idolCount => throw _privateConstructorUsedError;
  double? get percentage => throw _privateConstructorUsedError;
  double? get percent => throw _privateConstructorUsedError;

  /// Create a copy of CategoryBreakdown
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CategoryBreakdownCopyWith<CategoryBreakdown> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CategoryBreakdownCopyWith<$Res> {
  factory $CategoryBreakdownCopyWith(
    CategoryBreakdown value,
    $Res Function(CategoryBreakdown) then,
  ) = _$CategoryBreakdownCopyWithImpl<$Res, CategoryBreakdown>;
  @useResult
  $Res call({
    String category,
    double userScore,
    double idolScore,
    int userCount,
    int idolCount,
    double? percentage,
    double? percent,
  });
}

/// @nodoc
class _$CategoryBreakdownCopyWithImpl<$Res, $Val extends CategoryBreakdown>
    implements $CategoryBreakdownCopyWith<$Res> {
  _$CategoryBreakdownCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CategoryBreakdown
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? category = null,
    Object? userScore = null,
    Object? idolScore = null,
    Object? userCount = null,
    Object? idolCount = null,
    Object? percentage = freezed,
    Object? percent = freezed,
  }) {
    return _then(
      _value.copyWith(
            category: null == category
                ? _value.category
                : category // ignore: cast_nullable_to_non_nullable
                      as String,
            userScore: null == userScore
                ? _value.userScore
                : userScore // ignore: cast_nullable_to_non_nullable
                      as double,
            idolScore: null == idolScore
                ? _value.idolScore
                : idolScore // ignore: cast_nullable_to_non_nullable
                      as double,
            userCount: null == userCount
                ? _value.userCount
                : userCount // ignore: cast_nullable_to_non_nullable
                      as int,
            idolCount: null == idolCount
                ? _value.idolCount
                : idolCount // ignore: cast_nullable_to_non_nullable
                      as int,
            percentage: freezed == percentage
                ? _value.percentage
                : percentage // ignore: cast_nullable_to_non_nullable
                      as double?,
            percent: freezed == percent
                ? _value.percent
                : percent // ignore: cast_nullable_to_non_nullable
                      as double?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$CategoryBreakdownImplCopyWith<$Res>
    implements $CategoryBreakdownCopyWith<$Res> {
  factory _$$CategoryBreakdownImplCopyWith(
    _$CategoryBreakdownImpl value,
    $Res Function(_$CategoryBreakdownImpl) then,
  ) = __$$CategoryBreakdownImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String category,
    double userScore,
    double idolScore,
    int userCount,
    int idolCount,
    double? percentage,
    double? percent,
  });
}

/// @nodoc
class __$$CategoryBreakdownImplCopyWithImpl<$Res>
    extends _$CategoryBreakdownCopyWithImpl<$Res, _$CategoryBreakdownImpl>
    implements _$$CategoryBreakdownImplCopyWith<$Res> {
  __$$CategoryBreakdownImplCopyWithImpl(
    _$CategoryBreakdownImpl _value,
    $Res Function(_$CategoryBreakdownImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of CategoryBreakdown
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? category = null,
    Object? userScore = null,
    Object? idolScore = null,
    Object? userCount = null,
    Object? idolCount = null,
    Object? percentage = freezed,
    Object? percent = freezed,
  }) {
    return _then(
      _$CategoryBreakdownImpl(
        category: null == category
            ? _value.category
            : category // ignore: cast_nullable_to_non_nullable
                  as String,
        userScore: null == userScore
            ? _value.userScore
            : userScore // ignore: cast_nullable_to_non_nullable
                  as double,
        idolScore: null == idolScore
            ? _value.idolScore
            : idolScore // ignore: cast_nullable_to_non_nullable
                  as double,
        userCount: null == userCount
            ? _value.userCount
            : userCount // ignore: cast_nullable_to_non_nullable
                  as int,
        idolCount: null == idolCount
            ? _value.idolCount
            : idolCount // ignore: cast_nullable_to_non_nullable
                  as int,
        percentage: freezed == percentage
            ? _value.percentage
            : percentage // ignore: cast_nullable_to_non_nullable
                  as double?,
        percent: freezed == percent
            ? _value.percent
            : percent // ignore: cast_nullable_to_non_nullable
                  as double?,
      ),
    );
  }
}

/// @nodoc

class _$CategoryBreakdownImpl implements _CategoryBreakdown {
  const _$CategoryBreakdownImpl({
    required this.category,
    this.userScore = 0,
    this.idolScore = 0,
    this.userCount = 0,
    this.idolCount = 0,
    this.percentage,
    this.percent,
  });

  @override
  final String category;
  @override
  @JsonKey()
  final double userScore;
  @override
  @JsonKey()
  final double idolScore;
  @override
  @JsonKey()
  final int userCount;
  @override
  @JsonKey()
  final int idolCount;
  @override
  final double? percentage;
  @override
  final double? percent;

  @override
  String toString() {
    return 'CategoryBreakdown(category: $category, userScore: $userScore, idolScore: $idolScore, userCount: $userCount, idolCount: $idolCount, percentage: $percentage, percent: $percent)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CategoryBreakdownImpl &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.userScore, userScore) ||
                other.userScore == userScore) &&
            (identical(other.idolScore, idolScore) ||
                other.idolScore == idolScore) &&
            (identical(other.userCount, userCount) ||
                other.userCount == userCount) &&
            (identical(other.idolCount, idolCount) ||
                other.idolCount == idolCount) &&
            (identical(other.percentage, percentage) ||
                other.percentage == percentage) &&
            (identical(other.percent, percent) || other.percent == percent));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    category,
    userScore,
    idolScore,
    userCount,
    idolCount,
    percentage,
    percent,
  );

  /// Create a copy of CategoryBreakdown
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CategoryBreakdownImplCopyWith<_$CategoryBreakdownImpl> get copyWith =>
      __$$CategoryBreakdownImplCopyWithImpl<_$CategoryBreakdownImpl>(
        this,
        _$identity,
      );
}

abstract class _CategoryBreakdown implements CategoryBreakdown {
  const factory _CategoryBreakdown({
    required final String category,
    final double userScore,
    final double idolScore,
    final int userCount,
    final int idolCount,
    final double? percentage,
    final double? percent,
  }) = _$CategoryBreakdownImpl;

  @override
  String get category;
  @override
  double get userScore;
  @override
  double get idolScore;
  @override
  int get userCount;
  @override
  int get idolCount;
  @override
  double? get percentage;
  @override
  double? get percent;

  /// Create a copy of CategoryBreakdown
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CategoryBreakdownImplCopyWith<_$CategoryBreakdownImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ComparisonStrength {
  String get category => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  String? get achievementId => throw _privateConstructorUsedError;
  String? get achievementTitle => throw _privateConstructorUsedError;

  /// Create a copy of ComparisonStrength
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ComparisonStrengthCopyWith<ComparisonStrength> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ComparisonStrengthCopyWith<$Res> {
  factory $ComparisonStrengthCopyWith(
    ComparisonStrength value,
    $Res Function(ComparisonStrength) then,
  ) = _$ComparisonStrengthCopyWithImpl<$Res, ComparisonStrength>;
  @useResult
  $Res call({
    String category,
    String description,
    String? achievementId,
    String? achievementTitle,
  });
}

/// @nodoc
class _$ComparisonStrengthCopyWithImpl<$Res, $Val extends ComparisonStrength>
    implements $ComparisonStrengthCopyWith<$Res> {
  _$ComparisonStrengthCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ComparisonStrength
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? category = null,
    Object? description = null,
    Object? achievementId = freezed,
    Object? achievementTitle = freezed,
  }) {
    return _then(
      _value.copyWith(
            category: null == category
                ? _value.category
                : category // ignore: cast_nullable_to_non_nullable
                      as String,
            description: null == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String,
            achievementId: freezed == achievementId
                ? _value.achievementId
                : achievementId // ignore: cast_nullable_to_non_nullable
                      as String?,
            achievementTitle: freezed == achievementTitle
                ? _value.achievementTitle
                : achievementTitle // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ComparisonStrengthImplCopyWith<$Res>
    implements $ComparisonStrengthCopyWith<$Res> {
  factory _$$ComparisonStrengthImplCopyWith(
    _$ComparisonStrengthImpl value,
    $Res Function(_$ComparisonStrengthImpl) then,
  ) = __$$ComparisonStrengthImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String category,
    String description,
    String? achievementId,
    String? achievementTitle,
  });
}

/// @nodoc
class __$$ComparisonStrengthImplCopyWithImpl<$Res>
    extends _$ComparisonStrengthCopyWithImpl<$Res, _$ComparisonStrengthImpl>
    implements _$$ComparisonStrengthImplCopyWith<$Res> {
  __$$ComparisonStrengthImplCopyWithImpl(
    _$ComparisonStrengthImpl _value,
    $Res Function(_$ComparisonStrengthImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ComparisonStrength
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? category = null,
    Object? description = null,
    Object? achievementId = freezed,
    Object? achievementTitle = freezed,
  }) {
    return _then(
      _$ComparisonStrengthImpl(
        category: null == category
            ? _value.category
            : category // ignore: cast_nullable_to_non_nullable
                  as String,
        description: null == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String,
        achievementId: freezed == achievementId
            ? _value.achievementId
            : achievementId // ignore: cast_nullable_to_non_nullable
                  as String?,
        achievementTitle: freezed == achievementTitle
            ? _value.achievementTitle
            : achievementTitle // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$ComparisonStrengthImpl implements _ComparisonStrength {
  const _$ComparisonStrengthImpl({
    required this.category,
    required this.description,
    this.achievementId,
    this.achievementTitle,
  });

  @override
  final String category;
  @override
  final String description;
  @override
  final String? achievementId;
  @override
  final String? achievementTitle;

  @override
  String toString() {
    return 'ComparisonStrength(category: $category, description: $description, achievementId: $achievementId, achievementTitle: $achievementTitle)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ComparisonStrengthImpl &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.achievementId, achievementId) ||
                other.achievementId == achievementId) &&
            (identical(other.achievementTitle, achievementTitle) ||
                other.achievementTitle == achievementTitle));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    category,
    description,
    achievementId,
    achievementTitle,
  );

  /// Create a copy of ComparisonStrength
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ComparisonStrengthImplCopyWith<_$ComparisonStrengthImpl> get copyWith =>
      __$$ComparisonStrengthImplCopyWithImpl<_$ComparisonStrengthImpl>(
        this,
        _$identity,
      );
}

abstract class _ComparisonStrength implements ComparisonStrength {
  const factory _ComparisonStrength({
    required final String category,
    required final String description,
    final String? achievementId,
    final String? achievementTitle,
  }) = _$ComparisonStrengthImpl;

  @override
  String get category;
  @override
  String get description;
  @override
  String? get achievementId;
  @override
  String? get achievementTitle;

  /// Create a copy of ComparisonStrength
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ComparisonStrengthImplCopyWith<_$ComparisonStrengthImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ComparisonGap {
  String get category => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  String? get milestoneId => throw _privateConstructorUsedError;
  String? get milestoneTitle => throw _privateConstructorUsedError;
  int? get idolAgeAtEvent => throw _privateConstructorUsedError;
  String? get suggestion => throw _privateConstructorUsedError;

  /// Create a copy of ComparisonGap
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ComparisonGapCopyWith<ComparisonGap> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ComparisonGapCopyWith<$Res> {
  factory $ComparisonGapCopyWith(
    ComparisonGap value,
    $Res Function(ComparisonGap) then,
  ) = _$ComparisonGapCopyWithImpl<$Res, ComparisonGap>;
  @useResult
  $Res call({
    String category,
    String description,
    String? milestoneId,
    String? milestoneTitle,
    int? idolAgeAtEvent,
    String? suggestion,
  });
}

/// @nodoc
class _$ComparisonGapCopyWithImpl<$Res, $Val extends ComparisonGap>
    implements $ComparisonGapCopyWith<$Res> {
  _$ComparisonGapCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ComparisonGap
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? category = null,
    Object? description = null,
    Object? milestoneId = freezed,
    Object? milestoneTitle = freezed,
    Object? idolAgeAtEvent = freezed,
    Object? suggestion = freezed,
  }) {
    return _then(
      _value.copyWith(
            category: null == category
                ? _value.category
                : category // ignore: cast_nullable_to_non_nullable
                      as String,
            description: null == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String,
            milestoneId: freezed == milestoneId
                ? _value.milestoneId
                : milestoneId // ignore: cast_nullable_to_non_nullable
                      as String?,
            milestoneTitle: freezed == milestoneTitle
                ? _value.milestoneTitle
                : milestoneTitle // ignore: cast_nullable_to_non_nullable
                      as String?,
            idolAgeAtEvent: freezed == idolAgeAtEvent
                ? _value.idolAgeAtEvent
                : idolAgeAtEvent // ignore: cast_nullable_to_non_nullable
                      as int?,
            suggestion: freezed == suggestion
                ? _value.suggestion
                : suggestion // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ComparisonGapImplCopyWith<$Res>
    implements $ComparisonGapCopyWith<$Res> {
  factory _$$ComparisonGapImplCopyWith(
    _$ComparisonGapImpl value,
    $Res Function(_$ComparisonGapImpl) then,
  ) = __$$ComparisonGapImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String category,
    String description,
    String? milestoneId,
    String? milestoneTitle,
    int? idolAgeAtEvent,
    String? suggestion,
  });
}

/// @nodoc
class __$$ComparisonGapImplCopyWithImpl<$Res>
    extends _$ComparisonGapCopyWithImpl<$Res, _$ComparisonGapImpl>
    implements _$$ComparisonGapImplCopyWith<$Res> {
  __$$ComparisonGapImplCopyWithImpl(
    _$ComparisonGapImpl _value,
    $Res Function(_$ComparisonGapImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ComparisonGap
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? category = null,
    Object? description = null,
    Object? milestoneId = freezed,
    Object? milestoneTitle = freezed,
    Object? idolAgeAtEvent = freezed,
    Object? suggestion = freezed,
  }) {
    return _then(
      _$ComparisonGapImpl(
        category: null == category
            ? _value.category
            : category // ignore: cast_nullable_to_non_nullable
                  as String,
        description: null == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String,
        milestoneId: freezed == milestoneId
            ? _value.milestoneId
            : milestoneId // ignore: cast_nullable_to_non_nullable
                  as String?,
        milestoneTitle: freezed == milestoneTitle
            ? _value.milestoneTitle
            : milestoneTitle // ignore: cast_nullable_to_non_nullable
                  as String?,
        idolAgeAtEvent: freezed == idolAgeAtEvent
            ? _value.idolAgeAtEvent
            : idolAgeAtEvent // ignore: cast_nullable_to_non_nullable
                  as int?,
        suggestion: freezed == suggestion
            ? _value.suggestion
            : suggestion // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$ComparisonGapImpl implements _ComparisonGap {
  const _$ComparisonGapImpl({
    required this.category,
    required this.description,
    this.milestoneId,
    this.milestoneTitle,
    this.idolAgeAtEvent,
    this.suggestion,
  });

  @override
  final String category;
  @override
  final String description;
  @override
  final String? milestoneId;
  @override
  final String? milestoneTitle;
  @override
  final int? idolAgeAtEvent;
  @override
  final String? suggestion;

  @override
  String toString() {
    return 'ComparisonGap(category: $category, description: $description, milestoneId: $milestoneId, milestoneTitle: $milestoneTitle, idolAgeAtEvent: $idolAgeAtEvent, suggestion: $suggestion)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ComparisonGapImpl &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.milestoneId, milestoneId) ||
                other.milestoneId == milestoneId) &&
            (identical(other.milestoneTitle, milestoneTitle) ||
                other.milestoneTitle == milestoneTitle) &&
            (identical(other.idolAgeAtEvent, idolAgeAtEvent) ||
                other.idolAgeAtEvent == idolAgeAtEvent) &&
            (identical(other.suggestion, suggestion) ||
                other.suggestion == suggestion));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    category,
    description,
    milestoneId,
    milestoneTitle,
    idolAgeAtEvent,
    suggestion,
  );

  /// Create a copy of ComparisonGap
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ComparisonGapImplCopyWith<_$ComparisonGapImpl> get copyWith =>
      __$$ComparisonGapImplCopyWithImpl<_$ComparisonGapImpl>(this, _$identity);
}

abstract class _ComparisonGap implements ComparisonGap {
  const factory _ComparisonGap({
    required final String category,
    required final String description,
    final String? milestoneId,
    final String? milestoneTitle,
    final int? idolAgeAtEvent,
    final String? suggestion,
  }) = _$ComparisonGapImpl;

  @override
  String get category;
  @override
  String get description;
  @override
  String? get milestoneId;
  @override
  String? get milestoneTitle;
  @override
  int? get idolAgeAtEvent;
  @override
  String? get suggestion;

  /// Create a copy of ComparisonGap
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ComparisonGapImplCopyWith<_$ComparisonGapImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$MissingMilestone {
  String? get id => throw _privateConstructorUsedError;
  String? get title => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  String? get category => throw _privateConstructorUsedError;
  int? get ageAtEvent => throw _privateConstructorUsedError;
  String? get eventDate => throw _privateConstructorUsedError;
  double? get importanceScore => throw _privateConstructorUsedError;

  /// Create a copy of MissingMilestone
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MissingMilestoneCopyWith<MissingMilestone> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MissingMilestoneCopyWith<$Res> {
  factory $MissingMilestoneCopyWith(
    MissingMilestone value,
    $Res Function(MissingMilestone) then,
  ) = _$MissingMilestoneCopyWithImpl<$Res, MissingMilestone>;
  @useResult
  $Res call({
    String? id,
    String? title,
    String? description,
    String? category,
    int? ageAtEvent,
    String? eventDate,
    double? importanceScore,
  });
}

/// @nodoc
class _$MissingMilestoneCopyWithImpl<$Res, $Val extends MissingMilestone>
    implements $MissingMilestoneCopyWith<$Res> {
  _$MissingMilestoneCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MissingMilestone
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? title = freezed,
    Object? description = freezed,
    Object? category = freezed,
    Object? ageAtEvent = freezed,
    Object? eventDate = freezed,
    Object? importanceScore = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: freezed == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String?,
            title: freezed == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String?,
            description: freezed == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String?,
            category: freezed == category
                ? _value.category
                : category // ignore: cast_nullable_to_non_nullable
                      as String?,
            ageAtEvent: freezed == ageAtEvent
                ? _value.ageAtEvent
                : ageAtEvent // ignore: cast_nullable_to_non_nullable
                      as int?,
            eventDate: freezed == eventDate
                ? _value.eventDate
                : eventDate // ignore: cast_nullable_to_non_nullable
                      as String?,
            importanceScore: freezed == importanceScore
                ? _value.importanceScore
                : importanceScore // ignore: cast_nullable_to_non_nullable
                      as double?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$MissingMilestoneImplCopyWith<$Res>
    implements $MissingMilestoneCopyWith<$Res> {
  factory _$$MissingMilestoneImplCopyWith(
    _$MissingMilestoneImpl value,
    $Res Function(_$MissingMilestoneImpl) then,
  ) = __$$MissingMilestoneImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String? id,
    String? title,
    String? description,
    String? category,
    int? ageAtEvent,
    String? eventDate,
    double? importanceScore,
  });
}

/// @nodoc
class __$$MissingMilestoneImplCopyWithImpl<$Res>
    extends _$MissingMilestoneCopyWithImpl<$Res, _$MissingMilestoneImpl>
    implements _$$MissingMilestoneImplCopyWith<$Res> {
  __$$MissingMilestoneImplCopyWithImpl(
    _$MissingMilestoneImpl _value,
    $Res Function(_$MissingMilestoneImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MissingMilestone
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? title = freezed,
    Object? description = freezed,
    Object? category = freezed,
    Object? ageAtEvent = freezed,
    Object? eventDate = freezed,
    Object? importanceScore = freezed,
  }) {
    return _then(
      _$MissingMilestoneImpl(
        id: freezed == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String?,
        title: freezed == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String?,
        description: freezed == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String?,
        category: freezed == category
            ? _value.category
            : category // ignore: cast_nullable_to_non_nullable
                  as String?,
        ageAtEvent: freezed == ageAtEvent
            ? _value.ageAtEvent
            : ageAtEvent // ignore: cast_nullable_to_non_nullable
                  as int?,
        eventDate: freezed == eventDate
            ? _value.eventDate
            : eventDate // ignore: cast_nullable_to_non_nullable
                  as String?,
        importanceScore: freezed == importanceScore
            ? _value.importanceScore
            : importanceScore // ignore: cast_nullable_to_non_nullable
                  as double?,
      ),
    );
  }
}

/// @nodoc

class _$MissingMilestoneImpl implements _MissingMilestone {
  const _$MissingMilestoneImpl({
    this.id,
    this.title,
    this.description,
    this.category,
    this.ageAtEvent,
    this.eventDate,
    this.importanceScore,
  });

  @override
  final String? id;
  @override
  final String? title;
  @override
  final String? description;
  @override
  final String? category;
  @override
  final int? ageAtEvent;
  @override
  final String? eventDate;
  @override
  final double? importanceScore;

  @override
  String toString() {
    return 'MissingMilestone(id: $id, title: $title, description: $description, category: $category, ageAtEvent: $ageAtEvent, eventDate: $eventDate, importanceScore: $importanceScore)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MissingMilestoneImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.ageAtEvent, ageAtEvent) ||
                other.ageAtEvent == ageAtEvent) &&
            (identical(other.eventDate, eventDate) ||
                other.eventDate == eventDate) &&
            (identical(other.importanceScore, importanceScore) ||
                other.importanceScore == importanceScore));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    title,
    description,
    category,
    ageAtEvent,
    eventDate,
    importanceScore,
  );

  /// Create a copy of MissingMilestone
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MissingMilestoneImplCopyWith<_$MissingMilestoneImpl> get copyWith =>
      __$$MissingMilestoneImplCopyWithImpl<_$MissingMilestoneImpl>(
        this,
        _$identity,
      );
}

abstract class _MissingMilestone implements MissingMilestone {
  const factory _MissingMilestone({
    final String? id,
    final String? title,
    final String? description,
    final String? category,
    final int? ageAtEvent,
    final String? eventDate,
    final double? importanceScore,
  }) = _$MissingMilestoneImpl;

  @override
  String? get id;
  @override
  String? get title;
  @override
  String? get description;
  @override
  String? get category;
  @override
  int? get ageAtEvent;
  @override
  String? get eventDate;
  @override
  double? get importanceScore;

  /// Create a copy of MissingMilestone
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MissingMilestoneImplCopyWith<_$MissingMilestoneImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ComparisonResponse {
  double get overallScore => throw _privateConstructorUsedError;
  List<CategoryBreakdown> get categoryBreakdown =>
      throw _privateConstructorUsedError;
  List<ComparisonStrength> get strengths => throw _privateConstructorUsedError;
  List<ComparisonGap> get gaps => throw _privateConstructorUsedError;
  List<MissingMilestone> get missingVsIdol =>
      throw _privateConstructorUsedError;
  double get completeness => throw _privateConstructorUsedError;
  int get countedUserAchievements => throw _privateConstructorUsedError;
  int get idolMilestonesAtAge => throw _privateConstructorUsedError;
  int get totalIdolMilestones => throw _privateConstructorUsedError;
  int get totalUserAchievements => throw _privateConstructorUsedError;
  int get matchedCount => throw _privateConstructorUsedError;
  int? get userAge => throw _privateConstructorUsedError;
  int? get targetAge => throw _privateConstructorUsedError;
  String? get mode => throw _privateConstructorUsedError;
  String? get idolId => throw _privateConstructorUsedError;
  String? get idolName => throw _privateConstructorUsedError;
  DateTime? get generatedAt =>
      throw _privateConstructorUsedError; // AI-enhanced fields
  String? get overallAnalysis => throw _privateConstructorUsedError;
  String? get realisticPerspective => throw _privateConstructorUsedError;
  String? get encouragement => throw _privateConstructorUsedError;
  NextMilestone? get nextMilestone => throw _privateConstructorUsedError;
  bool get aiEnhanced => throw _privateConstructorUsedError;

  /// Create a copy of ComparisonResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ComparisonResponseCopyWith<ComparisonResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ComparisonResponseCopyWith<$Res> {
  factory $ComparisonResponseCopyWith(
    ComparisonResponse value,
    $Res Function(ComparisonResponse) then,
  ) = _$ComparisonResponseCopyWithImpl<$Res, ComparisonResponse>;
  @useResult
  $Res call({
    double overallScore,
    List<CategoryBreakdown> categoryBreakdown,
    List<ComparisonStrength> strengths,
    List<ComparisonGap> gaps,
    List<MissingMilestone> missingVsIdol,
    double completeness,
    int countedUserAchievements,
    int idolMilestonesAtAge,
    int totalIdolMilestones,
    int totalUserAchievements,
    int matchedCount,
    int? userAge,
    int? targetAge,
    String? mode,
    String? idolId,
    String? idolName,
    DateTime? generatedAt,
    String? overallAnalysis,
    String? realisticPerspective,
    String? encouragement,
    NextMilestone? nextMilestone,
    bool aiEnhanced,
  });

  $NextMilestoneCopyWith<$Res>? get nextMilestone;
}

/// @nodoc
class _$ComparisonResponseCopyWithImpl<$Res, $Val extends ComparisonResponse>
    implements $ComparisonResponseCopyWith<$Res> {
  _$ComparisonResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ComparisonResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? overallScore = null,
    Object? categoryBreakdown = null,
    Object? strengths = null,
    Object? gaps = null,
    Object? missingVsIdol = null,
    Object? completeness = null,
    Object? countedUserAchievements = null,
    Object? idolMilestonesAtAge = null,
    Object? totalIdolMilestones = null,
    Object? totalUserAchievements = null,
    Object? matchedCount = null,
    Object? userAge = freezed,
    Object? targetAge = freezed,
    Object? mode = freezed,
    Object? idolId = freezed,
    Object? idolName = freezed,
    Object? generatedAt = freezed,
    Object? overallAnalysis = freezed,
    Object? realisticPerspective = freezed,
    Object? encouragement = freezed,
    Object? nextMilestone = freezed,
    Object? aiEnhanced = null,
  }) {
    return _then(
      _value.copyWith(
            overallScore: null == overallScore
                ? _value.overallScore
                : overallScore // ignore: cast_nullable_to_non_nullable
                      as double,
            categoryBreakdown: null == categoryBreakdown
                ? _value.categoryBreakdown
                : categoryBreakdown // ignore: cast_nullable_to_non_nullable
                      as List<CategoryBreakdown>,
            strengths: null == strengths
                ? _value.strengths
                : strengths // ignore: cast_nullable_to_non_nullable
                      as List<ComparisonStrength>,
            gaps: null == gaps
                ? _value.gaps
                : gaps // ignore: cast_nullable_to_non_nullable
                      as List<ComparisonGap>,
            missingVsIdol: null == missingVsIdol
                ? _value.missingVsIdol
                : missingVsIdol // ignore: cast_nullable_to_non_nullable
                      as List<MissingMilestone>,
            completeness: null == completeness
                ? _value.completeness
                : completeness // ignore: cast_nullable_to_non_nullable
                      as double,
            countedUserAchievements: null == countedUserAchievements
                ? _value.countedUserAchievements
                : countedUserAchievements // ignore: cast_nullable_to_non_nullable
                      as int,
            idolMilestonesAtAge: null == idolMilestonesAtAge
                ? _value.idolMilestonesAtAge
                : idolMilestonesAtAge // ignore: cast_nullable_to_non_nullable
                      as int,
            totalIdolMilestones: null == totalIdolMilestones
                ? _value.totalIdolMilestones
                : totalIdolMilestones // ignore: cast_nullable_to_non_nullable
                      as int,
            totalUserAchievements: null == totalUserAchievements
                ? _value.totalUserAchievements
                : totalUserAchievements // ignore: cast_nullable_to_non_nullable
                      as int,
            matchedCount: null == matchedCount
                ? _value.matchedCount
                : matchedCount // ignore: cast_nullable_to_non_nullable
                      as int,
            userAge: freezed == userAge
                ? _value.userAge
                : userAge // ignore: cast_nullable_to_non_nullable
                      as int?,
            targetAge: freezed == targetAge
                ? _value.targetAge
                : targetAge // ignore: cast_nullable_to_non_nullable
                      as int?,
            mode: freezed == mode
                ? _value.mode
                : mode // ignore: cast_nullable_to_non_nullable
                      as String?,
            idolId: freezed == idolId
                ? _value.idolId
                : idolId // ignore: cast_nullable_to_non_nullable
                      as String?,
            idolName: freezed == idolName
                ? _value.idolName
                : idolName // ignore: cast_nullable_to_non_nullable
                      as String?,
            generatedAt: freezed == generatedAt
                ? _value.generatedAt
                : generatedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            overallAnalysis: freezed == overallAnalysis
                ? _value.overallAnalysis
                : overallAnalysis // ignore: cast_nullable_to_non_nullable
                      as String?,
            realisticPerspective: freezed == realisticPerspective
                ? _value.realisticPerspective
                : realisticPerspective // ignore: cast_nullable_to_non_nullable
                      as String?,
            encouragement: freezed == encouragement
                ? _value.encouragement
                : encouragement // ignore: cast_nullable_to_non_nullable
                      as String?,
            nextMilestone: freezed == nextMilestone
                ? _value.nextMilestone
                : nextMilestone // ignore: cast_nullable_to_non_nullable
                      as NextMilestone?,
            aiEnhanced: null == aiEnhanced
                ? _value.aiEnhanced
                : aiEnhanced // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }

  /// Create a copy of ComparisonResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $NextMilestoneCopyWith<$Res>? get nextMilestone {
    if (_value.nextMilestone == null) {
      return null;
    }

    return $NextMilestoneCopyWith<$Res>(_value.nextMilestone!, (value) {
      return _then(_value.copyWith(nextMilestone: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$ComparisonResponseImplCopyWith<$Res>
    implements $ComparisonResponseCopyWith<$Res> {
  factory _$$ComparisonResponseImplCopyWith(
    _$ComparisonResponseImpl value,
    $Res Function(_$ComparisonResponseImpl) then,
  ) = __$$ComparisonResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    double overallScore,
    List<CategoryBreakdown> categoryBreakdown,
    List<ComparisonStrength> strengths,
    List<ComparisonGap> gaps,
    List<MissingMilestone> missingVsIdol,
    double completeness,
    int countedUserAchievements,
    int idolMilestonesAtAge,
    int totalIdolMilestones,
    int totalUserAchievements,
    int matchedCount,
    int? userAge,
    int? targetAge,
    String? mode,
    String? idolId,
    String? idolName,
    DateTime? generatedAt,
    String? overallAnalysis,
    String? realisticPerspective,
    String? encouragement,
    NextMilestone? nextMilestone,
    bool aiEnhanced,
  });

  @override
  $NextMilestoneCopyWith<$Res>? get nextMilestone;
}

/// @nodoc
class __$$ComparisonResponseImplCopyWithImpl<$Res>
    extends _$ComparisonResponseCopyWithImpl<$Res, _$ComparisonResponseImpl>
    implements _$$ComparisonResponseImplCopyWith<$Res> {
  __$$ComparisonResponseImplCopyWithImpl(
    _$ComparisonResponseImpl _value,
    $Res Function(_$ComparisonResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ComparisonResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? overallScore = null,
    Object? categoryBreakdown = null,
    Object? strengths = null,
    Object? gaps = null,
    Object? missingVsIdol = null,
    Object? completeness = null,
    Object? countedUserAchievements = null,
    Object? idolMilestonesAtAge = null,
    Object? totalIdolMilestones = null,
    Object? totalUserAchievements = null,
    Object? matchedCount = null,
    Object? userAge = freezed,
    Object? targetAge = freezed,
    Object? mode = freezed,
    Object? idolId = freezed,
    Object? idolName = freezed,
    Object? generatedAt = freezed,
    Object? overallAnalysis = freezed,
    Object? realisticPerspective = freezed,
    Object? encouragement = freezed,
    Object? nextMilestone = freezed,
    Object? aiEnhanced = null,
  }) {
    return _then(
      _$ComparisonResponseImpl(
        overallScore: null == overallScore
            ? _value.overallScore
            : overallScore // ignore: cast_nullable_to_non_nullable
                  as double,
        categoryBreakdown: null == categoryBreakdown
            ? _value._categoryBreakdown
            : categoryBreakdown // ignore: cast_nullable_to_non_nullable
                  as List<CategoryBreakdown>,
        strengths: null == strengths
            ? _value._strengths
            : strengths // ignore: cast_nullable_to_non_nullable
                  as List<ComparisonStrength>,
        gaps: null == gaps
            ? _value._gaps
            : gaps // ignore: cast_nullable_to_non_nullable
                  as List<ComparisonGap>,
        missingVsIdol: null == missingVsIdol
            ? _value._missingVsIdol
            : missingVsIdol // ignore: cast_nullable_to_non_nullable
                  as List<MissingMilestone>,
        completeness: null == completeness
            ? _value.completeness
            : completeness // ignore: cast_nullable_to_non_nullable
                  as double,
        countedUserAchievements: null == countedUserAchievements
            ? _value.countedUserAchievements
            : countedUserAchievements // ignore: cast_nullable_to_non_nullable
                  as int,
        idolMilestonesAtAge: null == idolMilestonesAtAge
            ? _value.idolMilestonesAtAge
            : idolMilestonesAtAge // ignore: cast_nullable_to_non_nullable
                  as int,
        totalIdolMilestones: null == totalIdolMilestones
            ? _value.totalIdolMilestones
            : totalIdolMilestones // ignore: cast_nullable_to_non_nullable
                  as int,
        totalUserAchievements: null == totalUserAchievements
            ? _value.totalUserAchievements
            : totalUserAchievements // ignore: cast_nullable_to_non_nullable
                  as int,
        matchedCount: null == matchedCount
            ? _value.matchedCount
            : matchedCount // ignore: cast_nullable_to_non_nullable
                  as int,
        userAge: freezed == userAge
            ? _value.userAge
            : userAge // ignore: cast_nullable_to_non_nullable
                  as int?,
        targetAge: freezed == targetAge
            ? _value.targetAge
            : targetAge // ignore: cast_nullable_to_non_nullable
                  as int?,
        mode: freezed == mode
            ? _value.mode
            : mode // ignore: cast_nullable_to_non_nullable
                  as String?,
        idolId: freezed == idolId
            ? _value.idolId
            : idolId // ignore: cast_nullable_to_non_nullable
                  as String?,
        idolName: freezed == idolName
            ? _value.idolName
            : idolName // ignore: cast_nullable_to_non_nullable
                  as String?,
        generatedAt: freezed == generatedAt
            ? _value.generatedAt
            : generatedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        overallAnalysis: freezed == overallAnalysis
            ? _value.overallAnalysis
            : overallAnalysis // ignore: cast_nullable_to_non_nullable
                  as String?,
        realisticPerspective: freezed == realisticPerspective
            ? _value.realisticPerspective
            : realisticPerspective // ignore: cast_nullable_to_non_nullable
                  as String?,
        encouragement: freezed == encouragement
            ? _value.encouragement
            : encouragement // ignore: cast_nullable_to_non_nullable
                  as String?,
        nextMilestone: freezed == nextMilestone
            ? _value.nextMilestone
            : nextMilestone // ignore: cast_nullable_to_non_nullable
                  as NextMilestone?,
        aiEnhanced: null == aiEnhanced
            ? _value.aiEnhanced
            : aiEnhanced // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc

class _$ComparisonResponseImpl implements _ComparisonResponse {
  const _$ComparisonResponseImpl({
    required this.overallScore,
    final List<CategoryBreakdown> categoryBreakdown = const [],
    final List<ComparisonStrength> strengths = const [],
    final List<ComparisonGap> gaps = const [],
    final List<MissingMilestone> missingVsIdol = const [],
    this.completeness = 0,
    this.countedUserAchievements = 0,
    this.idolMilestonesAtAge = 0,
    this.totalIdolMilestones = 0,
    this.totalUserAchievements = 0,
    this.matchedCount = 0,
    this.userAge,
    this.targetAge,
    this.mode,
    this.idolId,
    this.idolName,
    this.generatedAt,
    this.overallAnalysis,
    this.realisticPerspective,
    this.encouragement,
    this.nextMilestone,
    this.aiEnhanced = false,
  }) : _categoryBreakdown = categoryBreakdown,
       _strengths = strengths,
       _gaps = gaps,
       _missingVsIdol = missingVsIdol;

  @override
  final double overallScore;
  final List<CategoryBreakdown> _categoryBreakdown;
  @override
  @JsonKey()
  List<CategoryBreakdown> get categoryBreakdown {
    if (_categoryBreakdown is EqualUnmodifiableListView)
      return _categoryBreakdown;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_categoryBreakdown);
  }

  final List<ComparisonStrength> _strengths;
  @override
  @JsonKey()
  List<ComparisonStrength> get strengths {
    if (_strengths is EqualUnmodifiableListView) return _strengths;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_strengths);
  }

  final List<ComparisonGap> _gaps;
  @override
  @JsonKey()
  List<ComparisonGap> get gaps {
    if (_gaps is EqualUnmodifiableListView) return _gaps;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_gaps);
  }

  final List<MissingMilestone> _missingVsIdol;
  @override
  @JsonKey()
  List<MissingMilestone> get missingVsIdol {
    if (_missingVsIdol is EqualUnmodifiableListView) return _missingVsIdol;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_missingVsIdol);
  }

  @override
  @JsonKey()
  final double completeness;
  @override
  @JsonKey()
  final int countedUserAchievements;
  @override
  @JsonKey()
  final int idolMilestonesAtAge;
  @override
  @JsonKey()
  final int totalIdolMilestones;
  @override
  @JsonKey()
  final int totalUserAchievements;
  @override
  @JsonKey()
  final int matchedCount;
  @override
  final int? userAge;
  @override
  final int? targetAge;
  @override
  final String? mode;
  @override
  final String? idolId;
  @override
  final String? idolName;
  @override
  final DateTime? generatedAt;
  // AI-enhanced fields
  @override
  final String? overallAnalysis;
  @override
  final String? realisticPerspective;
  @override
  final String? encouragement;
  @override
  final NextMilestone? nextMilestone;
  @override
  @JsonKey()
  final bool aiEnhanced;

  @override
  String toString() {
    return 'ComparisonResponse(overallScore: $overallScore, categoryBreakdown: $categoryBreakdown, strengths: $strengths, gaps: $gaps, missingVsIdol: $missingVsIdol, completeness: $completeness, countedUserAchievements: $countedUserAchievements, idolMilestonesAtAge: $idolMilestonesAtAge, totalIdolMilestones: $totalIdolMilestones, totalUserAchievements: $totalUserAchievements, matchedCount: $matchedCount, userAge: $userAge, targetAge: $targetAge, mode: $mode, idolId: $idolId, idolName: $idolName, generatedAt: $generatedAt, overallAnalysis: $overallAnalysis, realisticPerspective: $realisticPerspective, encouragement: $encouragement, nextMilestone: $nextMilestone, aiEnhanced: $aiEnhanced)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ComparisonResponseImpl &&
            (identical(other.overallScore, overallScore) ||
                other.overallScore == overallScore) &&
            const DeepCollectionEquality().equals(
              other._categoryBreakdown,
              _categoryBreakdown,
            ) &&
            const DeepCollectionEquality().equals(
              other._strengths,
              _strengths,
            ) &&
            const DeepCollectionEquality().equals(other._gaps, _gaps) &&
            const DeepCollectionEquality().equals(
              other._missingVsIdol,
              _missingVsIdol,
            ) &&
            (identical(other.completeness, completeness) ||
                other.completeness == completeness) &&
            (identical(
                  other.countedUserAchievements,
                  countedUserAchievements,
                ) ||
                other.countedUserAchievements == countedUserAchievements) &&
            (identical(other.idolMilestonesAtAge, idolMilestonesAtAge) ||
                other.idolMilestonesAtAge == idolMilestonesAtAge) &&
            (identical(other.totalIdolMilestones, totalIdolMilestones) ||
                other.totalIdolMilestones == totalIdolMilestones) &&
            (identical(other.totalUserAchievements, totalUserAchievements) ||
                other.totalUserAchievements == totalUserAchievements) &&
            (identical(other.matchedCount, matchedCount) ||
                other.matchedCount == matchedCount) &&
            (identical(other.userAge, userAge) || other.userAge == userAge) &&
            (identical(other.targetAge, targetAge) ||
                other.targetAge == targetAge) &&
            (identical(other.mode, mode) || other.mode == mode) &&
            (identical(other.idolId, idolId) || other.idolId == idolId) &&
            (identical(other.idolName, idolName) ||
                other.idolName == idolName) &&
            (identical(other.generatedAt, generatedAt) ||
                other.generatedAt == generatedAt) &&
            (identical(other.overallAnalysis, overallAnalysis) ||
                other.overallAnalysis == overallAnalysis) &&
            (identical(other.realisticPerspective, realisticPerspective) ||
                other.realisticPerspective == realisticPerspective) &&
            (identical(other.encouragement, encouragement) ||
                other.encouragement == encouragement) &&
            (identical(other.nextMilestone, nextMilestone) ||
                other.nextMilestone == nextMilestone) &&
            (identical(other.aiEnhanced, aiEnhanced) ||
                other.aiEnhanced == aiEnhanced));
  }

  @override
  int get hashCode => Object.hashAll([
    runtimeType,
    overallScore,
    const DeepCollectionEquality().hash(_categoryBreakdown),
    const DeepCollectionEquality().hash(_strengths),
    const DeepCollectionEquality().hash(_gaps),
    const DeepCollectionEquality().hash(_missingVsIdol),
    completeness,
    countedUserAchievements,
    idolMilestonesAtAge,
    totalIdolMilestones,
    totalUserAchievements,
    matchedCount,
    userAge,
    targetAge,
    mode,
    idolId,
    idolName,
    generatedAt,
    overallAnalysis,
    realisticPerspective,
    encouragement,
    nextMilestone,
    aiEnhanced,
  ]);

  /// Create a copy of ComparisonResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ComparisonResponseImplCopyWith<_$ComparisonResponseImpl> get copyWith =>
      __$$ComparisonResponseImplCopyWithImpl<_$ComparisonResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _ComparisonResponse implements ComparisonResponse {
  const factory _ComparisonResponse({
    required final double overallScore,
    final List<CategoryBreakdown> categoryBreakdown,
    final List<ComparisonStrength> strengths,
    final List<ComparisonGap> gaps,
    final List<MissingMilestone> missingVsIdol,
    final double completeness,
    final int countedUserAchievements,
    final int idolMilestonesAtAge,
    final int totalIdolMilestones,
    final int totalUserAchievements,
    final int matchedCount,
    final int? userAge,
    final int? targetAge,
    final String? mode,
    final String? idolId,
    final String? idolName,
    final DateTime? generatedAt,
    final String? overallAnalysis,
    final String? realisticPerspective,
    final String? encouragement,
    final NextMilestone? nextMilestone,
    final bool aiEnhanced,
  }) = _$ComparisonResponseImpl;

  @override
  double get overallScore;
  @override
  List<CategoryBreakdown> get categoryBreakdown;
  @override
  List<ComparisonStrength> get strengths;
  @override
  List<ComparisonGap> get gaps;
  @override
  List<MissingMilestone> get missingVsIdol;
  @override
  double get completeness;
  @override
  int get countedUserAchievements;
  @override
  int get idolMilestonesAtAge;
  @override
  int get totalIdolMilestones;
  @override
  int get totalUserAchievements;
  @override
  int get matchedCount;
  @override
  int? get userAge;
  @override
  int? get targetAge;
  @override
  String? get mode;
  @override
  String? get idolId;
  @override
  String? get idolName;
  @override
  DateTime? get generatedAt; // AI-enhanced fields
  @override
  String? get overallAnalysis;
  @override
  String? get realisticPerspective;
  @override
  String? get encouragement;
  @override
  NextMilestone? get nextMilestone;
  @override
  bool get aiEnhanced;

  /// Create a copy of ComparisonResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ComparisonResponseImplCopyWith<_$ComparisonResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$NextMilestone {
  String get title => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  String? get estimatedTimeframe => throw _privateConstructorUsedError;

  /// Create a copy of NextMilestone
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $NextMilestoneCopyWith<NextMilestone> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $NextMilestoneCopyWith<$Res> {
  factory $NextMilestoneCopyWith(
    NextMilestone value,
    $Res Function(NextMilestone) then,
  ) = _$NextMilestoneCopyWithImpl<$Res, NextMilestone>;
  @useResult
  $Res call({String title, String description, String? estimatedTimeframe});
}

/// @nodoc
class _$NextMilestoneCopyWithImpl<$Res, $Val extends NextMilestone>
    implements $NextMilestoneCopyWith<$Res> {
  _$NextMilestoneCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of NextMilestone
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = null,
    Object? description = null,
    Object? estimatedTimeframe = freezed,
  }) {
    return _then(
      _value.copyWith(
            title: null == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String,
            description: null == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String,
            estimatedTimeframe: freezed == estimatedTimeframe
                ? _value.estimatedTimeframe
                : estimatedTimeframe // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$NextMilestoneImplCopyWith<$Res>
    implements $NextMilestoneCopyWith<$Res> {
  factory _$$NextMilestoneImplCopyWith(
    _$NextMilestoneImpl value,
    $Res Function(_$NextMilestoneImpl) then,
  ) = __$$NextMilestoneImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String title, String description, String? estimatedTimeframe});
}

/// @nodoc
class __$$NextMilestoneImplCopyWithImpl<$Res>
    extends _$NextMilestoneCopyWithImpl<$Res, _$NextMilestoneImpl>
    implements _$$NextMilestoneImplCopyWith<$Res> {
  __$$NextMilestoneImplCopyWithImpl(
    _$NextMilestoneImpl _value,
    $Res Function(_$NextMilestoneImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of NextMilestone
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = null,
    Object? description = null,
    Object? estimatedTimeframe = freezed,
  }) {
    return _then(
      _$NextMilestoneImpl(
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        description: null == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String,
        estimatedTimeframe: freezed == estimatedTimeframe
            ? _value.estimatedTimeframe
            : estimatedTimeframe // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$NextMilestoneImpl implements _NextMilestone {
  const _$NextMilestoneImpl({
    required this.title,
    required this.description,
    this.estimatedTimeframe,
  });

  @override
  final String title;
  @override
  final String description;
  @override
  final String? estimatedTimeframe;

  @override
  String toString() {
    return 'NextMilestone(title: $title, description: $description, estimatedTimeframe: $estimatedTimeframe)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NextMilestoneImpl &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.estimatedTimeframe, estimatedTimeframe) ||
                other.estimatedTimeframe == estimatedTimeframe));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, title, description, estimatedTimeframe);

  /// Create a copy of NextMilestone
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NextMilestoneImplCopyWith<_$NextMilestoneImpl> get copyWith =>
      __$$NextMilestoneImplCopyWithImpl<_$NextMilestoneImpl>(this, _$identity);
}

abstract class _NextMilestone implements NextMilestone {
  const factory _NextMilestone({
    required final String title,
    required final String description,
    final String? estimatedTimeframe,
  }) = _$NextMilestoneImpl;

  @override
  String get title;
  @override
  String get description;
  @override
  String? get estimatedTimeframe;

  /// Create a copy of NextMilestone
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NextMilestoneImplCopyWith<_$NextMilestoneImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
