// Pure data for the mission screen (`MissionScreen` in `v3/plan.jsx`): the
// kick line, the workload split, the definition-of-done checklist and the
// mental model card. No widgets, so each rule is unit-tested on its own. Material
// access is `accessTypeForMaterial` (today_data.dart), shared with Today.

import 'dart:math' as math;

import '../models/plan_models.dart';

/// "Week {w} · Mission {m} of {M}": [item]'s place among the missions that
/// start in its week, in plan order. A mission spanning weeks keeps its
/// range ("Week 3–4 · …"). "Week {w} · Mission" while [plan] is not loaded
/// or does not list the item.
String missionKick(BackendPlanItem item, BackendPlan? plan) {
  final start = item.weekStart;
  final week = item.weekEnd > start ? '$start–${item.weekEnd}' : '$start';
  if (plan == null) return 'Week $week · Mission';
  final missions = [
    for (final candidate in plan.items)
      if (candidate.isMissionTask && candidate.weekStart == start) candidate,
  ];
  final index = missions.indexWhere((mission) => mission.id == item.id);
  if (index < 0) return 'Week $week · Mission';
  return 'Week $week · Mission ${index + 1} of ${missions.length}';
}

/// The workload card's minutes. Reading and practice are the tutorials' own;
/// the deliverable is whatever the allocation leaves after them, so [total]
/// is the allocation unless the tutorials alone run over it, and the bar's
/// three segments always fill it.
///
/// The split is only drawn when [splitKnown]: while any tutorial has no
/// minutes yet (an outline still being written), its time is unknown, and
/// counting it as zero would show "Reading 0 · Practice 0" with the whole
/// allocation as the deliverable.
class MissionWorkload {
  const MissionWorkload({
    required this.allocated,
    required this.reading,
    required this.practice,
    required this.deliverable,
    this.splitKnown = true,
  });

  final int allocated;
  final int reading;
  final int practice;
  final int deliverable;

  /// Every tutorial's reading and practice minutes are known (or the
  /// mission has no tutorials and its details are final).
  final bool splitKnown;

  /// Reading + practice + deliverable: max(allocated, reading + practice).
  int get total => reading + practice + deliverable;
}

/// [item]'s allocation split across its [steps].
///
/// A tutorial's minutes are known when it has reading time and, for a
/// `tutorial_v1` step, practice time too (its reading and practice minutes,
/// or a written lesson's word-count estimate for reading). With any step
/// unknown, or with no steps while [tutorialsPending] (the details are still
/// being prepared), the split is not [MissionWorkload.splitKnown].
MissionWorkload missionWorkload(
  BackendPlanItem item,
  Iterable<PlanStepDetail> steps, {
  bool tutorialsPending = false,
}) {
  final minutes = item.estimatedMinutes;
  final allocated = math.max(
    0,
    minutes != null && minutes > 0 ? minutes : item.estimatedHours * 60,
  );
  var reading = 0;
  var practice = 0;
  var known = steps.isNotEmpty || !tutorialsPending;
  for (final step in steps) {
    final stepReading = step.effectiveReadingMinutes;
    final stepPractice = step.effectivePracticeMinutes;
    if (stepReading == null || (step.isTutorial && stepPractice == null)) {
      known = false;
    }
    reading += stepReading ?? 0;
    practice += stepPractice ?? 0;
  }
  return MissionWorkload(
    allocated: allocated,
    reading: reading,
    practice: practice,
    deliverable: math.max(0, allocated - reading - practice),
    splitKnown: known,
  );
}

final _leadingBullet = RegExp(r'^(?:[-•*]|\d+[.)])\s+');

/// The "Definition of done" checklist from `definition_of_done`: one line
/// per newline-separated (or "•"-separated) item with its bullet ("-", "•",
/// "*", "1.") removed; otherwise the whole text as a single line. Empty when
/// there is nothing to show.
List<String> definitionOfDoneLines(String? text) {
  final trimmed = text?.trim() ?? '';
  if (trimmed.isEmpty) return const [];
  var lines = trimmed
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  // "• one • two" on a single line.
  if (lines.length == 1 && '•'.allMatches(lines.single).length > 1) {
    lines = lines.single
        .split('•')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }
  return [
    for (final line in lines)
      if (line.replaceFirst(_leadingBullet, '').trim() case final item
          when item.isNotEmpty)
        item,
  ];
}

/// The mental model card's text: a display [title] and a serif [body].
///
/// - "Name: explanation" or "Name — explanation" splits at the first
///   separator when the name is at most 60 characters.
/// - A bare model name (the prompts ask for one, e.g. "Margin of safety"):
///   at most 60 characters and not ending in ".", "!" or "?" is the title,
///   with an empty body.
/// - Anything else (a sentence, as catalog missions store) is the body.
///
/// Null when there is nothing to show (the card is hidden).
({String? title, String body})? splitMentalModel(String? text) {
  final trimmed = text?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final cuts = [
    for (final separator in const [': ', ' — '])
      if (trimmed.indexOf(separator) case final at when at > 0)
        (at: at, length: separator.length),
  ]..sort((a, b) => a.at.compareTo(b.at));
  if (cuts.isNotEmpty) {
    final cut = cuts.first;
    final title = trimmed.substring(0, cut.at).trim();
    final body = trimmed.substring(cut.at + cut.length).trim();
    if (title.isNotEmpty && title.length <= 60 && body.isNotEmpty) {
      return (title: title, body: body);
    }
    return (title: null, body: trimmed);
  }
  final name = trimmed.replaceFirst(RegExp(r'\s*[:—]$'), '');
  if (name.isNotEmpty &&
      name.length <= 60 &&
      !RegExp(r'[.!?]$').hasMatch(name)) {
    return (title: name, body: '');
  }
  return (title: null, body: trimmed);
}
