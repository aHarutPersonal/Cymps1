import 'package:flutter/material.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../../core/ui/motion/motion_config.dart';
import '../../../session/models/interview_response_ui.dart';

/// Chat-native composer for one validated interview response request.
///
/// Choice and number answers require confirmation because they directly shape
/// the generated plan. Every structured control can switch back to free text,
/// preserving nuance when the suggested answers do not fit.
class IntakeAnswerComposer extends StatefulWidget {
  const IntakeAnswerComposer({
    super.key,
    required this.responseUi,
    required this.onSubmit,
    this.initialText,
    this.validationMessage,
  });

  final InterviewResponseUi responseUi;
  final ValueChanged<String> onSubmit;
  final String? initialText;
  final String? validationMessage;

  @override
  State<IntakeAnswerComposer> createState() => _IntakeAnswerComposerState();
}

class _IntakeAnswerComposerState extends State<IntakeAnswerComposer> {
  final TextEditingController _text = TextEditingController();
  String? _selectedChoice;
  late double _number;
  bool _custom = false;
  bool _submitted = false;
  bool _showValidation = false;

  @override
  void initState() {
    super.initState();
    _number = widget.responseUi.initial ?? widget.responseUi.min ?? 0;
    _restoreTextDraft();
    _showValidation = widget.validationMessage != null;
  }

