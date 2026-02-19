// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'note_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$NoteAttachment {
  String? get id => throw _privateConstructorUsedError;
  String? get idolId => throw _privateConstructorUsedError;
  String? get planItemId => throw _privateConstructorUsedError;
  String? get achievementId => throw _privateConstructorUsedError;

  /// Create a copy of NoteAttachment
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $NoteAttachmentCopyWith<NoteAttachment> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $NoteAttachmentCopyWith<$Res> {
  factory $NoteAttachmentCopyWith(
    NoteAttachment value,
    $Res Function(NoteAttachment) then,
  ) = _$NoteAttachmentCopyWithImpl<$Res, NoteAttachment>;
  @useResult
  $Res call({
    String? id,
    String? idolId,
    String? planItemId,
    String? achievementId,
  });
}

/// @nodoc
class _$NoteAttachmentCopyWithImpl<$Res, $Val extends NoteAttachment>
    implements $NoteAttachmentCopyWith<$Res> {
  _$NoteAttachmentCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of NoteAttachment
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? idolId = freezed,
    Object? planItemId = freezed,
    Object? achievementId = freezed,
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
            planItemId: freezed == planItemId
                ? _value.planItemId
                : planItemId // ignore: cast_nullable_to_non_nullable
                      as String?,
            achievementId: freezed == achievementId
                ? _value.achievementId
                : achievementId // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$NoteAttachmentImplCopyWith<$Res>
    implements $NoteAttachmentCopyWith<$Res> {
  factory _$$NoteAttachmentImplCopyWith(
    _$NoteAttachmentImpl value,
    $Res Function(_$NoteAttachmentImpl) then,
  ) = __$$NoteAttachmentImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String? id,
    String? idolId,
    String? planItemId,
    String? achievementId,
  });
}

