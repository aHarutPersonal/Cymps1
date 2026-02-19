// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'idol_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$IdolCandidate {
  /// Source type: "local" (from DB) or "web" (from LLM/Wikidata)
  String get source => throw _privateConstructorUsedError;

  /// For local suggestions: the idol's UUID in database
  String? get id => throw _privateConstructorUsedError;

  /// For web suggestions: provider name (e.g., "wikidata", "llm")
  String get provider => throw _privateConstructorUsedError;

  /// For web suggestions: external ID from provider (e.g., "Q317521", "llm:ray_dalio")
  String get externalId => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  DateTime? get birthDate => throw _privateConstructorUsedError;
  String? get wikipediaUrl => throw _privateConstructorUsedError;
  List<String> get occupations => throw _privateConstructorUsedError;

  /// For local suggestions: relevance score (0-1)
  double? get relevanceScore => throw _privateConstructorUsedError;

  /// For web suggestions: confidence score (0-1)
  double? get confidence => throw _privateConstructorUsedError;

  /// Domain/category (for local suggestions)
  String? get domain => throw _privateConstructorUsedError;

  /// Aliases list (for local suggestions)
  List<IdolAlias> get aliases => throw _privateConstructorUsedError;

  /// Tags list (for local suggestions)
  List<IdolTag> get tags => throw _privateConstructorUsedError;
  String? get avatarThumbUrl => throw _privateConstructorUsedError;

  /// Create a copy of IdolCandidate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IdolCandidateCopyWith<IdolCandidate> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IdolCandidateCopyWith<$Res> {
  factory $IdolCandidateCopyWith(
    IdolCandidate value,
    $Res Function(IdolCandidate) then,
  ) = _$IdolCandidateCopyWithImpl<$Res, IdolCandidate>;
  @useResult
  $Res call({
    String source,
    String? id,
    String provider,
    String externalId,
    String name,
    String? description,
    DateTime? birthDate,
    String? wikipediaUrl,
    List<String> occupations,
    double? relevanceScore,
    double? confidence,
    String? domain,
    List<IdolAlias> aliases,
    List<IdolTag> tags,
    String? avatarThumbUrl,
  });
}

