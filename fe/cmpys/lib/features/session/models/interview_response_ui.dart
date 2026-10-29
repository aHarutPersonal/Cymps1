enum InterviewResponseKind { text, singleChoice, multiChoice, scale, number }

/// The icon names the interview API may attach to a choice option (the
/// backend's `InterviewOptionIcon`). Anything else is dropped rather than guessed.
const Set<String> kInterviewOptionIcons = {
  'list',
  'book',
  'edit',
  'headphones',
  'clock',
  'target',
  'users',
  'layers',
  'calendar',
  'sparkle',
};

/// Optional description and icon shown beside one choice option. The API
/// sends these in a list parallel to `options`.
class InterviewOptionDetail {
  const InterviewOptionDetail({this.description, this.icon});

  static const empty = InterviewOptionDetail();

  final String? description;

  /// One of [kInterviewOptionIcons], or null.
  final String? icon;

  bool get isEmpty => description == null && icon == null;
}

/// A validated hint from the interview API describing the best composer for
/// the current question. It never contains the question itself; the assistant
/// chat bubble remains the complete, accessible source of truth.
class InterviewResponseUi {
  const InterviewResponseUi._({
    required this.kind,
    required this.placeholder,
    this.options = const [],
    this.optionDetails = const [],
    this.suggestions = const [],
    this.missingOption,
    this.lowLabel,
    this.highLabel,
    this.minSelected = 1,
    this.maxSelected,
    this.min,
    this.max,
    this.step,
    this.initial,
    this.presets = const [],
    this.dailyHint = false,
    this.unit,
    this.allowCustom = true,
    this.answerKey,
  });

  static const _defaultPlaceholder = 'Type your answer';

  factory InterviewResponseUi.text({
    String? placeholder,
    List<String> suggestions = const [],
    String? missingOption,
    String? answerKey,
  }) {
    return InterviewResponseUi._(
      kind: InterviewResponseKind.text,
      placeholder: _boundedText(placeholder, 100) ?? _defaultPlaceholder,
      suggestions: List.unmodifiable(suggestions),
      missingOption: missingOption,
      answerKey: answerKey,
    );
  }

  /// Parse defensively so an older backend, unknown future version, or
  /// malformed model-generated payload always leaves the interview answerable.
  /// Unknown kinds and payloads that break a kind's contract fall back to
  /// text; drifted *optional* fields (an unknown icon, an off-grid preset) are
  /// dropped without losing the control.
  factory InterviewResponseUi.fromJson(Object? value) {
    if (value is! Map) return InterviewResponseUi.text();
    final json = value.cast<Object?, Object?>();
    if (_asInt(json['version']) != 1) return InterviewResponseUi.text();

    final placeholder =
        _boundedText(json['placeholder']?.toString(), 100) ??
        _defaultPlaceholder;
    final answerKey = _answerKey(json['answer_key']);
    final allowCustom = json['allow_custom'] != false;
    switch (json['kind']?.toString()) {
      case 'single_choice':
      case 'multi_choice':
        final multi = json['kind'] == 'multi_choice';
        final choices = _choices(json['options'], json['option_details']);
        if (choices == null) return InterviewResponseUi.text();
        final (options, details) = choices;
        var minSelected = 1;
        int? maxSelected;
        if (multi) {
          final rawMin = json['min_selected'];
          final rawMax = json['max_selected'];
          final parsedMin = rawMin == null ? 1 : _asInt(rawMin);
          final parsedMax = rawMax == null ? null : _asInt(rawMax);
          if (parsedMin == null ||
              parsedMin < 1 ||
              parsedMin > options.length ||
              (rawMax != null &&
                  (parsedMax == null ||
                      parsedMax < parsedMin ||
                      parsedMax > options.length))) {
            return InterviewResponseUi.text();
          }
          minSelected = parsedMin;
          maxSelected = parsedMax;
        }
        return InterviewResponseUi._(
          kind: multi
              ? InterviewResponseKind.multiChoice
              : InterviewResponseKind.singleChoice,
          placeholder: placeholder,
          options: List.unmodifiable(options),
          optionDetails: List.unmodifiable(details),
          minSelected: minSelected,
          maxSelected: maxSelected,
          // Choice kinds always accept a custom answer (the server forces it).
          allowCustom: true,
          answerKey: answerKey,
        );
      case 'scale':
        // The server fixes the range to 1-5 whatever the payload says.
        return InterviewResponseUi._(
          kind: InterviewResponseKind.scale,
          placeholder: placeholder,
          lowLabel: _boundedText(json['low_label']?.toString(), 40),
          highLabel: _boundedText(json['high_label']?.toString(), 40),
          min: 1,
          max: 5,
          step: 1,
          allowCustom: allowCustom,
          answerKey: answerKey,
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
          min: min,
          max: max,
          step: step,
          initial: safeInitial,
          presets: List.unmodifiable(
            _presets(json['presets'], minScaled, maxScaled, stepScaled),
          ),
          dailyHint: json['daily_hint'] == true,
          unit: unit,
          allowCustom: allowCustom,
          answerKey: answerKey,
        );
      case 'text':
        final missingOption = _boundedText(
          json['missing_option']?.toString(),
          60,
        );
        return InterviewResponseUi.text(
          placeholder: placeholder,
          suggestions: _suggestions(json['suggestions'], missingOption),
          missingOption: missingOption,
          answerKey: answerKey,
        );
      default:
        return InterviewResponseUi.text();
    }
  }

