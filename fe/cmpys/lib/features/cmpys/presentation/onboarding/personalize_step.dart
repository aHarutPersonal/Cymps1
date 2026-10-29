import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/motion/motion_config.dart';
import '../../../../core/ui/v3/v3.dart';
import '../../data/cmpys_seed.dart';

/// Personal context (`v3/onboard.jsx` Context): four steps with a 4-segment
/// progress bar and an "N / 4" counter.
///
/// 1. name and age (a horizontal snapping [CmpysAgeWheel], 14–80)
/// 2. interests
/// 3. a free-text goal, with three starting points
/// 4. situation chips and an optional note
///
/// Everything is written onto [draft]; the flow sends it to the server when
/// discovery creates the session. Continue stays disabled until the step is
/// valid, and the last step's button reads "Find my mentors".
class CmpysPersonalizeStep extends StatefulWidget {
  const CmpysPersonalizeStep({
    super.key,
    required this.draft,
    required this.onUpdate,
    required this.onDone,
    this.onBack,
  });

  final CmpysOnboardingDraft draft;
  final ValueChanged<CmpysOnboardingDraft> onUpdate;
  final VoidCallback onDone;

  /// What Back does on the first step. Null (as in the onboarding flow today)
  /// shows no back button there.
  final VoidCallback? onBack;

  @override
  State<CmpysPersonalizeStep> createState() => _CmpysPersonalizeStepState();
}

class _CmpysPersonalizeStepState extends State<CmpysPersonalizeStep> {
  static const int _steps = 4;

  int _step = 0;
  int _dir = 1;

  late final TextEditingController _name = TextEditingController(
    text: widget.draft.name,
  );
  late final TextEditingController _goal = TextEditingController(
    text: widget.draft.goal,
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.draft.situationNote,
  );

  CmpysOnboardingDraft get _draft => widget.draft;

  @override
  void initState() {
    super.initState();
    // A resumed or default age must land on the wheel.
    _draft.age = _draft.age.clamp(CmpysAgeWheel.minAge, CmpysAgeWheel.maxAge);
  }

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _valid => switch (_step) {
    0 => _draft.name.trim().isNotEmpty,
    1 => _draft.interests.isNotEmpty,
    2 => _draft.goal.trim().length > 4,
    _ => true,
  };

  void _touched() {
    widget.onUpdate(_draft);
    setState(() {});
  }