  @override
  void didUpdateWidget(covariant IntakeAnswerComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.responseUi != widget.responseUi ||
        oldWidget.initialText != widget.initialText) {
      _selectedChoice = null;
      _number = widget.responseUi.initial ?? widget.responseUi.min ?? 0;
      _restoreTextDraft();
      _submitted = false;
    }
    if (oldWidget.validationMessage != widget.validationMessage) {
      _showValidation = widget.validationMessage != null;
    }
  }

  void _restoreTextDraft() {
    final initialText = widget.initialText ?? '';
    _text.value = TextEditingValue(
      text: initialText,
      selection: TextSelection.collapsed(offset: initialText.length),
    );
    _custom =
        initialText.isNotEmpty &&
        widget.responseUi.kind != InterviewResponseKind.text;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final answer = value.trim();
    if (_submitted || answer.isEmpty) return;
    _submitted = true;
    widget.onSubmit(answer);
  }

  void _useCustomAnswer() {
    setState(() => _custom = true);
  }

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

  @override
  Widget build(BuildContext context) {
    final duration = MotionConfig.enabled(context)
        ? AppDurations.fast
        : Duration.zero;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppCurves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _custom
          ? _textComposer(
              key: const ValueKey('custom-answer'),
              showStructuredBack: true,
            )
          : switch (widget.responseUi.kind) {
              InterviewResponseKind.singleChoice => _choiceComposer(),
              InterviewResponseKind.number => _numberComposer(),
              InterviewResponseKind.text => _textComposer(
                key: const ValueKey('text-answer'),
              ),
            },
    );
  }

  Widget _textComposer({Key? key, bool showStructuredBack = false}) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showStructuredBack) ...[
          _modeButton(
            icon: Icons.arrow_back_rounded,
            label: widget.responseUi.kind == InterviewResponseKind.singleChoice
                ? 'Back to choices'
                : 'Back to number picker',
            onTap: _returnToStructuredAnswer,
          ),
          const SizedBox(height: 7),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.hair2, width: 1.5),
          ),
          padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
          child: TextFieldTapRegion(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('intake-text-input'),
                    controller: _text,
                    minLines: 1,
                    maxLines: 5,
                    autofocus: true,
                    onChanged: _onTextChanged,
                    textAlignVertical: TextAlignVertical.center,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    style: AppTypography.body.copyWith(fontSize: 15.5),
                    cursorColor: AppColors.green,
                    decoration: InputDecoration(
                      hintText: widget.responseUi.placeholder,
                      errorText: _showValidation
                          ? widget.validationMessage
                          : null,
                      errorMaxLines: 2,
                      border: InputBorder.none,
                      isDense: true,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _text,
                  builder: (_, value, _) {
                    final enabled = value.text.trim().isNotEmpty && !_submitted;
                    return CmpysPressable(
                      key: const ValueKey('intake-text-submit'),
                      semanticLabel: 'Send answer',
                      haptic: CmpysHaptic.light,
                      onTap: enabled ? () => _submit(_text.text) : null,
                      child: AnimatedContainer(
                        duration: MotionConfig.enabled(context)
                            ? AppDurations.fast
                            : Duration.zero,
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.only(bottom: 1),
                        decoration: BoxDecoration(
                          color: enabled ? AppColors.green : AppColors.hair2,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_upward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _choiceComposer() {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.4;
    return ConstrainedBox(
      key: const ValueKey('choice-answer'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('CHOOSE ONE', style: AppTypography.kicker),
                Text(
                  'Tap, then send',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ink3,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  for (
                    var index = 0;
                    index < widget.responseUi.options.length;
                    index++
                  )
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                      ),
                      child: CmpysChipPill(
                        key: ValueKey('intake-choice-$index'),
                        label: widget.responseUi.options[index],
                        active:
                            _selectedChoice == widget.responseUi.options[index],
                        onTap: () => setState(
                          () => _selectedChoice =
                              widget.responseUi.options[index],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _confirmationRow(
              customLabel: 'Write my own',
              canSubmit: _selectedChoice != null,
              onSubmit: () => _submit(_selectedChoice ?? ''),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberComposer() {
    final min = widget.responseUi.min!;
    final max = widget.responseUi.max!;
    final step = widget.responseUi.step!;
    final canDecrease = _number > min + 0.000001;
    final canIncrease = _number < max - 0.000001;
    final unit = widget.responseUi.unit;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.4;

    return ConstrainedBox(
      key: const ValueKey('number-answer'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('CHOOSE A NUMBER', style: AppTypography.kicker),
                Text(
                  '${_formatNumber(min)}–${_formatNumber(max)}${unit == null ? '' : ' $unit'}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ink3,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Semantics(
              key: const ValueKey('intake-number-adjustable'),
              container: true,
              excludeSemantics: true,
              slider: true,
              liveRegion: true,
              label: 'Selected number',
              value: _numberAnswer,
              increasedValue: canIncrease
                  ? _numberAnswerFor(_clampNumber(_number + step, min, max))
                  : null,
              decreasedValue: canDecrease
                  ? _numberAnswerFor(_clampNumber(_number - step, min, max))
                  : null,
              onIncrease: canIncrease
                  ? () => setState(
                      () => _number = _clampNumber(_number + step, min, max),
                    )
                  : null,
              onDecrease: canDecrease
                  ? () => setState(
                      () => _number = _clampNumber(_number - step, min, max),
                    )
                  : null,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.hair2, width: 1.5),
                ),
                child: Row(
                  children: [
                    _numberButton(
                      key: const ValueKey('intake-number-minus'),
                      semanticLabel: 'Decrease number',
                      icon: Icons.remove_rounded,
                      background: AppColors.paper2,
                      foreground: AppColors.ink,
                      enabled: canDecrease,
                      onTap: () => setState(
                        () => _number = _clampNumber(_number - step, min, max),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatNumber(_number),
                              key: const ValueKey('intake-number-value'),
                              style: AppTypography.monoNum.copyWith(
                                fontSize: 30,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (unit != null)
                              Text(
                                unit,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.ink3,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _numberButton(
                      key: const ValueKey('intake-number-plus'),
                      semanticLabel: 'Increase number',
                      icon: Icons.add_rounded,
                      background: AppColors.greenSoft,
                      foreground: AppColors.green2,
                      enabled: canIncrease,
                      onTap: () => setState(
                        () => _number = _clampNumber(_number + step, min, max),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _confirmationRow(
              customLabel: 'Type instead',
              canSubmit: true,
              onSubmit: () => _submit(_numberAnswer),
            ),
          ],
        ),
      ),
    );
  }

  Widget _confirmationRow({
    required String customLabel,
    required bool canSubmit,
    required VoidCallback onSubmit,
  }) {
    final customButton = _modeButton(
      icon: Icons.edit_outlined,
      label: customLabel,
      onTap: _useCustomAnswer,
    );
    final submitButton = CmpysButton(
      key: const ValueKey('intake-answer-submit'),
      onTap: canSubmit && !_submitted ? onSubmit : null,
      disabled: !canSubmit || _submitted,
      size: CmpysBtnSize.sm,
      trailingIcon: Icons.arrow_upward_rounded,
      child: const Text('Send answer'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledActionFont = MediaQuery.textScalerOf(context).scale(14);
        if (constraints.maxWidth < 340 || scaledActionFont > 18) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.responseUi.allowCustom) ...[
                Align(alignment: Alignment.centerLeft, child: customButton),
                const SizedBox(height: 6),
              ],
              CmpysButton(
                key: const ValueKey('intake-answer-submit'),
                onTap: canSubmit && !_submitted ? onSubmit : null,
                disabled: !canSubmit || _submitted,
                size: CmpysBtnSize.sm,
                full: true,
                trailingIcon: Icons.arrow_upward_rounded,
                child: const Text('Send answer'),
              ),
            ],
          );
        }
        return Row(
          children: [
            if (widget.responseUi.allowCustom) customButton,
            const Spacer(),
            submitButton,
          ],
        );
      },
    );
  }

  Widget _modeButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return CmpysPressable(
      semanticLabel: label,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.ink2),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTypography.captionMedium.copyWith(
                color: AppColors.ink2,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberButton({
    required Key key,
    required String semanticLabel,
    required IconData icon,
    required Color background,
    required Color foreground,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: CmpysPressable(
        key: key,
        semanticLabel: semanticLabel,
        haptic: CmpysHaptic.selection,
        onTap: enabled ? onTap : null,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 21, color: foreground),
        ),
      ),
    );
  }

  String get _numberAnswer {
    return _numberAnswerFor(_number);
  }

  String _numberAnswerFor(double number) {
    final value = _formatNumber(number);
    final unit = widget.responseUi.unit;
    return unit == null ? value : '$value $unit';
  }

  static double _clampNumber(double value, double min, double max) {
    final clamped = value.clamp(min, max).toDouble();
    return (clamped * 10000).round() / 10000;
  }

  static String _formatNumber(double value) {
    if ((value - value.round()).abs() < 0.000001) {
      return value.round().toString();
    }
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
