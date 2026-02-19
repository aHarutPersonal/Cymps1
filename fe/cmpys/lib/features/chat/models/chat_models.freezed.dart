// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$ChatMessage {
  String get id => throw _privateConstructorUsedError;
  String get role => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  String? get threadId => throw _privateConstructorUsedError;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ChatMessageCopyWith<ChatMessage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChatMessageCopyWith<$Res> {
  factory $ChatMessageCopyWith(
    ChatMessage value,
    $Res Function(ChatMessage) then,
  ) = _$ChatMessageCopyWithImpl<$Res, ChatMessage>;
  @useResult
  $Res call({
    String id,
    String role,
    String content,
    DateTime createdAt,
    String? threadId,
  });
}

/// @nodoc
class _$ChatMessageCopyWithImpl<$Res, $Val extends ChatMessage>
    implements $ChatMessageCopyWith<$Res> {
  _$ChatMessageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? role = null,
    Object? content = null,
    Object? createdAt = null,
    Object? threadId = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            role: null == role
                ? _value.role
                : role // ignore: cast_nullable_to_non_nullable
                      as String,
            content: null == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                      as String,
            createdAt: null == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            threadId: freezed == threadId
                ? _value.threadId
                : threadId // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ChatMessageImplCopyWith<$Res>
    implements $ChatMessageCopyWith<$Res> {
  factory _$$ChatMessageImplCopyWith(
    _$ChatMessageImpl value,
    $Res Function(_$ChatMessageImpl) then,
  ) = __$$ChatMessageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String role,
    String content,
    DateTime createdAt,
    String? threadId,
  });
}

/// @nodoc
class __$$ChatMessageImplCopyWithImpl<$Res>
    extends _$ChatMessageCopyWithImpl<$Res, _$ChatMessageImpl>
    implements _$$ChatMessageImplCopyWith<$Res> {
  __$$ChatMessageImplCopyWithImpl(
    _$ChatMessageImpl _value,
    $Res Function(_$ChatMessageImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? role = null,
    Object? content = null,
    Object? createdAt = null,
    Object? threadId = freezed,
  }) {
    return _then(
      _$ChatMessageImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        role: null == role
            ? _value.role
            : role // ignore: cast_nullable_to_non_nullable
                  as String,
        content: null == content
            ? _value.content
            : content // ignore: cast_nullable_to_non_nullable
                  as String,
        createdAt: null == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        threadId: freezed == threadId
            ? _value.threadId
            : threadId // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$ChatMessageImpl extends _ChatMessage {
  const _$ChatMessageImpl({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.threadId,
  }) : super._();

  @override
  final String id;
  @override
  final String role;
  @override
  final String content;
  @override
  final DateTime createdAt;
  @override
  final String? threadId;

  @override
  String toString() {
    return 'ChatMessage(id: $id, role: $role, content: $content, createdAt: $createdAt, threadId: $threadId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChatMessageImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.role, role) || other.role == role) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.threadId, threadId) ||
                other.threadId == threadId));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, id, role, content, createdAt, threadId);

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ChatMessageImplCopyWith<_$ChatMessageImpl> get copyWith =>
      __$$ChatMessageImplCopyWithImpl<_$ChatMessageImpl>(this, _$identity);
}

abstract class _ChatMessage extends ChatMessage {
  const factory _ChatMessage({
    required final String id,
    required final String role,
    required final String content,
    required final DateTime createdAt,
    final String? threadId,
  }) = _$ChatMessageImpl;
  const _ChatMessage._() : super._();

