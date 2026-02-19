// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'job_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$ThinkingStream {
  /// The line currently being "typed" - animate with typewriter effect
  String get currentLine => throw _privateConstructorUsedError;

  /// Lines already shown - display immediately with checkmark
  List<String> get completedLines => throw _privateConstructorUsedError;

  /// Optional insight/tip - show as subtle aside
  String? get insight => throw _privateConstructorUsedError;

  /// Current processing step name
  String get step => throw _privateConstructorUsedError;

  /// Progress within current step (0-100)
  int get stepProgress => throw _privateConstructorUsedError;

  /// Create a copy of ThinkingStream
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThinkingStreamCopyWith<ThinkingStream> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThinkingStreamCopyWith<$Res> {
  factory $ThinkingStreamCopyWith(
    ThinkingStream value,
    $Res Function(ThinkingStream) then,
  ) = _$ThinkingStreamCopyWithImpl<$Res, ThinkingStream>;
  @useResult
  $Res call({
    String currentLine,
    List<String> completedLines,
    String? insight,
    String step,
    int stepProgress,
  });
}

/// @nodoc
class _$ThinkingStreamCopyWithImpl<$Res, $Val extends ThinkingStream>
    implements $ThinkingStreamCopyWith<$Res> {
  _$ThinkingStreamCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThinkingStream
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentLine = null,
    Object? completedLines = null,
    Object? insight = freezed,
    Object? step = null,
    Object? stepProgress = null,
  }) {
    return _then(
      _value.copyWith(
            currentLine: null == currentLine
                ? _value.currentLine
                : currentLine // ignore: cast_nullable_to_non_nullable
                      as String,
            completedLines: null == completedLines
                ? _value.completedLines
                : completedLines // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            insight: freezed == insight
                ? _value.insight
                : insight // ignore: cast_nullable_to_non_nullable
                      as String?,
            step: null == step
                ? _value.step
                : step // ignore: cast_nullable_to_non_nullable
                      as String,
            stepProgress: null == stepProgress
                ? _value.stepProgress
                : stepProgress // ignore: cast_nullable_to_non_nullable
                      as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ThinkingStreamImplCopyWith<$Res>
    implements $ThinkingStreamCopyWith<$Res> {
  factory _$$ThinkingStreamImplCopyWith(
    _$ThinkingStreamImpl value,
    $Res Function(_$ThinkingStreamImpl) then,
  ) = __$$ThinkingStreamImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String currentLine,
    List<String> completedLines,
    String? insight,
    String step,
    int stepProgress,
  });
}

/// @nodoc
class __$$ThinkingStreamImplCopyWithImpl<$Res>
    extends _$ThinkingStreamCopyWithImpl<$Res, _$ThinkingStreamImpl>
    implements _$$ThinkingStreamImplCopyWith<$Res> {
  __$$ThinkingStreamImplCopyWithImpl(
    _$ThinkingStreamImpl _value,
    $Res Function(_$ThinkingStreamImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ThinkingStream
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentLine = null,
    Object? completedLines = null,
    Object? insight = freezed,
    Object? step = null,
    Object? stepProgress = null,
  }) {
    return _then(
      _$ThinkingStreamImpl(
        currentLine: null == currentLine
            ? _value.currentLine
            : currentLine // ignore: cast_nullable_to_non_nullable
                  as String,
        completedLines: null == completedLines
            ? _value._completedLines
            : completedLines // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        insight: freezed == insight
            ? _value.insight
            : insight // ignore: cast_nullable_to_non_nullable
                  as String?,
        step: null == step
            ? _value.step
            : step // ignore: cast_nullable_to_non_nullable
                  as String,
        stepProgress: null == stepProgress
            ? _value.stepProgress
            : stepProgress // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc

class _$ThinkingStreamImpl extends _ThinkingStream {
  const _$ThinkingStreamImpl({
    required this.currentLine,
    required final List<String> completedLines,
    this.insight,
    required this.step,
    required this.stepProgress,
  }) : _completedLines = completedLines,
       super._();

  /// The line currently being "typed" - animate with typewriter effect
  @override
  final String currentLine;

  /// Lines already shown - display immediately with checkmark
  final List<String> _completedLines;

  /// Lines already shown - display immediately with checkmark
  @override
  List<String> get completedLines {
    if (_completedLines is EqualUnmodifiableListView) return _completedLines;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_completedLines);
  }

  /// Optional insight/tip - show as subtle aside
  @override
  final String? insight;

  /// Current processing step name
  @override
  final String step;

  /// Progress within current step (0-100)
  @override
  final int stepProgress;

  @override
  String toString() {
    return 'ThinkingStream(currentLine: $currentLine, completedLines: $completedLines, insight: $insight, step: $step, stepProgress: $stepProgress)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThinkingStreamImpl &&
            (identical(other.currentLine, currentLine) ||
                other.currentLine == currentLine) &&
            const DeepCollectionEquality().equals(
              other._completedLines,
              _completedLines,
            ) &&
            (identical(other.insight, insight) || other.insight == insight) &&
            (identical(other.step, step) || other.step == step) &&
            (identical(other.stepProgress, stepProgress) ||
                other.stepProgress == stepProgress));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    currentLine,
    const DeepCollectionEquality().hash(_completedLines),
    insight,
    step,
    stepProgress,
  );

  /// Create a copy of ThinkingStream
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThinkingStreamImplCopyWith<_$ThinkingStreamImpl> get copyWith =>
      __$$ThinkingStreamImplCopyWithImpl<_$ThinkingStreamImpl>(
        this,
        _$identity,
      );
}

abstract class _ThinkingStream extends ThinkingStream {
  const factory _ThinkingStream({
    required final String currentLine,
    required final List<String> completedLines,
    final String? insight,
    required final String step,
    required final int stepProgress,
  }) = _$ThinkingStreamImpl;
  const _ThinkingStream._() : super._();

  /// The line currently being "typed" - animate with typewriter effect
  @override
  String get currentLine;

  /// Lines already shown - display immediately with checkmark
  @override
  List<String> get completedLines;

  /// Optional insight/tip - show as subtle aside
  @override
  String? get insight;

  /// Current processing step name
  @override
  String get step;

  /// Progress within current step (0-100)
  @override
  int get stepProgress;

  /// Create a copy of ThinkingStream
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThinkingStreamImplCopyWith<_$ThinkingStreamImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$JobStatus {
  String? get id => throw _privateConstructorUsedError;

  /// The idol ID this job is processing
  String? get idolId => throw _privateConstructorUsedError;

  /// The idol's name
  String? get idolName => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;

  /// Current processing step (e.g., "extracting_achievements")
  String? get step => throw _privateConstructorUsedError;
  int get progressPercent => throw _privateConstructorUsedError;
  String? get errorMessage => throw _privateConstructorUsedError;
  DateTime? get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;
  DateTime? get completedAt => throw _privateConstructorUsedError;

  /// AI thinking stream - shows dynamic text during import
  ThinkingStream? get thinkingStream => throw _privateConstructorUsedError;

  /// Top achievements found (available after 60%)
  List<String>? get previewAchievements => throw _privateConstructorUsedError;

  /// Idol's domains (available after 25%)
  List<String>? get previewDomains => throw _privateConstructorUsedError;

  /// Final job results (e.g., suggestions)
  Map<String, dynamic>? get results => throw _privateConstructorUsedError;

  /// Create a copy of JobStatus
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $JobStatusCopyWith<JobStatus> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $JobStatusCopyWith<$Res> {
  factory $JobStatusCopyWith(JobStatus value, $Res Function(JobStatus) then) =
      _$JobStatusCopyWithImpl<$Res, JobStatus>;
  @useResult
  $Res call({
    String? id,
    String? idolId,
    String? idolName,
    String status,
    String? step,
    int progressPercent,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    ThinkingStream? thinkingStream,
    List<String>? previewAchievements,
    List<String>? previewDomains,
    Map<String, dynamic>? results,
  });

  $ThinkingStreamCopyWith<$Res>? get thinkingStream;
}

/// @nodoc
class _$JobStatusCopyWithImpl<$Res, $Val extends JobStatus>
    implements $JobStatusCopyWith<$Res> {
  _$JobStatusCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of JobStatus
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? idolId = freezed,
    Object? idolName = freezed,
    Object? status = null,
    Object? step = freezed,
    Object? progressPercent = null,
    Object? errorMessage = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
    Object? completedAt = freezed,
    Object? thinkingStream = freezed,
    Object? previewAchievements = freezed,
    Object? previewDomains = freezed,
    Object? results = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: freezed == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String?,
            idolId: freezed == idolId
                ? _value.idolId
                : idolId // ignore: cast_nullable_to_non_nullable
                      as String?,
            idolName: freezed == idolName
                ? _value.idolName
                : idolName // ignore: cast_nullable_to_non_nullable
                      as String?,
            status: null == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String,
            step: freezed == step
                ? _value.step
                : step // ignore: cast_nullable_to_non_nullable
                      as String?,
            progressPercent: null == progressPercent
                ? _value.progressPercent
                : progressPercent // ignore: cast_nullable_to_non_nullable
                      as int,
            errorMessage: freezed == errorMessage
                ? _value.errorMessage
                : errorMessage // ignore: cast_nullable_to_non_nullable
                      as String?,
            createdAt: freezed == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            updatedAt: freezed == updatedAt
                ? _value.updatedAt
                : updatedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            completedAt: freezed == completedAt
                ? _value.completedAt
                : completedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            thinkingStream: freezed == thinkingStream
                ? _value.thinkingStream
                : thinkingStream // ignore: cast_nullable_to_non_nullable
                      as ThinkingStream?,
            previewAchievements: freezed == previewAchievements
                ? _value.previewAchievements
                : previewAchievements // ignore: cast_nullable_to_non_nullable
                      as List<String>?,
            previewDomains: freezed == previewDomains
                ? _value.previewDomains
                : previewDomains // ignore: cast_nullable_to_non_nullable
                      as List<String>?,
            results: freezed == results
                ? _value.results
                : results // ignore: cast_nullable_to_non_nullable
                      as Map<String, dynamic>?,
          )
          as $Val,
    );
  }

  /// Create a copy of JobStatus
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ThinkingStreamCopyWith<$Res>? get thinkingStream {
    if (_value.thinkingStream == null) {
      return null;
    }

    return $ThinkingStreamCopyWith<$Res>(_value.thinkingStream!, (value) {
      return _then(_value.copyWith(thinkingStream: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$JobStatusImplCopyWith<$Res>
    implements $JobStatusCopyWith<$Res> {
  factory _$$JobStatusImplCopyWith(
    _$JobStatusImpl value,
    $Res Function(_$JobStatusImpl) then,
  ) = __$$JobStatusImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String? id,
    String? idolId,
    String? idolName,
    String status,
    String? step,
    int progressPercent,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    ThinkingStream? thinkingStream,
    List<String>? previewAchievements,
    List<String>? previewDomains,
    Map<String, dynamic>? results,
  });

  @override
  $ThinkingStreamCopyWith<$Res>? get thinkingStream;
}

/// @nodoc
class __$$JobStatusImplCopyWithImpl<$Res>
    extends _$JobStatusCopyWithImpl<$Res, _$JobStatusImpl>
    implements _$$JobStatusImplCopyWith<$Res> {
  __$$JobStatusImplCopyWithImpl(
    _$JobStatusImpl _value,
    $Res Function(_$JobStatusImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of JobStatus
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? idolId = freezed,
    Object? idolName = freezed,
    Object? status = null,
    Object? step = freezed,
    Object? progressPercent = null,
    Object? errorMessage = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
    Object? completedAt = freezed,
    Object? thinkingStream = freezed,
    Object? previewAchievements = freezed,
    Object? previewDomains = freezed,
    Object? results = freezed,
  }) {
    return _then(
      _$JobStatusImpl(
        id: freezed == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String?,
        idolId: freezed == idolId
            ? _value.idolId
            : idolId // ignore: cast_nullable_to_non_nullable
                  as String?,
        idolName: freezed == idolName
            ? _value.idolName
            : idolName // ignore: cast_nullable_to_non_nullable
                  as String?,
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String,
        step: freezed == step
            ? _value.step
            : step // ignore: cast_nullable_to_non_nullable
                  as String?,
        progressPercent: null == progressPercent
            ? _value.progressPercent
            : progressPercent // ignore: cast_nullable_to_non_nullable
                  as int,
        errorMessage: freezed == errorMessage
            ? _value.errorMessage
            : errorMessage // ignore: cast_nullable_to_non_nullable
                  as String?,
        createdAt: freezed == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        updatedAt: freezed == updatedAt
            ? _value.updatedAt
            : updatedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        completedAt: freezed == completedAt
            ? _value.completedAt
            : completedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        thinkingStream: freezed == thinkingStream
            ? _value.thinkingStream
            : thinkingStream // ignore: cast_nullable_to_non_nullable
                  as ThinkingStream?,
        previewAchievements: freezed == previewAchievements
            ? _value._previewAchievements
            : previewAchievements // ignore: cast_nullable_to_non_nullable
                  as List<String>?,
        previewDomains: freezed == previewDomains
            ? _value._previewDomains
            : previewDomains // ignore: cast_nullable_to_non_nullable
                  as List<String>?,
        results: freezed == results
            ? _value._results
            : results // ignore: cast_nullable_to_non_nullable
                  as Map<String, dynamic>?,
      ),
    );
  }
}

/// @nodoc

class _$JobStatusImpl extends _JobStatus {
  const _$JobStatusImpl({
    this.id,
    this.idolId,
    this.idolName,
    required this.status,
    this.step,
    this.progressPercent = 0,
    this.errorMessage,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.thinkingStream,
    final List<String>? previewAchievements,
    final List<String>? previewDomains,
    final Map<String, dynamic>? results,
  }) : _previewAchievements = previewAchievements,
       _previewDomains = previewDomains,
       _results = results,
       super._();

  @override
  final String? id;

  /// The idol ID this job is processing
  @override
  final String? idolId;

  /// The idol's name
  @override
  final String? idolName;
  @override
  final String status;

  /// Current processing step (e.g., "extracting_achievements")
  @override
  final String? step;
  @override
  @JsonKey()
  final int progressPercent;
  @override
  final String? errorMessage;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;
  @override
  final DateTime? completedAt;

  /// AI thinking stream - shows dynamic text during import
  @override
  final ThinkingStream? thinkingStream;

  /// Top achievements found (available after 60%)
  final List<String>? _previewAchievements;

  /// Top achievements found (available after 60%)
  @override
  List<String>? get previewAchievements {
    final value = _previewAchievements;
    if (value == null) return null;
    if (_previewAchievements is EqualUnmodifiableListView)
      return _previewAchievements;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  /// Idol's domains (available after 25%)
  final List<String>? _previewDomains;

  /// Idol's domains (available after 25%)
  @override
  List<String>? get previewDomains {
    final value = _previewDomains;
    if (value == null) return null;
    if (_previewDomains is EqualUnmodifiableListView) return _previewDomains;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  /// Final job results (e.g., suggestions)
  final Map<String, dynamic>? _results;

  /// Final job results (e.g., suggestions)
  @override
  Map<String, dynamic>? get results {
    final value = _results;
    if (value == null) return null;
    if (_results is EqualUnmodifiableMapView) return _results;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'JobStatus(id: $id, idolId: $idolId, idolName: $idolName, status: $status, step: $step, progressPercent: $progressPercent, errorMessage: $errorMessage, createdAt: $createdAt, updatedAt: $updatedAt, completedAt: $completedAt, thinkingStream: $thinkingStream, previewAchievements: $previewAchievements, previewDomains: $previewDomains, results: $results)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$JobStatusImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.idolId, idolId) || other.idolId == idolId) &&
            (identical(other.idolName, idolName) ||
                other.idolName == idolName) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.step, step) || other.step == step) &&
            (identical(other.progressPercent, progressPercent) ||
                other.progressPercent == progressPercent) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.completedAt, completedAt) ||
                other.completedAt == completedAt) &&
            (identical(other.thinkingStream, thinkingStream) ||
                other.thinkingStream == thinkingStream) &&
            const DeepCollectionEquality().equals(
              other._previewAchievements,
              _previewAchievements,
            ) &&
            const DeepCollectionEquality().equals(
              other._previewDomains,
              _previewDomains,
            ) &&
            const DeepCollectionEquality().equals(other._results, _results));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    idolId,
    idolName,
    status,
    step,
    progressPercent,
    errorMessage,
    createdAt,
    updatedAt,
    completedAt,
    thinkingStream,
    const DeepCollectionEquality().hash(_previewAchievements),
    const DeepCollectionEquality().hash(_previewDomains),
    const DeepCollectionEquality().hash(_results),
  );

  /// Create a copy of JobStatus
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$JobStatusImplCopyWith<_$JobStatusImpl> get copyWith =>
      __$$JobStatusImplCopyWithImpl<_$JobStatusImpl>(this, _$identity);
}

abstract class _JobStatus extends JobStatus {
  const factory _JobStatus({
    final String? id,
    final String? idolId,
    final String? idolName,
    required final String status,
    final String? step,
    final int progressPercent,
    final String? errorMessage,
    final DateTime? createdAt,
    final DateTime? updatedAt,
    final DateTime? completedAt,
    final ThinkingStream? thinkingStream,
    final List<String>? previewAchievements,
    final List<String>? previewDomains,
    final Map<String, dynamic>? results,
  }) = _$JobStatusImpl;
  const _JobStatus._() : super._();

  @override
  String? get id;

  /// The idol ID this job is processing
  @override
  String? get idolId;

  /// The idol's name
  @override
  String? get idolName;
  @override
  String get status;

  /// Current processing step (e.g., "extracting_achievements")
  @override
  String? get step;
  @override
  int get progressPercent;
  @override
  String? get errorMessage;
  @override
  DateTime? get createdAt;
  @override
  DateTime? get updatedAt;
  @override
  DateTime? get completedAt;

  /// AI thinking stream - shows dynamic text during import
  @override
  ThinkingStream? get thinkingStream;

  /// Top achievements found (available after 60%)
  @override
  List<String>? get previewAchievements;

  /// Idol's domains (available after 25%)
  @override
  List<String>? get previewDomains;

  /// Final job results (e.g., suggestions)
  @override
  Map<String, dynamic>? get results;

  /// Create a copy of JobStatus
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$JobStatusImplCopyWith<_$JobStatusImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
