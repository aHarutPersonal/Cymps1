import 'package:flutter/material.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../data/cmpys_seed.dart';

/// 3-step personalization: name+age → interests → goal.
class CmpysPersonalizeStep extends StatefulWidget {
  const CmpysPersonalizeStep({
    super.key,
    required this.draft,
    required this.onUpdate,
    required this.onDone,
  });

  final CmpysOnboardingDraft draft;
  final ValueChanged<CmpysOnboardingDraft> onUpdate;
  final VoidCallback onDone;

  @override
  State<CmpysPersonalizeStep> createState() => _CmpysPersonalizeStepState();
}

class _CmpysPersonalizeStepState extends State<CmpysPersonalizeStep> {
  int _step = 0;
  static const int _steps = 3;

  bool get _canNext {
    switch (_step) {
      case 0:
        return widget.draft.name.trim().isNotEmpty;
      case 1:
        return widget.draft.interests.isNotEmpty;
      case 2:
        return widget.draft.goalId != null;
    }
    return false;
  }

  void _next() {
    if (_step < _steps - 1) {
      setState(() => _step += 1);
    } else {
      widget.onDone();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step -= 1);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // top: back + dots + counter
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 14),
              child: Row(
                children: [
                  if (_step > 0)
                    GestureDetector(
                      onTap: _back,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.hair),
                        ),
                        child: const Icon(Icons.chevron_left_rounded,
                            size: 22, color: AppColors.ink),
                      ),
                    ),
                  Expanded(child: _dots()),
                  Text(
                    '${_step + 1}/$_steps',
                    style: AppTypography.kicker,
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: _currentStep(),
              ),
            ),
            const SizedBox(height: 12),
            CmpysButton(
              variant: CmpysBtnVariant.primary,
              size: CmpysBtnSize.lg,
              full: true,
              disabled: !_canNext,
              trailingIcon: Icons.arrow_forward_rounded,
              onTap: _canNext ? _next : null,
              child: Text(_step == _steps - 1 ? 'Find my mentor' : 'Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_steps, (i) {
        final active = i == _step;
        return Padding(
          padding: EdgeInsets.only(right: i == _steps - 1 ? 0 : 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            width: active ? 24 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? AppColors.green : AppColors.hair2,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }

  Widget _currentStep() {
    switch (_step) {
      case 0:
        return _stepName();
      case 1:
        return _stepInterests();
      case 2:
        return _stepGoal();
    }
    return const SizedBox.shrink();
  }

  // ─── Step 1: name + age
  Widget _stepName() {
    return ListView(
      key: const ValueKey('name'),
      padding: const EdgeInsets.only(top: 6),
      children: [
        const CmpysKicker('First, the basics', color: AppColors.green),
        const SizedBox(height: 8),
        // Bricolage Grotesque's `y` + `?` descenders extend further than
        // their declared font metrics. We do two things to keep them clear
        // of the input border below:
        //   1. `height: 1.4` enlarges the text-layout box so the descender
        //      tail renders inside it instead of spilling below.
        //   2. an extra `Padding(bottom: 12)` *plus* a 32px SizedBox gives
        //      explicit whitespace that the descender can't reach.
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'What should we call you?',
            style: AppTypography.h1
                .copyWith(fontSize: 30, letterSpacing: -0.3, height: 1.4),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hair2, width: 1.5),
          ),
          child: TextField(
            autofocus: true,
            onChanged: (v) {
              widget.draft.name = v;
              widget.onUpdate(widget.draft);
              setState(() {});
            },
            style: AppTypography.body.copyWith(fontSize: 16),
            cursorColor: AppColors.green,
            decoration: InputDecoration(
              hintText: 'Your first name',
              hintStyle: AppTypography.body.copyWith(
                fontSize: 16,
                color: AppColors.ink3,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'How old are you? We’ll compare you to your mentor at this exact age.',
          style: AppTypography.bodyDim.copyWith(fontSize: 13.5),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hair2, width: 1.5),
          ),
          child: Row(
            children: [
              _ageStep(
                  icon: '−',
                  bg: AppColors.paper2,
                  fg: AppColors.ink,
                  onTap: () => setState(() {
                        widget.draft.age =
                            widget.draft.age > 16 ? widget.draft.age - 1 : 16;
                      })),
              Expanded(
                child: Center(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: widget.draft.age.toString(),
                          style: AppTypography.display.copyWith(
                            fontSize: 40,
                            height: 1.0,
                          ),
                        ),
                        TextSpan(
                          text: ' years',
                          style: AppTypography.captionMedium.copyWith(
                            color: AppColors.ink3,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _ageStep(
                  icon: '+',
                  bg: AppColors.greenSoft,
                  fg: AppColors.green,
                  onTap: () => setState(() {
                        widget.draft.age =
                            widget.draft.age < 80 ? widget.draft.age + 1 : 80;
                      })),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ageStep({
    required String icon,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            icon,
            style: AppTypography.h2.copyWith(
              fontSize: 22,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Step 2: interests
  Widget _stepInterests() {
    return ListView(
      key: const ValueKey('interests'),
      padding: const EdgeInsets.only(top: 6),
      children: [
        const CmpysKicker('What pulls at you?', color: AppColors.green),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Pick what you care about.',
            style: AppTypography.h1
                .copyWith(fontSize: 30, letterSpacing: -0.3, height: 1.4),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We’ll tune your idea feed and plan around these. Choose a few.',
          style: AppTypography.bodyDim.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: cmpysInterests.map((label) {
            final active = widget.draft.interests.contains(label);
            return CmpysChipPill(
              label: label,
              active: active,
              onTap: () => setState(() {
                if (active) {
                  widget.draft.interests.remove(label);
                } else {
                  widget.draft.interests.add(label);
                }
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Step 3: goal
  Widget _stepGoal() {
    return ListView(
      key: const ValueKey('goal'),
      padding: const EdgeInsets.only(top: 6),
      children: [
        const CmpysKicker('Your north star', color: AppColors.green),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'What matters most right now?',
            style: AppTypography.h1
                .copyWith(fontSize: 30, letterSpacing: -0.3, height: 1.4),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pick the one thing you’d most like to compound.',
          style: AppTypography.bodyDim.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 20),
        for (final g in cmpysGoals) ...[
          _goalRow(g),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _goalRow(CmpysGoal g) {
    final on = widget.draft.goalId == g.id;
    return GestureDetector(
      onTap: () => setState(() => widget.draft.goalId = g.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: on ? AppColors.greenSoft : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: on ? AppColors.green : AppColors.hair2,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.label,
                    style: AppTypography.h4.copyWith(
                      fontSize: 16.5,
                      color: on ? AppColors.green2 : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    g.sub,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ink2,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: on ? AppColors.green : Colors.transparent,
                shape: BoxShape.circle,
                border: on
                    ? null
                    : Border.all(color: AppColors.hair2, width: 2),
              ),
              child: on
                  ? const Icon(Icons.check_rounded,
                      size: 15, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
