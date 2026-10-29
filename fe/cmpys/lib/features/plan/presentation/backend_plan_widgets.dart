// Widgets of the Plan tab's roadmap (`PlanTab`, `WeekPlan` in `v3/plan.jsx`)
// and the "plan is being generated" card: the week strip, the blueprint
// card, this week's summary and mission cards with their tutorial rows, and
// the all-weeks list.
//
// The plan is `currentPlanProvider`'s; a mission's tutorials are
// `todayMissionDetailProvider`'s for the mission to work on and
// `planMissionPeekProvider`'s (the same read with `?peek=true`, which never
// starts generation) for the others. All strings are the design's, curly
// quotes included.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/ui/v3/v3.dart';
import '../../cmpys/state/plan_data.dart';
import '../../cmpys/state/plan_providers.dart';
import '../models/plan_models.dart';
import '../state/current_plan_provider.dart';
import 'book_narration_checkpoint.dart';
import 'cycle_completion_screen.dart';
import 'open_lesson_reader.dart';
import 'plan_item_detail_screen.dart';

/// Opens the plan item (mission or habit) on the shell branch's navigator.
Future<void> openBackendPlanItemById(
  BuildContext context,
  String itemId, {
  int shellBranchIndex = ActiveBookNarrationResume.planBranchIndex,
}) {
  return Navigator.of(context).push(
    CmpysPageRoute<void>(
      builder: (_) => PlanItemDetailScreen(
        itemId: itemId,
        shellBranchIndex: shellBranchIndex,
      ),
    ),
  );
}

/// Key on a tutorial row (tests, layout probes).
Key planTutorialRowKey(String itemId, String stepId) =>
    ValueKey<String>('plan-tutorial-row-$itemId-$stepId');

/// Key on a locked row's lock icon, whose rocking is the design's `shake`.
Key planTutorialLockKey(String itemId, String stepId) =>
    ValueKey<String>('plan-tutorial-lock-$itemId-$stepId');

TextStyle _tnum(TextStyle style) => style.merge(AppTypography.tnum);

// ═════════════════════════════════════════════════════════════════════════
// Plan generating
// ═════════════════════════════════════════════════════════════════════════

/// Progress card while the plan is still being written by the worker.
class PlanGeneratingCard extends StatelessWidget {
  const PlanGeneratingCard({super.key, required this.progress, this.line = ''});

