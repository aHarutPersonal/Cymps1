// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'timeline_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Evidence {
  String? get sourceId => throw _privateConstructorUsedError;
  int? get chunkIndex => throw _privateConstructorUsedError;
  String? get sourceUrl => throw _privateConstructorUsedError;
  String? get snippet => throw _privateConstructorUsedError;
  double? get confidence => throw _privateConstructorUsedError;

  /// Create a copy of Evidence
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $EvidenceCopyWith<Evidence> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EvidenceCopyWith<$Res> {
  factory $EvidenceCopyWith(Evidence value, $Res Function(Evidence) then) =
      _$EvidenceCopyWithImpl<$Res, Evidence>;
  @useResult
  $Res call({
    String? sourceId,
    int? chunkIndex,
    String? sourceUrl,
    String? snippet,
    double? confidence,
  });
}

/// @nodoc
class _$EvidenceCopyWithImpl<$Res, $Val extends Evidence>
    implements $EvidenceCopyWith<$Res> {
  _$EvidenceCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Evidence
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sourceId = freezed,
    Object? chunkIndex = freezed,
    Object? sourceUrl = freezed,
    Object? snippet = freezed,
    Object? confidence = freezed,
  }) {
    return _then(
      _value.copyWith(
            sourceId: freezed == sourceId
                ? _value.sourceId
                : sourceId // ignore: cast_nullable_to_non_nullable
                      as String?,
            chunkIndex: freezed == chunkIndex
                ? _value.chunkIndex
                : chunkIndex // ignore: cast_nullable_to_non_nullable
                      as int?,
            sourceUrl: freezed == sourceUrl
                ? _value.sourceUrl
                : sourceUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            snippet: freezed == snippet
                ? _value.snippet
                : snippet // ignore: cast_nullable_to_non_nullable
                      as String?,
            confidence: freezed == confidence
                ? _value.confidence
                : confidence // ignore: cast_nullable_to_non_nullable
                      as double?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$EvidenceImplCopyWith<$Res>
    implements $EvidenceCopyWith<$Res> {
  factory _$$EvidenceImplCopyWith(
    _$EvidenceImpl value,
    $Res Function(_$EvidenceImpl) then,
  ) = __$$EvidenceImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String? sourceId,
    int? chunkIndex,
    String? sourceUrl,
    String? snippet,
    double? confidence,
  });
}

/// @nodoc
class __$$EvidenceImplCopyWithImpl<$Res>
    extends _$EvidenceCopyWithImpl<$Res, _$EvidenceImpl>
    implements _$$EvidenceImplCopyWith<$Res> {
  __$$EvidenceImplCopyWithImpl(
    _$EvidenceImpl _value,
    $Res Function(_$EvidenceImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Evidence
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sourceId = freezed,
    Object? chunkIndex = freezed,
    Object? sourceUrl = freezed,
    Object? snippet = freezed,
    Object? confidence = freezed,
  }) {
    return _then(
      _$EvidenceImpl(
        sourceId: freezed == sourceId
            ? _value.sourceId
            : sourceId // ignore: cast_nullable_to_non_nullable
                  as String?,
        chunkIndex: freezed == chunkIndex
            ? _value.chunkIndex
            : chunkIndex // ignore: cast_nullable_to_non_nullable
                  as int?,
        sourceUrl: freezed == sourceUrl
            ? _value.sourceUrl
            : sourceUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        snippet: freezed == snippet
            ? _value.snippet
            : snippet // ignore: cast_nullable_to_non_nullable
                  as String?,
        confidence: freezed == confidence
            ? _value.confidence
            : confidence // ignore: cast_nullable_to_non_nullable
                  as double?,
      ),
    );
  }
}

/// @nodoc

class _$EvidenceImpl implements _Evidence {
  const _$EvidenceImpl({
    this.sourceId,
    this.chunkIndex,
    this.sourceUrl,
    this.snippet,
    this.confidence,
  });

  @override
  final String? sourceId;
  @override
  final int? chunkIndex;
  @override
  final String? sourceUrl;
  @override
  final String? snippet;
  @override
  final double? confidence;

  @override
  String toString() {
    return 'Evidence(sourceId: $sourceId, chunkIndex: $chunkIndex, sourceUrl: $sourceUrl, snippet: $snippet, confidence: $confidence)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EvidenceImpl &&
            (identical(other.sourceId, sourceId) ||
                other.sourceId == sourceId) &&
            (identical(other.chunkIndex, chunkIndex) ||
                other.chunkIndex == chunkIndex) &&
            (identical(other.sourceUrl, sourceUrl) ||
                other.sourceUrl == sourceUrl) &&
            (identical(other.snippet, snippet) || other.snippet == snippet) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    sourceId,
    chunkIndex,
    sourceUrl,
    snippet,
    confidence,
  );

  /// Create a copy of Evidence
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$EvidenceImplCopyWith<_$EvidenceImpl> get copyWith =>
      __$$EvidenceImplCopyWithImpl<_$EvidenceImpl>(this, _$identity);
}

abstract class _Evidence implements Evidence {
  const factory _Evidence({
    final String? sourceId,
    final int? chunkIndex,
    final String? sourceUrl,
    final String? snippet,
    final double? confidence,
  }) = _$EvidenceImpl;

  @override
  String? get sourceId;
  @override
  int? get chunkIndex;
  @override
  String? get sourceUrl;
  @override
  String? get snippet;
  @override
  double? get confidence;

  /// Create a copy of Evidence
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$EvidenceImplCopyWith<_$EvidenceImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$TimelineItem {
  String? get id => throw _privateConstructorUsedError;

  /// Title of the milestone (backend may use 'canonical_title' or 'title')
  String? get canonicalTitle => throw _privateConstructorUsedError;
  String? get title => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  int? get ageAtEvent => throw _privateConstructorUsedError;
  String? get category => throw _privateConstructorUsedError;
  double? get importanceScore => throw _privateConstructorUsedError;
  double? get confidence => throw _privateConstructorUsedError;
  List<Evidence> get evidence => throw _privateConstructorUsedError;
  String? get dateText => throw _privateConstructorUsedError;
  DateTime? get date => throw _privateConstructorUsedError;

  /// Create a copy of TimelineItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TimelineItemCopyWith<TimelineItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TimelineItemCopyWith<$Res> {
  factory $TimelineItemCopyWith(
    TimelineItem value,
    $Res Function(TimelineItem) then,
  ) = _$TimelineItemCopyWithImpl<$Res, TimelineItem>;
  @useResult
  $Res call({
    String? id,
    String? canonicalTitle,
    String? title,
    String? description,
    int? ageAtEvent,
    String? category,
    double? importanceScore,
    double? confidence,
    List<Evidence> evidence,
    String? dateText,
    DateTime? date,
  });
}

/// @nodoc
class _$TimelineItemCopyWithImpl<$Res, $Val extends TimelineItem>
    implements $TimelineItemCopyWith<$Res> {
  _$TimelineItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TimelineItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? canonicalTitle = freezed,
    Object? title = freezed,
    Object? description = freezed,
    Object? ageAtEvent = freezed,
    Object? category = freezed,
    Object? importanceScore = freezed,
    Object? confidence = freezed,
    Object? evidence = null,
    Object? dateText = freezed,
    Object? date = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: freezed == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String?,
            canonicalTitle: freezed == canonicalTitle
                ? _value.canonicalTitle
                : canonicalTitle // ignore: cast_nullable_to_non_nullable
                      as String?,
            title: freezed == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String?,
            description: freezed == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String?,
            ageAtEvent: freezed == ageAtEvent
                ? _value.ageAtEvent
                : ageAtEvent // ignore: cast_nullable_to_non_nullable
                      as int?,
            category: freezed == category
                ? _value.category
                : category // ignore: cast_nullable_to_non_nullable
                      as String?,
            importanceScore: freezed == importanceScore
                ? _value.importanceScore
                : importanceScore // ignore: cast_nullable_to_non_nullable
                      as double?,
            confidence: freezed == confidence
                ? _value.confidence
                : confidence // ignore: cast_nullable_to_non_nullable
                      as double?,
            evidence: null == evidence
                ? _value.evidence
                : evidence // ignore: cast_nullable_to_non_nullable
                      as List<Evidence>,
            dateText: freezed == dateText
                ? _value.dateText
                : dateText // ignore: cast_nullable_to_non_nullable
                      as String?,
            date: freezed == date
                ? _value.date
                : date // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$TimelineItemImplCopyWith<$Res>
    implements $TimelineItemCopyWith<$Res> {
  factory _$$TimelineItemImplCopyWith(
    _$TimelineItemImpl value,
    $Res Function(_$TimelineItemImpl) then,
  ) = __$$TimelineItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String? id,
    String? canonicalTitle,
    String? title,
    String? description,
    int? ageAtEvent,
    String? category,
    double? importanceScore,
    double? confidence,
    List<Evidence> evidence,
    String? dateText,
    DateTime? date,
  });
}

/// @nodoc
class __$$TimelineItemImplCopyWithImpl<$Res>
    extends _$TimelineItemCopyWithImpl<$Res, _$TimelineItemImpl>
    implements _$$TimelineItemImplCopyWith<$Res> {
  __$$TimelineItemImplCopyWithImpl(
    _$TimelineItemImpl _value,
    $Res Function(_$TimelineItemImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of TimelineItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? canonicalTitle = freezed,
    Object? title = freezed,
    Object? description = freezed,
    Object? ageAtEvent = freezed,
    Object? category = freezed,
    Object? importanceScore = freezed,
    Object? confidence = freezed,
    Object? evidence = null,
    Object? dateText = freezed,
    Object? date = freezed,
  }) {
    return _then(
      _$TimelineItemImpl(
        id: freezed == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String?,
        canonicalTitle: freezed == canonicalTitle
            ? _value.canonicalTitle
            : canonicalTitle // ignore: cast_nullable_to_non_nullable
                  as String?,
        title: freezed == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String?,
        description: freezed == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String?,
        ageAtEvent: freezed == ageAtEvent
            ? _value.ageAtEvent
            : ageAtEvent // ignore: cast_nullable_to_non_nullable
                  as int?,
        category: freezed == category
            ? _value.category
            : category // ignore: cast_nullable_to_non_nullable
                  as String?,
        importanceScore: freezed == importanceScore
            ? _value.importanceScore
            : importanceScore // ignore: cast_nullable_to_non_nullable
                  as double?,
        confidence: freezed == confidence
            ? _value.confidence
            : confidence // ignore: cast_nullable_to_non_nullable
                  as double?,
        evidence: null == evidence
            ? _value._evidence
            : evidence // ignore: cast_nullable_to_non_nullable
                  as List<Evidence>,
        dateText: freezed == dateText
            ? _value.dateText
            : dateText // ignore: cast_nullable_to_non_nullable
                  as String?,
        date: freezed == date
            ? _value.date
            : date // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
      ),
    );
  }
}

/// @nodoc

class _$TimelineItemImpl extends _TimelineItem {
  const _$TimelineItemImpl({
    this.id,
    this.canonicalTitle,
    this.title,
    this.description,
    this.ageAtEvent,
    this.category,
    this.importanceScore,
    this.confidence,
    final List<Evidence> evidence = const [],
    this.dateText,
    this.date,
  }) : _evidence = evidence,
       super._();

  @override
  final String? id;

  /// Title of the milestone (backend may use 'canonical_title' or 'title')
  @override
  final String? canonicalTitle;
  @override
  final String? title;
  @override
  final String? description;
  @override
  final int? ageAtEvent;
  @override
  final String? category;
  @override
  final double? importanceScore;
  @override
  final double? confidence;
  final List<Evidence> _evidence;
  @override
  @JsonKey()
  List<Evidence> get evidence {
    if (_evidence is EqualUnmodifiableListView) return _evidence;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_evidence);
  }

  @override
  final String? dateText;
  @override
  final DateTime? date;

  @override
  String toString() {
    return 'TimelineItem(id: $id, canonicalTitle: $canonicalTitle, title: $title, description: $description, ageAtEvent: $ageAtEvent, category: $category, importanceScore: $importanceScore, confidence: $confidence, evidence: $evidence, dateText: $dateText, date: $date)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TimelineItemImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.canonicalTitle, canonicalTitle) ||
                other.canonicalTitle == canonicalTitle) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.ageAtEvent, ageAtEvent) ||
                other.ageAtEvent == ageAtEvent) &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.importanceScore, importanceScore) ||
                other.importanceScore == importanceScore) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence) &&
            const DeepCollectionEquality().equals(other._evidence, _evidence) &&
            (identical(other.dateText, dateText) ||
                other.dateText == dateText) &&
            (identical(other.date, date) || other.date == date));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    canonicalTitle,
    title,
    description,
    ageAtEvent,
    category,
    importanceScore,
    confidence,
    const DeepCollectionEquality().hash(_evidence),
    dateText,
    date,
  );

  /// Create a copy of TimelineItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TimelineItemImplCopyWith<_$TimelineItemImpl> get copyWith =>
      __$$TimelineItemImplCopyWithImpl<_$TimelineItemImpl>(this, _$identity);
}

