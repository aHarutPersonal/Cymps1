import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/motion/motion_config.dart';
import '../../../../core/ui/v3/v3.dart';
import '../../../session/models/interview_response_ui.dart';

/// The intake answer panel (design `v3/onboard2.jsx` `Intake`): one control
/// per interview response kind, under a kicker naming it.
///
/// - **text:** suggestion chips fill the field; the `missing_option` chip
///   sends at once through [onSubmitMissingEvidence].
/// - **single_choice:** rows with descriptions and a radio dot.
/// - **multi_choice:** a two-column card grid, sent as labels joined by ", ".
/// - **scale:** five tiles, sent as "N of 5".
/// - **number:** −/+, an editable big number, a slider, presets and the
///   daily hint. Typed values clamp to the range and snap to the step.
///
/// Structured kinds that allow a custom answer keep a small "Write my own"
/// link to a free-text field.
class IntakeAnswerComposer extends StatefulWidget {
  const IntakeAnswerComposer({
    super.key,
    required this.responseUi,
    required this.onSubmit,
    this.onSubmitMissingEvidence,
    this.initialText,
    this.validationMessage,
    this.maxHeight,
  });

  final InterviewResponseUi responseUi;

  /// Sends one answer exactly as it should be recorded.
  final ValueChanged<String> onSubmit;

  /// Sends the `missing_option` label flagged as missing evidence. Falls back
  /// to [onSubmit] when null.
  final ValueChanged<String>? onSubmitMissingEvidence;

  /// A rejected answer to put back into the field for correction.
  final String? initialText;
  final String? validationMessage;

  /// Height cap; the panel scrolls inside it. Defaults to 55% of the screen.
  final double? maxHeight;

  @override
  State<IntakeAnswerComposer> createState() => _IntakeAnswerComposerState();
}

