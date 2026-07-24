enum InterviewResponseKind { text, singleChoice, number }

/// A validated hint from the interview API describing the best composer for
/// the current question. It never contains the question itself; the assistant
/// chat bubble remains the complete, accessible source of truth.
class InterviewResponseUi {
  const InterviewResponseUi._({
    required this.kind,
    required this.placeholder,
    required this.options,
    required this.min,
    required this.max,
    required this.step,
    required this.initial,
    required this.unit,
    required this.allowCustom,
  });

  factory InterviewResponseUi.text({String? placeholder}) {
    return InterviewResponseUi._(
      kind: InterviewResponseKind.text,
      placeholder: _boundedText(placeholder, 100) ?? 'Type your answer…',
      options: const [],
      min: null,
      max: null,
      step: null,
      initial: null,
      unit: null,
      allowCustom: true,
    );
  }

  /// Parse defensively so an older backend, unknown future version, or
  /// malformed model-generated payload always leaves the interview answerable.
  factory InterviewResponseUi.fromJson(Object? value) {
    if (value is! Map) return InterviewResponseUi.text();
    final json = value.cast<Object?, Object?>();
    if (_asInt(json['version']) != 1) return InterviewResponseUi.text();

    final placeholder =
        _boundedText(json['placeholder']?.toString(), 100) ??
        'Type your answer…';
    switch (json['kind']?.toString()) {
      case 'single_choice':
        final rawOptions = json['options'];
        if (rawOptions is! List) return InterviewResponseUi.text();
        final options = <String>[];
        final seen = <String>{};
        for (final raw in rawOptions) {
          final option = raw.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
          if (option.isEmpty || option.length > 80) {
            return InterviewResponseUi.text();
          }
          if (seen.add(option.toLowerCase())) options.add(option);
        }
        if (options.length < 2 || options.length > 6) {
          return InterviewResponseUi.text();
        }
        return InterviewResponseUi._(
          kind: InterviewResponseKind.singleChoice,
          placeholder: placeholder,
          options: List.unmodifiable(options),
          min: null,
          max: null,
          step: null,
          initial: null,
          unit: null,
          allowCustom: true,
        );
      case 'number':
        final min = _asFiniteDouble(json['min'] ?? json['min_value']);
        final max = _asFiniteDouble(json['max'] ?? json['max_value']);
        final step = _asFiniteDouble(json['step']);
        final initial = _asFiniteDouble(
          json['initial'] ?? json['initial_value'],
        );
        final unit = _boundedText(json['unit']?.toString(), 40);
        if (min == null ||
            max == null ||
            step == null ||
            min >= max ||
            step <= 0 ||
            step > 1000) {
          return InterviewResponseUi.text();
        }
        final safeInitial = initial ?? min;
        if (safeInitial < min || safeInitial > max) {
          return InterviewResponseUi.text();
        }
        final minScaled = _scaledFourDecimals(min);
        final maxScaled = _scaledFourDecimals(max);
        final stepScaled = _scaledFourDecimals(step);
        final initialScaled = _scaledFourDecimals(safeInitial);
        if (minScaled == null ||
            maxScaled == null ||
            stepScaled == null ||
            initialScaled == null ||
            stepScaled <= 0) {
          return InterviewResponseUi.text();
        }
        final spanScaled = maxScaled - minScaled;
        if (stepScaled > spanScaled ||
            spanScaled % stepScaled != 0 ||
            (initialScaled - minScaled) % stepScaled != 0 ||
            spanScaled ~/ stepScaled > 200) {
          return InterviewResponseUi.text();
        }
        return InterviewResponseUi._(
          kind: InterviewResponseKind.number,
          placeholder: placeholder,
          options: const [],
          min: min,
          max: max,
          step: step,
          initial: safeInitial,
          unit: unit,
          allowCustom: true,
        );
      case 'text':
        return InterviewResponseUi.text(placeholder: placeholder);
      default:
        return InterviewResponseUi.text();
    }
  }

  final InterviewResponseKind kind;
  final String placeholder;
  final List<String> options;
  final double? min;
  final double? max;
  final double? step;
  final double? initial;
  final String? unit;
  final bool allowCustom;

  static String? _boundedText(String? value, int maxLength) {
    final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized == null ||
        normalized.isEmpty ||
        normalized.length > maxLength) {
      return null;
    }
    return normalized;
  }

  static double? _asFiniteDouble(Object? value) {
    final parsed = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text),
      _ => null,
    };
    return parsed != null && parsed.isFinite && parsed.abs() <= 1000000
        ? parsed
        : null;
  }

  static int? _asInt(Object? value) {
    return switch (value) {
      int number => number,
      num number when number.isFinite && number == number.toInt() =>
        number.toInt(),
      String text => int.tryParse(text),
      _ => null,
    };
  }

  static int? _scaledFourDecimals(double value) {
    final scaledValue = value * 10000;
    if (!scaledValue.isFinite) return null;
    final scaled = scaledValue.round();
    return (scaled / 10000 - value).abs() <= 0.000000001 ? scaled : null;
  }
}
