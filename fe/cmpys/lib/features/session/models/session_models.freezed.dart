// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$SelectedIdolInfo {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get era => throw _privateConstructorUsedError;

  /// Create a copy of SelectedIdolInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SelectedIdolInfoCopyWith<SelectedIdolInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SelectedIdolInfoCopyWith<$Res> {
  factory $SelectedIdolInfoCopyWith(
    SelectedIdolInfo value,
    $Res Function(SelectedIdolInfo) then,
  ) = _$SelectedIdolInfoCopyWithImpl<$Res, SelectedIdolInfo>;
  @useResult
  $Res call({String id, String name, String? era});
}

/// @nodoc
class _$SelectedIdolInfoCopyWithImpl<$Res, $Val extends SelectedIdolInfo>
    implements $SelectedIdolInfoCopyWith<$Res> {
  _$SelectedIdolInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SelectedIdolInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? id = null, Object? name = null, Object? era = freezed}) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            era: freezed == era
                ? _value.era
                : era // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SelectedIdolInfoImplCopyWith<$Res>
    implements $SelectedIdolInfoCopyWith<$Res> {
  factory _$$SelectedIdolInfoImplCopyWith(
    _$SelectedIdolInfoImpl value,
    $Res Function(_$SelectedIdolInfoImpl) then,
  ) = __$$SelectedIdolInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String name, String? era});
}