class _IntakeAnswerComposerState extends State<IntakeAnswerComposer> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _numberText = TextEditingController();
  final FocusNode _numberFocus = FocusNode();
  String? _pick;
  final List<String> _multi = [];
  int? _scale;
  late double _lastNumber;
  bool _custom = false;
  bool _submitted = false;
  bool _showValidation = false;

  InterviewResponseUi get _ui => widget.responseUi;

  static final Color _emberOnInk = Color.lerp(
    AppColors.ember,
    const Color(0xFFFFFFFF),
    0.35,
  )!;

  @override
  void initState() {
    super.initState();
    _numberFocus.addListener(_normalizeNumberOnBlur);
    _reset();
    _showValidation = widget.validationMessage != null;
  }

  @override
  void didUpdateWidget(covariant IntakeAnswerComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.responseUi != widget.responseUi ||
        oldWidget.initialText != widget.initialText) {
      _reset();
    }
    if (oldWidget.validationMessage != widget.validationMessage) {
      _showValidation = widget.validationMessage != null;
    }
  }

  void _reset() {
    _pick = null;
    _multi.clear();
    _scale = null;
    _submitted = false;
    _lastNumber = _ui.initial ?? _ui.min ?? 0;
    _numberText.text = _format(_lastNumber);
    final initialText = widget.initialText ?? '';
    _text.value = TextEditingValue(
      text: initialText,
      selection: TextSelection.collapsed(offset: initialText.length),
    );
    _custom = initialText.isNotEmpty && _ui.kind != InterviewResponseKind.text;
  }

  @override
  void dispose() {
    _text.dispose();
    _numberText.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  // ── Sending ──────────────────────────────────────────────────────────────

  void _submit(String value) {
    final answer = value.trim();
    if (_submitted || answer.isEmpty) return;
    _submitted = true;
    widget.onSubmit(answer);
  }

  void _submitMissing(String option) {
    if (_submitted) return;
    _submitted = true;
    (widget.onSubmitMissingEvidence ?? widget.onSubmit)(option);
  }

  void _useCustomAnswer() => setState(() => _custom = true);

  void _returnToStructuredAnswer() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _custom = false;
      _text.clear();
      _showValidation = false;
    });
  }

  void _onTextChanged(String _) {
    if (_showValidation) setState(() => _showValidation = false);
  }

  // ── Number arithmetic ────────────────────────────────────────────────────

  bool get _hoursUnit =>
      _ui.isWeeklyHours ||
      RegExp(r'\bhours?\b', caseSensitive: false).hasMatch(_ui.unit ?? '');

  /// The typed value, or null when the field is blank or malformed. A comma
  /// decimal ("4,5") reads as 4.5.
  double? get _typed {
    final text = _numberText.text.trim().replaceAll(',', '.');
    if (!RegExp(r'^-?(\d+\.?\d*|\.\d+)$').hasMatch(text)) return null;
    final value = double.tryParse(text);
    return value != null && value.isFinite ? value : null;
  }

  /// The value that would be sent: the typed number clamped to the range and
  /// snapped to the step grid (from `min`). Null blocks sending.
  double? get _effective {
    final typed = _typed;
    return typed == null ? null : _snap(typed);
  }

  /// What the slider, presets and hint show: the sendable value, or the last
  /// valid one while the field is blank or malformed.
  double get _shown => _effective ?? _lastNumber;

  double _snap(double value) {
    final min = _ui.min!;
    final max = _ui.max!;
    final step = _ui.step!;
    final clamped = value.clamp(min, max).toDouble();
    final snapped = min + ((clamped - min) / step).round() * step;
    return ((snapped.clamp(min, max).toDouble()) * 10000).round() / 10000;
  }

  void _setNumber(double value) {
    final snapped = _snap(value);
    setState(() {
      _lastNumber = snapped;
      _numberText.value = TextEditingValue(
        text: _format(snapped),
        selection: TextSelection.collapsed(offset: _format(snapped).length),
      );
    });
  }

  void _onNumberTyped(String _) {
    final effective = _effective;
    setState(() {
      if (effective != null) _lastNumber = effective;
    });
  }

  /// Show the value that will be sent once the user leaves the field.
  void _normalizeNumberOnBlur() {
    if (_numberFocus.hasFocus || !mounted) return;
    final effective = _effective;
    if (effective != null && _format(effective) != _numberText.text) {
      _setNumber(effective);
    }
  }

  String _numberAnswerFor(double number) {
    final value = _format(number);
    if (_ui.isWeeklyHours) {
      return number == 1 ? '1 hour a week' : '$value hours a week';
    }
    final unit = _ui.unit;
    return unit == null ? value : '$value $unit';
  }

  static String _format(double value) {
    if ((value - value.round()).abs() < 0.000001) {
      return value.round().toString();
    }
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  // ── Build ────────────────────────────────────────────────────────────────

  Duration get _motion => MotionConfig.enabled(context)
      ? const Duration(milliseconds: 250)
      : Duration.zero;

  @override
  Widget build(BuildContext context) {
    final maxHeight =
        widget.maxHeight ?? MediaQuery.sizeOf(context).height * 0.55;
    final Widget body = _custom
        ? _textComposer(key: const ValueKey('custom-answer'), custom: true)
        : switch (_ui.kind) {
            InterviewResponseKind.text => _textComposer(
              key: const ValueKey('text-answer'),
            ),
            InterviewResponseKind.singleChoice => _choiceComposer(),
            InterviewResponseKind.multiChoice => _multiComposer(),
            InterviewResponseKind.scale => _scaleComposer(),
            InterviewResponseKind.number => _numberComposer(),
          };
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        // Switching to "Write my own" swaps at once (the structured control
        // and its field never coexist) and the free-text field rises in.
        child: _custom
            ? V3Rise(
                key: const ValueKey('custom-rise'),
                duration: const Duration(milliseconds: 300),
                offset: 8,
                child: body,
              )
            : body,
      ),
    );
  }

  /// Whether the number control counts time (hours or minutes): only then
  /// does its header show the clock.
  bool get _timeUnit =>
      _hoursUnit ||
      RegExp(
        r'\b(hours?|hrs?|minutes?|mins?)\b',
        caseSensitive: false,
      ).hasMatch(_ui.unit ?? '');

  Widget _kicker(InterviewResponseKind kind) {
    final (label, icon) = switch (kind) {
      // Without starting-point chips there is nothing to pick from.
      InterviewResponseKind.text => (
        _ui.suggestions.isEmpty
            ? 'Type your answer'
            : 'Type or pick a starting point',
        V3Icons.edit,
      ),
      InterviewResponseKind.singleChoice => ('Choose one', V3Icons.target),
      InterviewResponseKind.multiChoice => (
        'Choose any that fit',
        V3Icons.list,
      ),
      InterviewResponseKind.scale => ('Rate 1 to 5', V3Icons.sliders),
      InterviewResponseKind.number => (
        'Set a number',
        _timeUnit ? V3Icons.clock : V3Icons.list,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          V3Icon(icon, size: 13, color: AppColors.ink3),
          const SizedBox(width: 6),
          Flexible(child: Text(label.toUpperCase(), style: AppTypography.kick)),
        ],
      ),
    );
  }

  /// The subtle free-text escape under a structured control.
  Widget _writeOwnLink() {
    if (!_ui.allowCustom || _ui.kind == InterviewResponseKind.scale) {
      return const SizedBox(height: 12);
    }
    return Align(
      alignment: Alignment.centerRight,
      child: V3Pressable(
        key: const ValueKey('intake-write-own'),
        onTap: _useCustomAnswer,
        focusRadius: AppRadii.br8,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const V3Icon(V3Icons.edit, size: 13, color: AppColors.ink3),
              const SizedBox(width: 5),
              Text(
                'Write my own',
                style: AppTypography.sans(
                  12.5,
                  FontWeight.w500,
                ).copyWith(color: AppColors.ink3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backLink() {
    final label = switch (_ui.kind) {
      InterviewResponseKind.number => 'Back to number picker',
      InterviewResponseKind.scale => 'Back to the scale',
      _ => 'Back to choices',
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: V3Pressable(
        onTap: _returnToStructuredAnswer,
        focusRadius: AppRadii.br8,
        child: Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const V3Icon(V3Icons.left, size: 15, color: AppColors.ink2),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTypography.sans(
                  12.5,
                  FontWeight.w600,
                ).copyWith(color: AppColors.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sendButton({
    required String label,
    required bool enabled,
    required VoidCallback onSend,
  }) {
    final active = enabled && !_submitted;
    return V3Button(
      key: const ValueKey('intake-answer-submit'),
      full: true,
      disabled: !active,
      onPressed: active ? onSend : null,
      child: Text(label),
    );
  }

  // ── text ─────────────────────────────────────────────────────────────────

  Widget _textComposer({Key? key, bool custom = false}) {
    final missing = custom ? null : _ui.missingOption;
    final chips = custom ? const <String>[] : _ui.suggestions;
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (custom) _backLink() else _kicker(InterviewResponseKind.text),
        if (chips.isNotEmpty || missing != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    V3Chip(
                      key: ValueKey('intake-suggestion-$i'),
                      onPressed: () => _fillSuggestion(chips[i]),
                      child: Text(chips[i]),
                    ),
                  ],
                  if (missing != null) ...[
                    if (chips.isNotEmpty) const SizedBox(width: 8),
                    V3Chip(
                      key: const ValueKey('intake-missing-option'),
                      onPressed: _submitted
                          ? null
                          : () => _submitMissing(missing),
                      child: Text(missing),
                    ),
                  ],
                ],
              ),
            ),
          ),
        _textPill(),
        if (_showValidation && widget.validationMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Text(
              widget.validationMessage!,
              style: AppTypography.sans(
                12.5,
                FontWeight.w500,
              ).copyWith(color: AppColors.danger, height: 1.4),
            ),
          ),
      ],
    );
  }

  void _fillSuggestion(String suggestion) {
    _text.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    _onTextChanged(suggestion);
  }

  Widget _textPill() {
    final largeText = MediaQuery.textScalerOf(context).scale(15.5) > 22;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: AppColors.hair),
      ),
      child: TextFieldTapRegion(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('intake-text-input'),
                controller: _text,
                minLines: 1,
                maxLines: largeText ? 2 : 4,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                // Leave the question visible until the user chooses to type;
                // opening the keyboard on every turn hides it on small phones.
                autofocus: _custom,
                onChanged: _onTextChanged,
                onSubmitted: _submit,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                style: AppTypography.sans(
                  15.5,
                ).copyWith(color: AppColors.ink, height: 1.35),
                cursorColor: AppColors.ember,
                decoration: InputDecoration(
                  hintText: _ui.placeholder,
                  hintStyle: AppTypography.sans(
                    15.5,
                  ).copyWith(color: AppColors.ink3),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  isDense: true,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _text,
              builder: (context, value, _) {
                final enabled = value.text.trim().isNotEmpty && !_submitted;
                return V3Pressable(
                  key: const ValueKey('intake-text-submit'),
                  semanticLabel: 'Send',
                  onTap: enabled ? () => _submit(_text.text) : null,
                  child: AnimatedContainer(
                    duration: _motion,
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: enabled ? AppColors.ember : AppColors.paper2,
                      shape: BoxShape.circle,
                    ),
                    child: V3Icon(
                      V3Icons.send,
                      size: 18,
                      strokeWidth: 2.2,
                      color: enabled ? Colors.white : AppColors.ink3,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── single_choice ────────────────────────────────────────────────────────

  Widget _choiceComposer() {
    return Column(
      key: const ValueKey('choice-answer'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kicker(InterviewResponseKind.singleChoice),
        for (var i = 0; i < _ui.options.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: _OptionRow(
              key: ValueKey('intake-choice-$i'),
              label: _ui.options[i],
              detail: _ui.detailAt(i),
              on: _pick == _ui.options[i],
              motion: _motion,
              onTap: () => setState(() => _pick = _ui.options[i]),
            ),
          ),
        _writeOwnLink(),
        _sendButton(
          label: 'Send answer',
          enabled: _pick != null,
          onSend: () => _submit(_pick ?? ''),
        ),
      ],
    );
  }

  // ── multi_choice ─────────────────────────────────────────────────────────

  Widget _multiComposer() {
    final options = _ui.options;
    final count = _multi.length;
    final atMax = _ui.maxSelected != null && count >= _ui.maxSelected!;
    final ready =
        count >= _ui.minSelected &&
        (_ui.maxSelected == null || count <= _ui.maxSelected!);
    final label = count >= _ui.minSelected && count > 0
        ? 'Send $count selected'
        : _ui.minSelected <= 1
        ? 'Select at least one'
        : 'Select at least ${_ui.minSelected}';

    Widget card(int i) {
      final option = options[i];
      final on = _multi.contains(option);
      return _MultiCard(
        key: ValueKey('intake-multi-$i'),
        label: option,
        icon: _ui.detailAt(i).icon,
        on: on,
        dimmed: atMax && !on,
        iconOnColor: _emberOnInk,
        motion: _motion,
        onTap: on
            ? () => setState(() => _multi.remove(option))
            : atMax
            ? null
            : () => setState(() => _multi.add(option)),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < options.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: i + 1 < options.length
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: card(i)),
                      const SizedBox(width: 8),
                      Expanded(child: card(i + 1)),
                    ],
                  ),
                )
              // An odd last card spans both columns.
              : card(i),
        ),
      );
    }

    return Column(
      key: const ValueKey('multi-answer'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kicker(InterviewResponseKind.multiChoice),
        ...rows,
        _writeOwnLink(),
        _sendButton(
          label: label,
          enabled: ready,
          // Sent in the options' order, joined as the server parses them.
          onSend: () => _submit(options.where(_multi.contains).join(', ')),
        ),
      ],
    );
  }

  // ── scale ────────────────────────────────────────────────────────────────

  Widget _scaleComposer() {
    final pick = _scale;
    return Column(
      key: const ValueKey('scale-answer'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kicker(InterviewResponseKind.scale),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: v3Card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  for (var v = 1; v <= 5; v++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: v == 1 ? 0 : 8),
                        child: _ScaleTile(
                          key: ValueKey('intake-scale-$v'),
                          value: v,
                          on: pick == v,
                          below: pick != null && v < pick,
                          motion: _motion,
                          onTap: () => setState(() => _scale = v),
                        ),
                      ),
                    ),
                ],
              ),
              if (_ui.lowLabel != null || _ui.highLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _ui.lowLabel ?? '',
                          style: AppTypography.sans(
                            12,
                          ).copyWith(color: AppColors.ink3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _ui.highLabel ?? '',
                          textAlign: TextAlign.end,
                          style: AppTypography.sans(
                            12,
                          ).copyWith(color: AppColors.ink3),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _writeOwnLink(),
        _sendButton(
          label: 'Send answer',
          enabled: pick != null,
          onSend: () => _submit('$pick of 5'),
        ),
      ],
    );
  }

  // ── number ───────────────────────────────────────────────────────────────

  Widget _numberComposer() {
    final min = _ui.min!;
    final max = _ui.max!;
    final step = _ui.step!;
    final shown = _shown;
    final effective = _effective;
    final canDecrease = shown > min + 0.000001;
    final canIncrease = shown < max - 0.000001;
    final suffix = _hoursUnit ? ' h' : '';
    final unit = _ui.unit;
    final divisions = ((max - min) / step).round();
    final labelStyle = AppTypography.sans(
      11.5,
    ).merge(AppTypography.tnum).copyWith(color: AppColors.ink3);

    return Column(
      key: const ValueKey('number-answer'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kicker(InterviewResponseKind.number),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: v3Card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _stepButton(
                    key: const ValueKey('intake-number-minus'),
                    icon: V3Icons.minus,
                    label: _hoursUnit ? 'Fewer hours' : 'Decrease number',
                    onTap: canDecrease ? () => _setNumber(shown - step) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          label: _hoursUnit
                              ? 'Hours per week'
                              : (unit ?? 'Number'),
                          child: TextField(
                            key: const ValueKey('intake-number-input'),
                            controller: _numberText,
                            focusNode: _numberFocus,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.numberWithOptions(
                              decimal: true,
                              signed: min < 0,
                            ),
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(min < 0 ? r'[0-9.,\-]' : r'[0-9.,]'),
                              ),
                              LengthLimitingTextInputFormatter(9),
                            ],
                            onChanged: _onNumberTyped,
                            onSubmitted: (_) => _normalizeNumberOnBlur(),
                            onTapOutside: (_) => _numberFocus.unfocus(),
                            cursorColor: AppColors.ember,
                            style: AppTypography.display(58)
                                .merge(AppTypography.tnum)
                                .copyWith(color: AppColors.ink, height: 1.1),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (unit != null)
                          Text(
                            unit,
                            textAlign: TextAlign.center,
                            style: AppTypography.sans(
                              12.5,
                              FontWeight.w600,
                            ).copyWith(color: AppColors.ink3),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _stepButton(
                    key: const ValueKey('intake-number-plus'),
                    icon: V3Icons.plus,
                    label: _hoursUnit ? 'More hours' : 'Increase number',
                    onTap: canIncrease ? () => _setNumber(shown + step) : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Semantics(
                key: const ValueKey('intake-number-adjustable'),
                container: true,
                excludeSemantics: true,
                slider: true,
                liveRegion: true,
                label: 'Selected number',
                value: _numberAnswerFor(shown),
                increasedValue: canIncrease
                    ? _numberAnswerFor(_snap(shown + step))
                    : null,
                decreasedValue: canDecrease
                    ? _numberAnswerFor(_snap(shown - step))
                    : null,
                onIncrease: canIncrease ? () => _setNumber(shown + step) : null,
                onDecrease: canDecrease ? () => _setNumber(shown - step) : null,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.ember,
                    inactiveTrackColor: AppColors.hair,
                    thumbColor: AppColors.ember,
                    overlayColor: AppColors.ember.withValues(alpha: 0.12),
                    trackHeight: 4,
                    showValueIndicator: ShowValueIndicator.never,
                    tickMarkShape: SliderTickMarkShape.noTickMark,
                  ),
                  child: Slider(
                    key: const ValueKey('intake-number-slider'),
                    value: shown.clamp(min, max).toDouble(),
                    min: min,
                    max: max,
                    divisions: divisions > 0 ? divisions : null,
                    onChanged: _setNumber,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_format(min)}$suffix', style: labelStyle),
                    Text('${_format(max)}$suffix', style: labelStyle),
                  ],
                ),
              ),
              if (_ui.presets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      for (var i = 0; i < _ui.presets.length; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                            child: _PresetPill(
                              key: ValueKey('intake-number-preset-$i'),
                              label: '${_format(_ui.presets[i])}$suffix',
                              on: effective == _ui.presets[i],
                              motion: _motion,
                              onTap: () => _setNumber(_ui.presets[i]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (_ui.dailyHint) _dailyHint(shown),
            ],
          ),
        ),
        _writeOwnLink(),
        _sendButton(
          label: 'Send answer',
          enabled: effective != null,
          onSend: () {
            final value = _effective;
            if (value != null) _submit(_numberAnswerFor(value));
          },
        ),
      ],
    );
  }

  Widget _dailyHint(double hoursPerWeek) {
    final perDay = (hoursPerWeek * 60 / 7).round();
    return Container(
      key: const ValueKey('intake-daily-hint'),
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: AppRadii.br12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: V3Icon(V3Icons.calendar, size: 15, color: AppColors.ember),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'About '),
                  TextSpan(
                    text: '$perDay min a day',
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: ' · your plan’s workload will fit this'),
                ],
              ),
              style: AppTypography.sans(13)
                  .merge(AppTypography.tnum)
                  .copyWith(color: AppColors.ink2, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required Key key,
    required V3Icons icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return AnimatedOpacity(
      key: key,
      duration: _motion,
      opacity: onTap == null ? 0.38 : 1,
      child: V3IconButton(icon: icon, label: label, size: 48, onPressed: onTap),
    );
  }
}

