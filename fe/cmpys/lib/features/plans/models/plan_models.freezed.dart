// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'plan_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$PlanItem {
  String get id => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  String get type => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  int? get weekStart => throw _privateConstructorUsedError;
  int? get weekEnd => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;
  int get progressPercent => throw _privateConstructorUsedError;
  String? get resourceTitle => throw _privateConstructorUsedError;
  String? get resourceUrl => throw _privateConstructorUsedError;
  String? get category => throw _privateConstructorUsedError;
  double? get estimatedHours => throw _privateConstructorUsedError;
  String? get successMetric => throw _privateConstructorUsedError;
  DateTime? get dueDate => throw _privateConstructorUsedError;
  DateTime? get completedAt => throw _privateConstructorUsedError;
  DateTime? get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  /// Create a copy of PlanItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PlanItemCopyWith<PlanItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlanItemCopyWith<$Res> {
  factory $PlanItemCopyWith(PlanItem value, $Res Function(PlanItem) then) =
      _$PlanItemCopyWithImpl<$Res, PlanItem>;
  @useResult
  $Res call({
    String id,
    String title,
    String type,
    String? description,
    int? weekStart,
    int? weekEnd,
    String status,
    int progressPercent,
    String? resourceTitle,
    String? resourceUrl,
    String? category,
    double? estimatedHours,
    String? successMetric,
    DateTime? dueDate,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
}

/// @nodoc
class _$PlanItemCopyWithImpl<$Res, $Val extends PlanItem>
    implements $PlanItemCopyWith<$Res> {
  _$PlanItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PlanItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? type = null,
    Object? description = freezed,
    Object? weekStart = freezed,
    Object? weekEnd = freezed,
    Object? status = null,
    Object? progressPercent = null,
    Object? resourceTitle = freezed,
    Object? resourceUrl = freezed,
    Object? category = freezed,
    Object? estimatedHours = freezed,
    Object? successMetric = freezed,
    Object? dueDate = freezed,
    Object? completedAt = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            title: null == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String,
            type: null == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as String,
            description: freezed == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String?,
            weekStart: freezed == weekStart
                ? _value.weekStart
                : weekStart // ignore: cast_nullable_to_non_nullable
                      as int?,
            weekEnd: freezed == weekEnd
                ? _value.weekEnd
                : weekEnd // ignore: cast_nullable_to_non_nullable
                      as int?,
            status: null == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String,
            progressPercent: null == progressPercent
                ? _value.progressPercent
                : progressPercent // ignore: cast_nullable_to_non_nullable
                      as int,
            resourceTitle: freezed == resourceTitle
                ? _value.resourceTitle
                : resourceTitle // ignore: cast_nullable_to_non_nullable
                      as String?,
            resourceUrl: freezed == resourceUrl
                ? _value.resourceUrl
                : resourceUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            category: freezed == category
                ? _value.category
                : category // ignore: cast_nullable_to_non_nullable
                      as String?,
            estimatedHours: freezed == estimatedHours
                ? _value.estimatedHours
                : estimatedHours // ignore: cast_nullable_to_non_nullable
                      as double?,
            successMetric: freezed == successMetric
                ? _value.successMetric
                : successMetric // ignore: cast_nullable_to_non_nullable
                      as String?,
            dueDate: freezed == dueDate
                ? _value.dueDate
                : dueDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            completedAt: freezed == completedAt
                ? _value.completedAt
                : completedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
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
abstract class _$$PlanItemImplCopyWith<$Res>
    implements $PlanItemCopyWith<$Res> {
  factory _$$PlanItemImplCopyWith(
    _$PlanItemImpl value,
    $Res Function(_$PlanItemImpl) then,
  ) = __$$PlanItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String title,
    String type,
    String? description,
    int? weekStart,
    int? weekEnd,
    String status,
    int progressPercent,
    String? resourceTitle,
    String? resourceUrl,
    String? category,
    double? estimatedHours,
    String? successMetric,
    DateTime? dueDate,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
}

/// @nodoc
class __$$PlanItemImplCopyWithImpl<$Res>
    extends _$PlanItemCopyWithImpl<$Res, _$PlanItemImpl>
    implements _$$PlanItemImplCopyWith<$Res> {
  __$$PlanItemImplCopyWithImpl(
    _$PlanItemImpl _value,
    $Res Function(_$PlanItemImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PlanItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? type = null,
    Object? description = freezed,
    Object? weekStart = freezed,
    Object? weekEnd = freezed,
    Object? status = null,
    Object? progressPercent = null,
    Object? resourceTitle = freezed,
    Object? resourceUrl = freezed,
    Object? category = freezed,
    Object? estimatedHours = freezed,
    Object? successMetric = freezed,
    Object? dueDate = freezed,
    Object? completedAt = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(
      _$PlanItemImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as String,
        description: freezed == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String?,
        weekStart: freezed == weekStart
            ? _value.weekStart
            : weekStart // ignore: cast_nullable_to_non_nullable
                  as int?,
        weekEnd: freezed == weekEnd
            ? _value.weekEnd
            : weekEnd // ignore: cast_nullable_to_non_nullable
                  as int?,
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String,
        progressPercent: null == progressPercent
            ? _value.progressPercent
            : progressPercent // ignore: cast_nullable_to_non_nullable
                  as int,
        resourceTitle: freezed == resourceTitle
            ? _value.resourceTitle
            : resourceTitle // ignore: cast_nullable_to_non_nullable
                  as String?,
        resourceUrl: freezed == resourceUrl
            ? _value.resourceUrl
            : resourceUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        category: freezed == category
            ? _value.category
            : category // ignore: cast_nullable_to_non_nullable
                  as String?,
        estimatedHours: freezed == estimatedHours
            ? _value.estimatedHours
            : estimatedHours // ignore: cast_nullable_to_non_nullable
                  as double?,
        successMetric: freezed == successMetric
            ? _value.successMetric
            : successMetric // ignore: cast_nullable_to_non_nullable
                  as String?,
        dueDate: freezed == dueDate
            ? _value.dueDate
            : dueDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        completedAt: freezed == completedAt
            ? _value.completedAt
            : completedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
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

class _$PlanItemImpl extends _PlanItem {
  const _$PlanItemImpl({
    required this.id,
    required this.title,
    required this.type,
    this.description,
    this.weekStart,
    this.weekEnd,
    this.status = 'pending',
    this.progressPercent = 0,
    this.resourceTitle,
    this.resourceUrl,
    this.category,
    this.estimatedHours,
    this.successMetric,
    this.dueDate,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
  }) : super._();

  @override
  final String id;
  @override
  final String title;
  @override
  final String type;
  @override
  final String? description;
  @override
  final int? weekStart;
  @override
  final int? weekEnd;
  @override
  @JsonKey()
  final String status;
  @override
  @JsonKey()
  final int progressPercent;
  @override
  final String? resourceTitle;
  @override
  final String? resourceUrl;
  @override
  final String? category;
  @override
  final double? estimatedHours;
  @override
  final String? successMetric;
  @override
  final DateTime? dueDate;
  @override
  final DateTime? completedAt;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;

  @override
  String toString() {
    return 'PlanItem(id: $id, title: $title, type: $type, description: $description, weekStart: $weekStart, weekEnd: $weekEnd, status: $status, progressPercent: $progressPercent, resourceTitle: $resourceTitle, resourceUrl: $resourceUrl, category: $category, estimatedHours: $estimatedHours, successMetric: $successMetric, dueDate: $dueDate, completedAt: $completedAt, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlanItemImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.weekStart, weekStart) ||
                other.weekStart == weekStart) &&
            (identical(other.weekEnd, weekEnd) || other.weekEnd == weekEnd) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.progressPercent, progressPercent) ||
                other.progressPercent == progressPercent) &&
            (identical(other.resourceTitle, resourceTitle) ||
                other.resourceTitle == resourceTitle) &&
            (identical(other.resourceUrl, resourceUrl) ||
                other.resourceUrl == resourceUrl) &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.estimatedHours, estimatedHours) ||
                other.estimatedHours == estimatedHours) &&
            (identical(other.successMetric, successMetric) ||
                other.successMetric == successMetric) &&
            (identical(other.dueDate, dueDate) || other.dueDate == dueDate) &&
            (identical(other.completedAt, completedAt) ||
                other.completedAt == completedAt) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    title,
    type,
    description,
    weekStart,
    weekEnd,
    status,
    progressPercent,
    resourceTitle,
    resourceUrl,
    category,
    estimatedHours,
    successMetric,
    dueDate,
    completedAt,
    createdAt,
    updatedAt,
  );

  /// Create a copy of PlanItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlanItemImplCopyWith<_$PlanItemImpl> get copyWith =>
      __$$PlanItemImplCopyWithImpl<_$PlanItemImpl>(this, _$identity);
}

abstract class _PlanItem extends PlanItem {
  const factory _PlanItem({
    required final String id,
    required final String title,
    required final String type,
    final String? description,
    final int? weekStart,
    final int? weekEnd,
    final String status,
    final int progressPercent,
    final String? resourceTitle,
    final String? resourceUrl,
    final String? category,
    final double? estimatedHours,
    final String? successMetric,
    final DateTime? dueDate,
    final DateTime? completedAt,
    final DateTime? createdAt,
    final DateTime? updatedAt,
  }) = _$PlanItemImpl;
  const _PlanItem._() : super._();

  @override
  String get id;
  @override
  String get title;
  @override
  String get type;
  @override
  String? get description;
  @override
  int? get weekStart;
  @override
  int? get weekEnd;
  @override
  String get status;
  @override
  int get progressPercent;
  @override
  String? get resourceTitle;
  @override
  String? get resourceUrl;
  @override
  String? get category;
  @override
  double? get estimatedHours;
  @override
  String? get successMetric;
  @override
  DateTime? get dueDate;
  @override
  DateTime? get completedAt;
  @override
  DateTime? get createdAt;
  @override
  DateTime? get updatedAt;

  /// Create a copy of PlanItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlanItemImplCopyWith<_$PlanItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$Plan {
  String get id => throw _privateConstructorUsedError;
  int get durationWeeks => throw _privateConstructorUsedError;
  double get weeklyHours => throw _privateConstructorUsedError;
  String? get focus => throw _privateConstructorUsedError;
  List<PlanItem> get items => throw _privateConstructorUsedError;
  String? get idolId => throw _privateConstructorUsedError;
  String? get idolName => throw _privateConstructorUsedError;
  int? get targetAge => throw _privateConstructorUsedError;
  DateTime? get startDate => throw _privateConstructorUsedError;
  DateTime? get endDate => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;
  DateTime? get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;
  int? get totalItems => throw _privateConstructorUsedError;
  int? get completedItems => throw _privateConstructorUsedError;
  double? get overallProgress => throw _privateConstructorUsedError;

  /// Create a copy of Plan
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PlanCopyWith<Plan> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlanCopyWith<$Res> {
  factory $PlanCopyWith(Plan value, $Res Function(Plan) then) =
      _$PlanCopyWithImpl<$Res, Plan>;
  @useResult
  $Res call({
    String id,
    int durationWeeks,
    double weeklyHours,
    String? focus,
    List<PlanItem> items,
    String? idolId,
    String? idolName,
    int? targetAge,
    DateTime? startDate,
    DateTime? endDate,
    String status,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? totalItems,
    int? completedItems,
    double? overallProgress,
  });
}

/// @nodoc
class _$PlanCopyWithImpl<$Res, $Val extends Plan>
    implements $PlanCopyWith<$Res> {
  _$PlanCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Plan
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? durationWeeks = null,
    Object? weeklyHours = null,
    Object? focus = freezed,
    Object? items = null,
    Object? idolId = freezed,
    Object? idolName = freezed,
    Object? targetAge = freezed,
    Object? startDate = freezed,
    Object? endDate = freezed,
    Object? status = null,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
    Object? totalItems = freezed,
    Object? completedItems = freezed,
    Object? overallProgress = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            durationWeeks: null == durationWeeks
                ? _value.durationWeeks
                : durationWeeks // ignore: cast_nullable_to_non_nullable
                      as int,
            weeklyHours: null == weeklyHours
                ? _value.weeklyHours
                : weeklyHours // ignore: cast_nullable_to_non_nullable
                      as double,
            focus: freezed == focus
                ? _value.focus
                : focus // ignore: cast_nullable_to_non_nullable
                      as String?,
            items: null == items
                ? _value.items
                : items // ignore: cast_nullable_to_non_nullable
                      as List<PlanItem>,
            idolId: freezed == idolId
                ? _value.idolId
                : idolId // ignore: cast_nullable_to_non_nullable
                      as String?,
            idolName: freezed == idolName
                ? _value.idolName
                : idolName // ignore: cast_nullable_to_non_nullable
                      as String?,
            targetAge: freezed == targetAge
                ? _value.targetAge
                : targetAge // ignore: cast_nullable_to_non_nullable
                      as int?,
            startDate: freezed == startDate
                ? _value.startDate
                : startDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            endDate: freezed == endDate
                ? _value.endDate
                : endDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            status: null == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String,
            createdAt: freezed == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            updatedAt: freezed == updatedAt
                ? _value.updatedAt
                : updatedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            totalItems: freezed == totalItems
                ? _value.totalItems
                : totalItems // ignore: cast_nullable_to_non_nullable
                      as int?,
            completedItems: freezed == completedItems
                ? _value.completedItems
                : completedItems // ignore: cast_nullable_to_non_nullable
                      as int?,
            overallProgress: freezed == overallProgress
                ? _value.overallProgress
                : overallProgress // ignore: cast_nullable_to_non_nullable
                      as double?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PlanImplCopyWith<$Res> implements $PlanCopyWith<$Res> {
  factory _$$PlanImplCopyWith(
    _$PlanImpl value,
    $Res Function(_$PlanImpl) then,
  ) = __$$PlanImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    int durationWeeks,
    double weeklyHours,
    String? focus,
    List<PlanItem> items,
    String? idolId,
    String? idolName,
    int? targetAge,
    DateTime? startDate,
    DateTime? endDate,
    String status,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? totalItems,
    int? completedItems,
    double? overallProgress,
  });
}

/// @nodoc
class __$$PlanImplCopyWithImpl<$Res>
    extends _$PlanCopyWithImpl<$Res, _$PlanImpl>
    implements _$$PlanImplCopyWith<$Res> {
  __$$PlanImplCopyWithImpl(_$PlanImpl _value, $Res Function(_$PlanImpl) _then)
    : super(_value, _then);

  /// Create a copy of Plan
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? durationWeeks = null,
    Object? weeklyHours = null,
    Object? focus = freezed,
    Object? items = null,
    Object? idolId = freezed,
    Object? idolName = freezed,
    Object? targetAge = freezed,
    Object? startDate = freezed,
    Object? endDate = freezed,
    Object? status = null,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
    Object? totalItems = freezed,
    Object? completedItems = freezed,
    Object? overallProgress = freezed,
  }) {
    return _then(
      _$PlanImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        durationWeeks: null == durationWeeks
            ? _value.durationWeeks
            : durationWeeks // ignore: cast_nullable_to_non_nullable
                  as int,
        weeklyHours: null == weeklyHours
            ? _value.weeklyHours
            : weeklyHours // ignore: cast_nullable_to_non_nullable
                  as double,
        focus: freezed == focus
            ? _value.focus
            : focus // ignore: cast_nullable_to_non_nullable
                  as String?,
        items: null == items
            ? _value._items
            : items // ignore: cast_nullable_to_non_nullable
                  as List<PlanItem>,
        idolId: freezed == idolId
            ? _value.idolId
            : idolId // ignore: cast_nullable_to_non_nullable
                  as String?,
        idolName: freezed == idolName
            ? _value.idolName
            : idolName // ignore: cast_nullable_to_non_nullable
                  as String?,
        targetAge: freezed == targetAge
            ? _value.targetAge
            : targetAge // ignore: cast_nullable_to_non_nullable
                  as int?,
        startDate: freezed == startDate
            ? _value.startDate
            : startDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        endDate: freezed == endDate
            ? _value.endDate
            : endDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String,
        createdAt: freezed == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        updatedAt: freezed == updatedAt
            ? _value.updatedAt
            : updatedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        totalItems: freezed == totalItems
            ? _value.totalItems
            : totalItems // ignore: cast_nullable_to_non_nullable
                  as int?,
        completedItems: freezed == completedItems
            ? _value.completedItems
            : completedItems // ignore: cast_nullable_to_non_nullable
                  as int?,
        overallProgress: freezed == overallProgress
            ? _value.overallProgress
            : overallProgress // ignore: cast_nullable_to_non_nullable
                  as double?,
      ),
    );
  }
}