/// @nodoc
class __$$NoteAttachmentImplCopyWithImpl<$Res>
    extends _$NoteAttachmentCopyWithImpl<$Res, _$NoteAttachmentImpl>
    implements _$$NoteAttachmentImplCopyWith<$Res> {
  __$$NoteAttachmentImplCopyWithImpl(
    _$NoteAttachmentImpl _value,
    $Res Function(_$NoteAttachmentImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of NoteAttachment
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? idolId = freezed,
    Object? planItemId = freezed,
    Object? achievementId = freezed,
  }) {
    return _then(
      _$NoteAttachmentImpl(
        id: freezed == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String?,
        idolId: freezed == idolId
            ? _value.idolId
            : idolId // ignore: cast_nullable_to_non_nullable
                  as String?,
        planItemId: freezed == planItemId
            ? _value.planItemId
            : planItemId // ignore: cast_nullable_to_non_nullable
                  as String?,
        achievementId: freezed == achievementId
            ? _value.achievementId
            : achievementId // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$NoteAttachmentImpl implements _NoteAttachment {
  const _$NoteAttachmentImpl({
    this.id,
    this.idolId,
    this.planItemId,
    this.achievementId,
  });

  @override
  final String? id;
  @override
  final String? idolId;
  @override
  final String? planItemId;
  @override
  final String? achievementId;

  @override
  String toString() {
    return 'NoteAttachment(id: $id, idolId: $idolId, planItemId: $planItemId, achievementId: $achievementId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NoteAttachmentImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.idolId, idolId) || other.idolId == idolId) &&
            (identical(other.planItemId, planItemId) ||
                other.planItemId == planItemId) &&
            (identical(other.achievementId, achievementId) ||
                other.achievementId == achievementId));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, id, idolId, planItemId, achievementId);

  /// Create a copy of NoteAttachment
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NoteAttachmentImplCopyWith<_$NoteAttachmentImpl> get copyWith =>
      __$$NoteAttachmentImplCopyWithImpl<_$NoteAttachmentImpl>(
        this,
        _$identity,
      );
}

abstract class _NoteAttachment implements NoteAttachment {
  const factory _NoteAttachment({
    final String? id,
    final String? idolId,
    final String? planItemId,
    final String? achievementId,
  }) = _$NoteAttachmentImpl;

  @override
  String? get id;
  @override
  String? get idolId;
  @override
  String? get planItemId;
  @override
  String? get achievementId;

  /// Create a copy of NoteAttachment
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NoteAttachmentImplCopyWith<_$NoteAttachmentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$Note {
  String get id => throw _privateConstructorUsedError;
  String? get userId => throw _privateConstructorUsedError;
  String? get title => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  DateTime get updatedAt => throw _privateConstructorUsedError;
  List<NoteAttachment> get attachments => throw _privateConstructorUsedError;

  /// Create a copy of Note
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $NoteCopyWith<Note> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $NoteCopyWith<$Res> {
  factory $NoteCopyWith(Note value, $Res Function(Note) then) =
      _$NoteCopyWithImpl<$Res, Note>;
  @useResult
  $Res call({
    String id,
    String? userId,
    String? title,
    String content,
    DateTime createdAt,
    DateTime updatedAt,
    List<NoteAttachment> attachments,
  });
}

/// @nodoc
class _$NoteCopyWithImpl<$Res, $Val extends Note>
    implements $NoteCopyWith<$Res> {
  _$NoteCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Note
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = freezed,
    Object? title = freezed,
    Object? content = null,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? attachments = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            userId: freezed == userId
                ? _value.userId
                : userId // ignore: cast_nullable_to_non_nullable
                      as String?,
            title: freezed == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String?,
            content: null == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                      as String,
            createdAt: null == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            updatedAt: null == updatedAt
                ? _value.updatedAt
                : updatedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            attachments: null == attachments
                ? _value.attachments
                : attachments // ignore: cast_nullable_to_non_nullable
                      as List<NoteAttachment>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$NoteImplCopyWith<$Res> implements $NoteCopyWith<$Res> {
  factory _$$NoteImplCopyWith(
    _$NoteImpl value,
    $Res Function(_$NoteImpl) then,
  ) = __$$NoteImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String? userId,
    String? title,
    String content,
    DateTime createdAt,
    DateTime updatedAt,
    List<NoteAttachment> attachments,
  });
}

/// @nodoc
class __$$NoteImplCopyWithImpl<$Res>
    extends _$NoteCopyWithImpl<$Res, _$NoteImpl>
    implements _$$NoteImplCopyWith<$Res> {
  __$$NoteImplCopyWithImpl(_$NoteImpl _value, $Res Function(_$NoteImpl) _then)
    : super(_value, _then);

  /// Create a copy of Note
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = freezed,
    Object? title = freezed,
    Object? content = null,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? attachments = null,
  }) {
    return _then(
      _$NoteImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        userId: freezed == userId
            ? _value.userId
            : userId // ignore: cast_nullable_to_non_nullable
                  as String?,
        title: freezed == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String?,
        content: null == content
            ? _value.content
            : content // ignore: cast_nullable_to_non_nullable
                  as String,
        createdAt: null == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        updatedAt: null == updatedAt
            ? _value.updatedAt
            : updatedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        attachments: null == attachments
            ? _value._attachments
            : attachments // ignore: cast_nullable_to_non_nullable
                  as List<NoteAttachment>,
      ),
    );
  }
}

/// @nodoc

class _$NoteImpl implements _Note {
  const _$NoteImpl({
    required this.id,
    this.userId,
    this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    final List<NoteAttachment> attachments = const [],
  }) : _attachments = attachments;

  @override
  final String id;
  @override
  final String? userId;
  @override
  final String? title;
  @override
  final String content;
  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  final List<NoteAttachment> _attachments;
  @override
  @JsonKey()
  List<NoteAttachment> get attachments {
    if (_attachments is EqualUnmodifiableListView) return _attachments;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_attachments);
  }

  @override
  String toString() {
    return 'Note(id: $id, userId: $userId, title: $title, content: $content, createdAt: $createdAt, updatedAt: $updatedAt, attachments: $attachments)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NoteImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            const DeepCollectionEquality().equals(
              other._attachments,
              _attachments,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    userId,
    title,
    content,
    createdAt,
    updatedAt,
    const DeepCollectionEquality().hash(_attachments),
  );

  /// Create a copy of Note
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NoteImplCopyWith<_$NoteImpl> get copyWith =>
      __$$NoteImplCopyWithImpl<_$NoteImpl>(this, _$identity);
}

abstract class _Note implements Note {
  const factory _Note({
    required final String id,
    final String? userId,
    final String? title,
    required final String content,
    required final DateTime createdAt,
    required final DateTime updatedAt,
    final List<NoteAttachment> attachments,
  }) = _$NoteImpl;

  @override
  String get id;
  @override
  String? get userId;
  @override
  String? get title;
  @override
  String get content;
  @override
  DateTime get createdAt;
  @override
  DateTime get updatedAt;
  @override
  List<NoteAttachment> get attachments;