/// A single-choice row (the design's `Opt`): optional icon, label, optional
/// description and a radio dot that fills ember when selected.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.label,
    required this.detail,
    required this.on,
    required this.motion,
    required this.onTap,
  });

  final String label;
  final InterviewOptionDetail detail;
  final bool on;
  final Duration motion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = detail.icon;
    final description = detail.description;
    // A radio button: one option of the question can be picked.
    return V3Pressable(
      onTap: onTap,
      checked: on,
      inMutuallyExclusiveGroup: true,
      button: false,
      minTapTarget: 0,
      pressedScale: 0.98,
      focusRadius: AppRadii.br16,
      child: AnimatedContainer(
        duration: motion,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: on ? AppColors.ink : AppColors.card,
          borderRadius: AppRadii.br16,
          border: Border.all(color: on ? AppColors.ink : AppColors.hair),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              V3Icon(
                V3Icons.fromName(icon),
                size: 18,
                color: on ? Colors.white : AppColors.ink2,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTypography.sans(
                      15,
                      FontWeight.w500,
                    ).copyWith(color: on ? Colors.white : AppColors.ink),
                  ),
                  if (description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        description,
                        style: AppTypography.sans(12.5).copyWith(
                          color: on
                              ? Colors.white.withValues(alpha: 0.65)
                              : AppColors.ink3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Mark(on: on, square: false, size: 22, motion: motion),
          ],
        ),
      ),
    );
  }
}