/// @nodoc

class _$PlanImpl extends _Plan {
  const _$PlanImpl({
    required this.id,
    required this.durationWeeks,
    required this.weeklyHours,
    this.focus,
    final List<PlanItem> items = const [],
    this.idolId,
    this.idolName,
    this.targetAge,
    this.startDate,
    this.endDate,
    this.status = 'active',
    this.createdAt,
    this.updatedAt,
    this.totalItems,
    this.completedItems,
    this.overallProgress,
  }) : _items = items,
       super._();

  @override
  final String id;
  @override
  final int durationWeeks;
  @override
  final double weeklyHours;
  @override
  final String? focus;
  final List<PlanItem> _items;
  @override
  @JsonKey()
  List<PlanItem> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  final String? idolId;
  @override
  final String? idolName;
  @override
  final int? targetAge;
  @override
  final DateTime? startDate;
  @override
  final DateTime? endDate;
  @override
  @JsonKey()
  final String status;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;
  @override
  final int? totalItems;
  @override
  final int? completedItems;
  @override
  final double? overallProgress;

  @override
  String toString() {
    return 'Plan(id: $id, durationWeeks: $durationWeeks, weeklyHours: $weeklyHours, focus: $focus, items: $items, idolId: $idolId, idolName: $idolName, targetAge: $targetAge, startDate: $startDate, endDate: $endDate, status: $status, createdAt: $createdAt, updatedAt: $updatedAt, totalItems: $totalItems, completedItems: $completedItems, overallProgress: $overallProgress)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlanImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.durationWeeks, durationWeeks) ||
                other.durationWeeks == durationWeeks) &&
            (identical(other.weeklyHours, weeklyHours) ||
                other.weeklyHours == weeklyHours) &&
            (identical(other.focus, focus) || other.focus == focus) &&
            const DeepCollectionEquality().equals(other._items, _items) &&
            (identical(other.idolId, idolId) || other.idolId == idolId) &&
            (identical(other.idolName, idolName) ||
                other.idolName == idolName) &&
            (identical(other.targetAge, targetAge) ||
                other.targetAge == targetAge) &&
            (identical(other.startDate, startDate) ||
                other.startDate == startDate) &&
            (identical(other.endDate, endDate) || other.endDate == endDate) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.totalItems, totalItems) ||
                other.totalItems == totalItems) &&
            (identical(other.completedItems, completedItems) ||
                other.completedItems == completedItems) &&
            (identical(other.overallProgress, overallProgress) ||
                other.overallProgress == overallProgress));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    durationWeeks,
    weeklyHours,
    focus,
    const DeepCollectionEquality().hash(_items),
    idolId,
    idolName,
    targetAge,
    startDate,
    endDate,
    status,
    createdAt,
    updatedAt,
    totalItems,
    completedItems,
    overallProgress,
  );

  /// Create a copy of Plan
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlanImplCopyWith<_$PlanImpl> get copyWith =>
      __$$PlanImplCopyWithImpl<_$PlanImpl>(this, _$identity);
}

abstract class _Plan extends Plan {
  const factory _Plan({
    required final String id,
    required final int durationWeeks,
    required final double weeklyHours,
    final String? focus,
    final List<PlanItem> items,
    final String? idolId,
    final String? idolName,
    final int? targetAge,
    final DateTime? startDate,
    final DateTime? endDate,
    final String status,
    final DateTime? createdAt,
    final DateTime? updatedAt,
    final int? totalItems,
    final int? completedItems,
    final double? overallProgress,
  }) = _$PlanImpl;
  const _Plan._() : super._();