  @override
  String get id;
  @override
  String get role;
  @override
  String get content;
  @override
  DateTime get createdAt;
  @override
  String? get threadId;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ChatMessageImplCopyWith<_$ChatMessageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ChatThread {
  String get id => throw _privateConstructorUsedError;
  String get idolId => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;
  ChatMessage? get lastMessage => throw _privateConstructorUsedError;
  int get messageCount => throw _privateConstructorUsedError;
  String? get title => throw _privateConstructorUsedError;
  String? get idolName => throw _privateConstructorUsedError;
  String? get idolImageUrl => throw _privateConstructorUsedError;
  List<ChatMessage>? get messages => throw _privateConstructorUsedError;

  /// Create a copy of ChatThread
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ChatThreadCopyWith<ChatThread> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChatThreadCopyWith<$Res> {
  factory $ChatThreadCopyWith(
    ChatThread value,
    $Res Function(ChatThread) then,
  ) = _$ChatThreadCopyWithImpl<$Res, ChatThread>;
  @useResult
  $Res call({
    String id,
    String idolId,
    DateTime createdAt,
    DateTime? updatedAt,
    ChatMessage? lastMessage,
    int messageCount,
    String? title,
    String? idolName,
    String? idolImageUrl,
    List<ChatMessage>? messages,
  });

  $ChatMessageCopyWith<$Res>? get lastMessage;
}

/// @nodoc
class _$ChatThreadCopyWithImpl<$Res, $Val extends ChatThread>
    implements $ChatThreadCopyWith<$Res> {
  _$ChatThreadCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ChatThread
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? idolId = null,
    Object? createdAt = null,
    Object? updatedAt = freezed,
    Object? lastMessage = freezed,
    Object? messageCount = null,
    Object? title = freezed,
    Object? idolName = freezed,
    Object? idolImageUrl = freezed,
    Object? messages = freezed,
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
            createdAt: null == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            updatedAt: freezed == updatedAt
                ? _value.updatedAt
                : updatedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            lastMessage: freezed == lastMessage
                ? _value.lastMessage
                : lastMessage // ignore: cast_nullable_to_non_nullable
                      as ChatMessage?,
            messageCount: null == messageCount
                ? _value.messageCount
                : messageCount // ignore: cast_nullable_to_non_nullable
                      as int,
            title: freezed == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String?,
            idolName: freezed == idolName
                ? _value.idolName
                : idolName // ignore: cast_nullable_to_non_nullable
                      as String?,
            idolImageUrl: freezed == idolImageUrl
                ? _value.idolImageUrl
                : idolImageUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            messages: freezed == messages
                ? _value.messages
                : messages // ignore: cast_nullable_to_non_nullable
                      as List<ChatMessage>?,
          )
          as $Val,
    );
  }

  /// Create a copy of ChatThread
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ChatMessageCopyWith<$Res>? get lastMessage {
    if (_value.lastMessage == null) {
      return null;
    }

    return $ChatMessageCopyWith<$Res>(_value.lastMessage!, (value) {
      return _then(_value.copyWith(lastMessage: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$ChatThreadImplCopyWith<$Res>
    implements $ChatThreadCopyWith<$Res> {
  factory _$$ChatThreadImplCopyWith(
    _$ChatThreadImpl value,
    $Res Function(_$ChatThreadImpl) then,
  ) = __$$ChatThreadImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String idolId,
    DateTime createdAt,
    DateTime? updatedAt,
    ChatMessage? lastMessage,
    int messageCount,
    String? title,
    String? idolName,
    String? idolImageUrl,
    List<ChatMessage>? messages,
  });

  @override
  $ChatMessageCopyWith<$Res>? get lastMessage;
}

/// @nodoc
class __$$ChatThreadImplCopyWithImpl<$Res>
    extends _$ChatThreadCopyWithImpl<$Res, _$ChatThreadImpl>
    implements _$$ChatThreadImplCopyWith<$Res> {
  __$$ChatThreadImplCopyWithImpl(
    _$ChatThreadImpl _value,
    $Res Function(_$ChatThreadImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ChatThread
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? idolId = null,
    Object? createdAt = null,
    Object? updatedAt = freezed,
    Object? lastMessage = freezed,
    Object? messageCount = null,
    Object? title = freezed,
    Object? idolName = freezed,
    Object? idolImageUrl = freezed,
    Object? messages = freezed,
  }) {
    return _then(
      _$ChatThreadImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        idolId: null == idolId
            ? _value.idolId
            : idolId // ignore: cast_nullable_to_non_nullable
                  as String,
        createdAt: null == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        updatedAt: freezed == updatedAt
            ? _value.updatedAt
            : updatedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        lastMessage: freezed == lastMessage
            ? _value.lastMessage
            : lastMessage // ignore: cast_nullable_to_non_nullable
                  as ChatMessage?,
        messageCount: null == messageCount
            ? _value.messageCount
            : messageCount // ignore: cast_nullable_to_non_nullable
                  as int,
        title: freezed == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String?,
        idolName: freezed == idolName
            ? _value.idolName
            : idolName // ignore: cast_nullable_to_non_nullable
                  as String?,
        idolImageUrl: freezed == idolImageUrl
            ? _value.idolImageUrl
            : idolImageUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        messages: freezed == messages
            ? _value._messages
            : messages // ignore: cast_nullable_to_non_nullable
                  as List<ChatMessage>?,
      ),
    );
  }
}

/// @nodoc

class _$ChatThreadImpl extends _ChatThread {
  const _$ChatThreadImpl({
    required this.id,
    required this.idolId,
    required this.createdAt,
    this.updatedAt,
    this.lastMessage,
    this.messageCount = 0,
    this.title,
    this.idolName,
    this.idolImageUrl,
    final List<ChatMessage>? messages,
  }) : _messages = messages,
       super._();

  @override
  final String id;
  @override
  final String idolId;
  @override
  final DateTime createdAt;
  @override
  final DateTime? updatedAt;
  @override
  final ChatMessage? lastMessage;
  @override
  @JsonKey()
  final int messageCount;
  @override
  final String? title;
  @override
  final String? idolName;
  @override
  final String? idolImageUrl;
  final List<ChatMessage>? _messages;
  @override
  List<ChatMessage>? get messages {
    final value = _messages;
    if (value == null) return null;
    if (_messages is EqualUnmodifiableListView) return _messages;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  String toString() {
    return 'ChatThread(id: $id, idolId: $idolId, createdAt: $createdAt, updatedAt: $updatedAt, lastMessage: $lastMessage, messageCount: $messageCount, title: $title, idolName: $idolName, idolImageUrl: $idolImageUrl, messages: $messages)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChatThreadImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.idolId, idolId) || other.idolId == idolId) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.lastMessage, lastMessage) ||
                other.lastMessage == lastMessage) &&
            (identical(other.messageCount, messageCount) ||
                other.messageCount == messageCount) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.idolName, idolName) ||
                other.idolName == idolName) &&
            (identical(other.idolImageUrl, idolImageUrl) ||
                other.idolImageUrl == idolImageUrl) &&
            const DeepCollectionEquality().equals(other._messages, _messages));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    idolId,
    createdAt,
    updatedAt,
    lastMessage,
    messageCount,
    title,
    idolName,
    idolImageUrl,
    const DeepCollectionEquality().hash(_messages),
  );

  /// Create a copy of ChatThread
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ChatThreadImplCopyWith<_$ChatThreadImpl> get copyWith =>
      __$$ChatThreadImplCopyWithImpl<_$ChatThreadImpl>(this, _$identity);
}