  final int progress;
  final String line;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.night,
        borderRadius: BorderRadius.circular(AppRadii.r2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const V3Spinner(color: AppColors.ember, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'YOUR 12-WEEK PLAN IS BEING WRITTEN',
                  style: AppTypography.kick.copyWith(color: AppColors.nink3),
                ),
              ),
              Text(
                '$progress%',
                style: _tnum(
                  AppTypography.sans(
                    13,
                    FontWeight.w700,
                  ).copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          V3Bar(
            value: progress.clamp(0, 100) / 100,
            color: AppColors.ember,
            height: 7,
            track: const Color(0x2EFFFFFF),
          ),
          if (line.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              line,
              style: AppTypography.sans(13).copyWith(
                color: AppColors.nink2,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Week strip
// ═════════════════════════════════════════════════════════════════════════

/// The strip of week chips ("WK" and the number): done sage, current ink,
/// locked a hairline card. [onTapWeek] gets the week and its state; the
/// screen decides what each does.
class PlanWeekStrip extends StatefulWidget {
  const PlanWeekStrip({super.key, required this.plan, required this.onTapWeek});

  final BackendPlan plan;
  final void Function(int week, PlanWeekState state) onTapWeek;

  @override
  State<PlanWeekStrip> createState() => _PlanWeekStripState();
}

class _PlanWeekStripState extends State<PlanWeekStrip> {
  static const _chipWidth = 56.0;
  static const _gap = 8.0;

  // Start with the current week in view; a plan can run past a screen's width
  // of chips.
  late final ScrollController _controller = ScrollController(
    initialScrollOffset: math.max(
      0,
      (widget.plan.focusWeek - 1) * (_chipWidth + _gap) -
          2 * (_chipWidth + _gap),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Row(
        children: [
          for (var week = 1; week <= plan.durationWeeks; week++) ...[
            if (week > 1) const SizedBox(width: _gap),
            _chip(plan, week),
          ],
        ],
      ),
    );
  }

  Widget _chip(BackendPlan plan, int week) {
    final state = planWeekState(plan, week);
    final current = state == PlanWeekState.current;
    final done = state == PlanWeekState.done;
    final foreground = current
        ? Colors.white
        : done
        ? AppColors.sage2
        : AppColors.ink3;
    final label = switch (state) {
      PlanWeekState.done => 'Week $week, done',
      PlanWeekState.current => 'Week $week, current',
      PlanWeekState.locked => 'Week $week, locked',
    };
    return V3Pop(
      child: V3Pressable(
        key: Key('plan-week-chip-$week'),
        semanticLabel: label,
        onTap: () => widget.onTapWeek(week, state),
        focusRadius: BorderRadius.circular(18),
        // 56 x 64 at normal text; it grows with large text rather than clip.
        child: Container(
          constraints: const BoxConstraints(
            minWidth: _chipWidth,
            minHeight: 64,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: current
                ? AppColors.ink
                : done
                ? AppColors.sageSoft
                : AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: state == PlanWeekState.locked
                ? Border.all(color: AppColors.hair)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WK',
                style: AppTypography.sans(
                  10,
                  FontWeight.w700,
                ).copyWith(color: foreground, letterSpacing: 0.8),
              ),
              const SizedBox(height: 4),
              Text(
                '$week',
                style: _tnum(
                  AppTypography.sans(
                    18,
                    FontWeight.w700,
                  ).copyWith(color: foreground, height: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Blueprint
// ═════════════════════════════════════════════════════════════════════════

/// The expandable Strategic blueprint card (iris-soft): the direction, and
/// once open the numbered priorities and "Why this order". A blueprint with
/// nothing to expand opens [onReadFull] on tap instead.
class PlanBlueprintCard extends StatefulWidget {
  const PlanBlueprintCard({
    super.key,
    required this.blueprint,
    required this.onReadFull,
  });

  final PlanBlueprint blueprint;

  /// Opens the blueprint in full.
  final VoidCallback onReadFull;

  @override
  State<PlanBlueprintCard> createState() => _PlanBlueprintCardState();
}

class _PlanBlueprintCardState extends State<PlanBlueprintCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final blueprint = widget.blueprint;
    final motion = MotionConfig.enabled(context);
    return V3Pressable(
      key: const Key('plan-blueprint'),
      pressedScale: 1,
      minTapTarget: 0,
      focusRadius: AppRadii.brR,
      onTap: blueprint.hasDetail
          ? () => setState(() => _open = !_open)
          : widget.onReadFull,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.irisSoft,
          borderRadius: AppRadii.brR,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const V3Icon(V3Icons.layers, size: 16, color: AppColors.iris2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'STRATEGIC BLUEPRINT',
                    style: AppTypography.kick.copyWith(color: AppColors.iris2),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: motion
                      ? const Duration(milliseconds: 350)
                      : Duration.zero,
                  curve: AppMotion.out,
                  child: V3Icon(
                    blueprint.hasDetail ? V3Icons.down : V3Icons.right,
                    size: 16,
                    color: AppColors.iris2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              blueprint.direction,
              style: AppTypography.display(
                24,
              ).copyWith(height: 1.15, color: AppColors.ink),
            ),
            if (blueprint.hasDetail)
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: _open ? 1 : 0),
                duration: motion
                    ? const Duration(milliseconds: 500)
                    : Duration.zero,
                curve: AppMotion.out,
                builder: (context, factor, child) => ClipRect(
                  key: const Key('plan-blueprint-body'),
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: factor,
                    child: child,
                  ),
                ),
                child: ExcludeSemantics(
                  excluding: !_open,
                  child: _body(blueprint),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(PlanBlueprint blueprint) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blueprint.priorities.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${i + 1}',
                      style: _tnum(
                        AppTypography.display(
                          24,
                        ).copyWith(color: AppColors.iris2),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          blueprint.priorities[i].title,
                          style: AppTypography.sans(
                            14.5,
                            FontWeight.w600,
                          ).copyWith(color: AppColors.ink),
                        ),
                        if (blueprint.priorities[i].detail.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              blueprint.priorities[i].detail,
                              style: AppTypography.sans(
                                13.5,
                              ).copyWith(color: AppColors.ink2, height: 1.45),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (blueprint.rationale != null) ...[
            const SizedBox(height: 16),
            Text(
              'Why this order',
              style: AppTypography.sans(
                12,
                FontWeight.w600,
              ).copyWith(color: AppColors.iris2),
            ),
            const SizedBox(height: 4),
            Text(
              blueprint.rationale!,
              style: AppTypography.sans(
                13.5,
              ).copyWith(color: AppColors.ink2, height: 1.5),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: V3Pressable(
              onTap: widget.onReadFull,
              focusRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Read the full blueprint',
                      style: AppTypography.sans(
                        13,
                        FontWeight.w600,
                      ).copyWith(color: AppColors.iris2),
                    ),
                    const SizedBox(width: 4),
                    const V3Icon(
                      V3Icons.right,
                      size: 14,
                      color: AppColors.iris2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// This week
// ═════════════════════════════════════════════════════════════════════════

/// "This week": the week's kicker, the summary card and one card per
/// mission. A finished plan shows [PlanCompleteCard] instead.
class PlanThisWeek extends ConsumerWidget {
  const PlanThisWeek({super.key, required this.plan});

  final BackendPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = plan.focusWeek;
    final missions = plan.missionsForWeek(week);
    final statuses = planMissionStatuses(plan, week);
    final peekSupported = planSupportsPeek(plan);
    // Only the mission to work on is read the normal way; the rest are
    // peeked, so opening this tab never starts or promotes generation. A
    // server that cannot peek gets no read for them at all.
    final details = [
      for (var i = 0; i < missions.length; i++)
        if (planMissionDetailProvider(
              missions[i].id,
              peek: statuses[i] != PlanMissionStatus.current,
              peekSupported: peekSupported,
            )
            case final provider?)
          ref.watch(provider),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The design pulls the kicker 6 pt up under the section title.
        Transform.translate(
          offset: const Offset(0, -6),
          child: Text(
            'Week $week · ${planWeekTitle(plan, week)}'.toUpperCase(),
            style: AppTypography.kick,
          ),
        ),
        const SizedBox(height: 6),
        _summary(details),
        for (var i = 0; i < missions.length; i++) ...[
          const SizedBox(height: 10),
          PlanMissionCard(
            key: Key('plan-mission-${missions[i].id}'),
            mission: missions[i],
            number: i + 1,
            status: statuses[i],
            peekSupported: peekSupported,
          ),
        ],
      ],
    );
  }

  Widget _summary(List<AsyncValue<PlanItemDetailed>> async) {
    if (async.any((a) => a.isLoading && !a.hasValue)) {
      return Container(
        decoration: v3Card(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: const Row(
          children: [
            V3Skel(width: 40, height: 40, radius: 20),
            SizedBox(width: 12),
            Expanded(child: V3Skel(height: 14)),
          ],
        ),
      );
    }
    var done = 0;
    var total = 0;
    var minutes = 0;
    var missionCount = 0;
    for (final value in async.map((a) => a.valueOrNull).nonNulls) {
      final counts = tutorialCounts(value);
      done += counts.done;
      total += counts.total;
      // A mission whose tutorials are not written yet is not counted.
      if (counts.total > 0) missionCount++;
      for (final step in value.steps) {
        minutes += tutorialMinutes(step) ?? 0;
      }
    }
    // Nothing written yet: the mission cards say so.
    if (total == 0) return const SizedBox.shrink();
    return Container(
      decoration: v3Card(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          V3Ring(
            value: done / total,
            size: 40,
            strokeWidth: 3.5,
            child: Text(
              '$done/$total',
              style: _tnum(
                AppTypography.sans(
                  11,
                  FontWeight.w700,
                ).copyWith(color: AppColors.ink),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total tutorial${total == 1 ? '' : 's'} across '
                  '$missionCount mission${missionCount == 1 ? '' : 's'}',
                  style: AppTypography.sans(
                    14,
                    FontWeight.w600,
                  ).copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: 1),
                Text(
                  'About ${formatTutorialHours(minutes)} h of tutorials · '
                  '${formatHalfHours(planWeeklyMinutes(plan))} h budget',
                  style: _tnum(
                    AppTypography.sans(12).copyWith(color: AppColors.ink3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A finished plan: the same card the focus card used to show, with the
/// cycle summary and next plan behind a button.
class PlanCompleteCard extends StatelessWidget {
  const PlanCompleteCard({super.key, required this.plan});

  final BackendPlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: v3Card(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.sageSoft,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: V3Icon(V3Icons.trophy, size: 20, color: AppColors.sage2),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Plan complete',
            style: AppTypography.display(27).copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'Every mission is complete. Your roadmap is open for review.',
            style: AppTypography.sans(
              13.5,
            ).copyWith(color: AppColors.ink2, height: 1.45),
          ),
          const SizedBox(height: 16),
          V3Button(
            kind: V3ButtonKind.dark,
            size: V3Size.md,
            iconRight: V3Icons.arrowR,
            onPressed: () => showCycleCompletion(context, plan: plan),
            child: const Text('See your cycle summary'),
          ),
        ],
      ),
    );
  }
}

/// One mission of this week: its title and tutorial segments, the current
/// tutorial and its neighbours (or all of them), and the next mission locked.
class PlanMissionCard extends ConsumerStatefulWidget {
  const PlanMissionCard({
    super.key,
    required this.mission,
    required this.number,
    required this.status,
    this.peekSupported = true,
  });

  final BackendPlanItem mission;

  /// 1-based position in the week.
  final int number;
  final PlanMissionStatus status;

  /// Whether the server can peek ([planSupportsPeek]). When it cannot, a
  /// mission other than the one to work on is not read: header only.
  final bool peekSupported;

  @override
  ConsumerState<PlanMissionCard> createState() => _PlanMissionCardState();
}

class _PlanMissionCardState extends ConsumerState<PlanMissionCard> {
  bool _all = false;
  final Map<String, int> _shakes = {};

  /// Locked until the mission before it is done, unless the learner has
  /// already started it (set in [build], where the tutorials are known).
  bool _locked = false;

  /// Only the mission to work on is read the normal way; the others are
  /// peeked (see [planMissionPeekProvider]), or not read at all on a server
  /// that cannot peek.
  AutoDisposeFutureProvider<PlanItemDetailed>? get _detailProvider =>
      planMissionDetailProvider(
        widget.mission.id,
        peek: widget.status != PlanMissionStatus.current,
        peekSupported: widget.peekSupported,
      );

  Future<void> _openMission() async {
    await openBackendPlanItemById(context, widget.mission.id);
    if (!mounted) return;
    final provider = _detailProvider;
    if (provider != null) ref.invalidate(provider);
    ref.invalidate(todayViewProvider);
  }

  Future<void> _openLesson(PlanItemDetailed detail, int index) =>
      openLessonReader(context, ref, detail, index);

  void _tapRow(PlanItemDetailed detail, int index, TutorialRowState state) {
    switch (state) {
      case TutorialRowState.done:
      case TutorialRowState.current:
        unawaited(_openLesson(detail, index));
      case TutorialRowState.preparing:
        showV3Toast(
          context,
          'Still being prepared and reviewed',
          icon: V3Icons.clock,
          tone: V3ToastTone.warn,
        );
      case TutorialRowState.stopped:
        // Generation stopped: "Generate again" lives on the mission screen.
        unawaited(_openMission());
      case TutorialRowState.locked:
        final stepId = detail.steps[index].id;
        setState(() => _shakes[stepId] = (_shakes[stepId] ?? 0) + 1);
        showV3Toast(
          context,
          _locked
              ? 'Opens when mission ${widget.number - 1} is complete'
              : 'Finish tutorial ${detail.activeStepIndex + 1} first',
          icon: V3Icons.lock,
          tone: V3ToastTone.warn,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = _detailProvider;
    final async = provider == null ? null : ref.watch(provider);
    final detail = async?.valueOrNull;
    // A mission the learner has already worked on is open, never locked, even
    // when the plan has not caught up with a finished tutorial.
    _locked =
        widget.status == PlanMissionStatus.locked &&
        !(detail != null &&
            (detail.completed || detail.completedStepIds.isNotEmpty));
    final states = detail == null
        ? const <TutorialRowState>[]
        : tutorialRowStates(detail, missionLocked: _locked);
    final current = widget.status == PlanMissionStatus.current;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: v3Card(
        boxShadow: current
            ? const [
                BoxShadow(
                  color: Color(0x6617151A),
                  offset: Offset(0, 14),
                  blurRadius: 30,
                  spreadRadius: -22,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(states),
          if (detail != null && detail.steps.isNotEmpty)
            _rows(detail, states)
          else if (async == null)
            // Not read (a server without peek): the header is the card.
            const SizedBox.shrink()
          else if (async.isLoading && !async.hasValue)
            _loading()
          else if (async.hasError && detail == null)
            _retry(),
        ],
      ),
    );
  }

  // ── header ──

  Widget _header(List<TutorialRowState> states) {
    final locked = _locked;
    final current = widget.status == PlanMissionStatus.current;
    final done = widget.status == PlanMissionStatus.done;
    final tag = locked
        ? V3Tag(
            icon: V3Icons.lock,
            child: Text('After mission ${widget.number - 1}'),
          )
        : current
        ? const V3Tag(
            background: AppColors.emberSoft,
            color: AppColors.ember2,
            child: Text('In progress'),
          )
        : done
        ? const V3Tag(
            icon: V3Icons.check,
            background: AppColors.sageSoft,
            color: AppColors.sage2,
            child: Text('Done'),
          )
        : null;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, locked ? 10 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'MISSION ${widget.number}',
                  style: AppTypography.kick,
                ),
              ),
              // A long tag (large text) shrinks instead of overflowing.
              if (tag != null)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: tag,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.mission.title,
                  style: AppTypography.sans(locked ? 17 : 18, FontWeight.w600)
                      .copyWith(
                        letterSpacing: -0.015 * (locked ? 17 : 18),
                        height: 1.25,
                        color: locked ? AppColors.ink2 : AppColors.ink,
                      ),
                ),
              ),
              if (!locked) ...[
                const SizedBox(width: 6),
                const V3Icon(V3Icons.right, size: 17, color: AppColors.ink3),
              ],
            ],
          ),
          if (!locked && states.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < states.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: _bar(states[i])),
                ],
              ],
            ),
          ],
        ],
      ),
    );
    return V3Pressable(
      onTap: locked
          ? () => showV3Toast(
              context,
              'Opens when mission ${widget.number - 1} is complete',
              icon: V3Icons.lock,
              tone: V3ToastTone.warn,
            )
          : _openMission,
      pressedScale: locked ? 1 : 0.965,
      minTapTarget: 0,
      semanticLabel: locked
          ? 'Mission ${widget.number}, locked'
          : 'Open mission ${widget.number}: ${widget.mission.title}',
      focusRadius: BorderRadius.circular(AppRadii.r),
      child: content,
    );
  }

  Widget _bar(TutorialRowState state) {
    const height = 5.0;
    return switch (state) {
      TutorialRowState.preparing => const CustomPaint(
        painter: _DashedPainter(color: AppColors.hair2, radius: 2.5, stroke: 1),
        child: SizedBox(height: height, width: double.infinity),
      ),
      _ => Container(
        height: height,
        decoration: BoxDecoration(
          color: switch (state) {
            TutorialRowState.done => AppColors.sage,
            TutorialRowState.current => AppColors.ember,
            _ => AppColors.paper2,
          },
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    };
  }

  // ── rows ──

  Widget _rows(PlanItemDetailed detail, List<TutorialRowState> states) {
    final count = detail.steps.length;
    // The current tutorial, one before and two after; a finished mission
    // anchors on its last tutorial, a locked one on its first.
    final firstOpen = states.indexWhere((s) => s != TutorialRowState.done);
    final anchor = _locked
        ? 0
        : firstOpen < 0
        ? count - 1
        : firstOpen;
    final shown = [
      for (var i = 0; i < count; i++)
        if (_all || (i >= anchor - 1 && i <= anchor + 2)) i,
    ];
    final canExpand = shown.length < count;
    final motion = MotionConfig.enabled(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.hair)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Opacity(
            opacity: _locked ? 0.75 : 1,
            child: AnimatedSize(
              duration: motion
                  ? const Duration(milliseconds: 350)
                  : Duration.zero,
              curve: AppMotion.out,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var n = 0; n < shown.length; n++)
                    V3Rise(
                      key: ValueKey<String>(
                        'rise-${detail.steps[shown[n]].id}',
                      ),
                      delay: Duration(milliseconds: n * 40),
                      duration: const Duration(milliseconds: 450),
                      child: PlanTutorialRow(
                        key: planTutorialRowKey(
                          detail.item.id,
                          detail.steps[shown[n]].id,
                        ),
                        itemId: detail.item.id,
                        step: detail.steps[shown[n]],
                        number: shown[n] + 1,
                        state: states[shown[n]],
                        first: n == 0,
                        shake: _shakes[detail.steps[shown[n]].id] ?? 0,
                        onTap: () =>
                            _tapRow(detail, shown[n], states[shown[n]]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (canExpand || _all)
          V3Pressable(
            onTap: () => setState(() => _all = !_all),
            pressedScale: 1,
            minTapTarget: 0,
            focusRadius: BorderRadius.zero,
            child: Container(
              constraints: const BoxConstraints(minHeight: kV3TapTarget),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.hair)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _all ? 'Show fewer' : 'Show all $count tutorials',
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.sans(
                        13,
                        FontWeight.w600,
                      ).copyWith(color: AppColors.ink2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _all ? 0.5 : 0,
                    duration: motion
                        ? const Duration(milliseconds: 300)
                        : Duration.zero,
                    curve: AppMotion.out,
                    child: const V3Icon(
                      V3Icons.down,
                      size: 15,
                      color: AppColors.ink2,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _loading() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hair)),
      ),
      padding: const EdgeInsets.all(16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V3Skel(height: 14),
          SizedBox(height: 12),
          V3Skel(height: 14, width: 200),
        ],
      ),
    );
  }

  Widget _retry() {
    return V3Pressable(
      onTap: () {
        final provider = _detailProvider;
        if (provider != null) ref.invalidate(provider);
      },
      pressedScale: 1,
      minTapTarget: 0,
      focusRadius: BorderRadius.zero,
      child: Container(
        constraints: const BoxConstraints(minHeight: kV3TapTarget),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hair)),
        ),
        child: Row(
          children: [
            const V3Icon(V3Icons.refresh, size: 16, color: AppColors.ink3),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Couldn’t load the tutorials — tap to retry.',
                style: AppTypography.sans(13.5).copyWith(color: AppColors.ink2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tutorial of a mission: a 30 pt disc (check, play with the glow,
/// spinner, lock or alert), the title (a skeleton while preparing), and
/// "Tutorial n · m min".
class PlanTutorialRow extends StatelessWidget {
  const PlanTutorialRow({
    super.key,
    required this.itemId,
    required this.step,
    required this.number,
    required this.state,
    required this.first,
    required this.shake,
    required this.onTap,
  });

  final String itemId;
  final PlanStepDetail step;

  /// 1-based position in the mission.
  final int number;
  final TutorialRowState state;
  final bool first;

  /// Bumped to rock the lock icon.
  final int shake;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preparing = state == TutorialRowState.preparing;
    final current = state == TutorialRowState.current;
    final minutes = tutorialMinutes(step);
    final subtitle = switch (state) {
      TutorialRowState.preparing => 'Tutorial $number · preparing',
      TutorialRowState.stopped => 'Tutorial $number · couldn’t be prepared',
      _ =>
        minutes == null
            ? 'Tutorial $number'
            : 'Tutorial $number · $minutes min',
    };
    return V3Pressable(
      onTap: onTap,
      minTapTarget: 0,
      focusRadius: BorderRadius.circular(12),
      semanticLabel: [
        'Tutorial $number',
        if (!preparing) step.title,
        switch (state) {
          TutorialRowState.done => 'done',
          TutorialRowState.current => 'current',
          TutorialRowState.locked => 'locked',
          TutorialRowState.preparing => 'preparing',
          TutorialRowState.stopped => 'could not be prepared',
        },
      ].join(', '),
      child: Container(
        constraints: const BoxConstraints(minHeight: kV3TapTarget),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: AppColors.hair)),
        ),
        child: Row(
          children: [
            _disc(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (preparing)
                    const FractionallySizedBox(
                      widthFactor: 0.65,
                      child: V3Skel(height: 12),
                    )
                  else
                    Text(
                      step.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppTypography.sans(
                            14.5,
                            current ? FontWeight.w600 : FontWeight.w500,
                          ).copyWith(
                            color: state == TutorialRowState.locked
                                ? AppColors.ink2
                                : AppColors.ink,
                          ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _tnum(
                      AppTypography.sans(11.5).copyWith(color: AppColors.ink3),
                    ),
                  ),
                ],
              ),
            ),
            if (current) ...[
              const SizedBox(width: 8),
              // Capped so large text shrinks the tag, not the title to zero.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: V3Tag(
                    background: AppColors.emberSoft,
                    color: AppColors.ember2,
                    child: Text('Continue'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _disc() {
    switch (state) {
      case TutorialRowState.done:
        return _plainDisc(
          AppColors.sage,
          null,
          const V3Icon(
            V3Icons.check,
            size: 14,
            strokeWidth: 3,
            color: Colors.white,
          ),
        );
      case TutorialRowState.current:
        return TutorialGlowDisc(
          child: V3Icon(V3Icons.play, size: 12, color: Colors.white),
        );
      case TutorialRowState.preparing:
        return _plainDisc(
          AppColors.paper,
          AppColors.hair2,
          const V3Spinner(color: AppColors.ink3, size: 13),
        );
      case TutorialRowState.stopped:
        return _plainDisc(
          AppColors.paper,
          AppColors.hair2,
          const V3Icon(V3Icons.alert, size: 14, color: AppColors.gold2),
        );
      case TutorialRowState.locked:
        return _plainDisc(
          AppColors.paper,
          AppColors.hair2,
          TutorialShake(
            key: planTutorialLockKey(itemId, step.id),
            tick: shake,
            child: const V3Icon(V3Icons.lock, size: 13, color: AppColors.ink3),
          ),
        );
    }
  }

  Widget _plainDisc(Color fill, Color? border, Widget child) => Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: fill,
      shape: BoxShape.circle,
      border: border == null ? null : Border.all(color: border, width: 1.5),
    ),
    child: child,
  );
}

/// The current tutorial's disc with the design's `glowPulse 2s infinite`: an
/// ember ring that grows 8 pt while it fades out. Still under reduced motion.
/// Shared with the mission screen's timeline, which uses a 44 pt disc.
class TutorialGlowDisc extends StatefulWidget {
  const TutorialGlowDisc({super.key, required this.child, this.size = 30});

  final Widget child;
  final double size;

  @override
  State<TutorialGlowDisc> createState() => _GlowDiscState();
}

class _GlowDiscState extends State<TutorialGlowDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionConfig.enabled(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final v = _controller.value;
        final k = Curves.easeInOut.transform(v < .5 ? v * 2 : (1 - v) * 2);
        return Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.ember,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.ember.withValues(alpha: 0.45 * (1 - k)),
                spreadRadius: 8 * k,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// `shake .5s`: rocks its child -14°, 12°, -8°, 5° and back whenever [tick]
/// changes. The child is wrapped in a [Transform] at rest too. Shared with
/// the mission screen's locked tutorials.
class TutorialShake extends StatefulWidget {
  const TutorialShake({super.key, required this.tick, required this.child});

  final int tick;
  final Widget child;

  @override
  State<TutorialShake> createState() => _ShakeState();
}

class _ShakeState extends State<TutorialShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  static const _frames = [0.0, -14.0, 12.0, -8.0, 5.0, 0.0];

  @override
  void didUpdateWidget(TutorialShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tick != oldWidget.tick && MotionConfig.enabled(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _angle(double t) {
    final scaled = t * (_frames.length - 1);
    final segment = math.min(scaled.floor(), _frames.length - 2);
    final f = Curves.easeInOut.transform(scaled - segment);
    final degrees =
        _frames[segment] + (_frames[segment + 1] - _frames[segment]) * f;
    return degrees * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) =>
          Transform.rotate(angle: _angle(_controller.value), child: child),
    );
  }
}

/// A dashed round-rect outline (the design's `1px dashed` / `1.5px dashed`).
class _DashedPainter extends CustomPainter {
  const _DashedPainter({
    required this.color,
    required this.radius,
    required this.stroke,
  });

  final Color color;
  final double radius;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 3, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 2.5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.stroke != stroke;
}

/// A dashed outline for a habit grid's open "Today" cell.
class PlanDashedCell extends StatelessWidget {
  const PlanDashedCell({
    super.key,
    required this.height,
    this.radius = 8,
    this.color = AppColors.hair2,
  });

  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedPainter(color: color, radius: radius, stroke: 1.5),
    child: SizedBox(height: height, width: double.infinity),
  );
}

// ═════════════════════════════════════════════════════════════════════════
// All weeks
// ═════════════════════════════════════════════════════════════════════════

/// The all-weeks list (Now, a check or a lock) and the unlock note.
class PlanAllWeeks extends StatelessWidget {
  const PlanAllWeeks({super.key, required this.plan});

  final BackendPlan plan;

  @override
  Widget build(BuildContext context) {
    final weeks = plan.durationWeeks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: v3Card(),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var week = 1; week <= weeks; week++)
                _row(week, planWeekState(plan, week)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Weeks unlock when the previous week’s required work is complete, '
          'not by calendar date. After week $weeks you’ll get a cycle summary '
          'and can start the next plan.',
          style: AppTypography.sans(
            12.5,
          ).copyWith(color: AppColors.ink3, height: 1.5),
        ),
      ],
    );
  }

  Widget _row(int week, PlanWeekState state) {
    final current = state == PlanWeekState.current;
    return Opacity(
      opacity: state == PlanWeekState.locked ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          border: week == 1
              ? null
              : const Border(top: BorderSide(color: AppColors.hair)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                week.toString().padLeft(2, '0'),
                style: _tnum(
                  AppTypography.sans(
                    12,
                    FontWeight.w700,
                  ).copyWith(color: AppColors.ink3),
                ),
              ),
            ),
            Expanded(
              child: Text(
                planWeekTitle(plan, week),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sans(
                  14.5,
                  current ? FontWeight.w600 : FontWeight.w500,
                ).copyWith(color: AppColors.ink),
              ),
            ),
            const SizedBox(width: 10),
            switch (state) {
              PlanWeekState.done => const V3Icon(
                V3Icons.check,
                size: 16,
                strokeWidth: 2.5,
                color: AppColors.sage2,
              ),
              PlanWeekState.current => const V3Tag(
                background: AppColors.emberSoft,
                color: AppColors.ember2,
                child: Text('Now'),
              ),
              PlanWeekState.locked => const V3Icon(
                V3Icons.lock,
                size: 14,
                color: AppColors.ink3,
              ),
            },
          ],
        ),
      ),
    );
  }
}