/// @nodoc
class _$IdolCandidateCopyWithImpl<$Res, $Val extends IdolCandidate>
    implements $IdolCandidateCopyWith<$Res> {
  _$IdolCandidateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IdolCandidate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? source = null,
    Object? id = freezed,
    Object? provider = null,
    Object? externalId = null,
    Object? name = null,
    Object? description = freezed,
    Object? birthDate = freezed,
    Object? wikipediaUrl = freezed,
    Object? occupations = null,
    Object? relevanceScore = freezed,
    Object? confidence = freezed,
    Object? domain = freezed,
    Object? aliases = null,
    Object? tags = null,
    Object? avatarThumbUrl = freezed,
  }) {
    return _then(
      _value.copyWith(
            source: null == source
                ? _value.source
                : source // ignore: cast_nullable_to_non_nullable
                      as String,
            id: freezed == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String?,
            provider: null == provider
                ? _value.provider
                : provider // ignore: cast_nullable_to_non_nullable
                      as String,
            externalId: null == externalId
                ? _value.externalId
                : externalId // ignore: cast_nullable_to_non_nullable
                      as String,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            description: freezed == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String?,
            birthDate: freezed == birthDate
                ? _value.birthDate
                : birthDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            wikipediaUrl: freezed == wikipediaUrl
                ? _value.wikipediaUrl
                : wikipediaUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            occupations: null == occupations
                ? _value.occupations
                : occupations // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            relevanceScore: freezed == relevanceScore
                ? _value.relevanceScore
                : relevanceScore // ignore: cast_nullable_to_non_nullable
                      as double?,
            confidence: freezed == confidence
                ? _value.confidence
                : confidence // ignore: cast_nullable_to_non_nullable
                      as double?,
            domain: freezed == domain
                ? _value.domain
                : domain // ignore: cast_nullable_to_non_nullable
                      as String?,
            aliases: null == aliases
                ? _value.aliases
                : aliases // ignore: cast_nullable_to_non_nullable
                      as List<IdolAlias>,
            tags: null == tags
                ? _value.tags
                : tags // ignore: cast_nullable_to_non_nullable
                      as List<IdolTag>,
            avatarThumbUrl: freezed == avatarThumbUrl
                ? _value.avatarThumbUrl
                : avatarThumbUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$IdolCandidateImplCopyWith<$Res>
    implements $IdolCandidateCopyWith<$Res> {
  factory _$$IdolCandidateImplCopyWith(
    _$IdolCandidateImpl value,
    $Res Function(_$IdolCandidateImpl) then,
  ) = __$$IdolCandidateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String source,
    String? id,
    String provider,
    String externalId,
    String name,
    String? description,
    DateTime? birthDate,
    String? wikipediaUrl,
    List<String> occupations,
    double? relevanceScore,
    double? confidence,
    String? domain,
    List<IdolAlias> aliases,
    List<IdolTag> tags,
    String? avatarThumbUrl,
  });
}

/// @nodoc
class __$$IdolCandidateImplCopyWithImpl<$Res>
    extends _$IdolCandidateCopyWithImpl<$Res, _$IdolCandidateImpl>
    implements _$$IdolCandidateImplCopyWith<$Res> {
  __$$IdolCandidateImplCopyWithImpl(
    _$IdolCandidateImpl _value,
    $Res Function(_$IdolCandidateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IdolCandidate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? source = null,
    Object? id = freezed,
    Object? provider = null,
    Object? externalId = null,
    Object? name = null,
    Object? description = freezed,
    Object? birthDate = freezed,
    Object? wikipediaUrl = freezed,
    Object? occupations = null,
    Object? relevanceScore = freezed,
    Object? confidence = freezed,
    Object? domain = freezed,
    Object? aliases = null,
    Object? tags = null,
    Object? avatarThumbUrl = freezed,
  }) {
    return _then(
      _$IdolCandidateImpl(
        source: null == source
            ? _value.source
            : source // ignore: cast_nullable_to_non_nullable
                  as String,
        id: freezed == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String?,
        provider: null == provider
            ? _value.provider
            : provider // ignore: cast_nullable_to_non_nullable
                  as String,
        externalId: null == externalId
            ? _value.externalId
            : externalId // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        description: freezed == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String?,
        birthDate: freezed == birthDate
            ? _value.birthDate
            : birthDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        wikipediaUrl: freezed == wikipediaUrl
            ? _value.wikipediaUrl
            : wikipediaUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        occupations: null == occupations
            ? _value._occupations
            : occupations // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        relevanceScore: freezed == relevanceScore
            ? _value.relevanceScore
            : relevanceScore // ignore: cast_nullable_to_non_nullable
                  as double?,
        confidence: freezed == confidence
            ? _value.confidence
            : confidence // ignore: cast_nullable_to_non_nullable
                  as double?,
        domain: freezed == domain
            ? _value.domain
            : domain // ignore: cast_nullable_to_non_nullable
                  as String?,
        aliases: null == aliases
            ? _value._aliases
            : aliases // ignore: cast_nullable_to_non_nullable
                  as List<IdolAlias>,
        tags: null == tags
            ? _value._tags
            : tags // ignore: cast_nullable_to_non_nullable
                  as List<IdolTag>,
        avatarThumbUrl: freezed == avatarThumbUrl
            ? _value.avatarThumbUrl
            : avatarThumbUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$IdolCandidateImpl extends _IdolCandidate {
  const _$IdolCandidateImpl({
    this.source = 'web',
    this.id,
    this.provider = '',
    this.externalId = '',
    this.name = 'Unknown',
    this.description,
    this.birthDate,
    this.wikipediaUrl,
    final List<String> occupations = const [],
    this.relevanceScore,
    this.confidence,
    this.domain,
    final List<IdolAlias> aliases = const [],
    final List<IdolTag> tags = const [],
    this.avatarThumbUrl,
  }) : _occupations = occupations,
       _aliases = aliases,
       _tags = tags,
       super._();

  /// Source type: "local" (from DB) or "web" (from LLM/Wikidata)
  @override
  @JsonKey()
  final String source;

  /// For local suggestions: the idol's UUID in database
  @override
  final String? id;

  /// For web suggestions: provider name (e.g., "wikidata", "llm")
  @override
  @JsonKey()
  final String provider;

  /// For web suggestions: external ID from provider (e.g., "Q317521", "llm:ray_dalio")
  @override
  @JsonKey()
  final String externalId;
  @override
  @JsonKey()
  final String name;
  @override
  final String? description;
  @override
  final DateTime? birthDate;
  @override
  final String? wikipediaUrl;
  final List<String> _occupations;
  @override
  @JsonKey()
  List<String> get occupations {
    if (_occupations is EqualUnmodifiableListView) return _occupations;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_occupations);
  }

  /// For local suggestions: relevance score (0-1)
  @override
  final double? relevanceScore;

  /// For web suggestions: confidence score (0-1)
  @override
  final double? confidence;

  /// Domain/category (for local suggestions)
  @override
  final String? domain;

  /// Aliases list (for local suggestions)
  final List<IdolAlias> _aliases;

  /// Aliases list (for local suggestions)
  @override
  @JsonKey()
  List<IdolAlias> get aliases {
    if (_aliases is EqualUnmodifiableListView) return _aliases;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_aliases);
  }

  /// Tags list (for local suggestions)
  final List<IdolTag> _tags;

  /// Tags list (for local suggestions)
  @override
  @JsonKey()
  List<IdolTag> get tags {
    if (_tags is EqualUnmodifiableListView) return _tags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tags);
  }

  @override
  final String? avatarThumbUrl;

  @override
  String toString() {
    return 'IdolCandidate(source: $source, id: $id, provider: $provider, externalId: $externalId, name: $name, description: $description, birthDate: $birthDate, wikipediaUrl: $wikipediaUrl, occupations: $occupations, relevanceScore: $relevanceScore, confidence: $confidence, domain: $domain, aliases: $aliases, tags: $tags, avatarThumbUrl: $avatarThumbUrl)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IdolCandidateImpl &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.provider, provider) ||
                other.provider == provider) &&
            (identical(other.externalId, externalId) ||
                other.externalId == externalId) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.birthDate, birthDate) ||
                other.birthDate == birthDate) &&
            (identical(other.wikipediaUrl, wikipediaUrl) ||
                other.wikipediaUrl == wikipediaUrl) &&
            const DeepCollectionEquality().equals(
              other._occupations,
              _occupations,
            ) &&
            (identical(other.relevanceScore, relevanceScore) ||
                other.relevanceScore == relevanceScore) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence) &&
            (identical(other.domain, domain) || other.domain == domain) &&
            const DeepCollectionEquality().equals(other._aliases, _aliases) &&
            const DeepCollectionEquality().equals(other._tags, _tags) &&
            (identical(other.avatarThumbUrl, avatarThumbUrl) ||
                other.avatarThumbUrl == avatarThumbUrl));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    source,
    id,
    provider,
    externalId,
    name,
    description,
    birthDate,
    wikipediaUrl,
    const DeepCollectionEquality().hash(_occupations),
    relevanceScore,
    confidence,
    domain,
    const DeepCollectionEquality().hash(_aliases),
    const DeepCollectionEquality().hash(_tags),
    avatarThumbUrl,
  );

  /// Create a copy of IdolCandidate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IdolCandidateImplCopyWith<_$IdolCandidateImpl> get copyWith =>
      __$$IdolCandidateImplCopyWithImpl<_$IdolCandidateImpl>(this, _$identity);
}

abstract class _IdolCandidate extends IdolCandidate {
  const factory _IdolCandidate({
    final String source,
    final String? id,
    final String provider,
    final String externalId,
    final String name,
    final String? description,
    final DateTime? birthDate,
    final String? wikipediaUrl,
    final List<String> occupations,
    final double? relevanceScore,
    final double? confidence,
    final String? domain,
    final List<IdolAlias> aliases,
    final List<IdolTag> tags,
    final String? avatarThumbUrl,
  }) = _$IdolCandidateImpl;
  const _IdolCandidate._() : super._();

  /// Source type: "local" (from DB) or "web" (from LLM/Wikidata)
  @override
  String get source;

  /// For local suggestions: the idol's UUID in database
  @override
  String? get id;

  /// For web suggestions: provider name (e.g., "wikidata", "llm")
  @override
  String get provider;

  /// For web suggestions: external ID from provider (e.g., "Q317521", "llm:ray_dalio")
  @override
  String get externalId;
  @override
  String get name;
  @override
  String? get description;
  @override
  DateTime? get birthDate;
  @override
  String? get wikipediaUrl;
  @override
  List<String> get occupations;

  /// For local suggestions: relevance score (0-1)
  @override
  double? get relevanceScore;

  /// For web suggestions: confidence score (0-1)
  @override
  double? get confidence;

  /// Domain/category (for local suggestions)
  @override
  String? get domain;

  /// Aliases list (for local suggestions)
  @override
  List<IdolAlias> get aliases;

  /// Tags list (for local suggestions)
  @override
  List<IdolTag> get tags;
  @override
  String? get avatarThumbUrl;

