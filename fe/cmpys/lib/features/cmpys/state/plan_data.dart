// Pure helpers behind the Plan tab (`PlanTab`, `WeekPlan` in `v3/plan.jsx`).
//
// The plan itself comes from `currentPlanProvider`; the tutorials of a
// mission come from `todayMissionDetailProvider` (today_data.dart). These
// helpers turn them into what the tab shows: the hours tag, the overall
// progress, week states, tutorial row states and the blueprint card's parts.
// They hold no Flutter, so they are unit-testable.

import '../../plan/models/plan_models.dart';

// ── hours and progress ────────────────────────────────────────────────────

/// Hours in half-hour steps without a trailing ".0" (240 → "4", 270 → "4.5").
String formatHalfHours(int minutes) {
  final hours = (minutes / 30).round() / 2;
  return hours == hours.roundToDouble()
      ? hours.round().toString()
      : hours.toStringAsFixed(1);
}

/// Hours with one decimal at most, as the design's `Math.round(x * 10) / 10`
/// prints them (130 min → "2.2", 120 min → "2").
String formatTutorialHours(int minutes) {
  final hours = (minutes / 60 * 10).round() / 10;
  return hours == hours.roundToDouble()
      ? hours.round().toString()
      : hours.toStringAsFixed(1);
}

/// The plan's weekly capacity in minutes: `weeklyMinutes` when the server
/// sends it, else the legacy whole hours.
int planWeeklyMinutes(BackendPlan plan) {
  final minutes = plan.weeklyMinutes;
  return minutes != null && minutes > 0 ? minutes : plan.weeklyHours * 60;
}

/// Overall progress, 0 to 1, over the required work: missions, not the daily
/// habits that reset every day. A finished mission counts 1, one under way
/// its own progress. A plan with no missions falls back to the server's
/// `overallProgress`.
double planOverallProgress(BackendPlan plan) {
  final missions = plan.items.where((item) => !item.isDailyRhythm).toList();
  if (missions.isEmpty) return (plan.overallProgress / 100).clamp(0.0, 1.0);
  var sum = 0.0;
  for (final item in missions) {
    sum += item.isCompleted
        ? 1
        : (item.progressPercent / 100).clamp(0.0, 1.0);
  }
  return (sum / missions.length).clamp(0.0, 1.0);
}

// ── weeks ─────────────────────────────────────────────────────────────────

enum PlanWeekState { done, current, locked }

/// Done before the focus week (or everywhere once all required work is
/// done), current at it, locked after it.
PlanWeekState planWeekState(BackendPlan plan, int week) {
  if (plan.allMissionWorkComplete) return PlanWeekState.done;
  final focus = plan.focusWeek;
  if (week < focus) return PlanWeekState.done;
  return week == focus ? PlanWeekState.current : PlanWeekState.locked;
}

/// A week's title: its first mission's title. The plan has no separate week
/// titles.
String planWeekTitle(BackendPlan plan, int week) {
  final missions = plan.missionsForWeek(week);
  if (missions.isEmpty) return 'Week $week';
  final title = missions.first.title.trim();
  return title.isEmpty ? 'Week $week' : title;
}

// ── missions ──────────────────────────────────────────────────────────────

/// How a mission sits in its week.
enum PlanMissionStatus {
  /// Finished.
  done,

  /// The mission to work on now.
  current,

  /// Unfinished and not the current one: the learner moved on, or started it.
  open,

  /// After the current mission, and not started.
  locked,
}

/// Whether the learner has already started [mission]: it is in progress or
/// has any progress. A started mission is never locked.
bool missionStarted(BackendPlanItem mission) =>
    mission.status == 'in_progress' || mission.progressPercent > 0;

/// The status of each of [week]'s missions, in order. The focus mission is
/// current; one after it that has not been started is locked; a started one,
/// or one before it, is open.
List<PlanMissionStatus> planMissionStatuses(BackendPlan plan, int week) {
  final missions = plan.missionsForWeek(week);
  final focus = plan.focusedItemForWeek(week);
  // Without a focus mission nothing is locked.
  final focusIndex = focus == null ? missions.length : missions.indexOf(focus);
  return [
    for (var i = 0; i < missions.length; i++)
      missions[i].isCompleted
          ? PlanMissionStatus.done
          : i == focusIndex
          ? PlanMissionStatus.current
          : i > focusIndex && !missionStarted(missions[i])
          ? PlanMissionStatus.locked
          : PlanMissionStatus.open,
  ];
}

// ── habits ────────────────────────────────────────────────────────────────

/// The Monday-to-Sunday grid of one habit for the week containing [today]:
/// true for a day it was done, false for one it was not (or has not come),
/// and null for today itself (the screen fills it from the live habit).
///
/// [status] is the habit's own `/daily-status`; days are matched by date, so
/// a server week that differs from the device's leaves the unmatched days
/// not done. Null [status] (still loading) shows no days done.
List<bool?> habitWeekFromStatus(DailyStatus? status, DateTime today) {
  final day = DateTime.utc(today.year, today.month, today.day);
  final monday = day.subtract(Duration(days: day.weekday - 1));
  final done = <DateTime>{
    for (final d in status?.days ?? const <DailyStatusDay>[])
      if (d.completed) DateTime.utc(d.date.year, d.date.month, d.date.day),
  };
  return [
    for (var i = 0; i < 7; i++)
      () {
        final d = monday.add(Duration(days: i));
        if (d == day) return null;
        if (d.isAfter(day)) return false;
        return done.contains(d);
      }(),
  ];
}