  void _next() {
    if (!_valid) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_step < _steps - 1) {
      setState(() {
        _dir = 1;
        _step += 1;
      });
    } else {
      widget.onDone();
    }
  }

  void _back() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_step == 0) {
      widget.onBack?.call();
      return;
    }
    setState(() {
      _dir = -1;
      _step -= 1;
    });
  }

  void _toggle(Set<String> values, String value) {
    if (!values.remove(value)) values.add(value);
    _touched();
  }

  void _setGoal(String value) {
    _draft.goal = value;
    _draft.goalId = cmpysGoalIdForText(value);
    _touched();
  }

  void _pickGoal(String value) {
    FocusManager.instance.primaryFocus?.unfocus();
    _goal.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _setGoal(value);
  }

  @override
  Widget build(BuildContext context) {
    final canLeave = _step > 0 || widget.onBack != null;
    return PopScope(
      // The system back gesture steps back through the questions first.
      canPop: !canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: DefaultTextStyle(
        style: AppTypography.sans(16).copyWith(color: AppColors.ink),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gutter = math.max(24.0, (constraints.maxWidth - 520) / 2);
            return V3FooterScaffold(
              footerHorizontalPadding: gutter,
              topBar: Column(
                children: [
                  V3TopBar(
                    onBack: canLeave ? _back : null,
                    right: Semantics(
                      label: 'Step ${_step + 1} of $_steps',
                      excludeSemantics: true,
                      child: Text(
                        '${_step + 1} / $_steps',
                        style: AppTypography.sans(13, FontWeight.w600)
                            .merge(AppTypography.tnum)
                            .copyWith(color: AppColors.ink3),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: _progress(),
                  ),
                ],
              ),
              body: (context, bottomPadding) => SingleChildScrollView(
                // A new scroll position for each step.
                key: ValueKey('scroll-$_step'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: _StepSlide(
                  key: ValueKey('step-$_step'),
                  direction: _dir,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: _stepBody(gutter),
                  ),
                ),
              ),
              footer: V3Button(
                full: true,
                disabled: !_valid,
                onPressed: _next,
                iconRight: V3Icons.arrowR,
                child: Text(
                  _step == _steps - 1 ? 'Find my mentors' : 'Continue',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── chrome ───────────────────────────────────────────────────────────

  Widget _progress() {
    final motion = MotionConfig.enabled(context);
    return Row(
      children: [
        for (var i = 0; i < _steps; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 4,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.hair,
                borderRadius: BorderRadius.circular(9),
              ),
              child: AnimatedFractionallySizedBox(
                duration: motion
                    ? const Duration(milliseconds: 600)
                    : Duration.zero,
                curve: AppMotion.out,
                alignment: Alignment.centerLeft,
                widthFactor: i <= _step ? 1 : 0,
                heightFactor: 1,
                child: const ColoredBox(color: AppColors.ink),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─── steps ────────────────────────────────────────────────────────────

  Widget _stepBody(double gutter) {
    Widget padded(Widget child, {double top = 0}) => Padding(
      padding: EdgeInsets.fromLTRB(gutter, top, gutter, 0),
      child: child,
    );
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            padded(
              const _Title(
                kicker: 'About you',
                lead: 'Let’s start',
                tail: 'with the basics.',
              ),
            ),
            padded(
              V3Field(
                label: 'First name',
                controller: _name,
                placeholder: 'Your name',
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.givenName],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _next(),
                onChanged: (v) {
                  _draft.name = v;
                  _touched();
                },
              ),
            ),
            padded(
              Text(
                'Age',
                style: AppTypography.sans(
                  12.5,
                  FontWeight.w600,
                ).copyWith(color: AppColors.ink2),
              ),
              top: 26,
            ),
            const SizedBox(height: 10),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 568),
                child: CmpysAgeWheel(
                  value: _draft.age,
                  onChanged: (age) {
                    _draft.age = age;
                    _touched();
                  },
                ),
              ),
            ),
            padded(
              Text(
                'Age is context for comparison: what your mentor had done by '
                '${_draft.age}. It is never used to rank you.',
                style: AppTypography.sans(
                  13,
                ).copyWith(color: AppColors.ink3, height: 1.5),
              ),
              top: 12,
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            padded(
              const _Title(
                kicker: 'Interests',
                lead: 'What pulls',
                tail: 'your attention?',
              ),
            ),
            padded(
              _chips(
                cmpysOnboardingInterests,
                _draft.interests,
                (x) => _toggle(_draft.interests, x),
              ),
            ),
            padded(
              Text(
                'We use these to suggest mentors. Pick as many as you like.',
                style: AppTypography.sans(
                  13,
                ).copyWith(color: AppColors.ink3, height: 1.45),
              ),
              top: 18,
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            padded(
              const _Title(
                kicker: 'Goal',
                lead: 'What do you want',
                tail: 'to be able to do?',
              ),
            ),
            padded(
              V3Field(
                multiline: true,
                rows: 3,
                controller: _goal,
                placeholder: 'A skill, in your own words',
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(cmpysGoalMaxLength),
                ],
                onChanged: _setGoal,
              ),
            ),
            padded(
              Text('Or start from'.toUpperCase(), style: AppTypography.kick),
              top: 22,
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < cmpysOnboardingGoalSuggestions.length; i++)
              padded(
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                  child: V3Rise(
                    delay: Duration(milliseconds: i * 60),
                    child: _goalCard(cmpysOnboardingGoalSuggestions[i]),
                  ),
                ),
              ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            padded(
              const _Title(
                kicker: 'Your situation',
                lead: 'Anything we',
                tail: 'should plan around?',
              ),
            ),
            padded(
              _chips(
                cmpysOnboardingSituations,
                _draft.situation,
                (x) => _toggle(_draft.situation, x),
              ),
            ),
            padded(
              V3Field(
                multiline: true,
                rows: 3,
                controller: _note,
                placeholder: 'Optional: anything else',
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(cmpysSituationNoteMaxLength),
                ],
                onChanged: (v) {
                  _draft.situationNote = v;
                  _touched();
                },
              ),
              top: 18,
            ),
          ],
        );
    }
  }

  Widget _chips(
    List<String> options,
    Set<String> selected,
    ValueChanged<String> onTap,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < options.length; i++)
          // A label wider than the screen (large text, narrow phone)
          // ellipsizes inside the chip.
          V3Rise(
            delay: Duration(milliseconds: i * 35),
            child: V3Chip(
              on: selected.contains(options[i]),
              onPressed: () => onTap(options[i]),
              child: Text(options[i]),
            ),
          ),
      ],
    );
  }

  Widget _goalCard(String goal) {
    final on = _draft.goal == goal;
    return V3Pressable(
      onTap: () => _pickGoal(goal),
      selected: on,
      focusRadius: AppRadii.brR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: v3Card(borderColor: on ? AppColors.ink : AppColors.hair),
        child: Row(
          children: [
            const V3Icon(V3Icons.target, size: 18, color: AppColors.ember),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                goal,
                style: AppTypography.sans(
                  14.5,
                  FontWeight.w500,
                ).copyWith(color: AppColors.ink),
              ),
            ),
            const SizedBox(width: 12),
            const V3Icon(V3Icons.arrowR, size: 16, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

/// `Title` from Context: a kicker over a 40 pt display heading whose second
/// line is italic.
class _Title extends StatelessWidget {
  const _Title({required this.kicker, required this.lead, required this.tail});

  final String kicker;
  final String lead;
  final String tail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Semantics(
        header: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kicker.toUpperCase(), style: AppTypography.kick),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: AppTypography.display(40).copyWith(color: AppColors.ink),
                children: [
                  TextSpan(text: '$lead\n'),
                  TextSpan(
                    text: tail,
                    style: AppTypography.displayItalic(
                      40,
                    ).copyWith(color: AppColors.ink),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The `stepR` / `stepL` keyframes: the step fades in while sliding 40 px in
/// from the side it came from, over .55 s on `--out`. Reduced motion shows it
/// at once.
class _StepSlide extends StatefulWidget {
  const _StepSlide({super.key, required this.direction, required this.child});

  /// 1 slides in from the right (forward), -1 from the left (back).
  final int direction;
  final Widget child;

  @override
  State<_StepSlide> createState() => _StepSlideState();
}

class _StepSlideState extends State<_StepSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.out,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MotionConfig.enabled(context)) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: AnimatedBuilder(
        animation: _curve,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(widget.direction * 40 * (1 - _curve.value), 0),
          child: child,
        ),
      ),
    );
  }
}

/// `AgeWheel` from Context: a horizontal wheel of the ages 14–80 that snaps
/// the nearest number under a 64 pt ink pill. The chosen number is 30 pt white,
/// the rest 20 pt ink3, and both ends fade out.
///
/// It is a [ListWheelScrollView] turned on its side, so it scrolls and snaps
/// on its own (the same job as the design's `scroll-snap-type`). It starts on
/// [value]; after that the wheel owns the position and reports every number it
/// passes through [onChanged]. Screen readers get an adjustable "Age" with
/// increase and decrease actions.
class CmpysAgeWheel extends StatefulWidget {
  const CmpysAgeWheel({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const int minAge = 14;
  static const int maxAge = 80;

  /// Width of one number, in logical pixels (`W` in the design).
  static const double itemWidth = 58;

  /// The age to start on (clamped to 14–80).
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<CmpysAgeWheel> createState() => _CmpysAgeWheelState();
}

class _CmpysAgeWheelState extends State<CmpysAgeWheel> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(
        initialItem:
            widget.value.clamp(CmpysAgeWheel.minAge, CmpysAgeWheel.maxAge) -
            CmpysAgeWheel.minAge,
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _age =>
      widget.value.clamp(CmpysAgeWheel.minAge, CmpysAgeWheel.maxAge);

  void _move(int delta) {
    final target = (_age + delta).clamp(
      CmpysAgeWheel.minAge,
      CmpysAgeWheel.maxAge,
    );
    if (target == _age || !_controller.hasClients) return;
    final item = target - CmpysAgeWheel.minAge;
    if (MotionConfig.enabled(context)) {
      _controller.animateToItem(
        item,
        duration: const Duration(milliseconds: 250),
        curve: AppMotion.out,
      );
    } else {
      _controller.jumpToItem(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = MotionConfig.enabled(context);
    final age = _age;
    final canIncrease = age < CmpysAgeWheel.maxAge;
    final canDecrease = age > CmpysAgeWheel.minAge;
    return Semantics(
      label: 'Age',
      value: '$age',
      slider: true,
      increasedValue: canIncrease ? '${age + 1}' : null,
      decreasedValue: canDecrease ? '${age - 1}' : null,
      onIncrease: canIncrease ? () => _move(1) : null,
      onDecrease: canDecrease ? () => _move(-1) : null,
      excludeSemantics: true,
      child: SizedBox(
        height: 72,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0x00000000),
                  Color(0xFF000000),
                  Color(0xFF000000),
                  Color(0x00000000),
                ],
                stops: [0, 0.25, 0.75, 1],
              ).createShader(bounds),
              child: RotatedBox(
                quarterTurns: 3,
                child: ListWheelScrollView.useDelegate(
                  controller: _controller,
                  itemExtent: CmpysAgeWheel.itemWidth,
                  // Nearly flat: the design's wheel is a plain strip.
                  diameterRatio: 100,
                  perspective: 0.0001,
                  physics: const FixedExtentScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  onSelectedItemChanged: (item) =>
                      widget.onChanged(CmpysAgeWheel.minAge + item),
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: CmpysAgeWheel.maxAge - CmpysAgeWheel.minAge + 1,
                    builder: (context, item) {
                      final number = CmpysAgeWheel.minAge + item;
                      final on = number == age;
                      return RotatedBox(
                        quarterTurns: 1,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: motion
                                ? const Duration(milliseconds: 200)
                                : Duration.zero,
                            curve: Curves.ease,
                            style:
                                AppTypography.sans(
                                      on ? 30 : 20,
                                      FontWeight.w600,
                                    )
                                    .merge(AppTypography.tnum)
                                    .copyWith(
                                      color: on ? Colors.white : AppColors.ink3,
                                    ),
                            child: Text(
                              '$number',
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
