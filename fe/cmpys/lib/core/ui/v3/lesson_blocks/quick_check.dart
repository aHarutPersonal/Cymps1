import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/design_tokens.dart';
import '../../../reading/lesson_fences.dart';
import '../../motion/motion_config.dart';
import '../buttons.dart';
import '../field.dart';
import '../icons.dart';
import '../motion.dart';

/// `QuickCheck` from v3/tutorial.jsx for a `check` fence: a single choice as
/// a 2×2 grid (one tap answers), select-all as square checks plus "Check"
/// (every correct option and no other), or a number field plus "Check"
/// (within the fence's tolerance). A wrong answer shakes, a right one pops,
/// then the explanation and "Quick checks aren’t graded." show. Nothing is
/// sent anywhere.
class QuickCheck extends StatefulWidget {
  const QuickCheck({
    super.key,
    required this.block,
    this.theme = ReaderTheme.light,
  });

  final CheckBlock block;
  final ReaderTheme theme;

  /// The shaking wrapper around a wrong answer (one at a time).
  static const shakeKey = ValueKey('quick-check-shake');

  @override
  State<QuickCheck> createState() => _QuickCheckState();
}

/// The values a typed number can mean, empty when it is not a number.
///
/// - An optional sign (including "−"); spaces are ignored.
/// - "." is the decimal separator ("4.5"); a lone "," is one too ("4,5").
/// - "1,250.5" reads the comma as thousands, and "1.250,5" the dot.
/// - A single comma after a 1–3 digit lead with no leading zero, followed by
///   exactly three digits ("1,250"), is ambiguous: both 1250 and 1.25 are
///   returned, and either may be accepted. Any other single comma is a
///   decimal comma ("0,500" is 0.5, "1234,567" is 1234.567).
List<double> checkNumberReadings(String input) {
  final text = input.replaceAll(RegExp(r'\s'), '').replaceAll('−', '-');
  final match = RegExp(r'^([+-]?)(.+)$').firstMatch(text);
  if (match == null) return const [];
  final negative = match[1] == '-';
  final digits = match[2]!;
  List<double> read(List<String> candidates) => [
    for (final candidate in candidates)
      if (double.tryParse(candidate) case final value? when value.isFinite)
        negative ? -value : value,
  ];

  if (RegExp(r'^(\d+(\.\d*)?|\.\d+)$').hasMatch(digits)) {
    return read([digits]);
  }
  // Thousands groups need a 1–3 digit lead without a leading zero, so
  // "0,500" is 0.5 and "1234,567" is 1234.567 (a decimal comma).
  if (RegExp(r'^[1-9]\d{0,2},\d{3}$').hasMatch(digits)) {
    return read([digits.replaceAll(',', ''), digits.replaceAll(',', '.')]);
  }
  if (RegExp(r'^(\d+(,\d*)?|,\d+)$').hasMatch(digits)) {
    return read([digits.replaceAll(',', '.')]);
  }
  if (RegExp(r'^[1-9]\d{0,2}(,\d{3})+(\.\d*)?$').hasMatch(digits)) {
    return read([digits.replaceAll(',', '')]);
  }
  if (RegExp(r'^[1-9]\d{0,2}(\.\d{3})+(,\d*)?$').hasMatch(digits)) {
    return read([digits.replaceAll('.', '').replaceAll(',', '.')]);
  }
  return const [];
}

class _QuickCheckState extends State<QuickCheck> {
  int? _pick;
  final Set<int> _selected = {};
  final TextEditingController _number = TextEditingController();
  bool? _right;

  CheckBlock get _block => widget.block;
  bool get _answered => _right != null;