  final InterviewResponseKind kind;
  final String placeholder;

  /// single_choice / multi_choice: 2-6 unique labels.
  final List<String> options;

  /// Empty, or one entry per option (in the same order).
  final List<InterviewOptionDetail> optionDetails;

  /// text: tappable starting points that fill the field (at most 4).
  final List<String> suggestions;

  /// text: the "I have none" option; sent at once as missing evidence.
  final String? missingOption;

  /// scale: captions for the two ends of the 1-5 range.
  final String? lowLabel;
  final String? highLabel;

  /// multi_choice: how many options may be selected.
  final int minSelected;
  final int? maxSelected;

  final double? min;
  final double? max;
  final double? step;
  final double? initial;

  /// number: quick-pick values, each inside the range and on the step grid.
  final List<double> presets;

  /// number: show "About N min a day" for a weekly-hours value.
  final bool dailyHint;
  final String? unit;
  final bool allowCustom;

  /// The server-owned semantic key of the question (e.g. `weekly_hours`).
  final String? answerKey;

  /// The weekly-capacity question, answered as "N hours a week".
  bool get isWeeklyHours => answerKey == 'weekly_hours';

  /// The detail for option [index], or [InterviewOptionDetail.empty].
  InterviewOptionDetail detailAt(int index) => index < optionDetails.length
      ? optionDetails[index]
      : InterviewOptionDetail.empty;

  /// Options plus their aligned details, deduplicated together so they stay
  /// aligned. Null when the options break the 2-6 unique-label contract.
  static (List<String>, List<InterviewOptionDetail>)? _choices(
    Object? rawOptions,
    Object? rawDetails,
  ) {
    if (rawOptions is! List) return null;
    final details = rawDetails is List && rawDetails.length == rawOptions.length
        ? rawDetails
        : null;
    final options = <String>[];
    final kept = <InterviewOptionDetail>[];
    final seen = <String>{};
    for (var index = 0; index < rawOptions.length; index++) {
      final option = rawOptions[index]
          .toString()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (option.isEmpty || option.length > 80) return null;
      if (!seen.add(option.toLowerCase())) continue;
      options.add(option);
      kept.add(
        details == null ? InterviewOptionDetail.empty : _detail(details[index]),
      );
    }
    if (options.length < 2 || options.length > 6) return null;
    return (options, kept.every((d) => d.isEmpty) ? const [] : kept);
  }

  static InterviewOptionDetail _detail(Object? raw) {
    if (raw is String) {
      return InterviewOptionDetail(description: _boundedText(raw, 90));
    }
    if (raw is! Map) return InterviewOptionDetail.empty;
    final icon = raw['icon']?.toString();
    return InterviewOptionDetail(
      description: _boundedText(raw['description']?.toString(), 90),
      icon: kInterviewOptionIcons.contains(icon) ? icon : null,
    );
  }

  static List<String> _suggestions(Object? raw, String? missingOption) {
    if (raw is! List) return const [];
    final out = <String>[];
    final seen = <String>{
      if (missingOption != null) missingOption.toLowerCase(),
    };
    for (final item in raw) {
      if (item is! String) continue;
      final suggestion = _boundedText(item, 60);
      if (suggestion == null || !seen.add(suggestion.toLowerCase())) continue;
      out.add(suggestion);
      if (out.length == 4) break;
    }
    return out;
  }

  static List<double> _presets(
    Object? raw,
    int minScaled,
    int maxScaled,
    int stepScaled,
  ) {
    if (raw is! List) return const [];
    final out = <double>[];
    for (final item in raw) {
      if (item is! num) continue;
      final value = _asFiniteDouble(item);
      final scaled = value == null ? null : _scaledFourDecimals(value);
      if (value == null ||
          scaled == null ||
          scaled < minScaled ||
          scaled > maxScaled ||
          (scaled - minScaled) % stepScaled != 0 ||
          out.contains(value)) {
        continue;
      }
      out.add(value);
      if (out.length == 4) break;
    }
    return out;
  }

  static String? _answerKey(Object? raw) {
    final key = raw?.toString().trim();
    if (key == null || !RegExp(r'^[a-z][a-z0-9_]{0,59}$').hasMatch(key)) {
      return null;
    }
    return key;
  }

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