abstract class _ChatThread extends ChatThread {
  const factory _ChatThread({
    required final String id,
    required final String idolId,
    required final DateTime createdAt,
    final DateTime? updatedAt,
    final ChatMessage? lastMessage,
    final int messageCount,
    final String? title,
    final String? idolName,
    final String? idolImageUrl,
    final List<ChatMessage>? messages,
  }) = _$ChatThreadImpl;
  const _ChatThread._() : super._();

  @override
  String get id;
  @override
  String get idolId;
  @override
  DateTime get createdAt;
  @override
  DateTime? get updatedAt;
  @override
  ChatMessage? get lastMessage;
  @override
  int get messageCount;
  @override
  String? get title;
  @override
  String? get idolName;
  @override
  String? get idolImageUrl;
  @override
  List<ChatMessage>? get messages;

  /// Create a copy of ChatThread
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ChatThreadImplCopyWith<_$ChatThreadImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SuggestedAction {
  String get type => throw _privateConstructorUsedError;
  String get label => throw _privateConstructorUsedError;
  Map<String, dynamic>? get payload => throw _privateConstructorUsedError;

  /// Create a copy of SuggestedAction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SuggestedActionCopyWith<SuggestedAction> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SuggestedActionCopyWith<$Res> {
  factory $SuggestedActionCopyWith(
    SuggestedAction value,
    $Res Function(SuggestedAction) then,
  ) = _$SuggestedActionCopyWithImpl<$Res, SuggestedAction>;
  @useResult
  $Res call({String type, String label, Map<String, dynamic>? payload});
}

/// @nodoc
class _$SuggestedActionCopyWithImpl<$Res, $Val extends SuggestedAction>
    implements $SuggestedActionCopyWith<$Res> {
  _$SuggestedActionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SuggestedAction
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? label = null,
    Object? payload = freezed,
  }) {
    return _then(
      _value.copyWith(
            type: null == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as String,
            label: null == label
                ? _value.label
                : label // ignore: cast_nullable_to_non_nullable
                      as String,
            payload: freezed == payload
                ? _value.payload
                : payload // ignore: cast_nullable_to_non_nullable
                      as Map<String, dynamic>?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SuggestedActionImplCopyWith<$Res>
    implements $SuggestedActionCopyWith<$Res> {
  factory _$$SuggestedActionImplCopyWith(
    _$SuggestedActionImpl value,
    $Res Function(_$SuggestedActionImpl) then,
  ) = __$$SuggestedActionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String type, String label, Map<String, dynamic>? payload});
}

/// @nodoc
class __$$SuggestedActionImplCopyWithImpl<$Res>
    extends _$SuggestedActionCopyWithImpl<$Res, _$SuggestedActionImpl>
    implements _$$SuggestedActionImplCopyWith<$Res> {
  __$$SuggestedActionImplCopyWithImpl(
    _$SuggestedActionImpl _value,
    $Res Function(_$SuggestedActionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SuggestedAction
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? label = null,
    Object? payload = freezed,
  }) {
    return _then(
      _$SuggestedActionImpl(
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as String,
        label: null == label
            ? _value.label
            : label // ignore: cast_nullable_to_non_nullable
                  as String,
        payload: freezed == payload
            ? _value._payload
            : payload // ignore: cast_nullable_to_non_nullable
                  as Map<String, dynamic>?,
      ),
    );
  }
}

/// @nodoc

class _$SuggestedActionImpl implements _SuggestedAction {
  const _$SuggestedActionImpl({
    required this.type,
    required this.label,
    final Map<String, dynamic>? payload,
  }) : _payload = payload;

  @override
  final String type;
  @override
  final String label;
  final Map<String, dynamic>? _payload;
  @override
  Map<String, dynamic>? get payload {
    final value = _payload;
    if (value == null) return null;
    if (_payload is EqualUnmodifiableMapView) return _payload;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'SuggestedAction(type: $type, label: $label, payload: $payload)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SuggestedActionImpl &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.label, label) || other.label == label) &&
            const DeepCollectionEquality().equals(other._payload, _payload));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    type,
    label,
    const DeepCollectionEquality().hash(_payload),
  );

  /// Create a copy of SuggestedAction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SuggestedActionImplCopyWith<_$SuggestedActionImpl> get copyWith =>
      __$$SuggestedActionImplCopyWithImpl<_$SuggestedActionImpl>(
        this,
        _$identity,
      );
}