  @override
  void initState() {
    super.initState();
    _number.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _choose(int index) {
    if (_answered) return;
    setState(() {
      _pick = index;
      _right = _block.options[index].correct;
    });
  }

  void _checkAll() {
    final correct = {
      for (var i = 0; i < _block.options.length; i++)
        if (_block.options[i].correct) i,
    };
    setState(
      () => _right =
          _selected.length == correct.length && _selected.containsAll(correct),
    );
  }

  void _checkNumber() {
    final readings = checkNumberReadings(_number.text);
    if (readings.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _right = readings.any(_block.numeric!.accepts));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _block.question,
            style: AppTypography.sans(
              15,
              FontWeight.w500,
            ).copyWith(color: theme.fg, height: 1.5),
          ),
          const SizedBox(height: 14),
          switch (_block.kind) {
            CheckKind.single => _grid(theme),
            CheckKind.selectAll => _selectAll(theme),
            CheckKind.numeric => _numeric(theme),
          },
          if (_answered) _feedback(theme),
        ],
      ),
    );
  }

  // ── single choice ─────────────────────────────────────────────────────────

  Widget _grid(ReaderTheme theme) {
    final options = _block.options;
    return Column(
      children: [
        for (var start = 0; start < options.length; start += 2) ...[
          if (start > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (
                  var i = start;
                  i < math.min(start + 2, options.length);
                  i++
                ) ...[
                  if (i > start) const SizedBox(width: 8),
                  Expanded(child: _gridOption(i, theme)),
                ],
                if (start + 1 >= options.length) ...[
                  const SizedBox(width: 8),
                  const Expanded(child: SizedBox()),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _gridOption(int i, ReaderTheme theme) {
    final option = _block.options[i];
    final show = _answered;
    final selected = _pick == i;
    final right = option.correct;
    final long = option.text.runes.length > 24;
    final (border, background) = show && right
        ? (AppColors.sage, AppColors.sageSoft)
        : show && selected
        ? (AppColors.danger, AppColors.dangerSoft)
        : (theme.hair, const Color(0x00000000));
    Widget button = _Pressable(
      onTap: show ? null : () => _choose(i),
      selected: selected,
      label: option.text,
      child: AnimatedContainer(
        duration: _duration(const Duration(milliseconds: 300)),
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Text(
          option.text,
          textAlign: TextAlign.center,
          style: AppTypography.sans(long ? 14 : 16, FontWeight.w600).copyWith(
            color: show && (right || selected) ? AppColors.ink : theme.fg,
            height: 1.3,
          ),
        ),
      ),
    );
    if (show && right) {
      button = V3Pop(
        duration: const Duration(milliseconds: 400),
        child: button,
      );
    } else if (show && selected) {
      button = _Shake(key: QuickCheck.shakeKey, child: button);
    }
    return button;
  }

  // ── select all ────────────────────────────────────────────────────────────

  Widget _selectAll(ReaderTheme theme) {
    final dark = theme == ReaderTheme.dark;
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _block.options.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _squareOption(i, theme),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Select all that apply',
            style: AppTypography.sans(
              12.5,
              FontWeight.w600,
            ).copyWith(color: theme.fg2),
          ),
        ),
        if (_right == false)
          _Shake(key: QuickCheck.shakeKey, sideways: true, child: rows)
        else
          rows,
        if (!_answered) ...[
          const SizedBox(height: 12),
          V3Button(
            size: V3Size.md,
            kind: dark ? V3ButtonKind.light : V3ButtonKind.dark,
            full: true,
            disabled: _selected.isEmpty,
            onPressed: _selected.isEmpty ? null : _checkAll,
            child: const Text('Check'),
          ),
        ],
      ],
    );
  }

  Widget _squareOption(int i, ReaderTheme theme) {
    final option = _block.options[i];
    final checked = _selected.contains(i);
    final show = _answered;
    final (border, background) = show && option.correct
        ? (AppColors.sage, AppColors.sageSoft)
        : show && checked
        ? (AppColors.danger, AppColors.dangerSoft)
        : (checked ? AppColors.ember : theme.hair, const Color(0x00000000));
    final ink = show && (option.correct || checked) ? AppColors.ink : theme.fg;
    Widget row = _Pressable(
      onTap: show
          ? null
          : () => setState(
              () => checked ? _selected.remove(i) : _selected.add(i),
            ),
      checked: checked,
      label: option.text,
      child: AnimatedContainer(
        duration: _duration(const Duration(milliseconds: 300)),
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: _duration(const Duration(milliseconds: 200)),
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: checked ? AppColors.ember : const Color(0x00000000),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: checked ? AppColors.ember : theme.fg2,
                  width: 1.5,
                ),
              ),
              child: checked
                  ? const V3Icon(
                      V3Icons.check,
                      size: 14,
                      strokeWidth: 2.8,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                option.text,
                style: AppTypography.sans(
                  15,
                  FontWeight.w500,
                ).copyWith(color: ink, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
    if (show && _right == true && option.correct) {
      row = V3Pop(duration: const Duration(milliseconds: 400), child: row);
    }
    return row;
  }

  // ── numeric ───────────────────────────────────────────────────────────────

  Widget _numeric(ReaderTheme theme) {
    final dark = theme == ReaderTheme.dark;
    final numeric = _block.numeric!;
    final ready = checkNumberReadings(_number.text).isNotEmpty;
    Widget field = V3Field(
      controller: _number,
      dark: dark,
      enabled: !_answered,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+\-−\s]')),
      ],
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _checkNumber(),
      right: numeric.unit.isEmpty
          ? null
          : Text(
              numeric.unit,
              style: AppTypography.sans(
                14,
                FontWeight.w600,
              ).copyWith(color: dark ? AppColors.nink3 : AppColors.ink3),
            ),
    );
    if (_right == true) {
      field = V3Pop(duration: const Duration(milliseconds: 400), child: field);
    } else if (_right == false) {
      field = _Shake(key: QuickCheck.shakeKey, sideways: true, child: field);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        if (!_answered) ...[
          const SizedBox(height: 12),
          V3Button(
            size: V3Size.md,
            kind: dark ? V3ButtonKind.light : V3ButtonKind.dark,
            full: true,
            disabled: !ready,
            onPressed: ready ? _checkNumber : null,
            child: const Text('Check'),
          ),
        ],
      ],
    );
  }

  // ── feedback ──────────────────────────────────────────────────────────────

  Widget _feedback(ReaderTheme theme) {
    final right = _right!;
    return V3Rise(
      duration: const Duration(milliseconds: 450),
      child: Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: right ? 'Right. ' : 'Not quite. ',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: right ? AppColors.sage2 : AppColors.danger,
                      ),
                    ),
                    TextSpan(text: _block.why),
                  ],
                ),
                style: AppTypography.sans(
                  14,
                ).copyWith(color: theme.fg2, height: 1.5),
              ),
              const SizedBox(height: 6),
              Opacity(
                opacity: .8,
                child: Text(
                  'Quick checks aren’t graded.',
                  style: AppTypography.sans(12).copyWith(color: theme.fg2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Duration _duration(Duration value) =>
      MotionConfig.enabled(context) ? value : Duration.zero;
}

/// A ≥44 pt tap target with button semantics; null [onTap] disables it.
class _Pressable extends StatelessWidget {
  const _Pressable({
    required this.onTap,
    required this.label,
    required this.child,
    this.selected,
    this.checked,
  });

  final VoidCallback? onTap;
  final String label;
  final Widget child;
  final bool? selected;
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      checked: checked,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: child,
        ),
      ),
    );
  }
}

/// The design's `shake .45s` (rotate 0 → −14° → 12° → −8° → 5° → 0), played
/// once when it first builds. [sideways] swaps the rotation for a small
/// horizontal shake on wide rows, where a 14° turn would leave the card.
class _Shake extends StatefulWidget {
  const _Shake({super.key, required this.child, this.sideways = false});

  final Widget child;
  final bool sideways;

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  static const _degrees = [0.0, -14.0, 12.0, -8.0, 5.0, 0.0];
  static const _pixels = [0.0, -8.0, 7.0, -5.0, 3.0, 0.0];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (MotionConfig.enabled(context)) _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _at(List<double> frames, double t) {
    final scaled = t * (frames.length - 1);
    final segment = math.min(scaled.floor(), frames.length - 2);
    final f = Curves.easeInOut.transform(scaled - segment);
    return frames[segment] + (frames[segment + 1] - frames[segment]) * f;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        return widget.sideways
            ? Transform.translate(
                offset: Offset(_at(_pixels, t), 0),
                child: child,
              )
            : Transform.rotate(
                angle: _at(_degrees, t) * math.pi / 180,
                child: child,
              );
      },
    );
  }
}
