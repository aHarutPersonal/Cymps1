// The one way into the tutorial reader: Today's "Continue", the Plan tab's
// tutorial rows and the mission screen's timeline all open it here, so every
// entry refreshes the same reads when the reader closes.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/motion/page_transition.dart';
import '../../cmpys/state/plan_providers.dart';
import '../../cmpys/state/today_data.dart';
import '../models/plan_models.dart';
import '../state/current_plan_provider.dart';
import 'book_narration_checkpoint.dart';
import 'lesson_reader_screen.dart';

/// Opens tutorial [index] of [detail] in [LessonReaderScreen] on the root
/// navigator. Resolves to whether the reader completed the step.
///
/// When the reader closes, the mission's reads refresh: its normal read
/// (Today's and the Plan tab's mission to work on) and its peek (the Plan
/// tab's other missions); after a completion the plan refreshes too. They
/// refresh even when the screen that opened the reader has gone meanwhile.
/// [shellBranchIndex] is the shell branch the caller lives in; it defaults to
/// Plan's.
/// Screen-specific follow-ups (a reload, a toast) stay with the caller.
Future<bool> openLessonReader(
  BuildContext context,
  WidgetRef ref,
  PlanItemDetailed detail,
  int index, {
  int shellBranchIndex = ActiveBookNarrationResume.planBranchIndex,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final plan = ref.read(currentPlanProvider.notifier);
  final step = detail.steps[index];
  final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
    CmpysPageRoute<bool>(
      builder: (_) => LessonReaderScreen(
        itemId: detail.item.id,
        missionTitle: detail.item.title,
        step: step,
        stepNumber: index + 1,
        totalSteps: detail.steps.length,
        week: lessonWeekLabel(detail.item),
        materials: detail.materials,
        completed: detail.isStepCompleted(step.id),
        artifactJobId: detail.artifactJobId,
        nextTitle: index + 1 < detail.steps.length
            ? detail.steps[index + 1].title
            : '',
        shellBranchIndex: shellBranchIndex,
      ),
    ),
  );
  final itemId = detail.item.id;
  container
    ..invalidate(todayMissionDetailProvider(itemId))
    ..invalidate(planMissionPeekProvider(itemId));
  if (changed == true && plan.mounted) unawaited(plan.refresh());
  return changed == true;
}