  /// Create a copy of IdolCandidate
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IdolCandidateImplCopyWith<_$IdolCandidateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$IdolAlias {
  String? get id => throw _privateConstructorUsedError;
  String? get aliasText => throw _privateConstructorUsedError;

  /// Create a copy of IdolAlias
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IdolAliasCopyWith<IdolAlias> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IdolAliasCopyWith<$Res> {
  factory $IdolAliasCopyWith(IdolAlias value, $Res Function(IdolAlias) then) =
      _$IdolAliasCopyWithImpl<$Res, IdolAlias>;
  @useResult
  $Res call({String? id, String? aliasText});
}

/// @nodoc
class _$IdolAliasCopyWithImpl<$Res, $Val extends IdolAlias>
    implements $IdolAliasCopyWith<$Res> {
  _$IdolAliasCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IdolAlias
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? id = freezed, Object? aliasText = freezed}) {
    return _then(
      _value.copyWith(
            id: freezed == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String?,
            aliasText: freezed == aliasText
                ? _value.aliasText
                : aliasText // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$IdolAliasImplCopyWith<$Res>
    implements $IdolAliasCopyWith<$Res> {
  factory _$$IdolAliasImplCopyWith(
    _$IdolAliasImpl value,
    $Res Function(_$IdolAliasImpl) then,
  ) = __$$IdolAliasImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? id, String? aliasText});
}

/// @nodoc
class __$$IdolAliasImplCopyWithImpl<$Res>
    extends _$IdolAliasCopyWithImpl<$Res, _$IdolAliasImpl>
    implements _$$IdolAliasImplCopyWith<$Res> {
  __$$IdolAliasImplCopyWithImpl(
    _$IdolAliasImpl _value,
    $Res Function(_$IdolAliasImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IdolAlias
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? id = freezed, Object? aliasText = freezed}) {
    return _then(
      _$IdolAliasImpl(
        id: freezed == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String?,
        aliasText: freezed == aliasText
            ? _value.aliasText
            : aliasText // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$IdolAliasImpl implements _IdolAlias {
  const _$IdolAliasImpl({this.id, this.aliasText});

  @override
  final String? id;
  @override
  final String? aliasText;

  @override
  String toString() {
    return 'IdolAlias(id: $id, aliasText: $aliasText)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IdolAliasImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.aliasText, aliasText) ||
                other.aliasText == aliasText));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, aliasText);

  /// Create a copy of IdolAlias
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IdolAliasImplCopyWith<_$IdolAliasImpl> get copyWith =>
      __$$IdolAliasImplCopyWithImpl<_$IdolAliasImpl>(this, _$identity);
}

abstract class _IdolAlias implements IdolAlias {
  const factory _IdolAlias({final String? id, final String? aliasText}) =
      _$IdolAliasImpl;

  @override
  String? get id;
  @override
  String? get aliasText;

  /// Create a copy of IdolAlias
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IdolAliasImplCopyWith<_$IdolAliasImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$IdolTag {
  String? get id => throw _privateConstructorUsedError;
  String? get name => throw _privateConstructorUsedError;
  String? get type => throw _privateConstructorUsedError;

  /// Create a copy of IdolTag
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IdolTagCopyWith<IdolTag> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IdolTagCopyWith<$Res> {
  factory $IdolTagCopyWith(IdolTag value, $Res Function(IdolTag) then) =
      _$IdolTagCopyWithImpl<$Res, IdolTag>;
  @useResult
  $Res call({String? id, String? name, String? type});
}

/// @nodoc
class _$IdolTagCopyWithImpl<$Res, $Val extends IdolTag>
    implements $IdolTagCopyWith<$Res> {
  _$IdolTagCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IdolTag
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? name = freezed,
    Object? type = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: freezed == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String?,
            name: freezed == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String?,
            type: freezed == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$IdolTagImplCopyWith<$Res> implements $IdolTagCopyWith<$Res> {
  factory _$$IdolTagImplCopyWith(
    _$IdolTagImpl value,
    $Res Function(_$IdolTagImpl) then,
  ) = __$$IdolTagImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? id, String? name, String? type});
}

/// @nodoc
class __$$IdolTagImplCopyWithImpl<$Res>
    extends _$IdolTagCopyWithImpl<$Res, _$IdolTagImpl>
    implements _$$IdolTagImplCopyWith<$Res> {
  __$$IdolTagImplCopyWithImpl(
    _$IdolTagImpl _value,
    $Res Function(_$IdolTagImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IdolTag
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? name = freezed,
    Object? type = freezed,
  }) {
    return _then(
      _$IdolTagImpl(
        id: freezed == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String?,
        name: freezed == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String?,
        type: freezed == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$IdolTagImpl implements _IdolTag {
  const _$IdolTagImpl({this.id, this.name, this.type});

  @override
  final String? id;
  @override
  final String? name;
  @override
  final String? type;

  @override
  String toString() {
    return 'IdolTag(id: $id, name: $name, type: $type)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IdolTagImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.type, type) || other.type == type));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, name, type);

  /// Create a copy of IdolTag
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IdolTagImplCopyWith<_$IdolTagImpl> get copyWith =>
      __$$IdolTagImplCopyWithImpl<_$IdolTagImpl>(this, _$identity);
}

abstract class _IdolTag implements IdolTag {
  const factory _IdolTag({
    final String? id,
    final String? name,
    final String? type,
  }) = _$IdolTagImpl;

  @override
  String? get id;
  @override
  String? get name;
  @override
  String? get type;

  /// Create a copy of IdolTag
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IdolTagImplCopyWith<_$IdolTagImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$DiscoverResponse {
  String get query => throw _privateConstructorUsedError;
  List<IdolCandidate> get candidates => throw _privateConstructorUsedError;

  /// Create a copy of DiscoverResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DiscoverResponseCopyWith<DiscoverResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DiscoverResponseCopyWith<$Res> {
  factory $DiscoverResponseCopyWith(
    DiscoverResponse value,
    $Res Function(DiscoverResponse) then,
  ) = _$DiscoverResponseCopyWithImpl<$Res, DiscoverResponse>;
  @useResult
  $Res call({String query, List<IdolCandidate> candidates});
}

/// @nodoc
class _$DiscoverResponseCopyWithImpl<$Res, $Val extends DiscoverResponse>
    implements $DiscoverResponseCopyWith<$Res> {
  _$DiscoverResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DiscoverResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? query = null, Object? candidates = null}) {
    return _then(
      _value.copyWith(
            query: null == query
                ? _value.query
                : query // ignore: cast_nullable_to_non_nullable
                      as String,
            candidates: null == candidates
                ? _value.candidates
                : candidates // ignore: cast_nullable_to_non_nullable
                      as List<IdolCandidate>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$DiscoverResponseImplCopyWith<$Res>
    implements $DiscoverResponseCopyWith<$Res> {
  factory _$$DiscoverResponseImplCopyWith(
    _$DiscoverResponseImpl value,
    $Res Function(_$DiscoverResponseImpl) then,
  ) = __$$DiscoverResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String query, List<IdolCandidate> candidates});
}

/// @nodoc
class __$$DiscoverResponseImplCopyWithImpl<$Res>
    extends _$DiscoverResponseCopyWithImpl<$Res, _$DiscoverResponseImpl>
    implements _$$DiscoverResponseImplCopyWith<$Res> {
  __$$DiscoverResponseImplCopyWithImpl(
    _$DiscoverResponseImpl _value,
    $Res Function(_$DiscoverResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of DiscoverResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? query = null, Object? candidates = null}) {
    return _then(
      _$DiscoverResponseImpl(
        query: null == query
            ? _value.query
            : query // ignore: cast_nullable_to_non_nullable
                  as String,
        candidates: null == candidates
            ? _value._candidates
            : candidates // ignore: cast_nullable_to_non_nullable
                  as List<IdolCandidate>,
      ),
    );
  }
}

/// @nodoc

class _$DiscoverResponseImpl implements _DiscoverResponse {
  const _$DiscoverResponseImpl({
    required this.query,
    required final List<IdolCandidate> candidates,
  }) : _candidates = candidates;

  @override
  final String query;
  final List<IdolCandidate> _candidates;
  @override
  List<IdolCandidate> get candidates {
    if (_candidates is EqualUnmodifiableListView) return _candidates;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_candidates);
  }

  @override
  String toString() {
    return 'DiscoverResponse(query: $query, candidates: $candidates)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DiscoverResponseImpl &&
            (identical(other.query, query) || other.query == query) &&
            const DeepCollectionEquality().equals(
              other._candidates,
              _candidates,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    query,
    const DeepCollectionEquality().hash(_candidates),
  );

  /// Create a copy of DiscoverResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DiscoverResponseImplCopyWith<_$DiscoverResponseImpl> get copyWith =>
      __$$DiscoverResponseImplCopyWithImpl<_$DiscoverResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _DiscoverResponse implements DiscoverResponse {
  const factory _DiscoverResponse({
    required final String query,
    required final List<IdolCandidate> candidates,
  }) = _$DiscoverResponseImpl;

  @override
  String get query;
  @override
  List<IdolCandidate> get candidates;

  /// Create a copy of DiscoverResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DiscoverResponseImplCopyWith<_$DiscoverResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SourceMix {
  int get local => throw _privateConstructorUsedError;
  int get web => throw _privateConstructorUsedError;
  int get total => throw _privateConstructorUsedError;

  /// Create a copy of SourceMix
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SourceMixCopyWith<SourceMix> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SourceMixCopyWith<$Res> {
  factory $SourceMixCopyWith(SourceMix value, $Res Function(SourceMix) then) =
      _$SourceMixCopyWithImpl<$Res, SourceMix>;
  @useResult
  $Res call({int local, int web, int total});
}

/// @nodoc
class _$SourceMixCopyWithImpl<$Res, $Val extends SourceMix>
    implements $SourceMixCopyWith<$Res> {
  _$SourceMixCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SourceMix
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? local = null, Object? web = null, Object? total = null}) {
    return _then(
      _value.copyWith(
            local: null == local
                ? _value.local
                : local // ignore: cast_nullable_to_non_nullable
                      as int,
            web: null == web
                ? _value.web
                : web // ignore: cast_nullable_to_non_nullable
                      as int,
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
abstract class _$$SourceMixImplCopyWith<$Res>
    implements $SourceMixCopyWith<$Res> {
  factory _$$SourceMixImplCopyWith(
    _$SourceMixImpl value,
    $Res Function(_$SourceMixImpl) then,
  ) = __$$SourceMixImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int local, int web, int total});
}

/// @nodoc
class __$$SourceMixImplCopyWithImpl<$Res>
    extends _$SourceMixCopyWithImpl<$Res, _$SourceMixImpl>
    implements _$$SourceMixImplCopyWith<$Res> {
  __$$SourceMixImplCopyWithImpl(
    _$SourceMixImpl _value,
    $Res Function(_$SourceMixImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SourceMix
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? local = null, Object? web = null, Object? total = null}) {
    return _then(
      _$SourceMixImpl(
        local: null == local
            ? _value.local
            : local // ignore: cast_nullable_to_non_nullable
                  as int,
        web: null == web
            ? _value.web
            : web // ignore: cast_nullable_to_non_nullable
                  as int,
        total: null == total
            ? _value.total
            : total // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc

class _$SourceMixImpl implements _SourceMix {
  const _$SourceMixImpl({this.local = 0, this.web = 0, this.total = 0});

  @override
  @JsonKey()
  final int local;
  @override
  @JsonKey()
  final int web;
  @override
  @JsonKey()
  final int total;

  @override
  String toString() {
    return 'SourceMix(local: $local, web: $web, total: $total)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SourceMixImpl &&
            (identical(other.local, local) || other.local == local) &&
            (identical(other.web, web) || other.web == web) &&
            (identical(other.total, total) || other.total == total));
  }

  @override
  int get hashCode => Object.hash(runtimeType, local, web, total);

  /// Create a copy of SourceMix
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SourceMixImplCopyWith<_$SourceMixImpl> get copyWith =>
      __$$SourceMixImplCopyWithImpl<_$SourceMixImpl>(this, _$identity);
}

abstract class _SourceMix implements SourceMix {
  const factory _SourceMix({final int local, final int web, final int total}) =
      _$SourceMixImpl;

  @override
  int get local;
  @override
  int get web;
  @override
  int get total;

  /// Create a copy of SourceMix
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SourceMixImplCopyWith<_$SourceMixImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SuggestResponse {
  List<String> get interests => throw _privateConstructorUsedError;
  SourceMix? get sourceMix => throw _privateConstructorUsedError;
  List<IdolCandidate> get candidates => throw _privateConstructorUsedError;

  /// Create a copy of SuggestResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SuggestResponseCopyWith<SuggestResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SuggestResponseCopyWith<$Res> {
  factory $SuggestResponseCopyWith(
    SuggestResponse value,
    $Res Function(SuggestResponse) then,
  ) = _$SuggestResponseCopyWithImpl<$Res, SuggestResponse>;
  @useResult
  $Res call({
    List<String> interests,
    SourceMix? sourceMix,
    List<IdolCandidate> candidates,
  });

  $SourceMixCopyWith<$Res>? get sourceMix;
}

/// @nodoc
class _$SuggestResponseCopyWithImpl<$Res, $Val extends SuggestResponse>
    implements $SuggestResponseCopyWith<$Res> {
  _$SuggestResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SuggestResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? interests = null,
    Object? sourceMix = freezed,
    Object? candidates = null,
  }) {
    return _then(
      _value.copyWith(
            interests: null == interests
                ? _value.interests
                : interests // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            sourceMix: freezed == sourceMix
                ? _value.sourceMix
                : sourceMix // ignore: cast_nullable_to_non_nullable
                      as SourceMix?,
            candidates: null == candidates
                ? _value.candidates
                : candidates // ignore: cast_nullable_to_non_nullable
                      as List<IdolCandidate>,
          )
          as $Val,
    );
  }

  /// Create a copy of SuggestResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SourceMixCopyWith<$Res>? get sourceMix {
    if (_value.sourceMix == null) {
      return null;
    }

    return $SourceMixCopyWith<$Res>(_value.sourceMix!, (value) {
      return _then(_value.copyWith(sourceMix: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$SuggestResponseImplCopyWith<$Res>
    implements $SuggestResponseCopyWith<$Res> {
  factory _$$SuggestResponseImplCopyWith(
    _$SuggestResponseImpl value,
    $Res Function(_$SuggestResponseImpl) then,
  ) = __$$SuggestResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    List<String> interests,
    SourceMix? sourceMix,
    List<IdolCandidate> candidates,
  });

  @override
  $SourceMixCopyWith<$Res>? get sourceMix;
}

/// @nodoc
class __$$SuggestResponseImplCopyWithImpl<$Res>
    extends _$SuggestResponseCopyWithImpl<$Res, _$SuggestResponseImpl>
    implements _$$SuggestResponseImplCopyWith<$Res> {
  __$$SuggestResponseImplCopyWithImpl(
    _$SuggestResponseImpl _value,
    $Res Function(_$SuggestResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SuggestResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? interests = null,
    Object? sourceMix = freezed,
    Object? candidates = null,
  }) {
    return _then(
      _$SuggestResponseImpl(
        interests: null == interests
            ? _value._interests
            : interests // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        sourceMix: freezed == sourceMix
            ? _value.sourceMix
            : sourceMix // ignore: cast_nullable_to_non_nullable
                  as SourceMix?,
        candidates: null == candidates
            ? _value._candidates
            : candidates // ignore: cast_nullable_to_non_nullable
                  as List<IdolCandidate>,
      ),
    );
  }
}

/// @nodoc

class _$SuggestResponseImpl extends _SuggestResponse {
  const _$SuggestResponseImpl({
    final List<String> interests = const [],
    this.sourceMix,
    final List<IdolCandidate> candidates = const [],
  }) : _interests = interests,
       _candidates = candidates,
       super._();

  final List<String> _interests;
  @override
  @JsonKey()
  List<String> get interests {
    if (_interests is EqualUnmodifiableListView) return _interests;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_interests);
  }

  @override
  final SourceMix? sourceMix;
  final List<IdolCandidate> _candidates;
  @override
  @JsonKey()
  List<IdolCandidate> get candidates {
    if (_candidates is EqualUnmodifiableListView) return _candidates;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_candidates);
  }

  @override
  String toString() {
    return 'SuggestResponse(interests: $interests, sourceMix: $sourceMix, candidates: $candidates)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SuggestResponseImpl &&
            const DeepCollectionEquality().equals(
              other._interests,
              _interests,
            ) &&
            (identical(other.sourceMix, sourceMix) ||
                other.sourceMix == sourceMix) &&
            const DeepCollectionEquality().equals(
              other._candidates,
              _candidates,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_interests),
    sourceMix,
    const DeepCollectionEquality().hash(_candidates),
  );

  /// Create a copy of SuggestResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SuggestResponseImplCopyWith<_$SuggestResponseImpl> get copyWith =>
      __$$SuggestResponseImplCopyWithImpl<_$SuggestResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _SuggestResponse extends SuggestResponse {
  const factory _SuggestResponse({
    final List<String> interests,
    final SourceMix? sourceMix,
    final List<IdolCandidate> candidates,
  }) = _$SuggestResponseImpl;
  const _SuggestResponse._() : super._();

  @override
  List<String> get interests;
  @override
  SourceMix? get sourceMix;
  @override
  List<IdolCandidate> get candidates;

  /// Create a copy of SuggestResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SuggestResponseImplCopyWith<_$SuggestResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ImportRequest {
  String get provider => throw _privateConstructorUsedError;
  String get externalId => throw _privateConstructorUsedError;

  /// Required for LLM imports
  String? get name => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;

  /// Date string in YYYY-MM-DD format
  String? get birthDate => throw _privateConstructorUsedError;
  String? get wikipediaUrl => throw _privateConstructorUsedError;

  /// List of occupations/roles
  List<String>? get occupations => throw _privateConstructorUsedError;

  /// Create a copy of ImportRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ImportRequestCopyWith<ImportRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ImportRequestCopyWith<$Res> {
  factory $ImportRequestCopyWith(
    ImportRequest value,
    $Res Function(ImportRequest) then,
  ) = _$ImportRequestCopyWithImpl<$Res, ImportRequest>;
  @useResult
  $Res call({
    String provider,
    String externalId,
    String? name,
    String? description,
    String? birthDate,
    String? wikipediaUrl,
    List<String>? occupations,
  });
}

/// @nodoc
class _$ImportRequestCopyWithImpl<$Res, $Val extends ImportRequest>
    implements $ImportRequestCopyWith<$Res> {
  _$ImportRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ImportRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? provider = null,
    Object? externalId = null,
    Object? name = freezed,
    Object? description = freezed,
    Object? birthDate = freezed,
    Object? wikipediaUrl = freezed,
    Object? occupations = freezed,
  }) {
    return _then(
      _value.copyWith(
            provider: null == provider
                ? _value.provider
                : provider // ignore: cast_nullable_to_non_nullable
                      as String,
            externalId: null == externalId
                ? _value.externalId
                : externalId // ignore: cast_nullable_to_non_nullable
                      as String,
            name: freezed == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String?,
            description: freezed == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String?,
            birthDate: freezed == birthDate
                ? _value.birthDate
                : birthDate // ignore: cast_nullable_to_non_nullable
                      as String?,
            wikipediaUrl: freezed == wikipediaUrl
                ? _value.wikipediaUrl
                : wikipediaUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            occupations: freezed == occupations
                ? _value.occupations
                : occupations // ignore: cast_nullable_to_non_nullable
                      as List<String>?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ImportRequestImplCopyWith<$Res>
    implements $ImportRequestCopyWith<$Res> {
  factory _$$ImportRequestImplCopyWith(
    _$ImportRequestImpl value,
    $Res Function(_$ImportRequestImpl) then,
  ) = __$$ImportRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String provider,
    String externalId,
    String? name,
    String? description,
    String? birthDate,
    String? wikipediaUrl,
    List<String>? occupations,
  });
}

/// @nodoc
class __$$ImportRequestImplCopyWithImpl<$Res>
    extends _$ImportRequestCopyWithImpl<$Res, _$ImportRequestImpl>
    implements _$$ImportRequestImplCopyWith<$Res> {
  __$$ImportRequestImplCopyWithImpl(
    _$ImportRequestImpl _value,
    $Res Function(_$ImportRequestImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ImportRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? provider = null,
    Object? externalId = null,
    Object? name = freezed,
    Object? description = freezed,
    Object? birthDate = freezed,
    Object? wikipediaUrl = freezed,
    Object? occupations = freezed,
  }) {
    return _then(
      _$ImportRequestImpl(
        provider: null == provider
            ? _value.provider
            : provider // ignore: cast_nullable_to_non_nullable
                  as String,
        externalId: null == externalId
            ? _value.externalId
            : externalId // ignore: cast_nullable_to_non_nullable
                  as String,
        name: freezed == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String?,
        description: freezed == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String?,
        birthDate: freezed == birthDate
            ? _value.birthDate
            : birthDate // ignore: cast_nullable_to_non_nullable
                  as String?,
        wikipediaUrl: freezed == wikipediaUrl
            ? _value.wikipediaUrl
            : wikipediaUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        occupations: freezed == occupations
            ? _value._occupations
            : occupations // ignore: cast_nullable_to_non_nullable
                  as List<String>?,
      ),
    );
  }
}

/// @nodoc

class _$ImportRequestImpl extends _ImportRequest {
  const _$ImportRequestImpl({
    required this.provider,
    required this.externalId,
    this.name,
    this.description,
    this.birthDate,
    this.wikipediaUrl,
    final List<String>? occupations,
  }) : _occupations = occupations,
       super._();

  @override
  final String provider;
  @override
  final String externalId;

  /// Required for LLM imports
  @override
  final String? name;
  @override
  final String? description;

  /// Date string in YYYY-MM-DD format
  @override
  final String? birthDate;
  @override
  final String? wikipediaUrl;

  /// List of occupations/roles
  final List<String>? _occupations;

  /// List of occupations/roles
  @override
  List<String>? get occupations {
    final value = _occupations;
    if (value == null) return null;
    if (_occupations is EqualUnmodifiableListView) return _occupations;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  String toString() {
    return 'ImportRequest(provider: $provider, externalId: $externalId, name: $name, description: $description, birthDate: $birthDate, wikipediaUrl: $wikipediaUrl, occupations: $occupations)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ImportRequestImpl &&
            (identical(other.provider, provider) ||
                other.provider == provider) &&
            (identical(other.externalId, externalId) ||
                other.externalId == externalId) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.birthDate, birthDate) ||
                other.birthDate == birthDate) &&
            (identical(other.wikipediaUrl, wikipediaUrl) ||
                other.wikipediaUrl == wikipediaUrl) &&
            const DeepCollectionEquality().equals(
              other._occupations,
              _occupations,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    provider,
    externalId,
    name,
    description,
    birthDate,
    wikipediaUrl,
    const DeepCollectionEquality().hash(_occupations),
  );

  /// Create a copy of ImportRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ImportRequestImplCopyWith<_$ImportRequestImpl> get copyWith =>
      __$$ImportRequestImplCopyWithImpl<_$ImportRequestImpl>(this, _$identity);
}

abstract class _ImportRequest extends ImportRequest {
  const factory _ImportRequest({
    required final String provider,
    required final String externalId,
    final String? name,
    final String? description,
    final String? birthDate,
    final String? wikipediaUrl,
    final List<String>? occupations,
  }) = _$ImportRequestImpl;
  const _ImportRequest._() : super._();

  @override
  String get provider;
  @override
  String get externalId;

  /// Required for LLM imports
  @override
  String? get name;
  @override
  String? get description;

  /// Date string in YYYY-MM-DD format
  @override
  String? get birthDate;
  @override
  String? get wikipediaUrl;

  /// List of occupations/roles
  @override
  List<String>? get occupations;

  /// Create a copy of ImportRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ImportRequestImplCopyWith<_$ImportRequestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ImportResponse {
  String? get idolId => throw _privateConstructorUsedError;
  String? get jobId => throw _privateConstructorUsedError;
  String? get status => throw _privateConstructorUsedError;
  String? get detail => throw _privateConstructorUsedError;

  /// Create a copy of ImportResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ImportResponseCopyWith<ImportResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ImportResponseCopyWith<$Res> {
  factory $ImportResponseCopyWith(
    ImportResponse value,
    $Res Function(ImportResponse) then,
  ) = _$ImportResponseCopyWithImpl<$Res, ImportResponse>;
  @useResult
  $Res call({String? idolId, String? jobId, String? status, String? detail});
}

/// @nodoc
class _$ImportResponseCopyWithImpl<$Res, $Val extends ImportResponse>
    implements $ImportResponseCopyWith<$Res> {
  _$ImportResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ImportResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? idolId = freezed,
    Object? jobId = freezed,
    Object? status = freezed,
    Object? detail = freezed,
  }) {
    return _then(
      _value.copyWith(
            idolId: freezed == idolId
                ? _value.idolId
                : idolId // ignore: cast_nullable_to_non_nullable
                      as String?,
            jobId: freezed == jobId
                ? _value.jobId
                : jobId // ignore: cast_nullable_to_non_nullable
                      as String?,
            status: freezed == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String?,
            detail: freezed == detail
                ? _value.detail
                : detail // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ImportResponseImplCopyWith<$Res>
    implements $ImportResponseCopyWith<$Res> {
  factory _$$ImportResponseImplCopyWith(
    _$ImportResponseImpl value,
    $Res Function(_$ImportResponseImpl) then,
  ) = __$$ImportResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? idolId, String? jobId, String? status, String? detail});
}

/// @nodoc
class __$$ImportResponseImplCopyWithImpl<$Res>
    extends _$ImportResponseCopyWithImpl<$Res, _$ImportResponseImpl>
    implements _$$ImportResponseImplCopyWith<$Res> {
  __$$ImportResponseImplCopyWithImpl(
    _$ImportResponseImpl _value,
    $Res Function(_$ImportResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ImportResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? idolId = freezed,
    Object? jobId = freezed,
    Object? status = freezed,
    Object? detail = freezed,
  }) {
    return _then(
      _$ImportResponseImpl(
        idolId: freezed == idolId
            ? _value.idolId
            : idolId // ignore: cast_nullable_to_non_nullable
                  as String?,
        jobId: freezed == jobId
            ? _value.jobId
            : jobId // ignore: cast_nullable_to_non_nullable
                  as String?,
        status: freezed == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String?,
        detail: freezed == detail
            ? _value.detail
            : detail // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$ImportResponseImpl implements _ImportResponse {
  const _$ImportResponseImpl({
    this.idolId,
    this.jobId,
    this.status,
    this.detail,
  });

  @override
  final String? idolId;
  @override
  final String? jobId;
  @override
  final String? status;
  @override
  final String? detail;

  @override
  String toString() {
    return 'ImportResponse(idolId: $idolId, jobId: $jobId, status: $status, detail: $detail)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ImportResponseImpl &&
            (identical(other.idolId, idolId) || other.idolId == idolId) &&
            (identical(other.jobId, jobId) || other.jobId == jobId) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.detail, detail) || other.detail == detail));
  }

  @override
  int get hashCode => Object.hash(runtimeType, idolId, jobId, status, detail);

  /// Create a copy of ImportResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ImportResponseImplCopyWith<_$ImportResponseImpl> get copyWith =>
      __$$ImportResponseImplCopyWithImpl<_$ImportResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _ImportResponse implements ImportResponse {
  const factory _ImportResponse({
    final String? idolId,
    final String? jobId,
    final String? status,
    final String? detail,
  }) = _$ImportResponseImpl;

  @override
  String? get idolId;
  @override
  String? get jobId;
  @override
  String? get status;
  @override
  String? get detail;

  /// Create a copy of ImportResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ImportResponseImplCopyWith<_$ImportResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$IdolProfile {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  DateTime? get birthDate => throw _privateConstructorUsedError;
  DateTime? get deathDate => throw _privateConstructorUsedError;
  String? get wikipediaUrl => throw _privateConstructorUsedError;
  List<String> get occupations => throw _privateConstructorUsedError;
  String? get avatarUrl => throw _privateConstructorUsedError;
  String? get avatarThumbUrl => throw _privateConstructorUsedError;
  List<String>? get knownFor => throw _privateConstructorUsedError;
  String? get nationality => throw _privateConstructorUsedError;
  String? get birthPlace => throw _privateConstructorUsedError;
  String? get summary => throw _privateConstructorUsedError;
  String? get timelineStatus => throw _privateConstructorUsedError;
  double? get timelineCompleteness => throw _privateConstructorUsedError;
  DateTime? get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  /// Create a copy of IdolProfile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IdolProfileCopyWith<IdolProfile> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IdolProfileCopyWith<$Res> {
  factory $IdolProfileCopyWith(
    IdolProfile value,
    $Res Function(IdolProfile) then,
  ) = _$IdolProfileCopyWithImpl<$Res, IdolProfile>;
  @useResult
  $Res call({
    String id,
    String name,
    String? description,
    DateTime? birthDate,
    DateTime? deathDate,
    String? wikipediaUrl,
    List<String> occupations,
    String? avatarUrl,
    String? avatarThumbUrl,
    List<String>? knownFor,
    String? nationality,
    String? birthPlace,
    String? summary,
    String? timelineStatus,
    double? timelineCompleteness,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
}

/// @nodoc
class _$IdolProfileCopyWithImpl<$Res, $Val extends IdolProfile>
    implements $IdolProfileCopyWith<$Res> {
  _$IdolProfileCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IdolProfile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? birthDate = freezed,
    Object? deathDate = freezed,
    Object? wikipediaUrl = freezed,
    Object? occupations = null,
    Object? avatarUrl = freezed,
    Object? avatarThumbUrl = freezed,
    Object? knownFor = freezed,
    Object? nationality = freezed,
    Object? birthPlace = freezed,
    Object? summary = freezed,
    Object? timelineStatus = freezed,
    Object? timelineCompleteness = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
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
            description: freezed == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String?,
            birthDate: freezed == birthDate
                ? _value.birthDate
                : birthDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            deathDate: freezed == deathDate
                ? _value.deathDate
                : deathDate // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            wikipediaUrl: freezed == wikipediaUrl
                ? _value.wikipediaUrl
                : wikipediaUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            occupations: null == occupations
                ? _value.occupations
                : occupations // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            avatarUrl: freezed == avatarUrl
                ? _value.avatarUrl
                : avatarUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            avatarThumbUrl: freezed == avatarThumbUrl
                ? _value.avatarThumbUrl
                : avatarThumbUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            knownFor: freezed == knownFor
                ? _value.knownFor
                : knownFor // ignore: cast_nullable_to_non_nullable
                      as List<String>?,
            nationality: freezed == nationality
                ? _value.nationality
                : nationality // ignore: cast_nullable_to_non_nullable
                      as String?,
            birthPlace: freezed == birthPlace
                ? _value.birthPlace
                : birthPlace // ignore: cast_nullable_to_non_nullable
                      as String?,
            summary: freezed == summary
                ? _value.summary
                : summary // ignore: cast_nullable_to_non_nullable
                      as String?,
            timelineStatus: freezed == timelineStatus
                ? _value.timelineStatus
                : timelineStatus // ignore: cast_nullable_to_non_nullable
                      as String?,
            timelineCompleteness: freezed == timelineCompleteness
                ? _value.timelineCompleteness
                : timelineCompleteness // ignore: cast_nullable_to_non_nullable
                      as double?,
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
abstract class _$$IdolProfileImplCopyWith<$Res>
    implements $IdolProfileCopyWith<$Res> {
  factory _$$IdolProfileImplCopyWith(
    _$IdolProfileImpl value,
    $Res Function(_$IdolProfileImpl) then,
  ) = __$$IdolProfileImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    String? description,
    DateTime? birthDate,
    DateTime? deathDate,
    String? wikipediaUrl,
    List<String> occupations,
    String? avatarUrl,
    String? avatarThumbUrl,
    List<String>? knownFor,
    String? nationality,
    String? birthPlace,
    String? summary,
    String? timelineStatus,
    double? timelineCompleteness,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
}

/// @nodoc
class __$$IdolProfileImplCopyWithImpl<$Res>
    extends _$IdolProfileCopyWithImpl<$Res, _$IdolProfileImpl>
    implements _$$IdolProfileImplCopyWith<$Res> {
  __$$IdolProfileImplCopyWithImpl(
    _$IdolProfileImpl _value,
    $Res Function(_$IdolProfileImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IdolProfile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? birthDate = freezed,
    Object? deathDate = freezed,
    Object? wikipediaUrl = freezed,
    Object? occupations = null,
    Object? avatarUrl = freezed,
    Object? avatarThumbUrl = freezed,
    Object? knownFor = freezed,
    Object? nationality = freezed,
    Object? birthPlace = freezed,
    Object? summary = freezed,
    Object? timelineStatus = freezed,
    Object? timelineCompleteness = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(
      _$IdolProfileImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        description: freezed == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String?,
        birthDate: freezed == birthDate
            ? _value.birthDate
            : birthDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        deathDate: freezed == deathDate
            ? _value.deathDate
            : deathDate // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        wikipediaUrl: freezed == wikipediaUrl
            ? _value.wikipediaUrl
            : wikipediaUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        occupations: null == occupations
            ? _value._occupations
            : occupations // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        avatarUrl: freezed == avatarUrl
            ? _value.avatarUrl
            : avatarUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        avatarThumbUrl: freezed == avatarThumbUrl
            ? _value.avatarThumbUrl
            : avatarThumbUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        knownFor: freezed == knownFor
            ? _value._knownFor
            : knownFor // ignore: cast_nullable_to_non_nullable
                  as List<String>?,
        nationality: freezed == nationality
            ? _value.nationality
            : nationality // ignore: cast_nullable_to_non_nullable
                  as String?,
        birthPlace: freezed == birthPlace
            ? _value.birthPlace
            : birthPlace // ignore: cast_nullable_to_non_nullable
                  as String?,
        summary: freezed == summary
            ? _value.summary
            : summary // ignore: cast_nullable_to_non_nullable
                  as String?,
        timelineStatus: freezed == timelineStatus
            ? _value.timelineStatus
            : timelineStatus // ignore: cast_nullable_to_non_nullable
                  as String?,
        timelineCompleteness: freezed == timelineCompleteness
            ? _value.timelineCompleteness
            : timelineCompleteness // ignore: cast_nullable_to_non_nullable
                  as double?,
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

class _$IdolProfileImpl implements _IdolProfile {
  const _$IdolProfileImpl({
    required this.id,
    required this.name,
    this.description,
    this.birthDate,
    this.deathDate,
    this.wikipediaUrl,
    final List<String> occupations = const [],
    this.avatarUrl,
    this.avatarThumbUrl,
    final List<String>? knownFor,
    this.nationality,
    this.birthPlace,
    this.summary,
    this.timelineStatus,
    this.timelineCompleteness,
    this.createdAt,
    this.updatedAt,
  }) : _occupations = occupations,
       _knownFor = knownFor;

  @override
  final String id;
  @override
  final String name;
  @override
  final String? description;
  @override
  final DateTime? birthDate;
  @override
  final DateTime? deathDate;
  @override
  final String? wikipediaUrl;
  final List<String> _occupations;
  @override
  @JsonKey()
  List<String> get occupations {
    if (_occupations is EqualUnmodifiableListView) return _occupations;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_occupations);
  }

  @override
  final String? avatarUrl;
  @override
  final String? avatarThumbUrl;
  final List<String>? _knownFor;
  @override
  List<String>? get knownFor {
    final value = _knownFor;
    if (value == null) return null;
    if (_knownFor is EqualUnmodifiableListView) return _knownFor;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  final String? nationality;
  @override
  final String? birthPlace;
  @override
  final String? summary;
  @override
  final String? timelineStatus;
  @override
  final double? timelineCompleteness;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;

  @override
  String toString() {
    return 'IdolProfile(id: $id, name: $name, description: $description, birthDate: $birthDate, deathDate: $deathDate, wikipediaUrl: $wikipediaUrl, occupations: $occupations, avatarUrl: $avatarUrl, avatarThumbUrl: $avatarThumbUrl, knownFor: $knownFor, nationality: $nationality, birthPlace: $birthPlace, summary: $summary, timelineStatus: $timelineStatus, timelineCompleteness: $timelineCompleteness, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IdolProfileImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.birthDate, birthDate) ||
                other.birthDate == birthDate) &&
            (identical(other.deathDate, deathDate) ||
                other.deathDate == deathDate) &&
            (identical(other.wikipediaUrl, wikipediaUrl) ||
                other.wikipediaUrl == wikipediaUrl) &&
            const DeepCollectionEquality().equals(
              other._occupations,
              _occupations,
            ) &&
            (identical(other.avatarUrl, avatarUrl) ||
                other.avatarUrl == avatarUrl) &&
            (identical(other.avatarThumbUrl, avatarThumbUrl) ||
                other.avatarThumbUrl == avatarThumbUrl) &&
            const DeepCollectionEquality().equals(other._knownFor, _knownFor) &&
            (identical(other.nationality, nationality) ||
                other.nationality == nationality) &&
            (identical(other.birthPlace, birthPlace) ||
                other.birthPlace == birthPlace) &&
            (identical(other.summary, summary) || other.summary == summary) &&
            (identical(other.timelineStatus, timelineStatus) ||
                other.timelineStatus == timelineStatus) &&
            (identical(other.timelineCompleteness, timelineCompleteness) ||
                other.timelineCompleteness == timelineCompleteness) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    name,
    description,
    birthDate,
    deathDate,
    wikipediaUrl,
    const DeepCollectionEquality().hash(_occupations),
    avatarUrl,
    avatarThumbUrl,
    const DeepCollectionEquality().hash(_knownFor),
    nationality,
    birthPlace,
    summary,
    timelineStatus,
    timelineCompleteness,
    createdAt,
    updatedAt,
  );

  /// Create a copy of IdolProfile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IdolProfileImplCopyWith<_$IdolProfileImpl> get copyWith =>
      __$$IdolProfileImplCopyWithImpl<_$IdolProfileImpl>(this, _$identity);
}

abstract class _IdolProfile implements IdolProfile {
  const factory _IdolProfile({
    required final String id,
    required final String name,
    final String? description,
    final DateTime? birthDate,
    final DateTime? deathDate,
    final String? wikipediaUrl,
    final List<String> occupations,
    final String? avatarUrl,
    final String? avatarThumbUrl,
    final List<String>? knownFor,
    final String? nationality,
    final String? birthPlace,
    final String? summary,
    final String? timelineStatus,
    final double? timelineCompleteness,
    final DateTime? createdAt,
    final DateTime? updatedAt,
  }) = _$IdolProfileImpl;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get description;
  @override
  DateTime? get birthDate;
  @override
  DateTime? get deathDate;
  @override
  String? get wikipediaUrl;
  @override
  List<String> get occupations;
  @override
  String? get avatarUrl;
  @override
  String? get avatarThumbUrl;
  @override
  List<String>? get knownFor;
  @override
  String? get nationality;
  @override
  String? get birthPlace;
  @override
  String? get summary;
  @override
  String? get timelineStatus;
  @override
  double? get timelineCompleteness;
  @override
  DateTime? get createdAt;
  @override
  DateTime? get updatedAt;

  /// Create a copy of IdolProfile
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IdolProfileImplCopyWith<_$IdolProfileImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