// ── tutorials ─────────────────────────────────────────────────────────────

/// A tutorial row's state.
enum TutorialRowState {
  /// Finished.
  done,

  /// The next one to take; readable now.
  current,

  /// Written, but after the current one.
  locked,

  /// Not written (or reviewed) yet; generation is running.
  preparing,

  /// The one in front was never written and generation stopped.
  stopped,
}

/// The state of each of [detail]'s tutorials, in order.
///
/// A step without a lesson is "preparing" while the lessons are being
/// written, wherever it sits; the design shows the later ones that way too.
/// When generation has stopped, the first unfinished step is "stopped"
/// (the mission screen offers "Generate again") and later unwritten ones stay
/// locked. With [missionLocked] every unfinished tutorial is locked, as the
/// design shows the next mission.
List<TutorialRowState> tutorialRowStates(
  PlanItemDetailed detail, {
  bool missionLocked = false,
}) {
  final active = detail.activeStepIndex;
  return [
    for (var i = 0; i < detail.steps.length; i++)
      () {
        final step = detail.steps[i];
        if (detail.completed || detail.isStepCompleted(step.id)) {
          return TutorialRowState.done;
        }
        if (missionLocked) return TutorialRowState.locked;
        if (!step.hasContent) {
          if (detail.detailsFailed) {
            return i == active
                ? TutorialRowState.stopped
                : TutorialRowState.locked;
          }
          return TutorialRowState.preparing;
        }
        return i == active
            ? TutorialRowState.current
            : TutorialRowState.locked;
      }(),
  ];
}

/// How many of [detail]'s tutorials are finished, out of how many.
({int done, int total}) tutorialCounts(PlanItemDetailed detail) {
  final done = tutorialRowStates(
    detail,
  ).where((state) => state == TutorialRowState.done).length;
  return (done: done, total: detail.steps.length);
}

/// A tutorial's minutes: reading plus practice, else its single estimate;
/// null while it has neither.
int? tutorialMinutes(PlanStepDetail step) {
  final read = step.effectiveReadingMinutes ?? 0;
  final practice = step.effectivePracticeMinutes ?? 0;
  if (read + practice > 0) return read + practice;
  final estimate = step.estimateMinutes;
  return estimate != null && estimate > 0 ? estimate : null;
}

// ── blueprint ─────────────────────────────────────────────────────────────

/// One numbered priority of the blueprint card.
class BlueprintPriority {
  const BlueprintPriority(this.title, this.detail);

  final String title;

  /// May be empty.
  final String detail;
}

/// The blueprint card's parts, read from the mentor's blueprint markdown.
class PlanBlueprint {
  const PlanBlueprint({
    required this.direction,
    this.priorities = const [],
    this.rationale,
  });

  /// The one-line direction shown on the collapsed card.
  final String direction;

  /// The numbered priorities, in order.
  final List<BlueprintPriority> priorities;

  /// The "Why this order" paragraph.
  final String? rationale;

  /// Whether the card has anything to expand to.
  bool get hasDetail => priorities.isNotEmpty || rationale != null;
}

/// Reads the blueprint prompt's markdown (`blueprint_generate.txt`) into the
/// card's parts, by heading:
///
/// - **direction**: the first sentence under the heading that names the
///   thesis or direction (the "Twelve-Week Thesis"); without one, the raw
///   first paragraph.
/// - **priorities**: the bullets under a heading named "priorities", else
///   "phase" (the "Phase Intent" weeks), else "guardrails". A `**bold**`
///   lead-in, or the text before the first colon, is the title.
/// - **rationale**: the first paragraph under a heading naming a verdict,
///   rationale, reason or "why" (the "Strategic Verdict").
///
/// Anything the markdown lacks is simply left out. Null when it has no
/// prose at all.
PlanBlueprint? parseBlueprint(String? markdown) {
  if (markdown == null || markdown.trim().isEmpty) return null;
  final sections = _sections(markdown);

  _Section? find(RegExp heading) {
    for (final section in sections) {
      if (section.heading.isNotEmpty && heading.hasMatch(section.heading)) {
        return section;
      }
    }
    return null;
  }

  final thesis = find(RegExp(r'thesis|direction', caseSensitive: false));
  var direction = '';
  if (thesis != null) {
    direction = _clip(_firstSentence(thesis.prose), 200);
  }
  if (direction.isEmpty) {
    for (final section in sections) {
      final paragraph = section.firstParagraph;
      if (paragraph.isNotEmpty) {
        direction = _clip(paragraph, 240);
        break;
      }
    }
  }
  if (direction.isEmpty) {
    // Headings only.
    final heading = sections.firstWhere(
      (s) => s.heading.isNotEmpty,
      orElse: () => const _Section('', []),
    );
    direction = _plain(heading.heading);
  }
  if (direction.isEmpty) return null;

  final prioritySection =
      find(RegExp('priorit', caseSensitive: false)) ??
      find(RegExp('phase', caseSensitive: false)) ??
      find(RegExp('guardrail', caseSensitive: false));
  final priorities = prioritySection == null
      ? const <BlueprintPriority>[]
      : _priorities(prioritySection);

  final rationaleSection = find(
    RegExp(r'verdict|rationale|reason|\bwhy\b', caseSensitive: false),
  );
  final rationale = rationaleSection == null
      ? ''
      : _clip(rationaleSection.firstParagraph, 320);

  return PlanBlueprint(
    direction: direction,
    priorities: priorities,
    rationale: rationale.isEmpty ? null : rationale,
  );
}