/// One multi-choice card: icon top-left, label at the bottom, a square check
/// top-right.
class _MultiCard extends StatelessWidget {
  const _MultiCard({
    super.key,
    required this.label,
    required this.icon,
    required this.on,
    required this.dimmed,
    required this.iconOnColor,
    required this.motion,
    required this.onTap,
  });

  final String label;
  final String? icon;
  final bool on;
  final bool dimmed;
  final Color iconOnColor;
  final Duration motion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final iconName = icon;
    return AnimatedOpacity(
      duration: motion,
      opacity: dimmed ? 0.5 : 1,
      child: V3Pressable(
        onTap: onTap,
        checked: on,
        minTapTarget: 0,
        pressedScale: 0.97,
        focusRadius: const BorderRadius.all(Radius.circular(18)),
        child: AnimatedContainer(
          duration: motion,
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: on ? AppColors.ink : AppColors.card,
            borderRadius: const BorderRadius.all(Radius.circular(18)),
            border: Border.all(color: on ? AppColors.ink : AppColors.hair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (iconName != null)
                    V3Icon(
                      V3Icons.fromName(iconName),
                      size: 20,
                      color: on ? iconOnColor : AppColors.ink2,
                    )
                  else
                    const SizedBox(height: 20),
                  const Spacer(),
                  // The design's check sits 12 pt from the card's corner.
                  Transform.translate(
                    offset: const Offset(2, -2),
                    child: _Mark(
                      on: on,
                      square: true,
                      size: 20,
                      motion: motion,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  label,
                  style: AppTypography.sans(
                    14.5,
                    FontWeight.w600,
                  ).copyWith(color: on ? Colors.white : AppColors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The radio dot / square check: hair outline when off, ember with a white
/// check (popping in on the design's spring) when on.
class _Mark extends StatelessWidget {
  const _Mark({
    required this.on,
    required this.square,
    required this.size,
    required this.motion,
  });

  final bool on;
  final bool square;
  final double size;
  final Duration motion;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: motion,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? AppColors.ember : Colors.transparent,
        borderRadius: BorderRadius.circular(square ? 6 : size / 2),
        border: on ? null : Border.all(color: AppColors.hair2, width: 1.5),
      ),
      child: on
          ? V3Pop(
              child: V3Icon(
                V3Icons.check,
                size: size * 0.6,
                strokeWidth: 3,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}

/// One 56 pt scale tile; tiles below the pick are tinted ember-soft and the
/// pick is lifted.
class _ScaleTile extends StatelessWidget {
  const _ScaleTile({
    super.key,
    required this.value,
    required this.on,
    required this.below,
    required this.motion,
    required this.onTap,
  });

  final int value;
  final bool on;
  final bool below;
  final Duration motion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A radio button: one value of the scale can be picked.
    return V3Pressable(
      onTap: onTap,
      checked: on,
      inMutuallyExclusiveGroup: true,
      button: false,
      minTapTarget: 0,
      semanticLabel: '$value of 5',
      focusRadius: AppRadii.br16,
      child: AnimatedContainer(
        duration: motion,
        curve: AppMotion.out,
        height: 56,
        alignment: Alignment.center,
        transform: Matrix4.translationValues(0, on ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: on
              ? AppColors.ink
              : below
              ? AppColors.emberSoft
              : AppColors.paper,
          borderRadius: AppRadii.br16,
          boxShadow: on
              ? const [
                  BoxShadow(
                    color: Color(0x80000000),
                    offset: Offset(0, 10),
                    blurRadius: 20,
                    spreadRadius: -10,
                  ),
                ]
              : null,
        ),
        child: Text(
          '$value',
          style: AppTypography.sans(20, FontWeight.w600)
              .merge(AppTypography.tnum)
              .copyWith(color: on ? Colors.white : AppColors.ink),
        ),
      ),
    );
  }
}

class _PresetPill extends StatelessWidget {
  const _PresetPill({
    super.key,
    required this.label,
    required this.on,
    required this.motion,
    required this.onTap,
  });

  final String label;
  final bool on;
  final Duration motion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return V3Pressable(
      onTap: onTap,
      selected: on,
      child: AnimatedContainer(
        duration: motion,
        width: double.infinity,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.ink : AppColors.paper,
          borderRadius: AppRadii.brFull,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: AppTypography.sans(13, FontWeight.w600)
              .merge(AppTypography.tnum)
              .copyWith(color: on ? Colors.white : AppColors.ink2),
        ),
      ),
    );
  }
}