abstract class _TimelineItem extends TimelineItem {
  const factory _TimelineItem({
    final String? id,
    final String? canonicalTitle,
    final String? title,
    final String? description,
    final int? ageAtEvent,
    final String? category,
    final double? importanceScore,
    final double? confidence,
    final List<Evidence> evidence,
    final String? dateText,
    final DateTime? date,
  }) = _$TimelineItemImpl;
  const _TimelineItem._() : super._();

  @override
  String? get id;

  /// Title of the milestone (backend may use 'canonical_title' or 'title')
  @override
  String? get canonicalTitle;
  @override
  String? get title;
  @override
  String? get description;
  @override
  int? get ageAtEvent;
  @override
  String? get category;
  @override
  double? get importanceScore;
  @override
  double? get confidence;
  @override
  List<Evidence> get evidence;
  @override
  String? get dateText;
  @override
  DateTime? get date;

  /// Create a copy of TimelineItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TimelineItemImplCopyWith<_$TimelineItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$TimelineResponse {
  /// Backend returns 'events', but we also check 'timeline' and 'milestones' for compatibility
  List<TimelineItem> get events => throw _privateConstructorUsedError;
  List<TimelineItem> get timeline => throw _privateConstructorUsedError;
  List<TimelineItem> get milestones => throw _privateConstructorUsedError;
  double? get completenessEstimate => throw _privateConstructorUsedError;
  int? get totalCount => throw _privateConstructorUsedError;
  int? get totalEvents => throw _privateConstructorUsedError;
  String? get idolId => throw _privateConstructorUsedError;
  String? get idolName => throw _privateConstructorUsedError;
  String? get mode => throw _privateConstructorUsedError;
  int? get age => throw _privateConstructorUsedError;
  String? get idol => throw _privateConstructorUsedError;