  /// Create a copy of Note
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NoteImplCopyWith<_$NoteImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$CreateNoteRequest {
  String? get title => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  List<NoteAttachment>? get attachments => throw _privateConstructorUsedError;

  /// Create a copy of CreateNoteRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CreateNoteRequestCopyWith<CreateNoteRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CreateNoteRequestCopyWith<$Res> {
  factory $CreateNoteRequestCopyWith(
    CreateNoteRequest value,
    $Res Function(CreateNoteRequest) then,
  ) = _$CreateNoteRequestCopyWithImpl<$Res, CreateNoteRequest>;
  @useResult
  $Res call({String? title, String content, List<NoteAttachment>? attachments});
}

/// @nodoc
class _$CreateNoteRequestCopyWithImpl<$Res, $Val extends CreateNoteRequest>
    implements $CreateNoteRequestCopyWith<$Res> {
  _$CreateNoteRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CreateNoteRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = freezed,
    Object? content = null,
    Object? attachments = freezed,
  }) {
    return _then(
      _value.copyWith(
            title: freezed == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String?,
            content: null == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                      as String,
            attachments: freezed == attachments
                ? _value.attachments
                : attachments // ignore: cast_nullable_to_non_nullable
                      as List<NoteAttachment>?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$CreateNoteRequestImplCopyWith<$Res>
    implements $CreateNoteRequestCopyWith<$Res> {
  factory _$$CreateNoteRequestImplCopyWith(
    _$CreateNoteRequestImpl value,
    $Res Function(_$CreateNoteRequestImpl) then,
  ) = __$$CreateNoteRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? title, String content, List<NoteAttachment>? attachments});
}

/// @nodoc
class __$$CreateNoteRequestImplCopyWithImpl<$Res>
    extends _$CreateNoteRequestCopyWithImpl<$Res, _$CreateNoteRequestImpl>
    implements _$$CreateNoteRequestImplCopyWith<$Res> {
  __$$CreateNoteRequestImplCopyWithImpl(
    _$CreateNoteRequestImpl _value,
    $Res Function(_$CreateNoteRequestImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of CreateNoteRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = freezed,
    Object? content = null,
    Object? attachments = freezed,
  }) {
    return _then(
      _$CreateNoteRequestImpl(
        title: freezed == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String?,
        content: null == content
            ? _value.content
            : content // ignore: cast_nullable_to_non_nullable
                  as String,
        attachments: freezed == attachments
            ? _value._attachments
            : attachments // ignore: cast_nullable_to_non_nullable
                  as List<NoteAttachment>?,
      ),
    );
  }
}

/// @nodoc

class _$CreateNoteRequestImpl extends _CreateNoteRequest {
  const _$CreateNoteRequestImpl({
    this.title,
    required this.content,
    final List<NoteAttachment>? attachments,
  }) : _attachments = attachments,
       super._();

  @override
  final String? title;
  @override
  final String content;
  final List<NoteAttachment>? _attachments;
  @override
  List<NoteAttachment>? get attachments {
    final value = _attachments;
    if (value == null) return null;
    if (_attachments is EqualUnmodifiableListView) return _attachments;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  String toString() {
    return 'CreateNoteRequest(title: $title, content: $content, attachments: $attachments)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CreateNoteRequestImpl &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.content, content) || other.content == content) &&
            const DeepCollectionEquality().equals(
              other._attachments,
              _attachments,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    title,
    content,
    const DeepCollectionEquality().hash(_attachments),
  );

  /// Create a copy of CreateNoteRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CreateNoteRequestImplCopyWith<_$CreateNoteRequestImpl> get copyWith =>
      __$$CreateNoteRequestImplCopyWithImpl<_$CreateNoteRequestImpl>(
        this,
        _$identity,
      );
}

abstract class _CreateNoteRequest extends CreateNoteRequest {
  const factory _CreateNoteRequest({
    final String? title,
    required final String content,
    final List<NoteAttachment>? attachments,
  }) = _$CreateNoteRequestImpl;
  const _CreateNoteRequest._() : super._();

  @override
  String? get title;
  @override
  String get content;
  @override
  List<NoteAttachment>? get attachments;

  /// Create a copy of CreateNoteRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CreateNoteRequestImplCopyWith<_$CreateNoteRequestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$UpdateNoteRequest {
  String? get title => throw _privateConstructorUsedError;
  String? get content => throw _privateConstructorUsedError;
  List<NoteAttachment>? get attachments => throw _privateConstructorUsedError;

  /// Create a copy of UpdateNoteRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UpdateNoteRequestCopyWith<UpdateNoteRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UpdateNoteRequestCopyWith<$Res> {
  factory $UpdateNoteRequestCopyWith(
    UpdateNoteRequest value,
    $Res Function(UpdateNoteRequest) then,
  ) = _$UpdateNoteRequestCopyWithImpl<$Res, UpdateNoteRequest>;
  @useResult
  $Res call({
    String? title,
    String? content,
    List<NoteAttachment>? attachments,
  });
}

/// @nodoc
class _$UpdateNoteRequestCopyWithImpl<$Res, $Val extends UpdateNoteRequest>
    implements $UpdateNoteRequestCopyWith<$Res> {
  _$UpdateNoteRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UpdateNoteRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = freezed,
    Object? content = freezed,
    Object? attachments = freezed,
  }) {
    return _then(
      _value.copyWith(
            title: freezed == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String?,
            content: freezed == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                      as String?,
            attachments: freezed == attachments
                ? _value.attachments
                : attachments // ignore: cast_nullable_to_non_nullable
                      as List<NoteAttachment>?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$UpdateNoteRequestImplCopyWith<$Res>
    implements $UpdateNoteRequestCopyWith<$Res> {
  factory _$$UpdateNoteRequestImplCopyWith(
    _$UpdateNoteRequestImpl value,
    $Res Function(_$UpdateNoteRequestImpl) then,
  ) = __$$UpdateNoteRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String? title,
    String? content,
    List<NoteAttachment>? attachments,
  });
}

/// @nodoc
class __$$UpdateNoteRequestImplCopyWithImpl<$Res>
    extends _$UpdateNoteRequestCopyWithImpl<$Res, _$UpdateNoteRequestImpl>
    implements _$$UpdateNoteRequestImplCopyWith<$Res> {
  __$$UpdateNoteRequestImplCopyWithImpl(
    _$UpdateNoteRequestImpl _value,
    $Res Function(_$UpdateNoteRequestImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of UpdateNoteRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = freezed,
    Object? content = freezed,
    Object? attachments = freezed,
  }) {
    return _then(
      _$UpdateNoteRequestImpl(
        title: freezed == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String?,
        content: freezed == content
            ? _value.content
            : content // ignore: cast_nullable_to_non_nullable
                  as String?,
        attachments: freezed == attachments
            ? _value._attachments
            : attachments // ignore: cast_nullable_to_non_nullable
                  as List<NoteAttachment>?,
      ),
    );
  }
}

/// @nodoc

class _$UpdateNoteRequestImpl extends _UpdateNoteRequest {
  const _$UpdateNoteRequestImpl({
    this.title,
    this.content,
    final List<NoteAttachment>? attachments,
  }) : _attachments = attachments,
       super._();

  @override
  final String? title;
  @override
  final String? content;
  final List<NoteAttachment>? _attachments;
  @override
  List<NoteAttachment>? get attachments {
    final value = _attachments;
    if (value == null) return null;
    if (_attachments is EqualUnmodifiableListView) return _attachments;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  String toString() {
    return 'UpdateNoteRequest(title: $title, content: $content, attachments: $attachments)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UpdateNoteRequestImpl &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.content, content) || other.content == content) &&
            const DeepCollectionEquality().equals(
              other._attachments,
              _attachments,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    title,
    content,
    const DeepCollectionEquality().hash(_attachments),
  );

  /// Create a copy of UpdateNoteRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UpdateNoteRequestImplCopyWith<_$UpdateNoteRequestImpl> get copyWith =>
      __$$UpdateNoteRequestImplCopyWithImpl<_$UpdateNoteRequestImpl>(
        this,
        _$identity,
      );
}

abstract class _UpdateNoteRequest extends UpdateNoteRequest {
  const factory _UpdateNoteRequest({
    final String? title,
    final String? content,
    final List<NoteAttachment>? attachments,
  }) = _$UpdateNoteRequestImpl;
  const _UpdateNoteRequest._() : super._();

  @override
  String? get title;
  @override
  String? get content;
  @override
  List<NoteAttachment>? get attachments;

  /// Create a copy of UpdateNoteRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UpdateNoteRequestImplCopyWith<_$UpdateNoteRequestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$NotesListResponse {
  List<Note> get notes => throw _privateConstructorUsedError;
  int? get totalCount => throw _privateConstructorUsedError;
  int? get total => throw _privateConstructorUsedError;
  bool get hasMore => throw _privateConstructorUsedError;

  /// Create a copy of NotesListResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $NotesListResponseCopyWith<NotesListResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $NotesListResponseCopyWith<$Res> {
  factory $NotesListResponseCopyWith(
    NotesListResponse value,
    $Res Function(NotesListResponse) then,
  ) = _$NotesListResponseCopyWithImpl<$Res, NotesListResponse>;
  @useResult
  $Res call({List<Note> notes, int? totalCount, int? total, bool hasMore});
}

/// @nodoc
class _$NotesListResponseCopyWithImpl<$Res, $Val extends NotesListResponse>
    implements $NotesListResponseCopyWith<$Res> {
  _$NotesListResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of NotesListResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? notes = null,
    Object? totalCount = freezed,
    Object? total = freezed,
    Object? hasMore = null,
  }) {
    return _then(
      _value.copyWith(
            notes: null == notes
                ? _value.notes
                : notes // ignore: cast_nullable_to_non_nullable
                      as List<Note>,
            totalCount: freezed == totalCount
                ? _value.totalCount
                : totalCount // ignore: cast_nullable_to_non_nullable
                      as int?,
            total: freezed == total
                ? _value.total
                : total // ignore: cast_nullable_to_non_nullable
                      as int?,
            hasMore: null == hasMore
                ? _value.hasMore
                : hasMore // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$NotesListResponseImplCopyWith<$Res>
    implements $NotesListResponseCopyWith<$Res> {
  factory _$$NotesListResponseImplCopyWith(
    _$NotesListResponseImpl value,
    $Res Function(_$NotesListResponseImpl) then,
  ) = __$$NotesListResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<Note> notes, int? totalCount, int? total, bool hasMore});
}

/// @nodoc
class __$$NotesListResponseImplCopyWithImpl<$Res>
    extends _$NotesListResponseCopyWithImpl<$Res, _$NotesListResponseImpl>
    implements _$$NotesListResponseImplCopyWith<$Res> {
  __$$NotesListResponseImplCopyWithImpl(
    _$NotesListResponseImpl _value,
    $Res Function(_$NotesListResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of NotesListResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? notes = null,
    Object? totalCount = freezed,
    Object? total = freezed,
    Object? hasMore = null,
  }) {
    return _then(
      _$NotesListResponseImpl(
        notes: null == notes
            ? _value._notes
            : notes // ignore: cast_nullable_to_non_nullable
                  as List<Note>,
        totalCount: freezed == totalCount
            ? _value.totalCount
            : totalCount // ignore: cast_nullable_to_non_nullable
                  as int?,
        total: freezed == total
            ? _value.total
            : total // ignore: cast_nullable_to_non_nullable
                  as int?,
        hasMore: null == hasMore
            ? _value.hasMore
            : hasMore // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc

class _$NotesListResponseImpl implements _NotesListResponse {
  const _$NotesListResponseImpl({
    final List<Note> notes = const [],
    this.totalCount,
    this.total,
    this.hasMore = false,
  }) : _notes = notes;

  final List<Note> _notes;
  @override
  @JsonKey()
  List<Note> get notes {
    if (_notes is EqualUnmodifiableListView) return _notes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_notes);
  }

  @override
  final int? totalCount;
  @override
  final int? total;
  @override
  @JsonKey()
  final bool hasMore;

  @override
  String toString() {
    return 'NotesListResponse(notes: $notes, totalCount: $totalCount, total: $total, hasMore: $hasMore)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NotesListResponseImpl &&
            const DeepCollectionEquality().equals(other._notes, _notes) &&
            (identical(other.totalCount, totalCount) ||
                other.totalCount == totalCount) &&
            (identical(other.total, total) || other.total == total) &&
            (identical(other.hasMore, hasMore) || other.hasMore == hasMore));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_notes),
    totalCount,
    total,
    hasMore,
  );

  /// Create a copy of NotesListResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NotesListResponseImplCopyWith<_$NotesListResponseImpl> get copyWith =>
      __$$NotesListResponseImplCopyWithImpl<_$NotesListResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _NotesListResponse implements NotesListResponse {
  const factory _NotesListResponse({
    final List<Note> notes,
    final int? totalCount,
    final int? total,
    final bool hasMore,
  }) = _$NotesListResponseImpl;

  @override
  List<Note> get notes;
  @override
  int? get totalCount;
  @override
  int? get total;
  @override
  bool get hasMore;

  /// Create a copy of NotesListResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NotesListResponseImplCopyWith<_$NotesListResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
