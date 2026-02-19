// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'intake_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$IntakeValidation {
  int? get minLength => throw _privateConstructorUsedError;
  int? get maxLength => throw _privateConstructorUsedError;
  int? get min => throw _privateConstructorUsedError;
  int? get max => throw _privateConstructorUsedError;
  String? get pattern => throw _privateConstructorUsedError;
  String? get errorMessage => throw _privateConstructorUsedError;

  /// Create a copy of IntakeValidation
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IntakeValidationCopyWith<IntakeValidation> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IntakeValidationCopyWith<$Res> {
  factory $IntakeValidationCopyWith(
    IntakeValidation value,
    $Res Function(IntakeValidation) then,
  ) = _$IntakeValidationCopyWithImpl<$Res, IntakeValidation>;
  @useResult
  $Res call({
    int? minLength,
    int? maxLength,
    int? min,
    int? max,
    String? pattern,
    String? errorMessage,
  });
}

/// @nodoc
class _$IntakeValidationCopyWithImpl<$Res, $Val extends IntakeValidation>
    implements $IntakeValidationCopyWith<$Res> {
  _$IntakeValidationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IntakeValidation
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? minLength = freezed,
    Object? maxLength = freezed,
    Object? min = freezed,
    Object? max = freezed,
    Object? pattern = freezed,
    Object? errorMessage = freezed,
  }) {
    return _then(
      _value.copyWith(
            minLength: freezed == minLength
                ? _value.minLength
                : minLength // ignore: cast_nullable_to_non_nullable
                      as int?,
            maxLength: freezed == maxLength
                ? _value.maxLength
                : maxLength // ignore: cast_nullable_to_non_nullable
                      as int?,
            min: freezed == min
                ? _value.min
                : min // ignore: cast_nullable_to_non_nullable
                      as int?,
            max: freezed == max
                ? _value.max
                : max // ignore: cast_nullable_to_non_nullable
                      as int?,
            pattern: freezed == pattern
                ? _value.pattern
                : pattern // ignore: cast_nullable_to_non_nullable
                      as String?,
            errorMessage: freezed == errorMessage
                ? _value.errorMessage
                : errorMessage // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$IntakeValidationImplCopyWith<$Res>
    implements $IntakeValidationCopyWith<$Res> {
  factory _$$IntakeValidationImplCopyWith(
    _$IntakeValidationImpl value,
    $Res Function(_$IntakeValidationImpl) then,
  ) = __$$IntakeValidationImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int? minLength,
    int? maxLength,
    int? min,
    int? max,
    String? pattern,
    String? errorMessage,
  });
}

/// @nodoc
class __$$IntakeValidationImplCopyWithImpl<$Res>
    extends _$IntakeValidationCopyWithImpl<$Res, _$IntakeValidationImpl>
    implements _$$IntakeValidationImplCopyWith<$Res> {
  __$$IntakeValidationImplCopyWithImpl(
    _$IntakeValidationImpl _value,
    $Res Function(_$IntakeValidationImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IntakeValidation
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? minLength = freezed,
    Object? maxLength = freezed,
    Object? min = freezed,
    Object? max = freezed,
    Object? pattern = freezed,
    Object? errorMessage = freezed,
  }) {
    return _then(
      _$IntakeValidationImpl(
        minLength: freezed == minLength
            ? _value.minLength
            : minLength // ignore: cast_nullable_to_non_nullable
                  as int?,
        maxLength: freezed == maxLength
            ? _value.maxLength
            : maxLength // ignore: cast_nullable_to_non_nullable
                  as int?,
        min: freezed == min
            ? _value.min
            : min // ignore: cast_nullable_to_non_nullable
                  as int?,
        max: freezed == max
            ? _value.max
            : max // ignore: cast_nullable_to_non_nullable
                  as int?,
        pattern: freezed == pattern
            ? _value.pattern
            : pattern // ignore: cast_nullable_to_non_nullable
                  as String?,
        errorMessage: freezed == errorMessage
            ? _value.errorMessage
            : errorMessage // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$IntakeValidationImpl extends _IntakeValidation {
  const _$IntakeValidationImpl({
    this.minLength,
    this.maxLength,
    this.min,
    this.max,
    this.pattern,
    this.errorMessage,
  }) : super._();

  @override
  final int? minLength;
  @override
  final int? maxLength;
  @override
  final int? min;
  @override
  final int? max;
  @override
  final String? pattern;
  @override
  final String? errorMessage;

  @override
  String toString() {
    return 'IntakeValidation(minLength: $minLength, maxLength: $maxLength, min: $min, max: $max, pattern: $pattern, errorMessage: $errorMessage)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IntakeValidationImpl &&
            (identical(other.minLength, minLength) ||
                other.minLength == minLength) &&
            (identical(other.maxLength, maxLength) ||
                other.maxLength == maxLength) &&
            (identical(other.min, min) || other.min == min) &&
            (identical(other.max, max) || other.max == max) &&
            (identical(other.pattern, pattern) || other.pattern == pattern) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    minLength,
    maxLength,
    min,
    max,
    pattern,
    errorMessage,
  );

  /// Create a copy of IntakeValidation
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IntakeValidationImplCopyWith<_$IntakeValidationImpl> get copyWith =>
      __$$IntakeValidationImplCopyWithImpl<_$IntakeValidationImpl>(
        this,
        _$identity,
      );
}

abstract class _IntakeValidation extends IntakeValidation {
  const factory _IntakeValidation({
    final int? minLength,
    final int? maxLength,
    final int? min,
    final int? max,
    final String? pattern,
    final String? errorMessage,
  }) = _$IntakeValidationImpl;
  const _IntakeValidation._() : super._();

  @override
  int? get minLength;
  @override
  int? get maxLength;
  @override
  int? get min;
  @override
  int? get max;
  @override
  String? get pattern;
  @override
  String? get errorMessage;

  /// Create a copy of IntakeValidation
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IntakeValidationImplCopyWith<_$IntakeValidationImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$IntakeOption {
  String get value => throw _privateConstructorUsedError;
  String get label => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  String? get icon => throw _privateConstructorUsedError;

  /// Create a copy of IntakeOption
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IntakeOptionCopyWith<IntakeOption> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IntakeOptionCopyWith<$Res> {
  factory $IntakeOptionCopyWith(
    IntakeOption value,
    $Res Function(IntakeOption) then,
  ) = _$IntakeOptionCopyWithImpl<$Res, IntakeOption>;
  @useResult
  $Res call({String value, String label, String? description, String? icon});
}

/// @nodoc
class _$IntakeOptionCopyWithImpl<$Res, $Val extends IntakeOption>
    implements $IntakeOptionCopyWith<$Res> {
  _$IntakeOptionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IntakeOption
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? value = null,
    Object? label = null,
    Object? description = freezed,
    Object? icon = freezed,
  }) {
    return _then(
      _value.copyWith(
            value: null == value
                ? _value.value
                : value // ignore: cast_nullable_to_non_nullable
                      as String,
            label: null == label
                ? _value.label
                : label // ignore: cast_nullable_to_non_nullable
                      as String,
            description: freezed == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String?,
            icon: freezed == icon
                ? _value.icon
                : icon // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$IntakeOptionImplCopyWith<$Res>
    implements $IntakeOptionCopyWith<$Res> {
  factory _$$IntakeOptionImplCopyWith(
    _$IntakeOptionImpl value,
    $Res Function(_$IntakeOptionImpl) then,
  ) = __$$IntakeOptionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String value, String label, String? description, String? icon});
}

/// @nodoc
class __$$IntakeOptionImplCopyWithImpl<$Res>
    extends _$IntakeOptionCopyWithImpl<$Res, _$IntakeOptionImpl>
    implements _$$IntakeOptionImplCopyWith<$Res> {
  __$$IntakeOptionImplCopyWithImpl(
    _$IntakeOptionImpl _value,
    $Res Function(_$IntakeOptionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IntakeOption
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? value = null,
    Object? label = null,
    Object? description = freezed,
    Object? icon = freezed,
  }) {
    return _then(
      _$IntakeOptionImpl(
        value: null == value
            ? _value.value
            : value // ignore: cast_nullable_to_non_nullable
                  as String,
        label: null == label
            ? _value.label
            : label // ignore: cast_nullable_to_non_nullable
                  as String,
        description: freezed == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String?,
        icon: freezed == icon
            ? _value.icon
            : icon // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$IntakeOptionImpl extends _IntakeOption {
  const _$IntakeOptionImpl({
    required this.value,
    required this.label,
    this.description,
    this.icon,
  }) : super._();

  @override
  final String value;
  @override
  final String label;
  @override
  final String? description;
  @override
  final String? icon;

  @override
  String toString() {
    return 'IntakeOption(value: $value, label: $label, description: $description, icon: $icon)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IntakeOptionImpl &&
            (identical(other.value, value) || other.value == value) &&
            (identical(other.label, label) || other.label == label) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.icon, icon) || other.icon == icon));
  }

  @override
  int get hashCode => Object.hash(runtimeType, value, label, description, icon);

  /// Create a copy of IntakeOption
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IntakeOptionImplCopyWith<_$IntakeOptionImpl> get copyWith =>
      __$$IntakeOptionImplCopyWithImpl<_$IntakeOptionImpl>(this, _$identity);
}

abstract class _IntakeOption extends IntakeOption {
  const factory _IntakeOption({
    required final String value,
    required final String label,
    final String? description,
    final String? icon,
  }) = _$IntakeOptionImpl;
  const _IntakeOption._() : super._();

  @override
  String get value;
  @override
  String get label;
  @override
  String? get description;
  @override
  String? get icon;

  /// Create a copy of IntakeOption
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IntakeOptionImplCopyWith<_$IntakeOptionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$IntakeQuestion {
  /// Unique question identifier.
  String get id => throw _privateConstructorUsedError;

  /// Short title for the question.
  String get title => throw _privateConstructorUsedError;

  /// The full prompt/question text to display.
  String get prompt => throw _privateConstructorUsedError;

  /// Question type (text, number, select, etc.).
  String get type => throw _privateConstructorUsedError;

  /// Whether an answer is required.
  bool get isRequired => throw _privateConstructorUsedError;

  /// Options for select/multiselect questions.
  List<IntakeOption> get options => throw _privateConstructorUsedError;

  /// Placeholder text for input fields.
  String? get placeholder => throw _privateConstructorUsedError;

  /// Validation rules.
  IntakeValidation? get validation => throw _privateConstructorUsedError;

  /// Category for grouping questions.
  String? get category => throw _privateConstructorUsedError;

  /// Hint for mapping answer to profile field.
  String? get mappingHint => throw _privateConstructorUsedError;

  /// Create a copy of IntakeQuestion
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IntakeQuestionCopyWith<IntakeQuestion> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IntakeQuestionCopyWith<$Res> {
  factory $IntakeQuestionCopyWith(
    IntakeQuestion value,
    $Res Function(IntakeQuestion) then,
  ) = _$IntakeQuestionCopyWithImpl<$Res, IntakeQuestion>;
  @useResult
  $Res call({
    String id,
    String title,
    String prompt,
    String type,
    bool isRequired,
    List<IntakeOption> options,
    String? placeholder,
    IntakeValidation? validation,
    String? category,
    String? mappingHint,
  });

  $IntakeValidationCopyWith<$Res>? get validation;
}

/// @nodoc
class _$IntakeQuestionCopyWithImpl<$Res, $Val extends IntakeQuestion>
    implements $IntakeQuestionCopyWith<$Res> {
  _$IntakeQuestionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IntakeQuestion
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? prompt = null,
    Object? type = null,
    Object? isRequired = null,
    Object? options = null,
    Object? placeholder = freezed,
    Object? validation = freezed,
    Object? category = freezed,
    Object? mappingHint = freezed,
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
            prompt: null == prompt
                ? _value.prompt
                : prompt // ignore: cast_nullable_to_non_nullable
                      as String,
            type: null == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as String,
            isRequired: null == isRequired
                ? _value.isRequired
                : isRequired // ignore: cast_nullable_to_non_nullable
                      as bool,
            options: null == options
                ? _value.options
                : options // ignore: cast_nullable_to_non_nullable
                      as List<IntakeOption>,
            placeholder: freezed == placeholder
                ? _value.placeholder
                : placeholder // ignore: cast_nullable_to_non_nullable
                      as String?,
            validation: freezed == validation
                ? _value.validation
                : validation // ignore: cast_nullable_to_non_nullable
                      as IntakeValidation?,
            category: freezed == category
                ? _value.category
                : category // ignore: cast_nullable_to_non_nullable
                      as String?,
            mappingHint: freezed == mappingHint
                ? _value.mappingHint
                : mappingHint // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }

  /// Create a copy of IntakeQuestion
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $IntakeValidationCopyWith<$Res>? get validation {
    if (_value.validation == null) {
      return null;
    }

    return $IntakeValidationCopyWith<$Res>(_value.validation!, (value) {
      return _then(_value.copyWith(validation: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$IntakeQuestionImplCopyWith<$Res>
    implements $IntakeQuestionCopyWith<$Res> {
  factory _$$IntakeQuestionImplCopyWith(
    _$IntakeQuestionImpl value,
    $Res Function(_$IntakeQuestionImpl) then,
  ) = __$$IntakeQuestionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String title,
    String prompt,
    String type,
    bool isRequired,
    List<IntakeOption> options,
    String? placeholder,
    IntakeValidation? validation,
    String? category,
    String? mappingHint,
  });

  @override
  $IntakeValidationCopyWith<$Res>? get validation;
}

/// @nodoc
class __$$IntakeQuestionImplCopyWithImpl<$Res>
    extends _$IntakeQuestionCopyWithImpl<$Res, _$IntakeQuestionImpl>
    implements _$$IntakeQuestionImplCopyWith<$Res> {
  __$$IntakeQuestionImplCopyWithImpl(
    _$IntakeQuestionImpl _value,
    $Res Function(_$IntakeQuestionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IntakeQuestion
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? prompt = null,
    Object? type = null,
    Object? isRequired = null,
    Object? options = null,
    Object? placeholder = freezed,
    Object? validation = freezed,
    Object? category = freezed,
    Object? mappingHint = freezed,
  }) {
    return _then(
      _$IntakeQuestionImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        prompt: null == prompt
            ? _value.prompt
            : prompt // ignore: cast_nullable_to_non_nullable
                  as String,
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as String,
        isRequired: null == isRequired
            ? _value.isRequired
            : isRequired // ignore: cast_nullable_to_non_nullable
                  as bool,
        options: null == options
            ? _value._options
            : options // ignore: cast_nullable_to_non_nullable
                  as List<IntakeOption>,
        placeholder: freezed == placeholder
            ? _value.placeholder
            : placeholder // ignore: cast_nullable_to_non_nullable
                  as String?,
        validation: freezed == validation
            ? _value.validation
            : validation // ignore: cast_nullable_to_non_nullable
                  as IntakeValidation?,
        category: freezed == category
            ? _value.category
            : category // ignore: cast_nullable_to_non_nullable
                  as String?,
        mappingHint: freezed == mappingHint
            ? _value.mappingHint
            : mappingHint // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$IntakeQuestionImpl extends _IntakeQuestion {
  const _$IntakeQuestionImpl({
    required this.id,
    required this.title,
    required this.prompt,
    required this.type,
    this.isRequired = true,
    final List<IntakeOption> options = const [],
    this.placeholder,
    this.validation,
    this.category,
    this.mappingHint,
  }) : _options = options,
       super._();

  /// Unique question identifier.
  @override
  final String id;

  /// Short title for the question.
  @override
  final String title;

  /// The full prompt/question text to display.
  @override
  final String prompt;

  /// Question type (text, number, select, etc.).
  @override
  final String type;

  /// Whether an answer is required.
  @override
  @JsonKey()
  final bool isRequired;

  /// Options for select/multiselect questions.
  final List<IntakeOption> _options;

  /// Options for select/multiselect questions.
  @override
  @JsonKey()
  List<IntakeOption> get options {
    if (_options is EqualUnmodifiableListView) return _options;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_options);
  }

  /// Placeholder text for input fields.
  @override
  final String? placeholder;

  /// Validation rules.
  @override
  final IntakeValidation? validation;

  /// Category for grouping questions.
  @override
  final String? category;

  /// Hint for mapping answer to profile field.
  @override
  final String? mappingHint;

  @override
  String toString() {
    return 'IntakeQuestion(id: $id, title: $title, prompt: $prompt, type: $type, isRequired: $isRequired, options: $options, placeholder: $placeholder, validation: $validation, category: $category, mappingHint: $mappingHint)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IntakeQuestionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.isRequired, isRequired) ||
                other.isRequired == isRequired) &&
            const DeepCollectionEquality().equals(other._options, _options) &&
            (identical(other.placeholder, placeholder) ||
                other.placeholder == placeholder) &&
            (identical(other.validation, validation) ||
                other.validation == validation) &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.mappingHint, mappingHint) ||
                other.mappingHint == mappingHint));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    title,
    prompt,
    type,
    isRequired,
    const DeepCollectionEquality().hash(_options),
    placeholder,
    validation,
    category,
    mappingHint,
  );

  /// Create a copy of IntakeQuestion
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IntakeQuestionImplCopyWith<_$IntakeQuestionImpl> get copyWith =>
      __$$IntakeQuestionImplCopyWithImpl<_$IntakeQuestionImpl>(
        this,
        _$identity,
      );
}

abstract class _IntakeQuestion extends IntakeQuestion {
  const factory _IntakeQuestion({
    required final String id,
    required final String title,
    required final String prompt,
    required final String type,
    final bool isRequired,
    final List<IntakeOption> options,
    final String? placeholder,
    final IntakeValidation? validation,
    final String? category,
    final String? mappingHint,
  }) = _$IntakeQuestionImpl;
  const _IntakeQuestion._() : super._();

  /// Unique question identifier.
  @override
  String get id;

  /// Short title for the question.
  @override
  String get title;

  /// The full prompt/question text to display.
  @override
  String get prompt;

  /// Question type (text, number, select, etc.).
  @override
  String get type;

  /// Whether an answer is required.
  @override
  bool get isRequired;

  /// Options for select/multiselect questions.
  @override
  List<IntakeOption> get options;

  /// Placeholder text for input fields.
  @override
  String? get placeholder;

  /// Validation rules.
  @override
  IntakeValidation? get validation;

  /// Category for grouping questions.
  @override
  String? get category;

  /// Hint for mapping answer to profile field.
  @override
  String? get mappingHint;

  /// Create a copy of IntakeQuestion
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IntakeQuestionImplCopyWith<_$IntakeQuestionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$IntakeAnswer {
  /// Question ID this answer is for.
  String get questionId => throw _privateConstructorUsedError;

  /// The answer value (can be string, number, list, etc.).
  dynamic get answer => throw _privateConstructorUsedError;

  /// When the answer was submitted.
  DateTime? get answeredAt => throw _privateConstructorUsedError;

  /// Create a copy of IntakeAnswer
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IntakeAnswerCopyWith<IntakeAnswer> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IntakeAnswerCopyWith<$Res> {
  factory $IntakeAnswerCopyWith(
    IntakeAnswer value,
    $Res Function(IntakeAnswer) then,
  ) = _$IntakeAnswerCopyWithImpl<$Res, IntakeAnswer>;
  @useResult
  $Res call({String questionId, dynamic answer, DateTime? answeredAt});
}

/// @nodoc
class _$IntakeAnswerCopyWithImpl<$Res, $Val extends IntakeAnswer>
    implements $IntakeAnswerCopyWith<$Res> {
  _$IntakeAnswerCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IntakeAnswer
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? questionId = null,
    Object? answer = freezed,
    Object? answeredAt = freezed,
  }) {
    return _then(
      _value.copyWith(
            questionId: null == questionId
                ? _value.questionId
                : questionId // ignore: cast_nullable_to_non_nullable
                      as String,
            answer: freezed == answer
                ? _value.answer
                : answer // ignore: cast_nullable_to_non_nullable
                      as dynamic,
            answeredAt: freezed == answeredAt
                ? _value.answeredAt
                : answeredAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$IntakeAnswerImplCopyWith<$Res>
    implements $IntakeAnswerCopyWith<$Res> {
  factory _$$IntakeAnswerImplCopyWith(
    _$IntakeAnswerImpl value,
    $Res Function(_$IntakeAnswerImpl) then,
  ) = __$$IntakeAnswerImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String questionId, dynamic answer, DateTime? answeredAt});
}

/// @nodoc
class __$$IntakeAnswerImplCopyWithImpl<$Res>
    extends _$IntakeAnswerCopyWithImpl<$Res, _$IntakeAnswerImpl>
    implements _$$IntakeAnswerImplCopyWith<$Res> {
  __$$IntakeAnswerImplCopyWithImpl(
    _$IntakeAnswerImpl _value,
    $Res Function(_$IntakeAnswerImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IntakeAnswer
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? questionId = null,
    Object? answer = freezed,
    Object? answeredAt = freezed,
  }) {
    return _then(
      _$IntakeAnswerImpl(
        questionId: null == questionId
            ? _value.questionId
            : questionId // ignore: cast_nullable_to_non_nullable
                  as String,
        answer: freezed == answer
            ? _value.answer
            : answer // ignore: cast_nullable_to_non_nullable
                  as dynamic,
        answeredAt: freezed == answeredAt
            ? _value.answeredAt
            : answeredAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
      ),
    );
  }
}

/// @nodoc

class _$IntakeAnswerImpl extends _IntakeAnswer {
  const _$IntakeAnswerImpl({
    required this.questionId,
    required this.answer,
    this.answeredAt,
  }) : super._();

  /// Question ID this answer is for.
  @override
  final String questionId;

  /// The answer value (can be string, number, list, etc.).
  @override
  final dynamic answer;

  /// When the answer was submitted.
  @override
  final DateTime? answeredAt;

  @override
  String toString() {
    return 'IntakeAnswer(questionId: $questionId, answer: $answer, answeredAt: $answeredAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IntakeAnswerImpl &&
            (identical(other.questionId, questionId) ||
                other.questionId == questionId) &&
            const DeepCollectionEquality().equals(other.answer, answer) &&
            (identical(other.answeredAt, answeredAt) ||
                other.answeredAt == answeredAt));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    questionId,
    const DeepCollectionEquality().hash(answer),
    answeredAt,
  );

  /// Create a copy of IntakeAnswer
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IntakeAnswerImplCopyWith<_$IntakeAnswerImpl> get copyWith =>
      __$$IntakeAnswerImplCopyWithImpl<_$IntakeAnswerImpl>(this, _$identity);
}

abstract class _IntakeAnswer extends IntakeAnswer {
  const factory _IntakeAnswer({
    required final String questionId,
    required final dynamic answer,
    final DateTime? answeredAt,
  }) = _$IntakeAnswerImpl;
  const _IntakeAnswer._() : super._();

  /// Question ID this answer is for.
  @override
  String get questionId;

  /// The answer value (can be string, number, list, etc.).
  @override
  dynamic get answer;

  /// When the answer was submitted.
  @override
  DateTime? get answeredAt;

  /// Create a copy of IntakeAnswer
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IntakeAnswerImplCopyWith<_$IntakeAnswerImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$IntakeStartResponse {
  /// Session ID for this intake flow.
  String get sessionId => throw _privateConstructorUsedError;

  /// List of questions to answer.
  List<IntakeQuestion> get questions => throw _privateConstructorUsedError;

  /// Create a copy of IntakeStartResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IntakeStartResponseCopyWith<IntakeStartResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IntakeStartResponseCopyWith<$Res> {
  factory $IntakeStartResponseCopyWith(
    IntakeStartResponse value,
    $Res Function(IntakeStartResponse) then,
  ) = _$IntakeStartResponseCopyWithImpl<$Res, IntakeStartResponse>;
  @useResult
  $Res call({String sessionId, List<IntakeQuestion> questions});
}

/// @nodoc
class _$IntakeStartResponseCopyWithImpl<$Res, $Val extends IntakeStartResponse>
    implements $IntakeStartResponseCopyWith<$Res> {
  _$IntakeStartResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IntakeStartResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? sessionId = null, Object? questions = null}) {
    return _then(
      _value.copyWith(
            sessionId: null == sessionId
                ? _value.sessionId
                : sessionId // ignore: cast_nullable_to_non_nullable
                      as String,
            questions: null == questions
                ? _value.questions
                : questions // ignore: cast_nullable_to_non_nullable
                      as List<IntakeQuestion>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$IntakeStartResponseImplCopyWith<$Res>
    implements $IntakeStartResponseCopyWith<$Res> {
  factory _$$IntakeStartResponseImplCopyWith(
    _$IntakeStartResponseImpl value,
    $Res Function(_$IntakeStartResponseImpl) then,
  ) = __$$IntakeStartResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String sessionId, List<IntakeQuestion> questions});
}

/// @nodoc
class __$$IntakeStartResponseImplCopyWithImpl<$Res>
    extends _$IntakeStartResponseCopyWithImpl<$Res, _$IntakeStartResponseImpl>
    implements _$$IntakeStartResponseImplCopyWith<$Res> {
  __$$IntakeStartResponseImplCopyWithImpl(
    _$IntakeStartResponseImpl _value,
    $Res Function(_$IntakeStartResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IntakeStartResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? sessionId = null, Object? questions = null}) {
    return _then(
      _$IntakeStartResponseImpl(
        sessionId: null == sessionId
            ? _value.sessionId
            : sessionId // ignore: cast_nullable_to_non_nullable
                  as String,
        questions: null == questions
            ? _value._questions
            : questions // ignore: cast_nullable_to_non_nullable
                  as List<IntakeQuestion>,
      ),
    );
  }
}

/// @nodoc

class _$IntakeStartResponseImpl extends _IntakeStartResponse {
  const _$IntakeStartResponseImpl({
    required this.sessionId,
    required final List<IntakeQuestion> questions,
  }) : _questions = questions,
       super._();

  /// Session ID for this intake flow.
  @override
  final String sessionId;

  /// List of questions to answer.
  final List<IntakeQuestion> _questions;

  /// List of questions to answer.
  @override
  List<IntakeQuestion> get questions {
    if (_questions is EqualUnmodifiableListView) return _questions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_questions);
  }

  @override
  String toString() {
    return 'IntakeStartResponse(sessionId: $sessionId, questions: $questions)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IntakeStartResponseImpl &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            const DeepCollectionEquality().equals(
              other._questions,
              _questions,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    sessionId,
    const DeepCollectionEquality().hash(_questions),
  );

  /// Create a copy of IntakeStartResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IntakeStartResponseImplCopyWith<_$IntakeStartResponseImpl> get copyWith =>
      __$$IntakeStartResponseImplCopyWithImpl<_$IntakeStartResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _IntakeStartResponse extends IntakeStartResponse {
  const factory _IntakeStartResponse({
    required final String sessionId,
    required final List<IntakeQuestion> questions,
  }) = _$IntakeStartResponseImpl;
  const _IntakeStartResponse._() : super._();

  /// Session ID for this intake flow.
  @override
  String get sessionId;

  /// List of questions to answer.
  @override
  List<IntakeQuestion> get questions;

  /// Create a copy of IntakeStartResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IntakeStartResponseImplCopyWith<_$IntakeStartResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$IntakeAnswerRequest {
  /// Question ID being answered.
  String get questionId => throw _privateConstructorUsedError;

  /// The answer value.
  dynamic get answer => throw _privateConstructorUsedError;

  /// Create a copy of IntakeAnswerRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IntakeAnswerRequestCopyWith<IntakeAnswerRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IntakeAnswerRequestCopyWith<$Res> {
  factory $IntakeAnswerRequestCopyWith(
    IntakeAnswerRequest value,
    $Res Function(IntakeAnswerRequest) then,
  ) = _$IntakeAnswerRequestCopyWithImpl<$Res, IntakeAnswerRequest>;
  @useResult
  $Res call({String questionId, dynamic answer});
}

/// @nodoc
class _$IntakeAnswerRequestCopyWithImpl<$Res, $Val extends IntakeAnswerRequest>
    implements $IntakeAnswerRequestCopyWith<$Res> {
  _$IntakeAnswerRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IntakeAnswerRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? questionId = null, Object? answer = freezed}) {
    return _then(
      _value.copyWith(
            questionId: null == questionId
                ? _value.questionId
                : questionId // ignore: cast_nullable_to_non_nullable
                      as String,
            answer: freezed == answer
                ? _value.answer
                : answer // ignore: cast_nullable_to_non_nullable
                      as dynamic,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$IntakeAnswerRequestImplCopyWith<$Res>
    implements $IntakeAnswerRequestCopyWith<$Res> {
  factory _$$IntakeAnswerRequestImplCopyWith(
    _$IntakeAnswerRequestImpl value,
    $Res Function(_$IntakeAnswerRequestImpl) then,
  ) = __$$IntakeAnswerRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String questionId, dynamic answer});
}

/// @nodoc
class __$$IntakeAnswerRequestImplCopyWithImpl<$Res>
    extends _$IntakeAnswerRequestCopyWithImpl<$Res, _$IntakeAnswerRequestImpl>
    implements _$$IntakeAnswerRequestImplCopyWith<$Res> {
  __$$IntakeAnswerRequestImplCopyWithImpl(
    _$IntakeAnswerRequestImpl _value,
    $Res Function(_$IntakeAnswerRequestImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IntakeAnswerRequest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? questionId = null, Object? answer = freezed}) {
    return _then(
      _$IntakeAnswerRequestImpl(
        questionId: null == questionId
            ? _value.questionId
            : questionId // ignore: cast_nullable_to_non_nullable
                  as String,
        answer: freezed == answer
            ? _value.answer
            : answer // ignore: cast_nullable_to_non_nullable
                  as dynamic,
      ),
    );
  }
}

/// @nodoc

class _$IntakeAnswerRequestImpl extends _IntakeAnswerRequest {
  const _$IntakeAnswerRequestImpl({
    required this.questionId,
    required this.answer,
  }) : super._();

  /// Question ID being answered.
  @override
  final String questionId;

  /// The answer value.
  @override
  final dynamic answer;

  @override
  String toString() {
    return 'IntakeAnswerRequest(questionId: $questionId, answer: $answer)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IntakeAnswerRequestImpl &&
            (identical(other.questionId, questionId) ||
                other.questionId == questionId) &&
            const DeepCollectionEquality().equals(other.answer, answer));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    questionId,
    const DeepCollectionEquality().hash(answer),
  );

  /// Create a copy of IntakeAnswerRequest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IntakeAnswerRequestImplCopyWith<_$IntakeAnswerRequestImpl> get copyWith =>
      __$$IntakeAnswerRequestImplCopyWithImpl<_$IntakeAnswerRequestImpl>(
        this,
        _$identity,
      );
}

abstract class _IntakeAnswerRequest extends IntakeAnswerRequest {
  const factory _IntakeAnswerRequest({
    required final String questionId,
    required final dynamic answer,
  }) = _$IntakeAnswerRequestImpl;
  const _IntakeAnswerRequest._() : super._();

  /// Question ID being answered.
  @override
  String get questionId;

  /// The answer value.
  @override
  dynamic get answer;

  /// Create a copy of IntakeAnswerRequest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IntakeAnswerRequestImplCopyWith<_$IntakeAnswerRequestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$IntakeSessionResponse {
  /// Session ID.
  String get sessionId => throw _privateConstructorUsedError;

  /// Current status of the session.
  String get status => throw _privateConstructorUsedError;

  /// All questions in this intake.
  List<IntakeQuestion> get questions => throw _privateConstructorUsedError;

  /// Answers submitted so far.
  List<IntakeAnswer> get answers => throw _privateConstructorUsedError;

  /// Idol ID if associated.
  String? get idolId => throw _privateConstructorUsedError;

  /// Target age if set.
  int? get targetAge => throw _privateConstructorUsedError;

  /// When the session was created.
  DateTime? get createdAt => throw _privateConstructorUsedError;

  /// When the session was last updated.
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  /// Create a copy of IntakeSessionResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $IntakeSessionResponseCopyWith<IntakeSessionResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $IntakeSessionResponseCopyWith<$Res> {
  factory $IntakeSessionResponseCopyWith(
    IntakeSessionResponse value,
    $Res Function(IntakeSessionResponse) then,
  ) = _$IntakeSessionResponseCopyWithImpl<$Res, IntakeSessionResponse>;
  @useResult
  $Res call({
    String sessionId,
    String status,
    List<IntakeQuestion> questions,
    List<IntakeAnswer> answers,
    String? idolId,
    int? targetAge,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
}

/// @nodoc
class _$IntakeSessionResponseCopyWithImpl<
  $Res,
  $Val extends IntakeSessionResponse
>
    implements $IntakeSessionResponseCopyWith<$Res> {
  _$IntakeSessionResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of IntakeSessionResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionId = null,
    Object? status = null,
    Object? questions = null,
    Object? answers = null,
    Object? idolId = freezed,
    Object? targetAge = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(
      _value.copyWith(
            sessionId: null == sessionId
                ? _value.sessionId
                : sessionId // ignore: cast_nullable_to_non_nullable
                      as String,
            status: null == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String,
            questions: null == questions
                ? _value.questions
                : questions // ignore: cast_nullable_to_non_nullable
                      as List<IntakeQuestion>,
            answers: null == answers
                ? _value.answers
                : answers // ignore: cast_nullable_to_non_nullable
                      as List<IntakeAnswer>,
            idolId: freezed == idolId
                ? _value.idolId
                : idolId // ignore: cast_nullable_to_non_nullable
                      as String?,
            targetAge: freezed == targetAge
                ? _value.targetAge
                : targetAge // ignore: cast_nullable_to_non_nullable
                      as int?,
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
abstract class _$$IntakeSessionResponseImplCopyWith<$Res>
    implements $IntakeSessionResponseCopyWith<$Res> {
  factory _$$IntakeSessionResponseImplCopyWith(
    _$IntakeSessionResponseImpl value,
    $Res Function(_$IntakeSessionResponseImpl) then,
  ) = __$$IntakeSessionResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String sessionId,
    String status,
    List<IntakeQuestion> questions,
    List<IntakeAnswer> answers,
    String? idolId,
    int? targetAge,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
}

/// @nodoc
class __$$IntakeSessionResponseImplCopyWithImpl<$Res>
    extends
        _$IntakeSessionResponseCopyWithImpl<$Res, _$IntakeSessionResponseImpl>
    implements _$$IntakeSessionResponseImplCopyWith<$Res> {
  __$$IntakeSessionResponseImplCopyWithImpl(
    _$IntakeSessionResponseImpl _value,
    $Res Function(_$IntakeSessionResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of IntakeSessionResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionId = null,
    Object? status = null,
    Object? questions = null,
    Object? answers = null,
    Object? idolId = freezed,
    Object? targetAge = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(
      _$IntakeSessionResponseImpl(
        sessionId: null == sessionId
            ? _value.sessionId
            : sessionId // ignore: cast_nullable_to_non_nullable
                  as String,
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String,
        questions: null == questions
            ? _value._questions
            : questions // ignore: cast_nullable_to_non_nullable
                  as List<IntakeQuestion>,
        answers: null == answers
            ? _value._answers
            : answers // ignore: cast_nullable_to_non_nullable
                  as List<IntakeAnswer>,
        idolId: freezed == idolId
            ? _value.idolId
            : idolId // ignore: cast_nullable_to_non_nullable
                  as String?,
        targetAge: freezed == targetAge
            ? _value.targetAge
            : targetAge // ignore: cast_nullable_to_non_nullable
                  as int?,
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

class _$IntakeSessionResponseImpl extends _IntakeSessionResponse {
  const _$IntakeSessionResponseImpl({
    required this.sessionId,
    required this.status,
    required final List<IntakeQuestion> questions,
    required final List<IntakeAnswer> answers,
    this.idolId,
    this.targetAge,
    this.createdAt,
    this.updatedAt,
  }) : _questions = questions,
       _answers = answers,
       super._();

  /// Session ID.
  @override
  final String sessionId;

  /// Current status of the session.
  @override
  final String status;

  /// All questions in this intake.
  final List<IntakeQuestion> _questions;

  /// All questions in this intake.
  @override
  List<IntakeQuestion> get questions {
    if (_questions is EqualUnmodifiableListView) return _questions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_questions);
  }

  /// Answers submitted so far.
  final List<IntakeAnswer> _answers;

  /// Answers submitted so far.
  @override
  List<IntakeAnswer> get answers {
    if (_answers is EqualUnmodifiableListView) return _answers;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_answers);
  }

  /// Idol ID if associated.
  @override
  final String? idolId;

  /// Target age if set.
  @override
  final int? targetAge;

  /// When the session was created.
  @override
  final DateTime? createdAt;

  /// When the session was last updated.
  @override
  final DateTime? updatedAt;

  @override
  String toString() {
    return 'IntakeSessionResponse(sessionId: $sessionId, status: $status, questions: $questions, answers: $answers, idolId: $idolId, targetAge: $targetAge, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$IntakeSessionResponseImpl &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.status, status) || other.status == status) &&
            const DeepCollectionEquality().equals(
              other._questions,
              _questions,
            ) &&
            const DeepCollectionEquality().equals(other._answers, _answers) &&
            (identical(other.idolId, idolId) || other.idolId == idolId) &&
            (identical(other.targetAge, targetAge) ||
                other.targetAge == targetAge) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    sessionId,
    status,
    const DeepCollectionEquality().hash(_questions),
    const DeepCollectionEquality().hash(_answers),
    idolId,
    targetAge,
    createdAt,
    updatedAt,
  );

  /// Create a copy of IntakeSessionResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$IntakeSessionResponseImplCopyWith<_$IntakeSessionResponseImpl>
  get copyWith =>
      __$$IntakeSessionResponseImplCopyWithImpl<_$IntakeSessionResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _IntakeSessionResponse extends IntakeSessionResponse {
  const factory _IntakeSessionResponse({
    required final String sessionId,
    required final String status,
    required final List<IntakeQuestion> questions,
    required final List<IntakeAnswer> answers,
    final String? idolId,
    final int? targetAge,
    final DateTime? createdAt,
    final DateTime? updatedAt,
  }) = _$IntakeSessionResponseImpl;
  const _IntakeSessionResponse._() : super._();

  /// Session ID.
  @override
  String get sessionId;

  /// Current status of the session.
  @override
  String get status;

  /// All questions in this intake.
  @override
  List<IntakeQuestion> get questions;

  /// Answers submitted so far.
  @override
  List<IntakeAnswer> get answers;

  /// Idol ID if associated.
  @override
  String? get idolId;

  /// Target age if set.
  @override
  int? get targetAge;

  /// When the session was created.
  @override
  DateTime? get createdAt;

  /// When the session was last updated.
  @override
  DateTime? get updatedAt;

  /// Create a copy of IntakeSessionResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$IntakeSessionResponseImplCopyWith<_$IntakeSessionResponseImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$FinishIntakeResponse {
  /// Job ID for background processing.
  String get jobId => throw _privateConstructorUsedError;

  /// Optional idol ID if one was created.
  String? get idolId => throw _privateConstructorUsedError;

  /// Status message.
  String? get message => throw _privateConstructorUsedError;

  /// Create a copy of FinishIntakeResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FinishIntakeResponseCopyWith<FinishIntakeResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FinishIntakeResponseCopyWith<$Res> {
  factory $FinishIntakeResponseCopyWith(
    FinishIntakeResponse value,
    $Res Function(FinishIntakeResponse) then,
  ) = _$FinishIntakeResponseCopyWithImpl<$Res, FinishIntakeResponse>;
  @useResult
  $Res call({String jobId, String? idolId, String? message});
}

/// @nodoc
class _$FinishIntakeResponseCopyWithImpl<
  $Res,
  $Val extends FinishIntakeResponse
>
    implements $FinishIntakeResponseCopyWith<$Res> {
  _$FinishIntakeResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FinishIntakeResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? jobId = null,
    Object? idolId = freezed,
    Object? message = freezed,
  }) {
    return _then(
      _value.copyWith(
            jobId: null == jobId
                ? _value.jobId
                : jobId // ignore: cast_nullable_to_non_nullable
                      as String,
            idolId: freezed == idolId
                ? _value.idolId
                : idolId // ignore: cast_nullable_to_non_nullable
                      as String?,
            message: freezed == message
                ? _value.message
                : message // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$FinishIntakeResponseImplCopyWith<$Res>
    implements $FinishIntakeResponseCopyWith<$Res> {
  factory _$$FinishIntakeResponseImplCopyWith(
    _$FinishIntakeResponseImpl value,
    $Res Function(_$FinishIntakeResponseImpl) then,
  ) = __$$FinishIntakeResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String jobId, String? idolId, String? message});
}

/// @nodoc
class __$$FinishIntakeResponseImplCopyWithImpl<$Res>
    extends _$FinishIntakeResponseCopyWithImpl<$Res, _$FinishIntakeResponseImpl>
    implements _$$FinishIntakeResponseImplCopyWith<$Res> {
  __$$FinishIntakeResponseImplCopyWithImpl(
    _$FinishIntakeResponseImpl _value,
    $Res Function(_$FinishIntakeResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of FinishIntakeResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? jobId = null,
    Object? idolId = freezed,
    Object? message = freezed,
  }) {
    return _then(
      _$FinishIntakeResponseImpl(
        jobId: null == jobId
            ? _value.jobId
            : jobId // ignore: cast_nullable_to_non_nullable
                  as String,
        idolId: freezed == idolId
            ? _value.idolId
            : idolId // ignore: cast_nullable_to_non_nullable
                  as String?,
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$FinishIntakeResponseImpl extends _FinishIntakeResponse {
  const _$FinishIntakeResponseImpl({
    required this.jobId,
    this.idolId,
    this.message,
  }) : super._();

  /// Job ID for background processing.
  @override
  final String jobId;

  /// Optional idol ID if one was created.
  @override
  final String? idolId;

  /// Status message.
  @override
  final String? message;

  @override
  String toString() {
    return 'FinishIntakeResponse(jobId: $jobId, idolId: $idolId, message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FinishIntakeResponseImpl &&
            (identical(other.jobId, jobId) || other.jobId == jobId) &&
            (identical(other.idolId, idolId) || other.idolId == idolId) &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, jobId, idolId, message);

  /// Create a copy of FinishIntakeResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FinishIntakeResponseImplCopyWith<_$FinishIntakeResponseImpl>
  get copyWith =>
      __$$FinishIntakeResponseImplCopyWithImpl<_$FinishIntakeResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _FinishIntakeResponse extends FinishIntakeResponse {
  const factory _FinishIntakeResponse({
    required final String jobId,
    final String? idolId,
    final String? message,
  }) = _$FinishIntakeResponseImpl;
  const _FinishIntakeResponse._() : super._();

  /// Job ID for background processing.
  @override
  String get jobId;

  /// Optional idol ID if one was created.
  @override
  String? get idolId;

  /// Status message.
  @override
  String? get message;

  /// Create a copy of FinishIntakeResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FinishIntakeResponseImplCopyWith<_$FinishIntakeResponseImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SubmitAnswerResponse {
  /// Whether the submission was successful.
  bool get success => throw _privateConstructorUsedError;

  /// The submitted answer.
  IntakeAnswer? get answer => throw _privateConstructorUsedError;

  /// Next question if available.
  IntakeQuestion? get nextQuestion => throw _privateConstructorUsedError;

  /// Updated session status.
  String? get status => throw _privateConstructorUsedError;

  /// Progress percentage.
  double? get progress => throw _privateConstructorUsedError;

  /// Error message if failed.
  String? get error => throw _privateConstructorUsedError;

  /// Create a copy of SubmitAnswerResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SubmitAnswerResponseCopyWith<SubmitAnswerResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SubmitAnswerResponseCopyWith<$Res> {
  factory $SubmitAnswerResponseCopyWith(
    SubmitAnswerResponse value,
    $Res Function(SubmitAnswerResponse) then,
  ) = _$SubmitAnswerResponseCopyWithImpl<$Res, SubmitAnswerResponse>;
  @useResult
  $Res call({
    bool success,
    IntakeAnswer? answer,
    IntakeQuestion? nextQuestion,
    String? status,
    double? progress,
    String? error,
  });

  $IntakeAnswerCopyWith<$Res>? get answer;
  $IntakeQuestionCopyWith<$Res>? get nextQuestion;
}

/// @nodoc
class _$SubmitAnswerResponseCopyWithImpl<
  $Res,
  $Val extends SubmitAnswerResponse
>
    implements $SubmitAnswerResponseCopyWith<$Res> {
  _$SubmitAnswerResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SubmitAnswerResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? answer = freezed,
    Object? nextQuestion = freezed,
    Object? status = freezed,
    Object? progress = freezed,
    Object? error = freezed,
  }) {
    return _then(
      _value.copyWith(
            success: null == success
                ? _value.success
                : success // ignore: cast_nullable_to_non_nullable
                      as bool,
            answer: freezed == answer
                ? _value.answer
                : answer // ignore: cast_nullable_to_non_nullable
                      as IntakeAnswer?,
            nextQuestion: freezed == nextQuestion
                ? _value.nextQuestion
                : nextQuestion // ignore: cast_nullable_to_non_nullable
                      as IntakeQuestion?,
            status: freezed == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String?,
            progress: freezed == progress
                ? _value.progress
                : progress // ignore: cast_nullable_to_non_nullable
                      as double?,
            error: freezed == error
                ? _value.error
                : error // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }

  /// Create a copy of SubmitAnswerResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $IntakeAnswerCopyWith<$Res>? get answer {
    if (_value.answer == null) {
      return null;
    }

    return $IntakeAnswerCopyWith<$Res>(_value.answer!, (value) {
      return _then(_value.copyWith(answer: value) as $Val);
    });
  }

  /// Create a copy of SubmitAnswerResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $IntakeQuestionCopyWith<$Res>? get nextQuestion {
    if (_value.nextQuestion == null) {
      return null;
    }

    return $IntakeQuestionCopyWith<$Res>(_value.nextQuestion!, (value) {
      return _then(_value.copyWith(nextQuestion: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$SubmitAnswerResponseImplCopyWith<$Res>
    implements $SubmitAnswerResponseCopyWith<$Res> {
  factory _$$SubmitAnswerResponseImplCopyWith(
    _$SubmitAnswerResponseImpl value,
    $Res Function(_$SubmitAnswerResponseImpl) then,
  ) = __$$SubmitAnswerResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    bool success,
    IntakeAnswer? answer,
    IntakeQuestion? nextQuestion,
    String? status,
    double? progress,
    String? error,
  });

  @override
  $IntakeAnswerCopyWith<$Res>? get answer;
  @override
  $IntakeQuestionCopyWith<$Res>? get nextQuestion;
}

/// @nodoc
class __$$SubmitAnswerResponseImplCopyWithImpl<$Res>
    extends _$SubmitAnswerResponseCopyWithImpl<$Res, _$SubmitAnswerResponseImpl>
    implements _$$SubmitAnswerResponseImplCopyWith<$Res> {
  __$$SubmitAnswerResponseImplCopyWithImpl(
    _$SubmitAnswerResponseImpl _value,
    $Res Function(_$SubmitAnswerResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SubmitAnswerResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? answer = freezed,
    Object? nextQuestion = freezed,
    Object? status = freezed,
    Object? progress = freezed,
    Object? error = freezed,
  }) {
    return _then(
      _$SubmitAnswerResponseImpl(
        success: null == success
            ? _value.success
            : success // ignore: cast_nullable_to_non_nullable
                  as bool,
        answer: freezed == answer
            ? _value.answer
            : answer // ignore: cast_nullable_to_non_nullable
                  as IntakeAnswer?,
        nextQuestion: freezed == nextQuestion
            ? _value.nextQuestion
            : nextQuestion // ignore: cast_nullable_to_non_nullable
                  as IntakeQuestion?,
        status: freezed == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String?,
        progress: freezed == progress
            ? _value.progress
            : progress // ignore: cast_nullable_to_non_nullable
                  as double?,
        error: freezed == error
            ? _value.error
            : error // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$SubmitAnswerResponseImpl extends _SubmitAnswerResponse {
  const _$SubmitAnswerResponseImpl({
    this.success = true,
    this.answer,
    this.nextQuestion,
    this.status,
    this.progress,
    this.error,
  }) : super._();

  /// Whether the submission was successful.
  @override
  @JsonKey()
  final bool success;

  /// The submitted answer.
  @override
  final IntakeAnswer? answer;

  /// Next question if available.
  @override
  final IntakeQuestion? nextQuestion;

  /// Updated session status.
  @override
  final String? status;

  /// Progress percentage.
  @override
  final double? progress;

  /// Error message if failed.
  @override
  final String? error;

  @override
  String toString() {
    return 'SubmitAnswerResponse(success: $success, answer: $answer, nextQuestion: $nextQuestion, status: $status, progress: $progress, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SubmitAnswerResponseImpl &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.answer, answer) || other.answer == answer) &&
            (identical(other.nextQuestion, nextQuestion) ||
                other.nextQuestion == nextQuestion) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.progress, progress) ||
                other.progress == progress) &&
            (identical(other.error, error) || other.error == error));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    success,
    answer,
    nextQuestion,
    status,
    progress,
    error,
  );

  /// Create a copy of SubmitAnswerResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SubmitAnswerResponseImplCopyWith<_$SubmitAnswerResponseImpl>
  get copyWith =>
      __$$SubmitAnswerResponseImplCopyWithImpl<_$SubmitAnswerResponseImpl>(
        this,
        _$identity,
      );
}

abstract class _SubmitAnswerResponse extends SubmitAnswerResponse {
  const factory _SubmitAnswerResponse({
    final bool success,
    final IntakeAnswer? answer,
    final IntakeQuestion? nextQuestion,
    final String? status,
    final double? progress,
    final String? error,
  }) = _$SubmitAnswerResponseImpl;
  const _SubmitAnswerResponse._() : super._();

  /// Whether the submission was successful.
  @override
  bool get success;

  /// The submitted answer.
  @override
  IntakeAnswer? get answer;

  /// Next question if available.
  @override
  IntakeQuestion? get nextQuestion;

  /// Updated session status.
  @override
  String? get status;

  /// Progress percentage.
  @override
  double? get progress;

  /// Error message if failed.
  @override
  String? get error;

  /// Create a copy of SubmitAnswerResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SubmitAnswerResponseImplCopyWith<_$SubmitAnswerResponseImpl>
  get copyWith => throw _privateConstructorUsedError;
}