/// @nodoc
class __$$SelectedIdolInfoImplCopyWithImpl<$Res>
    extends _$SelectedIdolInfoCopyWithImpl<$Res, _$SelectedIdolInfoImpl>
    implements _$$SelectedIdolInfoImplCopyWith<$Res> {
  __$$SelectedIdolInfoImplCopyWithImpl(
    _$SelectedIdolInfoImpl _value,
    $Res Function(_$SelectedIdolInfoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SelectedIdolInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? id = null, Object? name = null, Object? era = freezed}) {
    return _then(
      _$SelectedIdolInfoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        era: freezed == era
            ? _value.era
            : era // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$SelectedIdolInfoImpl extends _SelectedIdolInfo {
  const _$SelectedIdolInfoImpl({required this.id, required this.name, this.era})
    : super._();

  @override
  final String id;
  @override
  final String name;
  @override
  final String? era;

  @override
  String toString() {
    return 'SelectedIdolInfo(id: $id, name: $name, era: $era)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SelectedIdolInfoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.era, era) || other.era == era));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, name, era);

  /// Create a copy of SelectedIdolInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SelectedIdolInfoImplCopyWith<_$SelectedIdolInfoImpl> get copyWith =>
      __$$SelectedIdolInfoImplCopyWithImpl<_$SelectedIdolInfoImpl>(
        this,
        _$identity,
      );
}

abstract class _SelectedIdolInfo extends SelectedIdolInfo {
  const factory _SelectedIdolInfo({
    required final String id,
    required final String name,
    final String? era,
  }) = _$SelectedIdolInfoImpl;
  const _SelectedIdolInfo._() : super._();

  @override
  String get id;
  @override
  String get name;
  @override
  String? get era;

  /// Create a copy of SelectedIdolInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SelectedIdolInfoImplCopyWith<_$SelectedIdolInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$Session {
  String get id => throw _privateConstructorUsedError;
  SessionPhase get phase => throw _privateConstructorUsedError;
  int get userAge => throw _privateConstructorUsedError;
  String get userFinancialStatus => throw _privateConstructorUsedError;
  List<String> get userInterests => throw _privateConstructorUsedError;
  SelectedIdolInfo? get selectedIdol => throw _privateConstructorUsedError;
  int get interviewTurnCount => throw _privateConstructorUsedError;
  String? get comparisonOutput => throw _privateConstructorUsedError;
  String? get blueprintOutput => throw _privateConstructorUsedError;
  String? get interviewThreadId => throw _privateConstructorUsedError;
  DateTime? get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SessionCopyWith<Session> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SessionCopyWith<$Res> {
  factory $SessionCopyWith(Session value, $Res Function(Session) then) =
      _$SessionCopyWithImpl<$Res, Session>;
  @useResult
  $Res call({
    String id,
    SessionPhase phase,
    int userAge,
    String userFinancialStatus,
    List<String> userInterests,
    SelectedIdolInfo? selectedIdol,
    int interviewTurnCount,
    String? comparisonOutput,
    String? blueprintOutput,
    String? interviewThreadId,
    DateTime? createdAt,
    DateTime? updatedAt,
  });

  $SelectedIdolInfoCopyWith<$Res>? get selectedIdol;
}

/// @nodoc
class _$SessionCopyWithImpl<$Res, $Val extends Session>
    implements $SessionCopyWith<$Res> {
  _$SessionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? phase = null,
    Object? userAge = null,
    Object? userFinancialStatus = null,
    Object? userInterests = null,
    Object? selectedIdol = freezed,
    Object? interviewTurnCount = null,
    Object? comparisonOutput = freezed,
    Object? blueprintOutput = freezed,
    Object? interviewThreadId = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            phase: null == phase
                ? _value.phase
                : phase // ignore: cast_nullable_to_non_nullable
                      as SessionPhase,
            userAge: null == userAge
                ? _value.userAge
                : userAge // ignore: cast_nullable_to_non_nullable
                      as int,
            userFinancialStatus: null == userFinancialStatus
                ? _value.userFinancialStatus
                : userFinancialStatus // ignore: cast_nullable_to_non_nullable
                      as String,
            userInterests: null == userInterests
                ? _value.userInterests
                : userInterests // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            selectedIdol: freezed == selectedIdol
                ? _value.selectedIdol
                : selectedIdol // ignore: cast_nullable_to_non_nullable
                      as SelectedIdolInfo?,
            interviewTurnCount: null == interviewTurnCount
                ? _value.interviewTurnCount
                : interviewTurnCount // ignore: cast_nullable_to_non_nullable
                      as int,
            comparisonOutput: freezed == comparisonOutput
                ? _value.comparisonOutput
                : comparisonOutput // ignore: cast_nullable_to_non_nullable
                      as String?,
            blueprintOutput: freezed == blueprintOutput
                ? _value.blueprintOutput
                : blueprintOutput // ignore: cast_nullable_to_non_nullable
                      as String?,
            interviewThreadId: freezed == interviewThreadId
                ? _value.interviewThreadId
                : interviewThreadId // ignore: cast_nullable_to_non_nullable
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

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SelectedIdolInfoCopyWith<$Res>? get selectedIdol {
    if (_value.selectedIdol == null) {
      return null;
    }

    return $SelectedIdolInfoCopyWith<$Res>(_value.selectedIdol!, (value) {
      return _then(_value.copyWith(selectedIdol: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$SessionImplCopyWith<$Res> implements $SessionCopyWith<$Res> {
  factory _$$SessionImplCopyWith(
    _$SessionImpl value,
    $Res Function(_$SessionImpl) then,
  ) = __$$SessionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    SessionPhase phase,
    int userAge,
    String userFinancialStatus,
    List<String> userInterests,
    SelectedIdolInfo? selectedIdol,
    int interviewTurnCount,
    String? comparisonOutput,
    String? blueprintOutput,
    String? interviewThreadId,
    DateTime? createdAt,
    DateTime? updatedAt,
  });

  @override
  $SelectedIdolInfoCopyWith<$Res>? get selectedIdol;
}

/// @nodoc
class __$$SessionImplCopyWithImpl<$Res>
    extends _$SessionCopyWithImpl<$Res, _$SessionImpl>
    implements _$$SessionImplCopyWith<$Res> {
  __$$SessionImplCopyWithImpl(
    _$SessionImpl _value,
    $Res Function(_$SessionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? phase = null,
    Object? userAge = null,
    Object? userFinancialStatus = null,
    Object? userInterests = null,
    Object? selectedIdol = freezed,
    Object? interviewTurnCount = null,
    Object? comparisonOutput = freezed,
    Object? blueprintOutput = freezed,
    Object? interviewThreadId = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(
      _$SessionImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        phase: null == phase
            ? _value.phase
            : phase // ignore: cast_nullable_to_non_nullable
                  as SessionPhase,
        userAge: null == userAge
            ? _value.userAge
            : userAge // ignore: cast_nullable_to_non_nullable
                  as int,
        userFinancialStatus: null == userFinancialStatus
            ? _value.userFinancialStatus
            : userFinancialStatus // ignore: cast_nullable_to_non_nullable
                  as String,
        userInterests: null == userInterests
            ? _value._userInterests
            : userInterests // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        selectedIdol: freezed == selectedIdol
            ? _value.selectedIdol
            : selectedIdol // ignore: cast_nullable_to_non_nullable
                  as SelectedIdolInfo?,
        interviewTurnCount: null == interviewTurnCount
            ? _value.interviewTurnCount
            : interviewTurnCount // ignore: cast_nullable_to_non_nullable
                  as int,
        comparisonOutput: freezed == comparisonOutput
            ? _value.comparisonOutput
            : comparisonOutput // ignore: cast_nullable_to_non_nullable
                  as String?,
        blueprintOutput: freezed == blueprintOutput
            ? _value.blueprintOutput
            : blueprintOutput // ignore: cast_nullable_to_non_nullable
                  as String?,
        interviewThreadId: freezed == interviewThreadId
            ? _value.interviewThreadId
            : interviewThreadId // ignore: cast_nullable_to_non_nullable
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

class _$SessionImpl extends _Session {
  const _$SessionImpl({
    required this.id,
    required this.phase,
    required this.userAge,
    required this.userFinancialStatus,
    required final List<String> userInterests,
    this.selectedIdol,
    this.interviewTurnCount = 0,
    this.comparisonOutput,
    this.blueprintOutput,
    this.interviewThreadId,
    this.createdAt,
    this.updatedAt,
  }) : _userInterests = userInterests,
       super._();

  @override
  final String id;
  @override
  final SessionPhase phase;
  @override
  final int userAge;
  @override
  final String userFinancialStatus;
  final List<String> _userInterests;
  @override
  List<String> get userInterests {
    if (_userInterests is EqualUnmodifiableListView) return _userInterests;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_userInterests);
  }

  @override
  final SelectedIdolInfo? selectedIdol;
  @override
  @JsonKey()
  final int interviewTurnCount;
  @override
  final String? comparisonOutput;
  @override
  final String? blueprintOutput;
  @override
  final String? interviewThreadId;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;

  @override
  String toString() {
    return 'Session(id: $id, phase: $phase, userAge: $userAge, userFinancialStatus: $userFinancialStatus, userInterests: $userInterests, selectedIdol: $selectedIdol, interviewTurnCount: $interviewTurnCount, comparisonOutput: $comparisonOutput, blueprintOutput: $blueprintOutput, interviewThreadId: $interviewThreadId, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SessionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.phase, phase) || other.phase == phase) &&
            (identical(other.userAge, userAge) || other.userAge == userAge) &&
            (identical(other.userFinancialStatus, userFinancialStatus) ||
                other.userFinancialStatus == userFinancialStatus) &&
            const DeepCollectionEquality().equals(
              other._userInterests,
              _userInterests,
            ) &&
            (identical(other.selectedIdol, selectedIdol) ||
                other.selectedIdol == selectedIdol) &&
            (identical(other.interviewTurnCount, interviewTurnCount) ||
                other.interviewTurnCount == interviewTurnCount) &&
            (identical(other.comparisonOutput, comparisonOutput) ||
                other.comparisonOutput == comparisonOutput) &&
            (identical(other.blueprintOutput, blueprintOutput) ||
                other.blueprintOutput == blueprintOutput) &&
            (identical(other.interviewThreadId, interviewThreadId) ||
                other.interviewThreadId == interviewThreadId) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    phase,
    userAge,
    userFinancialStatus,
    const DeepCollectionEquality().hash(_userInterests),
    selectedIdol,
    interviewTurnCount,
    comparisonOutput,
    blueprintOutput,
    interviewThreadId,
    createdAt,
    updatedAt,
  );

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SessionImplCopyWith<_$SessionImpl> get copyWith =>
      __$$SessionImplCopyWithImpl<_$SessionImpl>(this, _$identity);
}

abstract class _Session extends Session {
  const factory _Session({
    required final String id,
    required final SessionPhase phase,
    required final int userAge,
    required final String userFinancialStatus,
    required final List<String> userInterests,
    final SelectedIdolInfo? selectedIdol,
    final int interviewTurnCount,
    final String? comparisonOutput,
    final String? blueprintOutput,
    final String? interviewThreadId,
    final DateTime? createdAt,
    final DateTime? updatedAt,
  }) = _$SessionImpl;
  const _Session._() : super._();

  @override
  String get id;
  @override
  SessionPhase get phase;
  @override
  int get userAge;
  @override
  String get userFinancialStatus;
  @override
  List<String> get userInterests;
  @override
  SelectedIdolInfo? get selectedIdol;
  @override
  int get interviewTurnCount;
  @override
  String? get comparisonOutput;
  @override
  String? get blueprintOutput;
  @override
  String? get interviewThreadId;
  @override
  DateTime? get createdAt;
  @override
  DateTime? get updatedAt;

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SessionImplCopyWith<_$SessionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$IdolSuggestion {
  String get name => throw _privateConstructorUsedError;
  String get era => throw _privateConstructorUsedError;
  String get relevanceSummary => throw _privateConstructorUsedError;
  String? get wikidataId => throw _privateConstructorUsedError;
  List<String> get domains => throw _privateConstructorUsedError;
  double get confidence => throw _privateConstructorUsedError;

  /// Create a copy of IdolSuggestion
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IdolSuggestionCopyWith<IdolSuggestion> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IdolSuggestionCopyWith<$Res> {
  factory $IdolSuggestionCopyWith(
    IdolSuggestion value,
    $Res Function(IdolSuggestion) then,
  ) = _$IdolSuggestionCopyWithImpl<$Res, IdolSuggestion>;
  @useResult
  $Res call({
    String name,
    String era,
    String relevanceSummary,
    String? wikidataId,
    List<String> domains,
    double confidence,
  });
}

/// @nodoc
class _$IdolSuggestionCopyWithImpl<$Res, $Val extends IdolSuggestion>
    implements $IdolSuggestionCopyWith<$Res> {
  _$IdolSuggestionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IdolSuggestion
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? era = null,
    Object? relevanceSummary = null,
    Object? wikidataId = freezed,
    Object? domains = null,
    Object? confidence = null,
  }) {
    return _then(
      _value.copyWith(
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            era: null == era
                ? _value.era
                : era // ignore: cast_nullable_to_non_nullable
                      as String,
            relevanceSummary: null == relevanceSummary
                ? _value.relevanceSummary
                : relevanceSummary // ignore: cast_nullable_to_non_nullable
                      as String,
            wikidataId: freezed == wikidataId
                ? _value.wikidataId
                : wikidataId // ignore: cast_nullable_to_non_nullable
                      as String?,
            domains: null == domains
                ? _value.domains
                : domains // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            confidence: null == confidence
                ? _value.confidence
                : confidence // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$IdolSuggestionImplCopyWith<$Res>
    implements $IdolSuggestionCopyWith<$Res> {
  factory _$$IdolSuggestionImplCopyWith(
    _$IdolSuggestionImpl value,
    $Res Function(_$IdolSuggestionImpl) then,
  ) = __$$IdolSuggestionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String name,
    String era,
    String relevanceSummary,
    String? wikidataId,
    List<String> domains,
    double confidence,
  });
}

/// @nodoc
class __$$IdolSuggestionImplCopyWithImpl<$Res>
    extends _$IdolSuggestionCopyWithImpl<$Res, _$IdolSuggestionImpl>
    implements _$$IdolSuggestionImplCopyWith<$Res> {
  __$$IdolSuggestionImplCopyWithImpl(
    _$IdolSuggestionImpl _value,
    $Res Function(_$IdolSuggestionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IdolSuggestion
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? era = null,
    Object? relevanceSummary = null,
    Object? wikidataId = freezed,
    Object? domains = null,
    Object? confidence = null,
  }) {
    return _then(
      _$IdolSuggestionImpl(
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        era: null == era
            ? _value.era
            : era // ignore: cast_nullable_to_non_nullable
                  as String,
        relevanceSummary: null == relevanceSummary
            ? _value.relevanceSummary
            : relevanceSummary // ignore: cast_nullable_to_non_nullable
                  as String,
        wikidataId: freezed == wikidataId
            ? _value.wikidataId
            : wikidataId // ignore: cast_nullable_to_non_nullable
                  as String?,
        domains: null == domains
            ? _value._domains
            : domains // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        confidence: null == confidence
            ? _value.confidence
            : confidence // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc

class _$IdolSuggestionImpl extends _IdolSuggestion {
  const _$IdolSuggestionImpl({
    required this.name,
    required this.era,
    required this.relevanceSummary,
    this.wikidataId,
    final List<String> domains = const [],
    this.confidence = 0.8,
  }) : _domains = domains,
       super._();

  @override
  final String name;
  @override
  final String era;
  @override
  final String relevanceSummary;
  @override
  final String? wikidataId;
  final List<String> _domains;
  @override
  @JsonKey()
  List<String> get domains {
    if (_domains is EqualUnmodifiableListView) return _domains;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_domains);
  }

  @override
  @JsonKey()
  final double confidence;

  @override
  String toString() {
    return 'IdolSuggestion(name: $name, era: $era, relevanceSummary: $relevanceSummary, wikidataId: $wikidataId, domains: $domains, confidence: $confidence)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IdolSuggestionImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.era, era) || other.era == era) &&
            (identical(other.relevanceSummary, relevanceSummary) ||
                other.relevanceSummary == relevanceSummary) &&
            (identical(other.wikidataId, wikidataId) ||
                other.wikidataId == wikidataId) &&
            const DeepCollectionEquality().equals(other._domains, _domains) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    name,
    era,
    relevanceSummary,
    wikidataId,
    const DeepCollectionEquality().hash(_domains),
    confidence,
  );

  /// Create a copy of IdolSuggestion
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IdolSuggestionImplCopyWith<_$IdolSuggestionImpl> get copyWith =>
      __$$IdolSuggestionImplCopyWithImpl<_$IdolSuggestionImpl>(
        this,
        _$identity,
      );
}

abstract class _IdolSuggestion extends IdolSuggestion {
  const factory _IdolSuggestion({
    required final String name,
    required final String era,
    required final String relevanceSummary,
    final String? wikidataId,
    final List<String> domains,
    final double confidence,
  }) = _$IdolSuggestionImpl;
  const _IdolSuggestion._() : super._();

  @override
  String get name;
  @override
  String get era;
  @override
  String get relevanceSummary;
  @override
  String? get wikidataId;
  @override
  List<String> get domains;
  @override
  double get confidence;

  /// Create a copy of IdolSuggestion
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IdolSuggestionImplCopyWith<_$IdolSuggestionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SessionCreateRequest {
  int get age => throw _privateConstructorUsedError;
  String get financialStatus => throw _privateConstructorUsedError;
  List<String> get interests => throw _privateConstructorUsedError;

  /// Create a copy of SessionCreateRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SessionCreateRequestCopyWith<SessionCreateRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SessionCreateRequestCopyWith<$Res> {
  factory $SessionCreateRequestCopyWith(
    SessionCreateRequest value,
    $Res Function(SessionCreateRequest) then,
  ) = _$SessionCreateRequestCopyWithImpl<$Res, SessionCreateRequest>;
  @useResult
  $Res call({int age, String financialStatus, List<String> interests});
}

/// @nodoc
class _$SessionCreateRequestCopyWithImpl<
  $Res,
  $Val extends SessionCreateRequest
>
    implements $SessionCreateRequestCopyWith<$Res> {
  _$SessionCreateRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SessionCreateRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? age = null,
    Object? financialStatus = null,
    Object? interests = null,
  }) {
    return _then(
      _value.copyWith(
            age: null == age
                ? _value.age
                : age // ignore: cast_nullable_to_non_nullable
                      as int,
            financialStatus: null == financialStatus
                ? _value.financialStatus
                : financialStatus // ignore: cast_nullable_to_non_nullable
                      as String,
            interests: null == interests
                ? _value.interests
                : interests // ignore: cast_nullable_to_non_nullable
                      as List<String>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SessionCreateRequestImplCopyWith<$Res>
    implements $SessionCreateRequestCopyWith<$Res> {
  factory _$$SessionCreateRequestImplCopyWith(
    _$SessionCreateRequestImpl value,
    $Res Function(_$SessionCreateRequestImpl) then,
  ) = __$$SessionCreateRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int age, String financialStatus, List<String> interests});
}

/// @nodoc
class __$$SessionCreateRequestImplCopyWithImpl<$Res>
    extends _$SessionCreateRequestCopyWithImpl<$Res, _$SessionCreateRequestImpl>
    implements _$$SessionCreateRequestImplCopyWith<$Res> {
  __$$SessionCreateRequestImplCopyWithImpl(
    _$SessionCreateRequestImpl _value,
    $Res Function(_$SessionCreateRequestImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SessionCreateRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? age = null,
    Object? financialStatus = null,
    Object? interests = null,
  }) {
    return _then(
      _$SessionCreateRequestImpl(
        age: null == age
            ? _value.age
            : age // ignore: cast_nullable_to_non_nullable
                  as int,
        financialStatus: null == financialStatus
            ? _value.financialStatus
            : financialStatus // ignore: cast_nullable_to_non_nullable
                  as String,
        interests: null == interests
            ? _value._interests
            : interests // ignore: cast_nullable_to_non_nullable
                  as List<String>,
      ),
    );
  }
}

/// @nodoc

class _$SessionCreateRequestImpl extends _SessionCreateRequest {
  const _$SessionCreateRequestImpl({
    required this.age,
    required this.financialStatus,
    required final List<String> interests,
  }) : _interests = interests,
       super._();

  @override
  final int age;
  @override
  final String financialStatus;
  final List<String> _interests;
  @override
  List<String> get interests {
    if (_interests is EqualUnmodifiableListView) return _interests;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_interests);
  }

  @override
  String toString() {
    return 'SessionCreateRequest(age: $age, financialStatus: $financialStatus, interests: $interests)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SessionCreateRequestImpl &&
            (identical(other.age, age) || other.age == age) &&
            (identical(other.financialStatus, financialStatus) ||
                other.financialStatus == financialStatus) &&
            const DeepCollectionEquality().equals(
              other._interests,
              _interests,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    age,
    financialStatus,
    const DeepCollectionEquality().hash(_interests),
  );

  /// Create a copy of SessionCreateRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SessionCreateRequestImplCopyWith<_$SessionCreateRequestImpl>
  get copyWith =>
      __$$SessionCreateRequestImplCopyWithImpl<_$SessionCreateRequestImpl>(
        this,
        _$identity,
      );
}

abstract class _SessionCreateRequest extends SessionCreateRequest {
  const factory _SessionCreateRequest({
    required final int age,
    required final String financialStatus,
    required final List<String> interests,
  }) = _$SessionCreateRequestImpl;
  const _SessionCreateRequest._() : super._();

  @override
  int get age;
  @override
  String get financialStatus;
  @override
  List<String> get interests;

  /// Create a copy of SessionCreateRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SessionCreateRequestImplCopyWith<_$SessionCreateRequestImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SelectIdolRequest {
  String get idolName => throw _privateConstructorUsedError;
  String? get wikidataId => throw _privateConstructorUsedError;

  /// Create a copy of SelectIdolRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SelectIdolRequestCopyWith<SelectIdolRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SelectIdolRequestCopyWith<$Res> {
  factory $SelectIdolRequestCopyWith(
    SelectIdolRequest value,
    $Res Function(SelectIdolRequest) then,
  ) = _$SelectIdolRequestCopyWithImpl<$Res, SelectIdolRequest>;
  @useResult
  $Res call({String idolName, String? wikidataId});
}

/// @nodoc
class _$SelectIdolRequestCopyWithImpl<$Res, $Val extends SelectIdolRequest>
    implements $SelectIdolRequestCopyWith<$Res> {
  _$SelectIdolRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SelectIdolRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? idolName = null, Object? wikidataId = freezed}) {
    return _then(
      _value.copyWith(
            idolName: null == idolName
                ? _value.idolName
                : idolName // ignore: cast_nullable_to_non_nullable
                      as String,
            wikidataId: freezed == wikidataId
                ? _value.wikidataId
                : wikidataId // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SelectIdolRequestImplCopyWith<$Res>
    implements $SelectIdolRequestCopyWith<$Res> {
  factory _$$SelectIdolRequestImplCopyWith(
    _$SelectIdolRequestImpl value,
    $Res Function(_$SelectIdolRequestImpl) then,
  ) = __$$SelectIdolRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String idolName, String? wikidataId});
}

/// @nodoc
class __$$SelectIdolRequestImplCopyWithImpl<$Res>
    extends _$SelectIdolRequestCopyWithImpl<$Res, _$SelectIdolRequestImpl>
    implements _$$SelectIdolRequestImplCopyWith<$Res> {
  __$$SelectIdolRequestImplCopyWithImpl(
    _$SelectIdolRequestImpl _value,
    $Res Function(_$SelectIdolRequestImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SelectIdolRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? idolName = null, Object? wikidataId = freezed}) {
    return _then(
      _$SelectIdolRequestImpl(
        idolName: null == idolName
            ? _value.idolName
            : idolName // ignore: cast_nullable_to_non_nullable
                  as String,
        wikidataId: freezed == wikidataId
            ? _value.wikidataId
            : wikidataId // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$SelectIdolRequestImpl extends _SelectIdolRequest {
  const _$SelectIdolRequestImpl({required this.idolName, this.wikidataId})
    : super._();

  @override
  final String idolName;
  @override
  final String? wikidataId;

  @override
  String toString() {
    return 'SelectIdolRequest(idolName: $idolName, wikidataId: $wikidataId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SelectIdolRequestImpl &&
            (identical(other.idolName, idolName) ||
                other.idolName == idolName) &&
            (identical(other.wikidataId, wikidataId) ||
                other.wikidataId == wikidataId));
  }

  @override
  int get hashCode => Object.hash(runtimeType, idolName, wikidataId);

  /// Create a copy of SelectIdolRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SelectIdolRequestImplCopyWith<_$SelectIdolRequestImpl> get copyWith =>
      __$$SelectIdolRequestImplCopyWithImpl<_$SelectIdolRequestImpl>(
        this,
        _$identity,
      );
}

abstract class _SelectIdolRequest extends SelectIdolRequest {
  const factory _SelectIdolRequest({
    required final String idolName,
    final String? wikidataId,
  }) = _$SelectIdolRequestImpl;
  const _SelectIdolRequest._() : super._();

  @override
  String get idolName;
  @override
  String? get wikidataId;

  /// Create a copy of SelectIdolRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SelectIdolRequestImplCopyWith<_$SelectIdolRequestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$LearningMaterial {
  String get title => throw _privateConstructorUsedError;
  String get url => throw _privateConstructorUsedError;
  String get type => throw _privateConstructorUsedError;
  String get summary => throw _privateConstructorUsedError;
  String? get contentResourceId => throw _privateConstructorUsedError;
  String? get canonicalKey => throw _privateConstructorUsedError;
  String? get licenseStatus => throw _privateConstructorUsedError;
  String? get thumbnailUrl => throw _privateConstructorUsedError;
  int? get durationMinutes => throw _privateConstructorUsedError;

  /// Create a copy of LearningMaterial
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $LearningMaterialCopyWith<LearningMaterial> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LearningMaterialCopyWith<$Res> {
  factory $LearningMaterialCopyWith(
    LearningMaterial value,
    $Res Function(LearningMaterial) then,
  ) = _$LearningMaterialCopyWithImpl<$Res, LearningMaterial>;
  @useResult
  $Res call({
    String title,
    String url,
    String type,
    String summary,
    String? contentResourceId,
    String? canonicalKey,
    String? licenseStatus,
    String? thumbnailUrl,
    int? durationMinutes,
  });
}

/// @nodoc
class _$LearningMaterialCopyWithImpl<$Res, $Val extends LearningMaterial>
    implements $LearningMaterialCopyWith<$Res> {
  _$LearningMaterialCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of LearningMaterial
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = null,
    Object? url = null,
    Object? type = null,
    Object? summary = null,
    Object? contentResourceId = freezed,
    Object? canonicalKey = freezed,
    Object? licenseStatus = freezed,
    Object? thumbnailUrl = freezed,
    Object? durationMinutes = freezed,
  }) {
    return _then(
      _value.copyWith(
            title: null == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String,
            url: null == url
                ? _value.url
                : url // ignore: cast_nullable_to_non_nullable
                      as String,
            type: null == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as String,
            summary: null == summary
                ? _value.summary
                : summary // ignore: cast_nullable_to_non_nullable
                      as String,
            contentResourceId: freezed == contentResourceId
                ? _value.contentResourceId
                : contentResourceId // ignore: cast_nullable_to_non_nullable
                      as String?,
            canonicalKey: freezed == canonicalKey
                ? _value.canonicalKey
                : canonicalKey // ignore: cast_nullable_to_non_nullable
                      as String?,
            licenseStatus: freezed == licenseStatus
                ? _value.licenseStatus
                : licenseStatus // ignore: cast_nullable_to_non_nullable
                      as String?,
            thumbnailUrl: freezed == thumbnailUrl
                ? _value.thumbnailUrl
                : thumbnailUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            durationMinutes: freezed == durationMinutes
                ? _value.durationMinutes
                : durationMinutes // ignore: cast_nullable_to_non_nullable
                      as int?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$LearningMaterialImplCopyWith<$Res>
    implements $LearningMaterialCopyWith<$Res> {
  factory _$$LearningMaterialImplCopyWith(
    _$LearningMaterialImpl value,
    $Res Function(_$LearningMaterialImpl) then,
  ) = __$$LearningMaterialImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String title,
    String url,
    String type,
    String summary,
    String? contentResourceId,
    String? canonicalKey,
    String? licenseStatus,
    String? thumbnailUrl,
    int? durationMinutes,
  });
}

/// @nodoc
class __$$LearningMaterialImplCopyWithImpl<$Res>
    extends _$LearningMaterialCopyWithImpl<$Res, _$LearningMaterialImpl>
    implements _$$LearningMaterialImplCopyWith<$Res> {
  __$$LearningMaterialImplCopyWithImpl(
    _$LearningMaterialImpl _value,
    $Res Function(_$LearningMaterialImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of LearningMaterial
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = null,
    Object? url = null,
    Object? type = null,
    Object? summary = null,
    Object? contentResourceId = freezed,
    Object? canonicalKey = freezed,
    Object? licenseStatus = freezed,
    Object? thumbnailUrl = freezed,
    Object? durationMinutes = freezed,
  }) {
    return _then(
      _$LearningMaterialImpl(
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        url: null == url
            ? _value.url
            : url // ignore: cast_nullable_to_non_nullable
                  as String,
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as String,
        summary: null == summary
            ? _value.summary
            : summary // ignore: cast_nullable_to_non_nullable
                  as String,
        contentResourceId: freezed == contentResourceId
            ? _value.contentResourceId
            : contentResourceId // ignore: cast_nullable_to_non_nullable
                  as String?,
        canonicalKey: freezed == canonicalKey
            ? _value.canonicalKey
            : canonicalKey // ignore: cast_nullable_to_non_nullable
                  as String?,
        licenseStatus: freezed == licenseStatus
            ? _value.licenseStatus
            : licenseStatus // ignore: cast_nullable_to_non_nullable
                  as String?,
        thumbnailUrl: freezed == thumbnailUrl
            ? _value.thumbnailUrl
            : thumbnailUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        durationMinutes: freezed == durationMinutes
            ? _value.durationMinutes
            : durationMinutes // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc

class _$LearningMaterialImpl extends _LearningMaterial {
  const _$LearningMaterialImpl({
    required this.title,
    required this.url,
    required this.type,
    required this.summary,
    this.contentResourceId,
    this.canonicalKey,
    this.licenseStatus,
    this.thumbnailUrl,
    this.durationMinutes,
  }) : super._();

  @override
  final String title;
  @override
  final String url;
  @override
  final String type;
  @override
  final String summary;
  @override
  final String? contentResourceId;
  @override
  final String? canonicalKey;
  @override
  final String? licenseStatus;
  @override
  final String? thumbnailUrl;
  @override
  final int? durationMinutes;

  @override
  String toString() {
    return 'LearningMaterial(title: $title, url: $url, type: $type, summary: $summary, contentResourceId: $contentResourceId, canonicalKey: $canonicalKey, licenseStatus: $licenseStatus, thumbnailUrl: $thumbnailUrl, durationMinutes: $durationMinutes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LearningMaterialImpl &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.summary, summary) || other.summary == summary) &&
            (identical(other.contentResourceId, contentResourceId) ||
                other.contentResourceId == contentResourceId) &&
            (identical(other.canonicalKey, canonicalKey) ||
                other.canonicalKey == canonicalKey) &&
            (identical(other.licenseStatus, licenseStatus) ||
                other.licenseStatus == licenseStatus) &&
            (identical(other.thumbnailUrl, thumbnailUrl) ||
                other.thumbnailUrl == thumbnailUrl) &&
            (identical(other.durationMinutes, durationMinutes) ||
                other.durationMinutes == durationMinutes));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    title,
    url,
    type,
    summary,
    contentResourceId,
    canonicalKey,
    licenseStatus,
    thumbnailUrl,
    durationMinutes,
  );

  /// Create a copy of LearningMaterial
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$LearningMaterialImplCopyWith<_$LearningMaterialImpl> get copyWith =>
      __$$LearningMaterialImplCopyWithImpl<_$LearningMaterialImpl>(
        this,
        _$identity,
      );
}

abstract class _LearningMaterial extends LearningMaterial {
  const factory _LearningMaterial({
    required final String title,
    required final String url,
    required final String type,
    required final String summary,
    final String? contentResourceId,
    final String? canonicalKey,
    final String? licenseStatus,
    final String? thumbnailUrl,
    final int? durationMinutes,
  }) = _$LearningMaterialImpl;
  const _LearningMaterial._() : super._();

  @override
  String get title;
  @override
  String get url;
  @override
  String get type;
  @override
  String get summary;
  @override
  String? get contentResourceId;
  @override
  String? get canonicalKey;
  @override
  String? get licenseStatus;
  @override
  String? get thumbnailUrl;
  @override
  int? get durationMinutes;

  /// Create a copy of LearningMaterial
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$LearningMaterialImplCopyWith<_$LearningMaterialImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$DailyInsight {
  String get title => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  String get category => throw _privateConstructorUsedError;

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
  $Res call({String title, String content, String category});
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
  $Res call({String title, String content, String category});
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
      ),
    );
  }
}

/// @nodoc

class _$DailyInsightImpl extends _DailyInsight {
  const _$DailyInsightImpl({
    required this.title,
    required this.content,
    required this.category,
  }) : super._();

  @override
  final String title;
  @override
  final String content;
  @override
  final String category;

  @override
  String toString() {
    return 'DailyInsight(title: $title, content: $content, category: $category)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DailyInsightImpl &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.category, category) ||
                other.category == category));
  }

  @override
  int get hashCode => Object.hash(runtimeType, title, content, category);

  /// Create a copy of DailyInsight
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DailyInsightImplCopyWith<_$DailyInsightImpl> get copyWith =>
      __$$DailyInsightImplCopyWithImpl<_$DailyInsightImpl>(this, _$identity);
}

abstract class _DailyInsight extends DailyInsight {
  const factory _DailyInsight({
    required final String title,
    required final String content,
    required final String category,
  }) = _$DailyInsightImpl;
  const _DailyInsight._() : super._();

  @override
  String get title;
  @override
  String get content;
  @override
  String get category;

  /// Create a copy of DailyInsight
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DailyInsightImplCopyWith<_$DailyInsightImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$DailyFeedResponse {
  List<DailyInsight> get insights => throw _privateConstructorUsedError;

  /// Create a copy of DailyFeedResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DailyFeedResponseCopyWith<DailyFeedResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DailyFeedResponseCopyWith<$Res> {
  factory $DailyFeedResponseCopyWith(
    DailyFeedResponse value,
    $Res Function(DailyFeedResponse) then,
  ) = _$DailyFeedResponseCopyWithImpl<$Res, DailyFeedResponse>;
  @useResult
  $Res call({List<DailyInsight> insights});
}

/// @nodoc
class _$DailyFeedResponseCopyWithImpl<$Res, $Val extends DailyFeedResponse>
    implements $DailyFeedResponseCopyWith<$Res> {
  _$DailyFeedResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DailyFeedResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? insights = null}) {
    return _then(
      _value.copyWith(
            insights: null == insights
                ? _value.insights
                : insights // ignore: cast_nullable_to_non_nullable
                      as List<DailyInsight>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$DailyFeedResponseImplCopyWith<$Res>
    implements $DailyFeedResponseCopyWith<$Res> {
  factory _$$DailyFeedResponseImplCopyWith(
    _$DailyFeedResponseImpl value,
    $Res Function(_$DailyFeedResponseImpl) then,
  ) = __$$DailyFeedResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<DailyInsight> insights});
}

/// @nodoc
class __$$DailyFeedResponseImplCopyWithImpl<$Res>
    extends _$DailyFeedResponseCopyWithImpl<$Res, _$DailyFeedResponseImpl>
    implements _$$DailyFeedResponseImplCopyWith<$Res> {
  __$$DailyFeedResponseImplCopyWithImpl(
    _$DailyFeedResponseImpl _value,
    $Res Function(_$DailyFeedResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of DailyFeedResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? insights = null}) {
    return _then(
      _$DailyFeedResponseImpl(
        insights: null == insights
            ? _value._insights
            : insights // ignore: cast_nullable_to_non_nullable
                  as List<DailyInsight>,
      ),
    );
  }
}

/// @nodoc

class _$DailyFeedResponseImpl extends _DailyFeedResponse {
  const _$DailyFeedResponseImpl({final List<DailyInsight> insights = const []})
    : _insights = insights,
      super._();

  final List<DailyInsight> _insights;
  @override
  @JsonKey()
  List<DailyInsight> get insights {
    if (_insights is EqualUnmodifiableListView) return _insights;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_insights);
  }

  @override
  String toString() {
    return 'DailyFeedResponse(insights: $insights)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DailyFeedResponseImpl &&
            const DeepCollectionEquality().equals(other._insights, _insights));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(_insights));

  /// Create a copy of DailyFeedResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DailyFeedResponseImplCopyWith<_$DailyFeedResponseImpl> get copyWith =>
      __$$DailyFeedResponseImplCopyWithImpl<_$DailyFeedResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _DailyFeedResponse extends DailyFeedResponse {
  const factory _DailyFeedResponse({final List<DailyInsight> insights}) =
      _$DailyFeedResponseImpl;
  const _DailyFeedResponse._() : super._();

  @override
  List<DailyInsight> get insights;

  /// Create a copy of DailyFeedResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DailyFeedResponseImplCopyWith<_$DailyFeedResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