class _Section {
  const _Section(this.heading, this.lines);

  /// Heading text; empty for the text before the first heading.
  final String heading;
  final List<String> lines;

  /// Paragraphs (blank-line separated), as plain text.
  List<String> get paragraphs {
    final out = <String>[];
    final current = <String>[];
    void flush() {
      final text = _plain(current.join(' '));
      if (text.isNotEmpty) out.add(text);
      current.clear();
    }

    for (final line in lines) {
      if (line.trim().isEmpty) {
        flush();
      } else {
        current.add(line.trim());
      }
    }
    flush();
    return out;
  }

  String get firstParagraph {
    final all = paragraphs;
    return all.isEmpty ? '' : all.first;
  }

  /// All prose, paragraphs joined by a space.
  String get prose => paragraphs.join(' ');
}

List<_Section> _sections(String markdown) {
  final heading = RegExp(r'^#{1,6}\s+(.*?)\s*#*\s*$');
  final sections = <_Section>[];
  var title = '';
  var lines = <String>[];
  for (final raw in markdown.split('\n')) {
    final match = heading.firstMatch(raw.trim());
    if (match != null) {
      sections.add(_Section(title, lines));
      title = _plain(match.group(1)!);
      lines = <String>[];
    } else {
      lines.add(raw);
    }
  }
  sections.add(_Section(title, lines));
  return sections
      .where((s) => s.heading.isNotEmpty || s.paragraphs.isNotEmpty)
      .toList();
}

/// The bullets (or, without bullets, the lines) of [section] as priorities.
List<BlueprintPriority> _priorities(_Section section) {
  final bullet = RegExp(r'^([-*+]|\d+[.)])\s+');
  final lines = section.lines.map((l) => l.trim()).where((l) => l.isNotEmpty);
  final bullets = lines.where(bullet.hasMatch).toList();
  final source = (bullets.isNotEmpty ? bullets : lines.toList())
      .map((l) => l.replaceFirst(bullet, ''))
      .toList();

  final out = <BlueprintPriority>[];
  for (final line in source) {
    // `**Weeks 1-3 — Foundation:** one sentence`
    final bold = RegExp(r'^\*\*(.+?)\*\*\s*[:\-–—]?\s*(.*)$').firstMatch(line);
    if (bold != null) {
      final title = _plain(bold.group(1)!).replaceFirst(RegExp(r'[:\s]+$'), '');
      final detail = _plain(bold.group(2)!);
      if (title.isNotEmpty) out.add(BlueprintPriority(title, detail));
      continue;
    }
    final text = _plain(line);
    if (text.isEmpty) continue;
    final colon = text.indexOf(':');
    if (colon > 0 && colon <= 60) {
      out.add(
        BlueprintPriority(
          text.substring(0, colon).trim(),
          text.substring(colon + 1).trim(),
        ),
      );
    } else {
      out.add(BlueprintPriority(text, ''));
    }
    if (out.length >= 5) break;
  }
  return out.take(5).toList();
}

/// Markdown emphasis, code ticks and link syntax removed; whitespace
/// collapsed.
String _plain(String text) => text
    .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
    .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'[*_`]+'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

const _abbreviations = {
  'mr',
  'mrs',
  'ms',
  'dr',
  'st',
  'vs',
  'jr',
  'sr',
  'no',
  'inc',
  'e.g',
  'i.e',
  'u.s',
};

/// The first sentence of [text]. A full stop inside a decimal ("4.5") or
/// after an abbreviation ("Mr.") does not end it; text with no sentence end
/// is returned whole.
String _firstSentence(String text) {
  for (final match in RegExp(r'[.!?…]+["”’)\]]*').allMatches(text)) {
    final end = match.end;
    if (end < text.length && text[end] != ' ') continue;
    final word = RegExp(
      r'([\w.]+)$',
    ).firstMatch(text.substring(0, match.start))?.group(1)?.toLowerCase();
    if (word != null &&
        match.group(0) == '.' &&
        _abbreviations.contains(word)) {
      continue;
    }
    return text.substring(0, end).trim();
  }
  return text.trim();
}

String _clip(String text, int max) {
  if (text.length <= max) return text;
  final cut = text.substring(0, max);
  final space = cut.lastIndexOf(' ');
  return '${(space > max * 0.6 ? cut.substring(0, space) : cut).trimRight()}…';
}