  /// Create a copy of TimelineResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TimelineResponseCopyWith<TimelineResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TimelineResponseCopyWith<$Res> {
  factory $TimelineResponseCopyWith(
    TimelineResponse value,
    $Res Function(TimelineResponse) then,
  ) = _$TimelineResponseCopyWithImpl<$Res, TimelineResponse>;
  @useResult
  $Res call({
    List<TimelineItem> events,
    List<TimelineItem> timeline,
    List<TimelineItem> milestones,
    double? completenessEstimate,
    int? totalCount,
    int? totalEvents,
    String? idolId,
    String? idolName,
    String? mode,
    int? age,
    String? idol,
  });
}

/// @nodoc
class _$TimelineResponseCopyWithImpl<$Res, $Val extends TimelineResponse>
    implements $TimelineResponseCopyWith<$Res> {
  _$TimelineResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TimelineResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? events = null,
    Object? timeline = null,
    Object? milestones = null,
    Object? completenessEstimate = freezed,
    Object? totalCount = freezed,
    Object? totalEvents = freezed,
    Object? idolId = freezed,
    Object? idolName = freezed,
    Object? mode = freezed,
    Object? age = freezed,
    Object? idol = freezed,
  }) {
    return _then(
      _value.copyWith(
            events: null == events
                ? _value.events
                : events // ignore: cast_nullable_to_non_nullable
                      as List<TimelineItem>,
            timeline: null == timeline
                ? _value.timeline
                : timeline // ignore: cast_nullable_to_non_nullable
                      as List<TimelineItem>,
            milestones: null == milestones
                ? _value.milestones
                : milestones // ignore: cast_nullable_to_non_nullable
                      as List<TimelineItem>,
            completenessEstimate: freezed == completenessEstimate
                ? _value.completenessEstimate
                : completenessEstimate // ignore: cast_nullable_to_non_nullable
                      as double?,
            totalCount: freezed == totalCount
                ? _value.totalCount
                : totalCount // ignore: cast_nullable_to_non_nullable
                      as int?,
            totalEvents: freezed == totalEvents
                ? _value.totalEvents
                : totalEvents // ignore: cast_nullable_to_non_nullable
                      as int?,
            idolId: freezed == idolId
                ? _value.idolId
                : idolId // ignore: cast_nullable_to_non_nullable
                      as String?,
            idolName: freezed == idolName
                ? _value.idolName
                : idolName // ignore: cast_nullable_to_non_nullable
                      as String?,
            mode: freezed == mode
                ? _value.mode
                : mode // ignore: cast_nullable_to_non_nullable
                      as String?,
            age: freezed == age
                ? _value.age
                : age // ignore: cast_nullable_to_non_nullable
                      as int?,
            idol: freezed == idol
                ? _value.idol
                : idol // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$TimelineResponseImplCopyWith<$Res>
    implements $TimelineResponseCopyWith<$Res> {
  factory _$$TimelineResponseImplCopyWith(
    _$TimelineResponseImpl value,
    $Res Function(_$TimelineResponseImpl) then,
  ) = __$$TimelineResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    List<TimelineItem> events,
    List<TimelineItem> timeline,
    List<TimelineItem> milestones,
    double? completenessEstimate,
    int? totalCount,
    int? totalEvents,
    String? idolId,
    String? idolName,
    String? mode,
    int? age,
    String? idol,
  });
}

/// @nodoc
class __$$TimelineResponseImplCopyWithImpl<$Res>
    extends _$TimelineResponseCopyWithImpl<$Res, _$TimelineResponseImpl>
    implements _$$TimelineResponseImplCopyWith<$Res> {
  __$$TimelineResponseImplCopyWithImpl(
    _$TimelineResponseImpl _value,
    $Res Function(_$TimelineResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of TimelineResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? events = null,
    Object? timeline = null,
    Object? milestones = null,
    Object? completenessEstimate = freezed,
    Object? totalCount = freezed,
    Object? totalEvents = freezed,
    Object? idolId = freezed,
    Object? idolName = freezed,
    Object? mode = freezed,
    Object? age = freezed,
    Object? idol = freezed,
  }) {
    return _then(
      _$TimelineResponseImpl(
        events: null == events
            ? _value._events
            : events // ignore: cast_nullable_to_non_nullable
                  as List<TimelineItem>,
        timeline: null == timeline
            ? _value._timeline
            : timeline // ignore: cast_nullable_to_non_nullable
                  as List<TimelineItem>,
        milestones: null == milestones
            ? _value._milestones
            : milestones // ignore: cast_nullable_to_non_nullable
                  as List<TimelineItem>,
        completenessEstimate: freezed == completenessEstimate
            ? _value.completenessEstimate
            : completenessEstimate // ignore: cast_nullable_to_non_nullable
                  as double?,
        totalCount: freezed == totalCount
            ? _value.totalCount
            : totalCount // ignore: cast_nullable_to_non_nullable
                  as int?,
        totalEvents: freezed == totalEvents
            ? _value.totalEvents
            : totalEvents // ignore: cast_nullable_to_non_nullable
                  as int?,
        idolId: freezed == idolId
            ? _value.idolId
            : idolId // ignore: cast_nullable_to_non_nullable
                  as String?,
        idolName: freezed == idolName
            ? _value.idolName
            : idolName // ignore: cast_nullable_to_non_nullable
                  as String?,
        mode: freezed == mode
            ? _value.mode
            : mode // ignore: cast_nullable_to_non_nullable
                  as String?,
        age: freezed == age
            ? _value.age
            : age // ignore: cast_nullable_to_non_nullable
                  as int?,
        idol: freezed == idol
            ? _value.idol
            : idol // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$TimelineResponseImpl extends _TimelineResponse {
  const _$TimelineResponseImpl({
    final List<TimelineItem> events = const [],
    final List<TimelineItem> timeline = const [],
    final List<TimelineItem> milestones = const [],
    this.completenessEstimate,
    this.totalCount,
    this.totalEvents,
    this.idolId,
    this.idolName,
    this.mode,
    this.age,
    this.idol,
  }) : _events = events,
       _timeline = timeline,
       _milestones = milestones,
       super._();

  /// Backend returns 'events', but we also check 'timeline' and 'milestones' for compatibility
  final List<TimelineItem> _events;

  /// Backend returns 'events', but we also check 'timeline' and 'milestones' for compatibility
  @override
  @JsonKey()
  List<TimelineItem> get events {
    if (_events is EqualUnmodifiableListView) return _events;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_events);
  }

  final List<TimelineItem> _timeline;
  @override
  @JsonKey()
  List<TimelineItem> get timeline {
    if (_timeline is EqualUnmodifiableListView) return _timeline;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_timeline);
  }

  final List<TimelineItem> _milestones;
  @override
  @JsonKey()
  List<TimelineItem> get milestones {
    if (_milestones is EqualUnmodifiableListView) return _milestones;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_milestones);
  }

  @override
  final double? completenessEstimate;
  @override
  final int? totalCount;
  @override
  final int? totalEvents;
  @override
  final String? idolId;
  @override
  final String? idolName;
  @override
  final String? mode;
  @override
  final int? age;
  @override
  final String? idol;

  @override
  String toString() {
    return 'TimelineResponse(events: $events, timeline: $timeline, milestones: $milestones, completenessEstimate: $completenessEstimate, totalCount: $totalCount, totalEvents: $totalEvents, idolId: $idolId, idolName: $idolName, mode: $mode, age: $age, idol: $idol)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TimelineResponseImpl &&
            const DeepCollectionEquality().equals(other._events, _events) &&
            const DeepCollectionEquality().equals(other._timeline, _timeline) &&
            const DeepCollectionEquality().equals(
              other._milestones,
              _milestones,
            ) &&
            (identical(other.completenessEstimate, completenessEstimate) ||
                other.completenessEstimate == completenessEstimate) &&
            (identical(other.totalCount, totalCount) ||
                other.totalCount == totalCount) &&
            (identical(other.totalEvents, totalEvents) ||
                other.totalEvents == totalEvents) &&
            (identical(other.idolId, idolId) || other.idolId == idolId) &&
            (identical(other.idolName, idolName) ||
                other.idolName == idolName) &&
            (identical(other.mode, mode) || other.mode == mode) &&
            (identical(other.age, age) || other.age == age) &&
            (identical(other.idol, idol) || other.idol == idol));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_events),
    const DeepCollectionEquality().hash(_timeline),
    const DeepCollectionEquality().hash(_milestones),
    completenessEstimate,
    totalCount,
    totalEvents,
    idolId,
    idolName,
    mode,
    age,
    idol,
  );

  /// Create a copy of TimelineResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TimelineResponseImplCopyWith<_$TimelineResponseImpl> get copyWith =>
      __$$TimelineResponseImplCopyWithImpl<_$TimelineResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _TimelineResponse extends TimelineResponse {
  const factory _TimelineResponse({
    final List<TimelineItem> events,
    final List<TimelineItem> timeline,
    final List<TimelineItem> milestones,
    final double? completenessEstimate,
    final int? totalCount,
    final int? totalEvents,
    final String? idolId,
    final String? idolName,
    final String? mode,
    final int? age,
    final String? idol,
  }) = _$TimelineResponseImpl;
  const _TimelineResponse._() : super._();

  /// Backend returns 'events', but we also check 'timeline' and 'milestones' for compatibility
  @override
  List<TimelineItem> get events;
  @override
  List<TimelineItem> get timeline;
  @override
  List<TimelineItem> get milestones;
  @override
  double? get completenessEstimate;
  @override
  int? get totalCount;
  @override
  int? get totalEvents;
  @override
  String? get idolId;
  @override
  String? get idolName;
  @override
  String? get mode;
  @override
  int? get age;
  @override
  String? get idol;

  /// Create a copy of TimelineResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TimelineResponseImplCopyWith<_$TimelineResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