  @override
  String get id;
  @override
  int get durationWeeks;
  @override
  double get weeklyHours;
  @override
  String? get focus;
  @override
  List<PlanItem> get items;
  @override
  String? get idolId;
  @override
  String? get idolName;
  @override
  int? get targetAge;
  @override
  DateTime? get startDate;
  @override
  DateTime? get endDate;
  @override
  String get status;
  @override
  DateTime? get createdAt;
  @override
  DateTime? get updatedAt;
  @override
  int? get totalItems;
  @override
  int? get completedItems;
  @override
  double? get overallProgress;

  /// Create a copy of Plan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlanImplCopyWith<_$PlanImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$CreatePlanRequest {
  int get durationWeeks => throw _privateConstructorUsedError;
  double get weeklyHours => throw _privateConstructorUsedError;
  String? get focus => throw _privateConstructorUsedError;
  String? get idolId => throw _privateConstructorUsedError;
  int? get targetAge => throw _privateConstructorUsedError;
  List<String>? get gapIds => throw _privateConstructorUsedError;

  /// Create a copy of CreatePlanRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CreatePlanRequestCopyWith<CreatePlanRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CreatePlanRequestCopyWith<$Res> {
  factory $CreatePlanRequestCopyWith(
    CreatePlanRequest value,
    $Res Function(CreatePlanRequest) then,
  ) = _$CreatePlanRequestCopyWithImpl<$Res, CreatePlanRequest>;
  @useResult
  $Res call({
    int durationWeeks,
    double weeklyHours,
    String? focus,
    String? idolId,
    int? targetAge,
    List<String>? gapIds,
  });
}