abstract class _SuggestedAction implements SuggestedAction {
  const factory _SuggestedAction({
    required final String type,
    required final String label,
    final Map<String, dynamic>? payload,
  }) = _$SuggestedActionImpl;

  @override
  String get type;
  @override
  String get label;
  @override
  Map<String, dynamic>? get payload;

  /// Create a copy of SuggestedAction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SuggestedActionImplCopyWith<_$SuggestedActionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SendMessageResponse {
  String get reply => throw _privateConstructorUsedError;
  double? get confidence => throw _privateConstructorUsedError;
  bool get disclaimerIncluded => throw _privateConstructorUsedError;
  List<String>? get followUpQuestions => throw _privateConstructorUsedError;
  List<SuggestedAction>? get suggestedActions =>
      throw _privateConstructorUsedError;
  String? get messageId => throw _privateConstructorUsedError;
  String? get threadId => throw _privateConstructorUsedError;
  ChatMessage? get userMessage => throw _privateConstructorUsedError;
  ChatMessage? get assistantMessage => throw _privateConstructorUsedError;
  String? get disclaimer => throw _privateConstructorUsedError;

  /// Create a copy of SendMessageResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SendMessageResponseCopyWith<SendMessageResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SendMessageResponseCopyWith<$Res> {
  factory $SendMessageResponseCopyWith(
    SendMessageResponse value,
    $Res Function(SendMessageResponse) then,
  ) = _$SendMessageResponseCopyWithImpl<$Res, SendMessageResponse>;
  @useResult
  $Res call({
    String reply,
    double? confidence,
    bool disclaimerIncluded,
    List<String>? followUpQuestions,
    List<SuggestedAction>? suggestedActions,
    String? messageId,
    String? threadId,
    ChatMessage? userMessage,
    ChatMessage? assistantMessage,
    String? disclaimer,
  });

  $ChatMessageCopyWith<$Res>? get userMessage;
  $ChatMessageCopyWith<$Res>? get assistantMessage;
}