/// @nodoc
class _$CreatePlanRequestCopyWithImpl<$Res, $Val extends CreatePlanRequest>
    implements $CreatePlanRequestCopyWith<$Res> {
  _$CreatePlanRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CreatePlanRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? durationWeeks = null,
    Object? weeklyHours = null,
    Object? focus = freezed,
    Object? idolId = freezed,
    Object? targetAge = freezed,
    Object? gapIds = freezed,
  }) {
    return _then(
      _value.copyWith(
            durationWeeks: null == durationWeeks
                ? _value.durationWeeks
                : durationWeeks // ignore: cast_nullable_to_non_nullable
                      as int,
            weeklyHours: null == weeklyHours
                ? _value.weeklyHours
                : weeklyHours // ignore: cast_nullable_to_non_nullable
                      as double,
            focus: freezed == focus
                ? _value.focus
                : focus // ignore: cast_nullable_to_non_nullable
                      as String?,
            idolId: freezed == idolId
                ? _value.idolId
                : idolId // ignore: cast_nullable_to_non_nullable
                      as String?,
            targetAge: freezed == targetAge
                ? _value.targetAge
                : targetAge // ignore: cast_nullable_to_non_nullable
                      as int?,
            gapIds: freezed == gapIds
                ? _value.gapIds
                : gapIds // ignore: cast_nullable_to_non_nullable
                      as List<String>?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$CreatePlanRequestImplCopyWith<$Res>
    implements $CreatePlanRequestCopyWith<$Res> {
  factory _$$CreatePlanRequestImplCopyWith(
    _$CreatePlanRequestImpl value,
    $Res Function(_$CreatePlanRequestImpl) then,
  ) = __$$CreatePlanRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int durationWeeks,
    double weeklyHours,
    String? focus,
    String? idolId,
    int? targetAge,
    List<String>? gapIds,
  });
}

/// @nodoc
class __$$CreatePlanRequestImplCopyWithImpl<$Res>
    extends _$CreatePlanRequestCopyWithImpl<$Res, _$CreatePlanRequestImpl>
    implements _$$CreatePlanRequestImplCopyWith<$Res> {
  __$$CreatePlanRequestImplCopyWithImpl(
    _$CreatePlanRequestImpl _value,
    $Res Function(_$CreatePlanRequestImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of CreatePlanRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? durationWeeks = null,
    Object? weeklyHours = null,
    Object? focus = freezed,
    Object? idolId = freezed,
    Object? targetAge = freezed,
    Object? gapIds = freezed,
  }) {
    return _then(
      _$CreatePlanRequestImpl(
        durationWeeks: null == durationWeeks
            ? _value.durationWeeks
            : durationWeeks // ignore: cast_nullable_to_non_nullable
                  as int,
        weeklyHours: null == weeklyHours
            ? _value.weeklyHours
            : weeklyHours // ignore: cast_nullable_to_non_nullable
                  as double,
        focus: freezed == focus
            ? _value.focus
            : focus // ignore: cast_nullable_to_non_nullable
                  as String?,
        idolId: freezed == idolId
            ? _value.idolId
            : idolId // ignore: cast_nullable_to_non_nullable
                  as String?,
        targetAge: freezed == targetAge
            ? _value.targetAge
            : targetAge // ignore: cast_nullable_to_non_nullable
                  as int?,
        gapIds: freezed == gapIds
            ? _value._gapIds
            : gapIds // ignore: cast_nullable_to_non_nullable
                  as List<String>?,
      ),
    );
  }
}

/// @nodoc

class _$CreatePlanRequestImpl extends _CreatePlanRequest {
  const _$CreatePlanRequestImpl({
    required this.durationWeeks,
    required this.weeklyHours,
    this.focus,
    this.idolId,
    this.targetAge,
    final List<String>? gapIds,
  }) : _gapIds = gapIds,
       super._();

  @override
  final int durationWeeks;
  @override
  final double weeklyHours;
  @override
  final String? focus;
  @override
  final String? idolId;
  @override
  final int? targetAge;
  final List<String>? _gapIds;
  @override
  List<String>? get gapIds {
    final value = _gapIds;
    if (value == null) return null;
    if (_gapIds is EqualUnmodifiableListView) return _gapIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  String toString() {
    return 'CreatePlanRequest(durationWeeks: $durationWeeks, weeklyHours: $weeklyHours, focus: $focus, idolId: $idolId, targetAge: $targetAge, gapIds: $gapIds)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CreatePlanRequestImpl &&
            (identical(other.durationWeeks, durationWeeks) ||
                other.durationWeeks == durationWeeks) &&
            (identical(other.weeklyHours, weeklyHours) ||
                other.weeklyHours == weeklyHours) &&
            (identical(other.focus, focus) || other.focus == focus) &&
            (identical(other.idolId, idolId) || other.idolId == idolId) &&
            (identical(other.targetAge, targetAge) ||
                other.targetAge == targetAge) &&
            const DeepCollectionEquality().equals(other._gapIds, _gapIds));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    durationWeeks,
    weeklyHours,
    focus,
    idolId,
    targetAge,
    const DeepCollectionEquality().hash(_gapIds),
  );

  /// Create a copy of CreatePlanRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CreatePlanRequestImplCopyWith<_$CreatePlanRequestImpl> get copyWith =>
      __$$CreatePlanRequestImplCopyWithImpl<_$CreatePlanRequestImpl>(
        this,
        _$identity,
      );
}

abstract class _CreatePlanRequest extends CreatePlanRequest {
  const factory _CreatePlanRequest({
    required final int durationWeeks,
    required final double weeklyHours,
    final String? focus,
    final String? idolId,
    final int? targetAge,
    final List<String>? gapIds,
  }) = _$CreatePlanRequestImpl;
  const _CreatePlanRequest._() : super._();

  @override
  int get durationWeeks;
  @override
  double get weeklyHours;
  @override
  String? get focus;
  @override
  String? get idolId;
  @override
  int? get targetAge;
  @override
  List<String>? get gapIds;

  /// Create a copy of CreatePlanRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CreatePlanRequestImplCopyWith<_$CreatePlanRequestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$UpdatePlanItemRequest {
  String? get status => throw _privateConstructorUsedError;
  int? get progressPercent => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;

  /// Create a copy of UpdatePlanItemRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UpdatePlanItemRequestCopyWith<UpdatePlanItemRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UpdatePlanItemRequestCopyWith<$Res> {
  factory $UpdatePlanItemRequestCopyWith(
    UpdatePlanItemRequest value,
    $Res Function(UpdatePlanItemRequest) then,
  ) = _$UpdatePlanItemRequestCopyWithImpl<$Res, UpdatePlanItemRequest>;
  @useResult
  $Res call({String? status, int? progressPercent, String? notes});
}

/// @nodoc
class _$UpdatePlanItemRequestCopyWithImpl<
  $Res,
  $Val extends UpdatePlanItemRequest
>
    implements $UpdatePlanItemRequestCopyWith<$Res> {
  _$UpdatePlanItemRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UpdatePlanItemRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = freezed,
    Object? progressPercent = freezed,
    Object? notes = freezed,
  }) {
    return _then(
      _value.copyWith(
            status: freezed == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String?,
            progressPercent: freezed == progressPercent
                ? _value.progressPercent
                : progressPercent // ignore: cast_nullable_to_non_nullable
                      as int?,
            notes: freezed == notes
                ? _value.notes
                : notes // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$UpdatePlanItemRequestImplCopyWith<$Res>
    implements $UpdatePlanItemRequestCopyWith<$Res> {
  factory _$$UpdatePlanItemRequestImplCopyWith(
    _$UpdatePlanItemRequestImpl value,
    $Res Function(_$UpdatePlanItemRequestImpl) then,
  ) = __$$UpdatePlanItemRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? status, int? progressPercent, String? notes});
}

/// @nodoc
class __$$UpdatePlanItemRequestImplCopyWithImpl<$Res>
    extends
        _$UpdatePlanItemRequestCopyWithImpl<$Res, _$UpdatePlanItemRequestImpl>
    implements _$$UpdatePlanItemRequestImplCopyWith<$Res> {
  __$$UpdatePlanItemRequestImplCopyWithImpl(
    _$UpdatePlanItemRequestImpl _value,
    $Res Function(_$UpdatePlanItemRequestImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of UpdatePlanItemRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = freezed,
    Object? progressPercent = freezed,
    Object? notes = freezed,
  }) {
    return _then(
      _$UpdatePlanItemRequestImpl(
        status: freezed == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String?,
        progressPercent: freezed == progressPercent
            ? _value.progressPercent
            : progressPercent // ignore: cast_nullable_to_non_nullable
                  as int?,
        notes: freezed == notes
            ? _value.notes
            : notes // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$UpdatePlanItemRequestImpl extends _UpdatePlanItemRequest {
  const _$UpdatePlanItemRequestImpl({
    this.status,
    this.progressPercent,
    this.notes,
  }) : super._();

  @override
  final String? status;
  @override
  final int? progressPercent;
  @override
  final String? notes;

  @override
  String toString() {
    return 'UpdatePlanItemRequest(status: $status, progressPercent: $progressPercent, notes: $notes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UpdatePlanItemRequestImpl &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.progressPercent, progressPercent) ||
                other.progressPercent == progressPercent) &&
            (identical(other.notes, notes) || other.notes == notes));
  }

  @override
  int get hashCode => Object.hash(runtimeType, status, progressPercent, notes);

  /// Create a copy of UpdatePlanItemRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UpdatePlanItemRequestImplCopyWith<_$UpdatePlanItemRequestImpl>
  get copyWith =>
      __$$UpdatePlanItemRequestImplCopyWithImpl<_$UpdatePlanItemRequestImpl>(
        this,
        _$identity,
      );
}

abstract class _UpdatePlanItemRequest extends UpdatePlanItemRequest {
  const factory _UpdatePlanItemRequest({
    final String? status,
    final int? progressPercent,
    final String? notes,
  }) = _$UpdatePlanItemRequestImpl;
  const _UpdatePlanItemRequest._() : super._();

  @override
  String? get status;
  @override
  int? get progressPercent;
  @override
  String? get notes;

  /// Create a copy of UpdatePlanItemRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UpdatePlanItemRequestImplCopyWith<_$UpdatePlanItemRequestImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ProgressInfo {
  int get completedSteps => throw _privateConstructorUsedError;
  int get totalSteps => throw _privateConstructorUsedError;
  double get percent => throw _privateConstructorUsedError;

  /// Create a copy of ProgressInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ProgressInfoCopyWith<ProgressInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ProgressInfoCopyWith<$Res> {
  factory $ProgressInfoCopyWith(
    ProgressInfo value,
    $Res Function(ProgressInfo) then,
  ) = _$ProgressInfoCopyWithImpl<$Res, ProgressInfo>;
  @useResult
  $Res call({int completedSteps, int totalSteps, double percent});
}

/// @nodoc
class _$ProgressInfoCopyWithImpl<$Res, $Val extends ProgressInfo>
    implements $ProgressInfoCopyWith<$Res> {
  _$ProgressInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ProgressInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? completedSteps = null,
    Object? totalSteps = null,
    Object? percent = null,
  }) {
    return _then(
      _value.copyWith(
            completedSteps: null == completedSteps
                ? _value.completedSteps
                : completedSteps // ignore: cast_nullable_to_non_nullable
                      as int,
            totalSteps: null == totalSteps
                ? _value.totalSteps
                : totalSteps // ignore: cast_nullable_to_non_nullable
                      as int,
            percent: null == percent
                ? _value.percent
                : percent // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ProgressInfoImplCopyWith<$Res>
    implements $ProgressInfoCopyWith<$Res> {
  factory _$$ProgressInfoImplCopyWith(
    _$ProgressInfoImpl value,
    $Res Function(_$ProgressInfoImpl) then,
  ) = __$$ProgressInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int completedSteps, int totalSteps, double percent});
}

/// @nodoc
class __$$ProgressInfoImplCopyWithImpl<$Res>
    extends _$ProgressInfoCopyWithImpl<$Res, _$ProgressInfoImpl>
    implements _$$ProgressInfoImplCopyWith<$Res> {
  __$$ProgressInfoImplCopyWithImpl(
    _$ProgressInfoImpl _value,
    $Res Function(_$ProgressInfoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ProgressInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? completedSteps = null,
    Object? totalSteps = null,
    Object? percent = null,
  }) {
    return _then(
      _$ProgressInfoImpl(
        completedSteps: null == completedSteps
            ? _value.completedSteps
            : completedSteps // ignore: cast_nullable_to_non_nullable
                  as int,
        totalSteps: null == totalSteps
            ? _value.totalSteps
            : totalSteps // ignore: cast_nullable_to_non_nullable
                  as int,
        percent: null == percent
            ? _value.percent
            : percent // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc

class _$ProgressInfoImpl extends _ProgressInfo {
  const _$ProgressInfoImpl({
    this.completedSteps = 0,
    this.totalSteps = 0,
    this.percent = 0.0,
  }) : super._();

  @override
  @JsonKey()
  final int completedSteps;
  @override
  @JsonKey()
  final int totalSteps;
  @override
  @JsonKey()
  final double percent;

  @override
  String toString() {
    return 'ProgressInfo(completedSteps: $completedSteps, totalSteps: $totalSteps, percent: $percent)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ProgressInfoImpl &&
            (identical(other.completedSteps, completedSteps) ||
                other.completedSteps == completedSteps) &&
            (identical(other.totalSteps, totalSteps) ||
                other.totalSteps == totalSteps) &&
            (identical(other.percent, percent) || other.percent == percent));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, completedSteps, totalSteps, percent);

  /// Create a copy of ProgressInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ProgressInfoImplCopyWith<_$ProgressInfoImpl> get copyWith =>
      __$$ProgressInfoImplCopyWithImpl<_$ProgressInfoImpl>(this, _$identity);
}

abstract class _ProgressInfo extends ProgressInfo {
  const factory _ProgressInfo({
    final int completedSteps,
    final int totalSteps,
    final double percent,
  }) = _$ProgressInfoImpl;
  const _ProgressInfo._() : super._();

  @override
  int get completedSteps;
  @override
  int get totalSteps;
  @override
  double get percent;

  /// Create a copy of ProgressInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ProgressInfoImplCopyWith<_$ProgressInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$PlanStep {
  String get id => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  String? get instruction => throw _privateConstructorUsedError;
  String? get expectedOutput => throw _privateConstructorUsedError;
  int? get estimateMinutes => throw _privateConstructorUsedError;
  int get order => throw _privateConstructorUsedError;
  List<String> get resources => throw _privateConstructorUsedError;
  bool get completed => throw _privateConstructorUsedError;

  /// Create a copy of PlanStep
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PlanStepCopyWith<PlanStep> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlanStepCopyWith<$Res> {
  factory $PlanStepCopyWith(PlanStep value, $Res Function(PlanStep) then) =
      _$PlanStepCopyWithImpl<$Res, PlanStep>;
  @useResult
  $Res call({
    String id,
    String title,
    String? description,
    String? instruction,
    String? expectedOutput,
    int? estimateMinutes,
    int order,
    List<String> resources,
    bool completed,
  });
}

/// @nodoc
class _$PlanStepCopyWithImpl<$Res, $Val extends PlanStep>
    implements $PlanStepCopyWith<$Res> {
  _$PlanStepCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PlanStep
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? description = freezed,
    Object? instruction = freezed,
    Object? expectedOutput = freezed,
    Object? estimateMinutes = freezed,
    Object? order = null,
    Object? resources = null,
    Object? completed = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            title: null == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String,
            description: freezed == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String?,
            instruction: freezed == instruction
                ? _value.instruction
                : instruction // ignore: cast_nullable_to_non_nullable
                      as String?,
            expectedOutput: freezed == expectedOutput
                ? _value.expectedOutput
                : expectedOutput // ignore: cast_nullable_to_non_nullable
                      as String?,
            estimateMinutes: freezed == estimateMinutes
                ? _value.estimateMinutes
                : estimateMinutes // ignore: cast_nullable_to_non_nullable
                      as int?,
            order: null == order
                ? _value.order
                : order // ignore: cast_nullable_to_non_nullable
                      as int,
            resources: null == resources
                ? _value.resources
                : resources // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            completed: null == completed
                ? _value.completed
                : completed // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PlanStepImplCopyWith<$Res>
    implements $PlanStepCopyWith<$Res> {
  factory _$$PlanStepImplCopyWith(
    _$PlanStepImpl value,
    $Res Function(_$PlanStepImpl) then,
  ) = __$$PlanStepImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String title,
    String? description,
    String? instruction,
    String? expectedOutput,
    int? estimateMinutes,
    int order,
    List<String> resources,
    bool completed,
  });
}

/// @nodoc
class __$$PlanStepImplCopyWithImpl<$Res>
    extends _$PlanStepCopyWithImpl<$Res, _$PlanStepImpl>
    implements _$$PlanStepImplCopyWith<$Res> {
  __$$PlanStepImplCopyWithImpl(
    _$PlanStepImpl _value,
    $Res Function(_$PlanStepImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PlanStep
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? description = freezed,
    Object? instruction = freezed,
    Object? expectedOutput = freezed,
    Object? estimateMinutes = freezed,
    Object? order = null,
    Object? resources = null,
    Object? completed = null,
  }) {
    return _then(
      _$PlanStepImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        description: freezed == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String?,
        instruction: freezed == instruction
            ? _value.instruction
            : instruction // ignore: cast_nullable_to_non_nullable
                  as String?,
        expectedOutput: freezed == expectedOutput
            ? _value.expectedOutput
            : expectedOutput // ignore: cast_nullable_to_non_nullable
                  as String?,
        estimateMinutes: freezed == estimateMinutes
            ? _value.estimateMinutes
            : estimateMinutes // ignore: cast_nullable_to_non_nullable
                  as int?,
        order: null == order
            ? _value.order
            : order // ignore: cast_nullable_to_non_nullable
                  as int,
        resources: null == resources
            ? _value._resources
            : resources // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        completed: null == completed
            ? _value.completed
            : completed // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc

class _$PlanStepImpl extends _PlanStep {
  const _$PlanStepImpl({
    required this.id,
    required this.title,
    this.description,
    this.instruction,
    this.expectedOutput,
    this.estimateMinutes,
    this.order = 0,
    final List<String> resources = const [],
    this.completed = false,
  }) : _resources = resources,
       super._();

  @override
  final String id;
  @override
  final String title;
  @override
  final String? description;
  @override
  final String? instruction;
  @override
  final String? expectedOutput;
  @override
  final int? estimateMinutes;
  @override
  @JsonKey()
  final int order;
  final List<String> _resources;
  @override
  @JsonKey()
  List<String> get resources {
    if (_resources is EqualUnmodifiableListView) return _resources;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_resources);
  }

  @override
  @JsonKey()
  final bool completed;

  @override
  String toString() {
    return 'PlanStep(id: $id, title: $title, description: $description, instruction: $instruction, expectedOutput: $expectedOutput, estimateMinutes: $estimateMinutes, order: $order, resources: $resources, completed: $completed)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlanStepImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.instruction, instruction) ||
                other.instruction == instruction) &&
            (identical(other.expectedOutput, expectedOutput) ||
                other.expectedOutput == expectedOutput) &&
            (identical(other.estimateMinutes, estimateMinutes) ||
                other.estimateMinutes == estimateMinutes) &&
            (identical(other.order, order) || other.order == order) &&
            const DeepCollectionEquality().equals(
              other._resources,
              _resources,
            ) &&
            (identical(other.completed, completed) ||
                other.completed == completed));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    title,
    description,
    instruction,
    expectedOutput,
    estimateMinutes,
    order,
    const DeepCollectionEquality().hash(_resources),
    completed,
  );

  /// Create a copy of PlanStep
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlanStepImplCopyWith<_$PlanStepImpl> get copyWith =>
      __$$PlanStepImplCopyWithImpl<_$PlanStepImpl>(this, _$identity);
}

abstract class _PlanStep extends PlanStep {
  const factory _PlanStep({
    required final String id,
    required final String title,
    final String? description,
    final String? instruction,
    final String? expectedOutput,
    final int? estimateMinutes,
    final int order,
    final List<String> resources,
    final bool completed,
  }) = _$PlanStepImpl;
  const _PlanStep._() : super._();

  @override
  String get id;
  @override
  String get title;
  @override
  String? get description;
  @override
  String? get instruction;
  @override
  String? get expectedOutput;
  @override
  int? get estimateMinutes;
  @override
  int get order;
  @override
  List<String> get resources;
  @override
  bool get completed;

  /// Create a copy of PlanStep
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlanStepImplCopyWith<_$PlanStepImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$PlanMaterial {
  String? get id => throw _privateConstructorUsedError;
  PlanMaterialType get type => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  String? get url => throw _privateConstructorUsedError;
  String? get contentMarkdown => throw _privateConstructorUsedError;
  int? get durationMinutes => throw _privateConstructorUsedError;
  String? get reason => throw _privateConstructorUsedError;

  /// Create a copy of PlanMaterial
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PlanMaterialCopyWith<PlanMaterial> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlanMaterialCopyWith<$Res> {
  factory $PlanMaterialCopyWith(
    PlanMaterial value,
    $Res Function(PlanMaterial) then,
  ) = _$PlanMaterialCopyWithImpl<$Res, PlanMaterial>;
  @useResult
  $Res call({
    String? id,
    PlanMaterialType type,
    String title,
    String? url,
    String? contentMarkdown,
    int? durationMinutes,
    String? reason,
  });
}

/// @nodoc
class _$PlanMaterialCopyWithImpl<$Res, $Val extends PlanMaterial>
    implements $PlanMaterialCopyWith<$Res> {
  _$PlanMaterialCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PlanMaterial
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? type = null,
    Object? title = null,
    Object? url = freezed,
    Object? contentMarkdown = freezed,
    Object? durationMinutes = freezed,
    Object? reason = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: freezed == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String?,
            type: null == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as PlanMaterialType,
            title: null == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String,
            url: freezed == url
                ? _value.url
                : url // ignore: cast_nullable_to_non_nullable
                      as String?,
            contentMarkdown: freezed == contentMarkdown
                ? _value.contentMarkdown
                : contentMarkdown // ignore: cast_nullable_to_non_nullable
                      as String?,
            durationMinutes: freezed == durationMinutes
                ? _value.durationMinutes
                : durationMinutes // ignore: cast_nullable_to_non_nullable
                      as int?,
            reason: freezed == reason
                ? _value.reason
                : reason // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PlanMaterialImplCopyWith<$Res>
    implements $PlanMaterialCopyWith<$Res> {
  factory _$$PlanMaterialImplCopyWith(
    _$PlanMaterialImpl value,
    $Res Function(_$PlanMaterialImpl) then,
  ) = __$$PlanMaterialImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String? id,
    PlanMaterialType type,
    String title,
    String? url,
    String? contentMarkdown,
    int? durationMinutes,
    String? reason,
  });
}

/// @nodoc
class __$$PlanMaterialImplCopyWithImpl<$Res>
    extends _$PlanMaterialCopyWithImpl<$Res, _$PlanMaterialImpl>
    implements _$$PlanMaterialImplCopyWith<$Res> {
  __$$PlanMaterialImplCopyWithImpl(
    _$PlanMaterialImpl _value,
    $Res Function(_$PlanMaterialImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PlanMaterial
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? type = null,
    Object? title = null,
    Object? url = freezed,
    Object? contentMarkdown = freezed,
    Object? durationMinutes = freezed,
    Object? reason = freezed,
  }) {
    return _then(
      _$PlanMaterialImpl(
        id: freezed == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String?,
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as PlanMaterialType,
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        url: freezed == url
            ? _value.url
            : url // ignore: cast_nullable_to_non_nullable
                  as String?,
        contentMarkdown: freezed == contentMarkdown
            ? _value.contentMarkdown
            : contentMarkdown // ignore: cast_nullable_to_non_nullable
                  as String?,
        durationMinutes: freezed == durationMinutes
            ? _value.durationMinutes
            : durationMinutes // ignore: cast_nullable_to_non_nullable
                  as int?,
        reason: freezed == reason
            ? _value.reason
            : reason // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$PlanMaterialImpl extends _PlanMaterial {
  const _$PlanMaterialImpl({
    this.id,
    required this.type,
    required this.title,
    this.url,
    this.contentMarkdown,
    this.durationMinutes,
    this.reason,
  }) : super._();

  @override
  final String? id;
  @override
  final PlanMaterialType type;
  @override
  final String title;
  @override
  final String? url;
  @override
  final String? contentMarkdown;
  @override
  final int? durationMinutes;
  @override
  final String? reason;

  @override
  String toString() {
    return 'PlanMaterial(id: $id, type: $type, title: $title, url: $url, contentMarkdown: $contentMarkdown, durationMinutes: $durationMinutes, reason: $reason)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlanMaterialImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.contentMarkdown, contentMarkdown) ||
                other.contentMarkdown == contentMarkdown) &&
            (identical(other.durationMinutes, durationMinutes) ||
                other.durationMinutes == durationMinutes) &&
            (identical(other.reason, reason) || other.reason == reason));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    type,
    title,
    url,
    contentMarkdown,
    durationMinutes,
    reason,
  );

  /// Create a copy of PlanMaterial
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlanMaterialImplCopyWith<_$PlanMaterialImpl> get copyWith =>
      __$$PlanMaterialImplCopyWithImpl<_$PlanMaterialImpl>(this, _$identity);
}

abstract class _PlanMaterial extends PlanMaterial {
  const factory _PlanMaterial({
    final String? id,
    required final PlanMaterialType type,
    required final String title,
    final String? url,
    final String? contentMarkdown,
    final int? durationMinutes,
    final String? reason,
  }) = _$PlanMaterialImpl;
  const _PlanMaterial._() : super._();

  @override
  String? get id;
  @override
  PlanMaterialType get type;
  @override
  String get title;
  @override
  String? get url;
  @override
  String? get contentMarkdown;
  @override
  int? get durationMinutes;
  @override
  String? get reason;

  /// Create a copy of PlanMaterial
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlanMaterialImplCopyWith<_$PlanMaterialImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$PlanItemDetails {
  List<PlanStep> get steps => throw _privateConstructorUsedError;
  List<PlanMaterial> get materials => throw _privateConstructorUsedError;

  /// Create a copy of PlanItemDetails
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PlanItemDetailsCopyWith<PlanItemDetails> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlanItemDetailsCopyWith<$Res> {
  factory $PlanItemDetailsCopyWith(
    PlanItemDetails value,
    $Res Function(PlanItemDetails) then,
  ) = _$PlanItemDetailsCopyWithImpl<$Res, PlanItemDetails>;
  @useResult
  $Res call({List<PlanStep> steps, List<PlanMaterial> materials});
}

/// @nodoc
class _$PlanItemDetailsCopyWithImpl<$Res, $Val extends PlanItemDetails>
    implements $PlanItemDetailsCopyWith<$Res> {
  _$PlanItemDetailsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PlanItemDetails
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? steps = null, Object? materials = null}) {
    return _then(
      _value.copyWith(
            steps: null == steps
                ? _value.steps
                : steps // ignore: cast_nullable_to_non_nullable
                      as List<PlanStep>,
            materials: null == materials
                ? _value.materials
                : materials // ignore: cast_nullable_to_non_nullable
                      as List<PlanMaterial>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PlanItemDetailsImplCopyWith<$Res>
    implements $PlanItemDetailsCopyWith<$Res> {
  factory _$$PlanItemDetailsImplCopyWith(
    _$PlanItemDetailsImpl value,
    $Res Function(_$PlanItemDetailsImpl) then,
  ) = __$$PlanItemDetailsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<PlanStep> steps, List<PlanMaterial> materials});
}

/// @nodoc
class __$$PlanItemDetailsImplCopyWithImpl<$Res>
    extends _$PlanItemDetailsCopyWithImpl<$Res, _$PlanItemDetailsImpl>
    implements _$$PlanItemDetailsImplCopyWith<$Res> {
  __$$PlanItemDetailsImplCopyWithImpl(
    _$PlanItemDetailsImpl _value,
    $Res Function(_$PlanItemDetailsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PlanItemDetails
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? steps = null, Object? materials = null}) {
    return _then(
      _$PlanItemDetailsImpl(
        steps: null == steps
            ? _value._steps
            : steps // ignore: cast_nullable_to_non_nullable
                  as List<PlanStep>,
        materials: null == materials
            ? _value._materials
            : materials // ignore: cast_nullable_to_non_nullable
                  as List<PlanMaterial>,
      ),
    );
  }
}

/// @nodoc

class _$PlanItemDetailsImpl extends _PlanItemDetails {
  const _$PlanItemDetailsImpl({
    final List<PlanStep> steps = const [],
    final List<PlanMaterial> materials = const [],
  }) : _steps = steps,
       _materials = materials,
       super._();

  final List<PlanStep> _steps;
  @override
  @JsonKey()
  List<PlanStep> get steps {
    if (_steps is EqualUnmodifiableListView) return _steps;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_steps);
  }

  final List<PlanMaterial> _materials;
  @override
  @JsonKey()
  List<PlanMaterial> get materials {
    if (_materials is EqualUnmodifiableListView) return _materials;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_materials);
  }

  @override
  String toString() {
    return 'PlanItemDetails(steps: $steps, materials: $materials)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlanItemDetailsImpl &&
            const DeepCollectionEquality().equals(other._steps, _steps) &&
            const DeepCollectionEquality().equals(
              other._materials,
              _materials,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_steps),
    const DeepCollectionEquality().hash(_materials),
  );

  /// Create a copy of PlanItemDetails
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlanItemDetailsImplCopyWith<_$PlanItemDetailsImpl> get copyWith =>
      __$$PlanItemDetailsImplCopyWithImpl<_$PlanItemDetailsImpl>(
        this,
        _$identity,
      );
}

abstract class _PlanItemDetails extends PlanItemDetails {
  const factory _PlanItemDetails({
    final List<PlanStep> steps,
    final List<PlanMaterial> materials,
  }) = _$PlanItemDetailsImpl;
  const _PlanItemDetails._() : super._();

  @override
  List<PlanStep> get steps;
  @override
  List<PlanMaterial> get materials;

  /// Create a copy of PlanItemDetails
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlanItemDetailsImplCopyWith<_$PlanItemDetailsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$PlanItemDetailsResponse {
  PlanItem get item => throw _privateConstructorUsedError;
  PlanItemDetails? get details => throw _privateConstructorUsedError;
  ProgressInfo? get progress => throw _privateConstructorUsedError;
  bool get completed => throw _privateConstructorUsedError;
  DetailsStatus? get detailsStatus => throw _privateConstructorUsedError;
  String? get jobId => throw _privateConstructorUsedError;

  /// Create a copy of PlanItemDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PlanItemDetailsResponseCopyWith<PlanItemDetailsResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlanItemDetailsResponseCopyWith<$Res> {
  factory $PlanItemDetailsResponseCopyWith(
    PlanItemDetailsResponse value,
    $Res Function(PlanItemDetailsResponse) then,
  ) = _$PlanItemDetailsResponseCopyWithImpl<$Res, PlanItemDetailsResponse>;
  @useResult
  $Res call({
    PlanItem item,
    PlanItemDetails? details,
    ProgressInfo? progress,
    bool completed,
    DetailsStatus? detailsStatus,
    String? jobId,
  });

  $PlanItemCopyWith<$Res> get item;
  $PlanItemDetailsCopyWith<$Res>? get details;
  $ProgressInfoCopyWith<$Res>? get progress;
}

/// @nodoc
class _$PlanItemDetailsResponseCopyWithImpl<
  $Res,
  $Val extends PlanItemDetailsResponse
>
    implements $PlanItemDetailsResponseCopyWith<$Res> {
  _$PlanItemDetailsResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PlanItemDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? item = null,
    Object? details = freezed,
    Object? progress = freezed,
    Object? completed = null,
    Object? detailsStatus = freezed,
    Object? jobId = freezed,
  }) {
    return _then(
      _value.copyWith(
            item: null == item
                ? _value.item
                : item // ignore: cast_nullable_to_non_nullable
                      as PlanItem,
            details: freezed == details
                ? _value.details
                : details // ignore: cast_nullable_to_non_nullable
                      as PlanItemDetails?,
            progress: freezed == progress
                ? _value.progress
                : progress // ignore: cast_nullable_to_non_nullable
                      as ProgressInfo?,
            completed: null == completed
                ? _value.completed
                : completed // ignore: cast_nullable_to_non_nullable
                      as bool,
            detailsStatus: freezed == detailsStatus
                ? _value.detailsStatus
                : detailsStatus // ignore: cast_nullable_to_non_nullable
                      as DetailsStatus?,
            jobId: freezed == jobId
                ? _value.jobId
                : jobId // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }

  /// Create a copy of PlanItemDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $PlanItemCopyWith<$Res> get item {
    return $PlanItemCopyWith<$Res>(_value.item, (value) {
      return _then(_value.copyWith(item: value) as $Val);
    });
  }

  /// Create a copy of PlanItemDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $PlanItemDetailsCopyWith<$Res>? get details {
    if (_value.details == null) {
      return null;
    }

    return $PlanItemDetailsCopyWith<$Res>(_value.details!, (value) {
      return _then(_value.copyWith(details: value) as $Val);
    });
  }

  /// Create a copy of PlanItemDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ProgressInfoCopyWith<$Res>? get progress {
    if (_value.progress == null) {
      return null;
    }

    return $ProgressInfoCopyWith<$Res>(_value.progress!, (value) {
      return _then(_value.copyWith(progress: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$PlanItemDetailsResponseImplCopyWith<$Res>
    implements $PlanItemDetailsResponseCopyWith<$Res> {
  factory _$$PlanItemDetailsResponseImplCopyWith(
    _$PlanItemDetailsResponseImpl value,
    $Res Function(_$PlanItemDetailsResponseImpl) then,
  ) = __$$PlanItemDetailsResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    PlanItem item,
    PlanItemDetails? details,
    ProgressInfo? progress,
    bool completed,
    DetailsStatus? detailsStatus,
    String? jobId,
  });

  @override
  $PlanItemCopyWith<$Res> get item;
  @override
  $PlanItemDetailsCopyWith<$Res>? get details;
  @override
  $ProgressInfoCopyWith<$Res>? get progress;
}

/// @nodoc
class __$$PlanItemDetailsResponseImplCopyWithImpl<$Res>
    extends
        _$PlanItemDetailsResponseCopyWithImpl<
          $Res,
          _$PlanItemDetailsResponseImpl
        >
    implements _$$PlanItemDetailsResponseImplCopyWith<$Res> {
  __$$PlanItemDetailsResponseImplCopyWithImpl(
    _$PlanItemDetailsResponseImpl _value,
    $Res Function(_$PlanItemDetailsResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PlanItemDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? item = null,
    Object? details = freezed,
    Object? progress = freezed,
    Object? completed = null,
    Object? detailsStatus = freezed,
    Object? jobId = freezed,
  }) {
    return _then(
      _$PlanItemDetailsResponseImpl(
        item: null == item
            ? _value.item
            : item // ignore: cast_nullable_to_non_nullable
                  as PlanItem,
        details: freezed == details
            ? _value.details
            : details // ignore: cast_nullable_to_non_nullable
                  as PlanItemDetails?,
        progress: freezed == progress
            ? _value.progress
            : progress // ignore: cast_nullable_to_non_nullable
                  as ProgressInfo?,
        completed: null == completed
            ? _value.completed
            : completed // ignore: cast_nullable_to_non_nullable
                  as bool,
        detailsStatus: freezed == detailsStatus
            ? _value.detailsStatus
            : detailsStatus // ignore: cast_nullable_to_non_nullable
                  as DetailsStatus?,
        jobId: freezed == jobId
            ? _value.jobId
            : jobId // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$PlanItemDetailsResponseImpl extends _PlanItemDetailsResponse {
  const _$PlanItemDetailsResponseImpl({
    required this.item,
    this.details,
    this.progress,
    this.completed = false,
    this.detailsStatus,
    this.jobId,
  }) : super._();

  @override
  final PlanItem item;
  @override
  final PlanItemDetails? details;
  @override
  final ProgressInfo? progress;
  @override
  @JsonKey()
  final bool completed;
  @override
  final DetailsStatus? detailsStatus;
  @override
  final String? jobId;

  @override
  String toString() {
    return 'PlanItemDetailsResponse(item: $item, details: $details, progress: $progress, completed: $completed, detailsStatus: $detailsStatus, jobId: $jobId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlanItemDetailsResponseImpl &&
            (identical(other.item, item) || other.item == item) &&
            (identical(other.details, details) || other.details == details) &&
            (identical(other.progress, progress) ||
                other.progress == progress) &&
            (identical(other.completed, completed) ||
                other.completed == completed) &&
            (identical(other.detailsStatus, detailsStatus) ||
                other.detailsStatus == detailsStatus) &&
            (identical(other.jobId, jobId) || other.jobId == jobId));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    item,
    details,
    progress,
    completed,
    detailsStatus,
    jobId,
  );

  /// Create a copy of PlanItemDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlanItemDetailsResponseImplCopyWith<_$PlanItemDetailsResponseImpl>
  get copyWith =>
      __$$PlanItemDetailsResponseImplCopyWithImpl<
        _$PlanItemDetailsResponseImpl
      >(this, _$identity);
}

abstract class _PlanItemDetailsResponse extends PlanItemDetailsResponse {
  const factory _PlanItemDetailsResponse({
    required final PlanItem item,
    final PlanItemDetails? details,
    final ProgressInfo? progress,
    final bool completed,
    final DetailsStatus? detailsStatus,
    final String? jobId,
  }) = _$PlanItemDetailsResponseImpl;
  const _PlanItemDetailsResponse._() : super._();

  @override
  PlanItem get item;
  @override
  PlanItemDetails? get details;
  @override
  ProgressInfo? get progress;
  @override
  bool get completed;
  @override
  DetailsStatus? get detailsStatus;
  @override
  String? get jobId;

  /// Create a copy of PlanItemDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlanItemDetailsResponseImplCopyWith<_$PlanItemDetailsResponseImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$WeekSummary {
  int get week => throw _privateConstructorUsedError;
  int get totalItems => throw _privateConstructorUsedError;
  int get completedItems => throw _privateConstructorUsedError;
  double get percent => throw _privateConstructorUsedError;
  List<PlanItem> get items => throw _privateConstructorUsedError;
  String? get theme => throw _privateConstructorUsedError;
  String? get summary => throw _privateConstructorUsedError;
  int? get totalMinutes => throw _privateConstructorUsedError;
  int? get completedMinutes => throw _privateConstructorUsedError;

  /// Create a copy of WeekSummary
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $WeekSummaryCopyWith<WeekSummary> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WeekSummaryCopyWith<$Res> {
  factory $WeekSummaryCopyWith(
    WeekSummary value,
    $Res Function(WeekSummary) then,
  ) = _$WeekSummaryCopyWithImpl<$Res, WeekSummary>;
  @useResult
  $Res call({
    int week,
    int totalItems,
    int completedItems,
    double percent,
    List<PlanItem> items,
    String? theme,
    String? summary,
    int? totalMinutes,
    int? completedMinutes,
  });
}

/// @nodoc
class _$WeekSummaryCopyWithImpl<$Res, $Val extends WeekSummary>
    implements $WeekSummaryCopyWith<$Res> {
  _$WeekSummaryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of WeekSummary
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? week = null,
    Object? totalItems = null,
    Object? completedItems = null,
    Object? percent = null,
    Object? items = null,
    Object? theme = freezed,
    Object? summary = freezed,
    Object? totalMinutes = freezed,
    Object? completedMinutes = freezed,
  }) {
    return _then(
      _value.copyWith(
            week: null == week
                ? _value.week
                : week // ignore: cast_nullable_to_non_nullable
                      as int,
            totalItems: null == totalItems
                ? _value.totalItems
                : totalItems // ignore: cast_nullable_to_non_nullable
                      as int,
            completedItems: null == completedItems
                ? _value.completedItems
                : completedItems // ignore: cast_nullable_to_non_nullable
                      as int,
            percent: null == percent
                ? _value.percent
                : percent // ignore: cast_nullable_to_non_nullable
                      as double,
            items: null == items
                ? _value.items
                : items // ignore: cast_nullable_to_non_nullable
                      as List<PlanItem>,
            theme: freezed == theme
                ? _value.theme
                : theme // ignore: cast_nullable_to_non_nullable
                      as String?,
            summary: freezed == summary
                ? _value.summary
                : summary // ignore: cast_nullable_to_non_nullable
                      as String?,
            totalMinutes: freezed == totalMinutes
                ? _value.totalMinutes
                : totalMinutes // ignore: cast_nullable_to_non_nullable
                      as int?,
            completedMinutes: freezed == completedMinutes
                ? _value.completedMinutes
                : completedMinutes // ignore: cast_nullable_to_non_nullable
                      as int?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$WeekSummaryImplCopyWith<$Res>
    implements $WeekSummaryCopyWith<$Res> {
  factory _$$WeekSummaryImplCopyWith(
    _$WeekSummaryImpl value,
    $Res Function(_$WeekSummaryImpl) then,
  ) = __$$WeekSummaryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int week,
    int totalItems,
    int completedItems,
    double percent,
    List<PlanItem> items,
    String? theme,
    String? summary,
    int? totalMinutes,
    int? completedMinutes,
  });
}

/// @nodoc
class __$$WeekSummaryImplCopyWithImpl<$Res>
    extends _$WeekSummaryCopyWithImpl<$Res, _$WeekSummaryImpl>
    implements _$$WeekSummaryImplCopyWith<$Res> {
  __$$WeekSummaryImplCopyWithImpl(
    _$WeekSummaryImpl _value,
    $Res Function(_$WeekSummaryImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WeekSummary
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? week = null,
    Object? totalItems = null,
    Object? completedItems = null,
    Object? percent = null,
    Object? items = null,
    Object? theme = freezed,
    Object? summary = freezed,
    Object? totalMinutes = freezed,
    Object? completedMinutes = freezed,
  }) {
    return _then(
      _$WeekSummaryImpl(
        week: null == week
            ? _value.week
            : week // ignore: cast_nullable_to_non_nullable
                  as int,
        totalItems: null == totalItems
            ? _value.totalItems
            : totalItems // ignore: cast_nullable_to_non_nullable
                  as int,
        completedItems: null == completedItems
            ? _value.completedItems
            : completedItems // ignore: cast_nullable_to_non_nullable
                  as int,
        percent: null == percent
            ? _value.percent
            : percent // ignore: cast_nullable_to_non_nullable
                  as double,
        items: null == items
            ? _value._items
            : items // ignore: cast_nullable_to_non_nullable
                  as List<PlanItem>,
        theme: freezed == theme
            ? _value.theme
            : theme // ignore: cast_nullable_to_non_nullable
                  as String?,
        summary: freezed == summary
            ? _value.summary
            : summary // ignore: cast_nullable_to_non_nullable
                  as String?,
        totalMinutes: freezed == totalMinutes
            ? _value.totalMinutes
            : totalMinutes // ignore: cast_nullable_to_non_nullable
                  as int?,
        completedMinutes: freezed == completedMinutes
            ? _value.completedMinutes
            : completedMinutes // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc

class _$WeekSummaryImpl extends _WeekSummary {
  const _$WeekSummaryImpl({
    required this.week,
    required this.totalItems,
    required this.completedItems,
    required this.percent,
    final List<PlanItem> items = const [],
    this.theme,
    this.summary,
    this.totalMinutes,
    this.completedMinutes,
  }) : _items = items,
       super._();

  @override
  final int week;
  @override
  final int totalItems;
  @override
  final int completedItems;
  @override
  final double percent;
  final List<PlanItem> _items;
  @override
  @JsonKey()
  List<PlanItem> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  final String? theme;
  @override
  final String? summary;
  @override
  final int? totalMinutes;
  @override
  final int? completedMinutes;

  @override
  String toString() {
    return 'WeekSummary(week: $week, totalItems: $totalItems, completedItems: $completedItems, percent: $percent, items: $items, theme: $theme, summary: $summary, totalMinutes: $totalMinutes, completedMinutes: $completedMinutes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WeekSummaryImpl &&
            (identical(other.week, week) || other.week == week) &&
            (identical(other.totalItems, totalItems) ||
                other.totalItems == totalItems) &&
            (identical(other.completedItems, completedItems) ||
                other.completedItems == completedItems) &&
            (identical(other.percent, percent) || other.percent == percent) &&
            const DeepCollectionEquality().equals(other._items, _items) &&
            (identical(other.theme, theme) || other.theme == theme) &&
            (identical(other.summary, summary) || other.summary == summary) &&
            (identical(other.totalMinutes, totalMinutes) ||
                other.totalMinutes == totalMinutes) &&
            (identical(other.completedMinutes, completedMinutes) ||
                other.completedMinutes == completedMinutes));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    week,
    totalItems,
    completedItems,
    percent,
    const DeepCollectionEquality().hash(_items),
    theme,
    summary,
    totalMinutes,
    completedMinutes,
  );

  /// Create a copy of WeekSummary
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WeekSummaryImplCopyWith<_$WeekSummaryImpl> get copyWith =>
      __$$WeekSummaryImplCopyWithImpl<_$WeekSummaryImpl>(this, _$identity);
}

abstract class _WeekSummary extends WeekSummary {
  const factory _WeekSummary({
    required final int week,
    required final int totalItems,
    required final int completedItems,
    required final double percent,
    final List<PlanItem> items,
    final String? theme,
    final String? summary,
    final int? totalMinutes,
    final int? completedMinutes,
  }) = _$WeekSummaryImpl;
  const _WeekSummary._() : super._();

  @override
  int get week;
  @override
  int get totalItems;
  @override
  int get completedItems;
  @override
  double get percent;
  @override
  List<PlanItem> get items;
  @override
  String? get theme;
  @override
  String? get summary;
  @override
  int? get totalMinutes;
  @override
  int? get completedMinutes;

  /// Create a copy of WeekSummary
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WeekSummaryImplCopyWith<_$WeekSummaryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ToggleCompleteResponse {
  bool get completed => throw _privateConstructorUsedError;
  ProgressInfo? get progress => throw _privateConstructorUsedError;

  /// Create a copy of ToggleCompleteResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ToggleCompleteResponseCopyWith<ToggleCompleteResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ToggleCompleteResponseCopyWith<$Res> {
  factory $ToggleCompleteResponseCopyWith(
    ToggleCompleteResponse value,
    $Res Function(ToggleCompleteResponse) then,
  ) = _$ToggleCompleteResponseCopyWithImpl<$Res, ToggleCompleteResponse>;
  @useResult
  $Res call({bool completed, ProgressInfo? progress});

  $ProgressInfoCopyWith<$Res>? get progress;
}

/// @nodoc
class _$ToggleCompleteResponseCopyWithImpl<
  $Res,
  $Val extends ToggleCompleteResponse
>
    implements $ToggleCompleteResponseCopyWith<$Res> {
  _$ToggleCompleteResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ToggleCompleteResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? completed = null, Object? progress = freezed}) {
    return _then(
      _value.copyWith(
            completed: null == completed
                ? _value.completed
                : completed // ignore: cast_nullable_to_non_nullable
                      as bool,
            progress: freezed == progress
                ? _value.progress
                : progress // ignore: cast_nullable_to_non_nullable
                      as ProgressInfo?,
          )
          as $Val,
    );
  }

  /// Create a copy of ToggleCompleteResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ProgressInfoCopyWith<$Res>? get progress {
    if (_value.progress == null) {
      return null;
    }

    return $ProgressInfoCopyWith<$Res>(_value.progress!, (value) {
      return _then(_value.copyWith(progress: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$ToggleCompleteResponseImplCopyWith<$Res>
    implements $ToggleCompleteResponseCopyWith<$Res> {
  factory _$$ToggleCompleteResponseImplCopyWith(
    _$ToggleCompleteResponseImpl value,
    $Res Function(_$ToggleCompleteResponseImpl) then,
  ) = __$$ToggleCompleteResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({bool completed, ProgressInfo? progress});

  @override
  $ProgressInfoCopyWith<$Res>? get progress;
}

/// @nodoc
class __$$ToggleCompleteResponseImplCopyWithImpl<$Res>
    extends
        _$ToggleCompleteResponseCopyWithImpl<$Res, _$ToggleCompleteResponseImpl>
    implements _$$ToggleCompleteResponseImplCopyWith<$Res> {
  __$$ToggleCompleteResponseImplCopyWithImpl(
    _$ToggleCompleteResponseImpl _value,
    $Res Function(_$ToggleCompleteResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ToggleCompleteResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? completed = null, Object? progress = freezed}) {
    return _then(
      _$ToggleCompleteResponseImpl(
        completed: null == completed
            ? _value.completed
            : completed // ignore: cast_nullable_to_non_nullable
                  as bool,
        progress: freezed == progress
            ? _value.progress
            : progress // ignore: cast_nullable_to_non_nullable
                  as ProgressInfo?,
      ),
    );
  }
}

/// @nodoc

class _$ToggleCompleteResponseImpl extends _ToggleCompleteResponse {
  const _$ToggleCompleteResponseImpl({required this.completed, this.progress})
    : super._();

  @override
  final bool completed;
  @override
  final ProgressInfo? progress;

  @override
  String toString() {
    return 'ToggleCompleteResponse(completed: $completed, progress: $progress)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ToggleCompleteResponseImpl &&
            (identical(other.completed, completed) ||
                other.completed == completed) &&
            (identical(other.progress, progress) ||
                other.progress == progress));
  }

  @override
  int get hashCode => Object.hash(runtimeType, completed, progress);

  /// Create a copy of ToggleCompleteResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ToggleCompleteResponseImplCopyWith<_$ToggleCompleteResponseImpl>
  get copyWith =>
      __$$ToggleCompleteResponseImplCopyWithImpl<_$ToggleCompleteResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _ToggleCompleteResponse extends ToggleCompleteResponse {
  const factory _ToggleCompleteResponse({
    required final bool completed,
    final ProgressInfo? progress,
  }) = _$ToggleCompleteResponseImpl;
  const _ToggleCompleteResponse._() : super._();

  @override
  bool get completed;
  @override
  ProgressInfo? get progress;

  /// Create a copy of ToggleCompleteResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ToggleCompleteResponseImplCopyWith<_$ToggleCompleteResponseImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ToggleStepResponse {
  String get stepId => throw _privateConstructorUsedError;
  bool get completed => throw _privateConstructorUsedError;
  ProgressInfo? get progress => throw _privateConstructorUsedError;
  bool get itemCompleted => throw _privateConstructorUsedError;

  /// Create a copy of ToggleStepResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ToggleStepResponseCopyWith<ToggleStepResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ToggleStepResponseCopyWith<$Res> {
  factory $ToggleStepResponseCopyWith(
    ToggleStepResponse value,
    $Res Function(ToggleStepResponse) then,
  ) = _$ToggleStepResponseCopyWithImpl<$Res, ToggleStepResponse>;
  @useResult
  $Res call({
    String stepId,
    bool completed,
    ProgressInfo? progress,
    bool itemCompleted,
  });

  $ProgressInfoCopyWith<$Res>? get progress;
}

/// @nodoc
class _$ToggleStepResponseCopyWithImpl<$Res, $Val extends ToggleStepResponse>
    implements $ToggleStepResponseCopyWith<$Res> {
  _$ToggleStepResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ToggleStepResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? stepId = null,
    Object? completed = null,
    Object? progress = freezed,
    Object? itemCompleted = null,
  }) {
    return _then(
      _value.copyWith(
            stepId: null == stepId
                ? _value.stepId
                : stepId // ignore: cast_nullable_to_non_nullable
                      as String,
            completed: null == completed
                ? _value.completed
                : completed // ignore: cast_nullable_to_non_nullable
                      as bool,
            progress: freezed == progress
                ? _value.progress
                : progress // ignore: cast_nullable_to_non_nullable
                      as ProgressInfo?,
            itemCompleted: null == itemCompleted
                ? _value.itemCompleted
                : itemCompleted // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }

  /// Create a copy of ToggleStepResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ProgressInfoCopyWith<$Res>? get progress {
    if (_value.progress == null) {
      return null;
    }

    return $ProgressInfoCopyWith<$Res>(_value.progress!, (value) {
      return _then(_value.copyWith(progress: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$ToggleStepResponseImplCopyWith<$Res>
    implements $ToggleStepResponseCopyWith<$Res> {
  factory _$$ToggleStepResponseImplCopyWith(
    _$ToggleStepResponseImpl value,
    $Res Function(_$ToggleStepResponseImpl) then,
  ) = __$$ToggleStepResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String stepId,
    bool completed,
    ProgressInfo? progress,
    bool itemCompleted,
  });

  @override
  $ProgressInfoCopyWith<$Res>? get progress;
}

/// @nodoc
class __$$ToggleStepResponseImplCopyWithImpl<$Res>
    extends _$ToggleStepResponseCopyWithImpl<$Res, _$ToggleStepResponseImpl>
    implements _$$ToggleStepResponseImplCopyWith<$Res> {
  __$$ToggleStepResponseImplCopyWithImpl(
    _$ToggleStepResponseImpl _value,
    $Res Function(_$ToggleStepResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ToggleStepResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? stepId = null,
    Object? completed = null,
    Object? progress = freezed,
    Object? itemCompleted = null,
  }) {
    return _then(
      _$ToggleStepResponseImpl(
        stepId: null == stepId
            ? _value.stepId
            : stepId // ignore: cast_nullable_to_non_nullable
                  as String,
        completed: null == completed
            ? _value.completed
            : completed // ignore: cast_nullable_to_non_nullable
                  as bool,
        progress: freezed == progress
            ? _value.progress
            : progress // ignore: cast_nullable_to_non_nullable
                  as ProgressInfo?,
        itemCompleted: null == itemCompleted
            ? _value.itemCompleted
            : itemCompleted // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc

class _$ToggleStepResponseImpl extends _ToggleStepResponse {
  const _$ToggleStepResponseImpl({
    required this.stepId,
    required this.completed,
    this.progress,
    this.itemCompleted = false,
  }) : super._();

  @override
  final String stepId;
  @override
  final bool completed;
  @override
  final ProgressInfo? progress;
  @override
  @JsonKey()
  final bool itemCompleted;

  @override
  String toString() {
    return 'ToggleStepResponse(stepId: $stepId, completed: $completed, progress: $progress, itemCompleted: $itemCompleted)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ToggleStepResponseImpl &&
            (identical(other.stepId, stepId) || other.stepId == stepId) &&
            (identical(other.completed, completed) ||
                other.completed == completed) &&
            (identical(other.progress, progress) ||
                other.progress == progress) &&
            (identical(other.itemCompleted, itemCompleted) ||
                other.itemCompleted == itemCompleted));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, stepId, completed, progress, itemCompleted);

  /// Create a copy of ToggleStepResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ToggleStepResponseImplCopyWith<_$ToggleStepResponseImpl> get copyWith =>
      __$$ToggleStepResponseImplCopyWithImpl<_$ToggleStepResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _ToggleStepResponse extends ToggleStepResponse {
  const factory _ToggleStepResponse({
    required final String stepId,
    required final bool completed,
    final ProgressInfo? progress,
    final bool itemCompleted,
  }) = _$ToggleStepResponseImpl;
  const _ToggleStepResponse._() : super._();

  @override
  String get stepId;
  @override
  bool get completed;
  @override
  ProgressInfo? get progress;
  @override
  bool get itemCompleted;

  /// Create a copy of ToggleStepResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ToggleStepResponseImplCopyWith<_$ToggleStepResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$RegenerateDetailsResponse {
  String get jobId => throw _privateConstructorUsedError;

  /// Create a copy of RegenerateDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RegenerateDetailsResponseCopyWith<RegenerateDetailsResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RegenerateDetailsResponseCopyWith<$Res> {
  factory $RegenerateDetailsResponseCopyWith(
    RegenerateDetailsResponse value,
    $Res Function(RegenerateDetailsResponse) then,
  ) = _$RegenerateDetailsResponseCopyWithImpl<$Res, RegenerateDetailsResponse>;
  @useResult
  $Res call({String jobId});
}

/// @nodoc
class _$RegenerateDetailsResponseCopyWithImpl<
  $Res,
  $Val extends RegenerateDetailsResponse
>
    implements $RegenerateDetailsResponseCopyWith<$Res> {
  _$RegenerateDetailsResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RegenerateDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? jobId = null}) {
    return _then(
      _value.copyWith(
            jobId: null == jobId
                ? _value.jobId
                : jobId // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$RegenerateDetailsResponseImplCopyWith<$Res>
    implements $RegenerateDetailsResponseCopyWith<$Res> {
  factory _$$RegenerateDetailsResponseImplCopyWith(
    _$RegenerateDetailsResponseImpl value,
    $Res Function(_$RegenerateDetailsResponseImpl) then,
  ) = __$$RegenerateDetailsResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String jobId});
}

/// @nodoc
class __$$RegenerateDetailsResponseImplCopyWithImpl<$Res>
    extends
        _$RegenerateDetailsResponseCopyWithImpl<
          $Res,
          _$RegenerateDetailsResponseImpl
        >
    implements _$$RegenerateDetailsResponseImplCopyWith<$Res> {
  __$$RegenerateDetailsResponseImplCopyWithImpl(
    _$RegenerateDetailsResponseImpl _value,
    $Res Function(_$RegenerateDetailsResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of RegenerateDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? jobId = null}) {
    return _then(
      _$RegenerateDetailsResponseImpl(
        jobId: null == jobId
            ? _value.jobId
            : jobId // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$RegenerateDetailsResponseImpl extends _RegenerateDetailsResponse {
  const _$RegenerateDetailsResponseImpl({required this.jobId}) : super._();

  @override
  final String jobId;

  @override
  String toString() {
    return 'RegenerateDetailsResponse(jobId: $jobId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RegenerateDetailsResponseImpl &&
            (identical(other.jobId, jobId) || other.jobId == jobId));
  }

  @override
  int get hashCode => Object.hash(runtimeType, jobId);

  /// Create a copy of RegenerateDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RegenerateDetailsResponseImplCopyWith<_$RegenerateDetailsResponseImpl>
  get copyWith =>
      __$$RegenerateDetailsResponseImplCopyWithImpl<
        _$RegenerateDetailsResponseImpl
      >(this, _$identity);
}

abstract class _RegenerateDetailsResponse extends RegenerateDetailsResponse {
  const factory _RegenerateDetailsResponse({required final String jobId}) =
      _$RegenerateDetailsResponseImpl;
  const _RegenerateDetailsResponse._() : super._();

  @override
  String get jobId;

  /// Create a copy of RegenerateDetailsResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RegenerateDetailsResponseImplCopyWith<_$RegenerateDetailsResponseImpl>
  get copyWith => throw _privateConstructorUsedError;
}