/// @nodoc
class _$SendMessageResponseCopyWithImpl<$Res, $Val extends SendMessageResponse>
    implements $SendMessageResponseCopyWith<$Res> {
  _$SendMessageResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SendMessageResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reply = null,
    Object? confidence = freezed,
    Object? disclaimerIncluded = null,
    Object? followUpQuestions = freezed,
    Object? suggestedActions = freezed,
    Object? messageId = freezed,
    Object? threadId = freezed,
    Object? userMessage = freezed,
    Object? assistantMessage = freezed,
    Object? disclaimer = freezed,
  }) {
    return _then(
      _value.copyWith(
            reply: null == reply
                ? _value.reply
                : reply // ignore: cast_nullable_to_non_nullable
                      as String,
            confidence: freezed == confidence
                ? _value.confidence
                : confidence // ignore: cast_nullable_to_non_nullable
                      as double?,
            disclaimerIncluded: null == disclaimerIncluded
                ? _value.disclaimerIncluded
                : disclaimerIncluded // ignore: cast_nullable_to_non_nullable
                      as bool,
            followUpQuestions: freezed == followUpQuestions
                ? _value.followUpQuestions
                : followUpQuestions // ignore: cast_nullable_to_non_nullable
                      as List<String>?,
            suggestedActions: freezed == suggestedActions
                ? _value.suggestedActions
                : suggestedActions // ignore: cast_nullable_to_non_nullable
                      as List<SuggestedAction>?,
            messageId: freezed == messageId
                ? _value.messageId
                : messageId // ignore: cast_nullable_to_non_nullable
                      as String?,
            threadId: freezed == threadId
                ? _value.threadId
                : threadId // ignore: cast_nullable_to_non_nullable
                      as String?,
            userMessage: freezed == userMessage
                ? _value.userMessage
                : userMessage // ignore: cast_nullable_to_non_nullable
                      as ChatMessage?,
            assistantMessage: freezed == assistantMessage
                ? _value.assistantMessage
                : assistantMessage // ignore: cast_nullable_to_non_nullable
                      as ChatMessage?,
            disclaimer: freezed == disclaimer
                ? _value.disclaimer
                : disclaimer // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }

  /// Create a copy of SendMessageResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ChatMessageCopyWith<$Res>? get userMessage {
    if (_value.userMessage == null) {
      return null;
    }

    return $ChatMessageCopyWith<$Res>(_value.userMessage!, (value) {
      return _then(_value.copyWith(userMessage: value) as $Val);
    });
  }

  /// Create a copy of SendMessageResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ChatMessageCopyWith<$Res>? get assistantMessage {
    if (_value.assistantMessage == null) {
      return null;
    }

    return $ChatMessageCopyWith<$Res>(_value.assistantMessage!, (value) {
      return _then(_value.copyWith(assistantMessage: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$SendMessageResponseImplCopyWith<$Res>
    implements $SendMessageResponseCopyWith<$Res> {
  factory _$$SendMessageResponseImplCopyWith(
    _$SendMessageResponseImpl value,
    $Res Function(_$SendMessageResponseImpl) then,
  ) = __$$SendMessageResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String reply,
    double? confidence,
    bool disclaimerIncluded,
    List<String>? followUpQuestions,
    List<SuggestedAction>? suggestedActions,
    String? messageId,
    String? threadId,
    ChatMessage? userMessage,
    ChatMessage? assistantMessage,
    String? disclaimer,
  });

  @override
  $ChatMessageCopyWith<$Res>? get userMessage;
  @override
  $ChatMessageCopyWith<$Res>? get assistantMessage;
}

/// @nodoc
class __$$SendMessageResponseImplCopyWithImpl<$Res>
    extends _$SendMessageResponseCopyWithImpl<$Res, _$SendMessageResponseImpl>
    implements _$$SendMessageResponseImplCopyWith<$Res> {
  __$$SendMessageResponseImplCopyWithImpl(
    _$SendMessageResponseImpl _value,
    $Res Function(_$SendMessageResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SendMessageResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reply = null,
    Object? confidence = freezed,
    Object? disclaimerIncluded = null,
    Object? followUpQuestions = freezed,
    Object? suggestedActions = freezed,
    Object? messageId = freezed,
    Object? threadId = freezed,
    Object? userMessage = freezed,
    Object? assistantMessage = freezed,
    Object? disclaimer = freezed,
  }) {
    return _then(
      _$SendMessageResponseImpl(
        reply: null == reply
            ? _value.reply
            : reply // ignore: cast_nullable_to_non_nullable
                  as String,
        confidence: freezed == confidence
            ? _value.confidence
            : confidence // ignore: cast_nullable_to_non_nullable
                  as double?,
        disclaimerIncluded: null == disclaimerIncluded
            ? _value.disclaimerIncluded
            : disclaimerIncluded // ignore: cast_nullable_to_non_nullable
                  as bool,
        followUpQuestions: freezed == followUpQuestions
            ? _value._followUpQuestions
            : followUpQuestions // ignore: cast_nullable_to_non_nullable
                  as List<String>?,
        suggestedActions: freezed == suggestedActions
            ? _value._suggestedActions
            : suggestedActions // ignore: cast_nullable_to_non_nullable
                  as List<SuggestedAction>?,
        messageId: freezed == messageId
            ? _value.messageId
            : messageId // ignore: cast_nullable_to_non_nullable
                  as String?,
        threadId: freezed == threadId
            ? _value.threadId
            : threadId // ignore: cast_nullable_to_non_nullable
                  as String?,
        userMessage: freezed == userMessage
            ? _value.userMessage
            : userMessage // ignore: cast_nullable_to_non_nullable
                  as ChatMessage?,
        assistantMessage: freezed == assistantMessage
            ? _value.assistantMessage
            : assistantMessage // ignore: cast_nullable_to_non_nullable
                  as ChatMessage?,
        disclaimer: freezed == disclaimer
            ? _value.disclaimer
            : disclaimer // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$SendMessageResponseImpl implements _SendMessageResponse {
  const _$SendMessageResponseImpl({
    required this.reply,
    this.confidence,
    this.disclaimerIncluded = false,
    final List<String>? followUpQuestions,
    final List<SuggestedAction>? suggestedActions,
    this.messageId,
    this.threadId,
    this.userMessage,
    this.assistantMessage,
    this.disclaimer,
  }) : _followUpQuestions = followUpQuestions,
       _suggestedActions = suggestedActions;

  @override
  final String reply;
  @override
  final double? confidence;
  @override
  @JsonKey()
  final bool disclaimerIncluded;
  final List<String>? _followUpQuestions;
  @override
  List<String>? get followUpQuestions {
    final value = _followUpQuestions;
    if (value == null) return null;
    if (_followUpQuestions is EqualUnmodifiableListView)
      return _followUpQuestions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  final List<SuggestedAction>? _suggestedActions;
  @override
  List<SuggestedAction>? get suggestedActions {
    final value = _suggestedActions;
    if (value == null) return null;
    if (_suggestedActions is EqualUnmodifiableListView)
      return _suggestedActions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  final String? messageId;
  @override
  final String? threadId;
  @override
  final ChatMessage? userMessage;
  @override
  final ChatMessage? assistantMessage;
  @override
  final String? disclaimer;

  @override
  String toString() {
    return 'SendMessageResponse(reply: $reply, confidence: $confidence, disclaimerIncluded: $disclaimerIncluded, followUpQuestions: $followUpQuestions, suggestedActions: $suggestedActions, messageId: $messageId, threadId: $threadId, userMessage: $userMessage, assistantMessage: $assistantMessage, disclaimer: $disclaimer)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SendMessageResponseImpl &&
            (identical(other.reply, reply) || other.reply == reply) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence) &&
            (identical(other.disclaimerIncluded, disclaimerIncluded) ||
                other.disclaimerIncluded == disclaimerIncluded) &&
            const DeepCollectionEquality().equals(
              other._followUpQuestions,
              _followUpQuestions,
            ) &&
            const DeepCollectionEquality().equals(
              other._suggestedActions,
              _suggestedActions,
            ) &&
            (identical(other.messageId, messageId) ||
                other.messageId == messageId) &&
            (identical(other.threadId, threadId) ||
                other.threadId == threadId) &&
            (identical(other.userMessage, userMessage) ||
                other.userMessage == userMessage) &&
            (identical(other.assistantMessage, assistantMessage) ||
                other.assistantMessage == assistantMessage) &&
            (identical(other.disclaimer, disclaimer) ||
                other.disclaimer == disclaimer));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    reply,
    confidence,
    disclaimerIncluded,
    const DeepCollectionEquality().hash(_followUpQuestions),
    const DeepCollectionEquality().hash(_suggestedActions),
    messageId,
    threadId,
    userMessage,
    assistantMessage,
    disclaimer,
  );

  /// Create a copy of SendMessageResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SendMessageResponseImplCopyWith<_$SendMessageResponseImpl> get copyWith =>
      __$$SendMessageResponseImplCopyWithImpl<_$SendMessageResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _SendMessageResponse implements SendMessageResponse {
  const factory _SendMessageResponse({
    required final String reply,
    final double? confidence,
    final bool disclaimerIncluded,
    final List<String>? followUpQuestions,
    final List<SuggestedAction>? suggestedActions,
    final String? messageId,
    final String? threadId,
    final ChatMessage? userMessage,
    final ChatMessage? assistantMessage,
    final String? disclaimer,
  }) = _$SendMessageResponseImpl;

  @override
  String get reply;
  @override
  double? get confidence;
  @override
  bool get disclaimerIncluded;
  @override
  List<String>? get followUpQuestions;
  @override
  List<SuggestedAction>? get suggestedActions;
  @override
  String? get messageId;
  @override
  String? get threadId;
  @override
  ChatMessage? get userMessage;
  @override
  ChatMessage? get assistantMessage;
  @override
  String? get disclaimer;

  /// Create a copy of SendMessageResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SendMessageResponseImplCopyWith<_$SendMessageResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SendMessageRequest {
  String get content => throw _privateConstructorUsedError;

  /// Create a copy of SendMessageRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SendMessageRequestCopyWith<SendMessageRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SendMessageRequestCopyWith<$Res> {
  factory $SendMessageRequestCopyWith(
    SendMessageRequest value,
    $Res Function(SendMessageRequest) then,
  ) = _$SendMessageRequestCopyWithImpl<$Res, SendMessageRequest>;
  @useResult
  $Res call({String content});
}

/// @nodoc
class _$SendMessageRequestCopyWithImpl<$Res, $Val extends SendMessageRequest>
    implements $SendMessageRequestCopyWith<$Res> {
  _$SendMessageRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SendMessageRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? content = null}) {
    return _then(
      _value.copyWith(
            content: null == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SendMessageRequestImplCopyWith<$Res>
    implements $SendMessageRequestCopyWith<$Res> {
  factory _$$SendMessageRequestImplCopyWith(
    _$SendMessageRequestImpl value,
    $Res Function(_$SendMessageRequestImpl) then,
  ) = __$$SendMessageRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String content});
}

/// @nodoc
class __$$SendMessageRequestImplCopyWithImpl<$Res>
    extends _$SendMessageRequestCopyWithImpl<$Res, _$SendMessageRequestImpl>
    implements _$$SendMessageRequestImplCopyWith<$Res> {
  __$$SendMessageRequestImplCopyWithImpl(
    _$SendMessageRequestImpl _value,
    $Res Function(_$SendMessageRequestImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SendMessageRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? content = null}) {
    return _then(
      _$SendMessageRequestImpl(
        content: null == content
            ? _value.content
            : content // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$SendMessageRequestImpl extends _SendMessageRequest {
  const _$SendMessageRequestImpl({required this.content}) : super._();

  @override
  final String content;

  @override
  String toString() {
    return 'SendMessageRequest(content: $content)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SendMessageRequestImpl &&
            (identical(other.content, content) || other.content == content));
  }

  @override
  int get hashCode => Object.hash(runtimeType, content);

  /// Create a copy of SendMessageRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SendMessageRequestImplCopyWith<_$SendMessageRequestImpl> get copyWith =>
      __$$SendMessageRequestImplCopyWithImpl<_$SendMessageRequestImpl>(
        this,
        _$identity,
      );
}

abstract class _SendMessageRequest extends SendMessageRequest {
  const factory _SendMessageRequest({required final String content}) =
      _$SendMessageRequestImpl;
  const _SendMessageRequest._() : super._();

  @override
  String get content;

  /// Create a copy of SendMessageRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SendMessageRequestImplCopyWith<_$SendMessageRequestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$MessagesListResponse {
  List<ChatMessage> get messages => throw _privateConstructorUsedError;
  int? get totalCount => throw _privateConstructorUsedError;
  bool get hasMore => throw _privateConstructorUsedError;

  /// Create a copy of MessagesListResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MessagesListResponseCopyWith<MessagesListResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MessagesListResponseCopyWith<$Res> {
  factory $MessagesListResponseCopyWith(
    MessagesListResponse value,
    $Res Function(MessagesListResponse) then,
  ) = _$MessagesListResponseCopyWithImpl<$Res, MessagesListResponse>;
  @useResult
  $Res call({List<ChatMessage> messages, int? totalCount, bool hasMore});
}

/// @nodoc
class _$MessagesListResponseCopyWithImpl<
  $Res,
  $Val extends MessagesListResponse
>
    implements $MessagesListResponseCopyWith<$Res> {
  _$MessagesListResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MessagesListResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? messages = null,
    Object? totalCount = freezed,
    Object? hasMore = null,
  }) {
    return _then(
      _value.copyWith(
            messages: null == messages
                ? _value.messages
                : messages // ignore: cast_nullable_to_non_nullable
                      as List<ChatMessage>,
            totalCount: freezed == totalCount
                ? _value.totalCount
                : totalCount // ignore: cast_nullable_to_non_nullable
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
abstract class _$$MessagesListResponseImplCopyWith<$Res>
    implements $MessagesListResponseCopyWith<$Res> {
  factory _$$MessagesListResponseImplCopyWith(
    _$MessagesListResponseImpl value,
    $Res Function(_$MessagesListResponseImpl) then,
  ) = __$$MessagesListResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<ChatMessage> messages, int? totalCount, bool hasMore});
}

/// @nodoc
class __$$MessagesListResponseImplCopyWithImpl<$Res>
    extends _$MessagesListResponseCopyWithImpl<$Res, _$MessagesListResponseImpl>
    implements _$$MessagesListResponseImplCopyWith<$Res> {
  __$$MessagesListResponseImplCopyWithImpl(
    _$MessagesListResponseImpl _value,
    $Res Function(_$MessagesListResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MessagesListResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? messages = null,
    Object? totalCount = freezed,
    Object? hasMore = null,
  }) {
    return _then(
      _$MessagesListResponseImpl(
        messages: null == messages
            ? _value._messages
            : messages // ignore: cast_nullable_to_non_nullable
                  as List<ChatMessage>,
        totalCount: freezed == totalCount
            ? _value.totalCount
            : totalCount // ignore: cast_nullable_to_non_nullable
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

class _$MessagesListResponseImpl implements _MessagesListResponse {
  const _$MessagesListResponseImpl({
    final List<ChatMessage> messages = const [],
    this.totalCount,
    this.hasMore = false,
  }) : _messages = messages;

  final List<ChatMessage> _messages;
  @override
  @JsonKey()
  List<ChatMessage> get messages {
    if (_messages is EqualUnmodifiableListView) return _messages;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_messages);
  }

  @override
  final int? totalCount;
  @override
  @JsonKey()
  final bool hasMore;

  @override
  String toString() {
    return 'MessagesListResponse(messages: $messages, totalCount: $totalCount, hasMore: $hasMore)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MessagesListResponseImpl &&
            const DeepCollectionEquality().equals(other._messages, _messages) &&
            (identical(other.totalCount, totalCount) ||
                other.totalCount == totalCount) &&
            (identical(other.hasMore, hasMore) || other.hasMore == hasMore));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_messages),
    totalCount,
    hasMore,
  );

  /// Create a copy of MessagesListResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MessagesListResponseImplCopyWith<_$MessagesListResponseImpl>
  get copyWith =>
      __$$MessagesListResponseImplCopyWithImpl<_$MessagesListResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _MessagesListResponse implements MessagesListResponse {
  const factory _MessagesListResponse({
    final List<ChatMessage> messages,
    final int? totalCount,
    final bool hasMore,
  }) = _$MessagesListResponseImpl;

  @override
  List<ChatMessage> get messages;
  @override
  int? get totalCount;
  @override
  bool get hasMore;

  /// Create a copy of MessagesListResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MessagesListResponseImplCopyWith<_$MessagesListResponseImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ThreadsListResponse {
  List<ChatThread> get threads => throw _privateConstructorUsedError;
  int? get totalCount => throw _privateConstructorUsedError;
  bool get hasMore => throw _privateConstructorUsedError;
  int? get total => throw _privateConstructorUsedError;

  /// Create a copy of ThreadsListResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ThreadsListResponseCopyWith<ThreadsListResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ThreadsListResponseCopyWith<$Res> {
  factory $ThreadsListResponseCopyWith(
    ThreadsListResponse value,
    $Res Function(ThreadsListResponse) then,
  ) = _$ThreadsListResponseCopyWithImpl<$Res, ThreadsListResponse>;
  @useResult
  $Res call({
    List<ChatThread> threads,
    int? totalCount,
    bool hasMore,
    int? total,
  });
}

/// @nodoc
class _$ThreadsListResponseCopyWithImpl<$Res, $Val extends ThreadsListResponse>
    implements $ThreadsListResponseCopyWith<$Res> {
  _$ThreadsListResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ThreadsListResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? threads = null,
    Object? totalCount = freezed,
    Object? hasMore = null,
    Object? total = freezed,
  }) {
    return _then(
      _value.copyWith(
            threads: null == threads
                ? _value.threads
                : threads // ignore: cast_nullable_to_non_nullable
                      as List<ChatThread>,
            totalCount: freezed == totalCount
                ? _value.totalCount
                : totalCount // ignore: cast_nullable_to_non_nullable
                      as int?,
            hasMore: null == hasMore
                ? _value.hasMore
                : hasMore // ignore: cast_nullable_to_non_nullable
                      as bool,
            total: freezed == total
                ? _value.total
                : total // ignore: cast_nullable_to_non_nullable
                      as int?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ThreadsListResponseImplCopyWith<$Res>
    implements $ThreadsListResponseCopyWith<$Res> {
  factory _$$ThreadsListResponseImplCopyWith(
    _$ThreadsListResponseImpl value,
    $Res Function(_$ThreadsListResponseImpl) then,
  ) = __$$ThreadsListResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    List<ChatThread> threads,
    int? totalCount,
    bool hasMore,
    int? total,
  });
}

/// @nodoc
class __$$ThreadsListResponseImplCopyWithImpl<$Res>
    extends _$ThreadsListResponseCopyWithImpl<$Res, _$ThreadsListResponseImpl>
    implements _$$ThreadsListResponseImplCopyWith<$Res> {
  __$$ThreadsListResponseImplCopyWithImpl(
    _$ThreadsListResponseImpl _value,
    $Res Function(_$ThreadsListResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ThreadsListResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? threads = null,
    Object? totalCount = freezed,
    Object? hasMore = null,
    Object? total = freezed,
  }) {
    return _then(
      _$ThreadsListResponseImpl(
        threads: null == threads
            ? _value._threads
            : threads // ignore: cast_nullable_to_non_nullable
                  as List<ChatThread>,
        totalCount: freezed == totalCount
            ? _value.totalCount
            : totalCount // ignore: cast_nullable_to_non_nullable
                  as int?,
        hasMore: null == hasMore
            ? _value.hasMore
            : hasMore // ignore: cast_nullable_to_non_nullable
                  as bool,
        total: freezed == total
            ? _value.total
            : total // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc

class _$ThreadsListResponseImpl implements _ThreadsListResponse {
  const _$ThreadsListResponseImpl({
    final List<ChatThread> threads = const [],
    this.totalCount,
    this.hasMore = false,
    this.total,
  }) : _threads = threads;

  final List<ChatThread> _threads;
  @override
  @JsonKey()
  List<ChatThread> get threads {
    if (_threads is EqualUnmodifiableListView) return _threads;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_threads);
  }

  @override
  final int? totalCount;
  @override
  @JsonKey()
  final bool hasMore;
  @override
  final int? total;

  @override
  String toString() {
    return 'ThreadsListResponse(threads: $threads, totalCount: $totalCount, hasMore: $hasMore, total: $total)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ThreadsListResponseImpl &&
            const DeepCollectionEquality().equals(other._threads, _threads) &&
            (identical(other.totalCount, totalCount) ||
                other.totalCount == totalCount) &&
            (identical(other.hasMore, hasMore) || other.hasMore == hasMore) &&
            (identical(other.total, total) || other.total == total));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_threads),
    totalCount,
    hasMore,
    total,
  );

  /// Create a copy of ThreadsListResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ThreadsListResponseImplCopyWith<_$ThreadsListResponseImpl> get copyWith =>
      __$$ThreadsListResponseImplCopyWithImpl<_$ThreadsListResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _ThreadsListResponse implements ThreadsListResponse {
  const factory _ThreadsListResponse({
    final List<ChatThread> threads,
    final int? totalCount,
    final bool hasMore,
    final int? total,
  }) = _$ThreadsListResponseImpl;

  @override
  List<ChatThread> get threads;
  @override
  int? get totalCount;
  @override
  bool get hasMore;
  @override
  int? get total;

  /// Create a copy of ThreadsListResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ThreadsListResponseImplCopyWith<_$ThreadsListResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
