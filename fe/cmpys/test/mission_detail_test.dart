// The mission screen (`MissionScreen`, `MaterialRow` and `MaterialSheet` in
// `v3/plan.jsx`): kick, workload, tutorial timeline, deliverable, mental
// model and materials with their reading access.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/cmpys/state/today_data.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/book_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/material_video_screen.dart';
import 'package:cmpys/features/plan/presentation/material_web_screen.dart';
import 'package:cmpys/features/plan/presentation/mission_detail_data.dart';
import 'package:cmpys/features/plan/presentation/plan_item_detail_screen.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';

const _missionJson = {
  'id': 'mission-1',
  'title': 'Write the owner’s memo',
  'type': 'project',
  'description': 'Turn the week’s reading into one page an owner can act on.',
  'weekStart': 3,
  'weekEnd': 3,
  'successMetric': 'A one-page memo that ends in one clear decision.',
  'estimatedHours': 2,
  'estimatedMinutes': 120,
  'status': 'in_progress',
};

Map<String, Object?> _step(int n, {bool ready = true}) => {
  'id': 'step_$n',
  'title': 'Tutorial title $n',
  'estimate_minutes': 7,
  'reading_minutes': 4,
  'practice_minutes': 3,
  if (ready) 'lesson_content': 'A short tutorial body for step $n.',
};

/// Four tutorials: one done, the current one, one locked, one preparing.
PlanItemDetailed _mission({
  String status = 'partial',
  String? definitionOfDone,
  String? mentalModel,
  List<Map<String, Object?>> materials = const [],
  List<Map<String, Object?>>? steps,
  Set<String> completed = const {'step_1'},
}) => PlanItemDetailed.fromJson({
  'item': _missionJson,
  'details_status': status,
  if (status == 'partial') 'job_id': 'job-1',
  'artifact_job_id': 'artifact-1',
  'details_step': 'lessons_ready',
  'completed_step_ids': completed.toList(),
  'details': {
    'lesson_format': 'tutorial_v1',
    'steps': steps ?? [_step(1), _step(2), _step(3), _step(4, ready: false)],
    'materials': materials,
    if (definitionOfDone != null) 'definition_of_done': definitionOfDone,
    if (mentalModel != null) 'mental_model': mentalModel,
  },
});

class _Repo extends Fake implements PlanRepository {
  _Repo(this.detail, {this.access = const {}, this.pending = const {}});

  final PlanItemDetailed detail;
  final Map<String, BookReadingAccess> access;

  /// Access checks that stay in flight until the test completes them.
  final Map<String, Completer<BookReadingAccess>> pending;

  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async => detail;

  @override
  Future<PlanJobStatus> getPlanDetailJobStatus(String jobId) async =>
      const PlanJobStatus(
        id: 'job-1',
        status: 'running',
        step: 'lessons_ready',
        progressPercent: 70,
      );

  @override
  Future<BookReadingAccess> resolveBookReadingAccess(
    String key,
    String title,
    String? author,
  ) =>
      pending[title]?.future ??
      Future.value(access[title] ?? const BookReadingAccess());
}

/// Records the desired state each mission toggle sends, and the plan id an
/// achievement is saved under.
class _ToggleRepo extends _Repo {
  _ToggleRepo(super.detail);

  final toggles = <bool?>[];
  final savedPlanIds = <String?>[];
  int saves = 0;

  @override
  Future<ToggleResult> toggleItemComplete(
    String itemId, {
    String? artifactJobId,
    bool? complete,
  }) async {
    toggles.add(complete);
    return ToggleResult(completed: complete ?? !detail.completed);
  }

  /// The category the achievement suggestion carries.
  String suggestedCategory = 'project';

  @override
  Future<({String title, String category})> fetchAchievementSuggestion(
    String itemId,
  ) async => (title: 'Wrote the owner’s memo', category: suggestedCategory);

  @override
  Future<String?> saveAchievement({
    required String title,
    required String category,
    String? notes,
    String? evidenceLink,
    required String source,
    String? planId,
    String? planItemId,
    int cycleNumber = 1,
  }) async {
    saves++;
    savedPlanIds.add(planId);
    return 'ach-$saves';
  }
}

/// A mission without tutorials: "Mark as done" is its only way to finish.
PlanItemDetailed _plainMission({bool completed = false}) =>
    PlanItemDetailed.fromJson({
      'item': _missionJson,
      'details_status': 'available',
      'artifact_job_id': 'artifact-1',
      'completed': completed,
      'details': {'steps': <Object?>[], 'materials': <Object?>[]},
    });

/// Records each page a material CTA pushes, then removes it before it
/// builds: the web and video viewers need platform views a widget test
/// does not have.
class _Opened extends NavigatorObserver {
  final List<Widget> screens = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! MaterialPageRoute) return;
    screens.add(route.builder(navigator!.context));
    scheduleMicrotask(() => route.navigator?.removeRoute(route));
  }
}

class _Plan extends CurrentPlanController {
  _Plan(PlanRepository repo, BackendPlan plan)
    : super(repo: repo, readJobId: () => null) {
    state = CurrentPlanState(status: CurrentPlanStatus.ready, plan: plan);
  }

  @override
  Future<void> refresh() async {}
}

Widget _app(
  PlanRepository repo, {
  BackendPlan? plan,
  NavigatorObserver? observer,
}) => ProviderScope(
  overrides: [
    planRepositoryProvider.overrideWithValue(repo),
    if (plan != null)
      currentPlanProvider.overrideWith((_) => _Plan(repo, plan)),
  ],
  child: MaterialApp(
    // Reduced motion: the current tutorial's glow and spinners hold still.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    navigatorObservers: [?observer],
    home: const PlanItemDetailScreen(itemId: 'mission-1'),
  ),
);

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(390, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Unmount (stops polling) and let any toast timer run out.
Future<void> _end(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpWidget(const SizedBox());
}

BackendPlanItem _item(
  String id, {
  String type = 'project',
  int week = 3,
  int? weekEnd,
}) => BackendPlanItem.fromJson({
  'id': id,
  'title': id,
  'type': type,
  'weekStart': week,
  'weekEnd': weekEnd ?? week,
});

void main() {
  group('pure helpers', () {
    test('workload_bar_sums_to_allocated', () {
      final detail = _mission();
      final workload = missionWorkload(detail.item, detail.steps);
      expect(workload.allocated, 120);
      expect(workload.reading, 16);
      expect(workload.practice, 12);
      expect(workload.deliverable, 92);
      expect(workload.total, 120);
      expect(
        workload.reading + workload.practice + workload.deliverable,
        workload.allocated,
      );

      // Tutorials that overrun the allocation leave no deliverable time.
      final over = missionWorkload(
        BackendPlanItem.fromJson(const {'id': 'x', 'estimatedHours': 0}),
        detail.steps,
      );
      expect(over.allocated, 0);
      expect(over.deliverable, 0);
      // total == max(allocated, reading + practice).
      expect(over.total, 28);

      // Hours are the fallback when minutes are missing.
      final hours = missionWorkload(
        BackendPlanItem.fromJson(const {'id': 'x', 'estimatedHours': 3}),
        const [],
      );
      expect(hours.allocated, 180);
      expect(hours.deliverable, 180);
    });

    test('kick names the mission among its week’s missions', () {
      final item = _item('mission-1');
      final plan = BackendPlan(
        id: 'p',
        durationWeeks: 12,
        weeklyHours: 4,
        items: [
          _item('mission-0'),
          _item('habit', type: 'habit'),
          item,
          _item('later', week: 4),
        ],
      );
      expect(missionKick(item, plan), 'Week 3 · Mission 2 of 2');
      expect(missionKick(item, null), 'Week 3 · Mission');

      // A mission spanning weeks keeps its range.
      final span = _item('mission-1', weekEnd: 4);
      final spanPlan = BackendPlan(
        id: 'p',
        durationWeeks: 12,
        weeklyHours: 4,
        items: [_item('mission-0'), span],
      );
      expect(missionKick(span, spanPlan), 'Week 3–4 · Mission 2 of 2');
      expect(missionKick(span, null), 'Week 3–4 · Mission');
    });

    test('definition of done splits into checklist lines', () {
      expect(definitionOfDoneLines(null), isEmpty);
      expect(definitionOfDoneLines('   '), isEmpty);
      expect(definitionOfDoneLines('One page, one decision.'), [
        'One page, one decision.',
      ]);
      expect(definitionOfDoneLines('- One page\n- One decision\n\n* Sent'), [
        'One page',
        'One decision',
        'Sent',
      ]);
      expect(definitionOfDoneLines('1. Draft\n2) Review'), ['Draft', 'Review']);
      expect(definitionOfDoneLines('• Draft • Review'), ['Draft', 'Review']);
    });

    test('mental model splits a short head into a title', () {
      expect(splitMentalModel(null), isNull);
      expect(splitMentalModel(' '), isNull);
      // The prompts ask for a model name: a bare name is the title.
      expect(splitMentalModel('Margin of safety'), (
        title: 'Margin of safety',
        body: '',
      ));
      expect(splitMentalModel('Inversion:'), (title: 'Inversion', body: ''));
      // A name with its explanation.
      expect(splitMentalModel('Inversion: start from how it fails.'), (
        title: 'Inversion',
        body: 'start from how it fails.',
      ));
      // A long sentence, as catalog missions store, stays body text.
      const sentence =
          'Apply pricing power to produce an owner’s memo for a durable '
          'business';
      expect(splitMentalModel(sentence), (title: null, body: sentence));
      expect(splitMentalModel('Owner’s lens: decide before you write.'), (
        title: 'Owner’s lens',
        body: 'decide before you write.',
      ));
      expect(splitMentalModel('Owner’s lens — decide first.'), (
        title: 'Owner’s lens',
        body: 'decide first.',
      ));
      final long = '${'x' * 61}: body';
      expect(splitMentalModel(long), (title: null, body: long));
      expect(splitMentalModel('Apply the skill to the memo.'), (
        title: null,
        body: 'Apply the skill to the memo.',
      ));
    });

    test('material access type follows what the CTA opens', () {
      const guide = PlanMaterialDetail(
        title: 'Guide',
        type: 'in_app_lesson',
        contentMarkdown: '# Guide',
      );
      const book = PlanMaterialDetail(
        title: 'Book',
        type: 'book',
        canonicalKey: 'book:a:b',
      );
      const source = BookReadingSource(
        url: 'https://example.org/book',
        scope: 'full_text',
        description: 'Full text.',
      );
      const excerpt = BookReadingSource(
        url: 'https://example.org/excerpt',
        scope: 'excerpt',
        description: 'Excerpt.',
      );
      const unavailable = BookGuideUnavailableException(
        status: 'failed_quality',
        message: 'No verified source',
      );
      expect(accessTypeForMaterial(guide), AccessType.guide);
      expect(
        accessTypeForMaterial(book, resolvedGuideId: 'res-1'),
        AccessType.guide,
      );
      // Not checked yet: opening it prepares the in-app guide.
      expect(accessTypeForMaterial(book), AccessType.guide);
      expect(
        accessTypeForMaterial(
          book,
          bookAccess: const BookReadingAccess(source: source),
        ),
        AccessType.original,
      );
      expect(
        accessTypeForMaterial(
          book,
          bookAccess: const BookReadingAccess(
            source: excerpt,
            unavailable: unavailable,
          ),
        ),
        AccessType.excerpt,
      );
      expect(
        accessTypeForMaterial(
          book,
          bookAccess: const BookReadingAccess(unavailable: unavailable),
        ),
        AccessType.none,
      );
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Book',
            type: 'book',
            url: 'https://example.org/book',
          ),
        ),
        AccessType.web,
      );
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Talk',
            url: 'https://www.youtube.com/watch?v=abc123',
          ),
        ),
        AccessType.video,
      );
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Course',
            type: 'course',
            url: 'https://example.org/course',
            contentResourceId: 'legacy',
          ),
        ),
        AccessType.web,
      );
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Article',
            type: 'article',
            url: 'https://example.org/a',
          ),
        ),
        AccessType.web,
      );
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(title: 'Course', type: 'course'),
        ),
        AccessType.none,
      );
      // A video with nothing to play has no readable edition.
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(title: 'Talk', type: 'video'),
        ),
        AccessType.none,
      );
      // Only YouTube plays in the in-app video viewer; another video link is
      // a web source.
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Talk',
            type: 'video',
            url: 'https://www.youtube.com/watch?v=abc123',
          ),
        ),
        AccessType.video,
      );
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Talk',
            type: 'video',
            url: 'https://vimeo.com/123456',
          ),
        ),
        AccessType.web,
      );
      // A book's own link outranks an unresolved guide key: the CTA opens it.
      expect(
        accessTypeForMaterial(
          const PlanMaterialDetail(
            title: 'Book',
            type: 'book',
            canonicalKey: 'book:a:b',
            url: 'https://example.org/book',
          ),
        ),
        AccessType.web,
      );
    });
  });

  testWidgets('kick, title and workload follow the plan', (tester) async {
    final detail = _mission(status: 'available');
    final repo = _Repo(detail);
    await _pump(
      tester,
      _app(
        repo,
        plan: BackendPlan(
          id: 'p',
          durationWeeks: 12,
          weeklyHours: 4,
          items: [
            detail.item,
            _item('mission-2'),
            _item('h', type: 'habit'),
          ],
        ),
      ),
    );

    expect(find.text('WEEK 3 · MISSION 1 OF 2'), findsOneWidget);
    expect(find.text('Write the owner’s memo'), findsOneWidget);
    expect(find.text('120/120 min'), findsOneWidget);
    await _end(tester);
  });

  group('mission completion', () {
    testWidgets('mark as done asks for the completed state, not a toggle', (
      tester,
    ) async {
      final repo = _ToggleRepo(_plainMission());
      await _pump(tester, _app(repo));
      await tester.tap(find.text('Mark as done'));
      await tester.pumpAndSettle();
      // A retry after a lost response can never un-complete the mission.
      expect(repo.toggles, [true]);
      await _end(tester);
    });

    testWidgets('mark as not done asks for the not-completed state', (
      tester,
    ) async {
      final repo = _ToggleRepo(_plainMission(completed: true));
      await _pump(tester, _app(repo));
      await tester.tap(find.text('Mark as not done'));
      await tester.pumpAndSettle();
      expect(repo.toggles, [false]);
      await _end(tester);
    });

    testWidgets('an achievement saved before the plan loads carries no plan '
        'id, never an empty one', (tester) async {
      final repo = _ToggleRepo(_plainMission());
      await _pump(tester, _app(repo));
      await tester.tap(find.text('Mark as done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm achievement'));
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      expect(repo.savedPlanIds, [null]);
      await _end(tester);
    });
  });

  group('mission achievement on the record (R3-I1)', () {
    CmpysState store(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byType(PlanItemDetailScreen)),
    ).read(cmpysStoreProvider);

    testWidgets('a confirmed mission achievement joins the Record under its '
        'category’s dimension, with its server id', (tester) async {
      final repo = _ToggleRepo(_plainMission())..suggestedCategory = 'finance';
      await _pump(tester, _app(repo));
      await tester.tap(find.text('Mark as done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm achievement'));
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      final win = store(tester).achievements.single;
      expect(win.title, 'Wrote the owner’s memo');
      expect(win.dim, 'capital');
      expect(win.source, 'auto');
      expect(win.assessed, isTrue);
      expect(win.synced, isTrue);
      expect(win.serverId, 'ach-1');
      expect(win.idolNote, isNull);
      // No known age: kept at 0, so the Record files it under Undated.
      expect(win.age, 0);
      await _end(tester);
    });

    testWidgets('a category with no dimension files the win under Practice', (
      tester,
    ) async {
      final repo = _ToggleRepo(_plainMission())..suggestedCategory = 'other';
      await _pump(tester, _app(repo));
      await tester.tap(find.text('Mark as done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm achievement'));
      await tester.pumpAndSettle();
      expect(store(tester).achievements.single.dim, 'practice');
      await _end(tester);
    });

    testWidgets('a skipped achievement adds nothing to the Record', (
      tester,
    ) async {
      final repo = _ToggleRepo(_plainMission());
      await _pump(tester, _app(repo));
      await tester.tap(find.text('Mark as done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      expect(store(tester).achievements, isEmpty);
      await _end(tester);
    });
  });

  testWidgets('kick falls back while the plan is not loaded', (tester) async {
    await _pump(tester, _app(_Repo(_mission(status: 'available'))));
    expect(find.text('WEEK 3 · MISSION'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('workload_bar_sums_to_allocated', (tester) async {
    await _pump(tester, _app(_Repo(_mission(status: 'available'))));

    expect(find.text('Workload'), findsOneWidget);
    expect(find.text('120 / 120 min allocated'), findsOneWidget);
    expect(find.text('Reading 16'), findsOneWidget);
    expect(find.text('Practice 12'), findsOneWidget);
    expect(find.text('Deliverable 92'), findsOneWidget);

    final bar = tester.getSize(find.byKey(const Key('workload-bar')));
    double width(String part) =>
        tester.getSize(find.byKey(Key('workload-$part'))).width;
    // Three segments with two 2 pt gaps fill the bar: total == allocated.
    expect(
      width('reading') + width('practice') + width('deliverable') + 4,
      closeTo(bar.width, 0.5),
    );
    expect(width('reading') / width('deliverable'), closeTo(16 / 92, 0.02));
    await _end(tester);
  });

  group('workload split only from known tutorial minutes (F11)', () {
    Map<String, Object?> outlineStep(int n) => {
      'id': 'step_$n',
      'title': 'Tutorial title $n',
    };

    test('tutorials without minutes leave the split unknown, never zero', () {
      // The week-1 case: an outline of tutorials still being written.
      final pending = _mission(
        steps: [for (var n = 1; n <= 4; n++) outlineStep(n)],
      );
      final w = missionWorkload(
        pending.item,
        pending.steps,
        tutorialsPending: !pending.detailsReady,
      );
      expect(w.splitKnown, isFalse);
      expect(w.allocated, 120);

      // One tutorial written, the rest not: still unknown.
      final partial = _mission(
        steps: [_step(1), outlineStep(2), outlineStep(3)],
      );
      expect(
        missionWorkload(partial.item, partial.steps).splitKnown,
        isFalse,
      );

      // A tutorial with reading time but no practice time is not counted
      // as zero practice.
      final noPractice = _mission(
        steps: [
          {..._step(1), 'practice_minutes': null},
        ],
      );
      expect(
        missionWorkload(noPractice.item, noPractice.steps).splitKnown,
        isFalse,
      );

      // Every tutorial with its minutes (even before it is written): known.
      final known = _mission();
      expect(missionWorkload(known.item, known.steps).splitKnown, isTrue);

      // No tutorials at all: the whole allocation is the deliverable once
      // the details are ready, unknown while they are still coming.
      final plain = _plainMission();
      expect(missionWorkload(plain.item, plain.steps).splitKnown, isTrue);
      expect(
        missionWorkload(
          plain.item,
          const [],
          tutorialsPending: true,
        ).splitKnown,
        isFalse,
      );
    });

    testWidgets('a mission whose tutorials have no minutes yet hides the '
        'split', (tester) async {
      await _pump(
        tester,
        _app(
          _Repo(
            _mission(steps: [for (var n = 1; n <= 4; n++) outlineStep(n)]),
          ),
        ),
      );
      expect(find.text('Workload'), findsNothing);
      expect(find.byKey(const Key('workload-bar')), findsNothing);
      expect(find.text('Reading 0'), findsNothing);
      expect(find.text('Practice 0'), findsNothing);
      expect(find.textContaining(RegExp(r'^Deliverable \d')), findsNothing);
      // The allocation itself is still true.
      expect(find.text('120 min'), findsOneWidget);
      expect(find.text('120/120 min'), findsNothing);
      await _end(tester);
    });
  });

  testWidgets('timeline shows done, current, locked and preparing tutorials', (
    tester,
  ) async {
    await _pump(tester, _app(_Repo(_mission())));

    expect(find.text('Tutorials · 1 of 4'), findsOneWidget);
    expect(find.byKey(const Key('lesson-1-completed')), findsOneWidget);
    expect(find.byKey(const Key('lesson-2-active')), findsOneWidget);
    expect(find.byKey(const Key('lesson-3-locked')), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('4 min read + 3 min practice'), findsNWidgets(3));
    expect(find.byKey(const Key('tutorial-progress-line')), findsOneWidget);
    await _end(tester);
  });

  testWidgets('a locked tutorial tap toasts which tutorial to finish first', (
    tester,
  ) async {
    await _pump(tester, _app(_Repo(_mission())));

    await tester.tap(find.byKey(const Key('lesson-3-locked')));
    await tester.pump();
    expect(find.text('Finish tutorial 2 first'), findsOneWidget);
    // No v2 lock sheet.
    expect(find.text('Tutorial 3 is locked'), findsNothing);
    await _end(tester);
  });

  testWidgets('a preparing row shows "preparing and reviewing"', (
    tester,
  ) async {
    await _pump(tester, _app(_Repo(_mission())));

    expect(find.text('Tutorial 4 · preparing and reviewing'), findsOneWidget);
    // Screen readers hear the outline title too.
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(
        'Tutorial 4: Tutorial title 4, preparing and reviewing',
      ),
      findsOneWidget,
    );
    semantics.dispose();
    await tester.tap(find.text('Tutorial 4 · preparing and reviewing'));
    await tester.pump();
    expect(find.text('Still being prepared and reviewed'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('definition-of-done lines render as a checklist', (tester) async {
    await _pump(
      tester,
      _app(
        _Repo(
          _mission(
            status: 'available',
            definitionOfDone:
                '- Memo names one decision\n- A reviewer signs off',
          ),
        ),
      ),
    );

    expect(find.text('Deliverable'), findsOneWidget);
    expect(
      find.text('A one-page memo that ends in one clear decision.'),
      findsOneWidget,
    );
    expect(find.text('DEFINITION OF DONE'), findsOneWidget);
    expect(find.text('Memo names one decision'), findsOneWidget);
    expect(find.text('A reviewer signs off'), findsOneWidget);
    expect(find.byKey(const Key('done-check-0')), findsOneWidget);
    expect(find.byKey(const Key('done-check-1')), findsOneWidget);
    expect(find.byKey(const Key('done-check-2')), findsNothing);
    await _end(tester);
  });

  testWidgets('definition of done is hidden when empty', (tester) async {
    await _pump(tester, _app(_Repo(_mission(status: 'available'))));
    expect(find.text('DEFINITION OF DONE'), findsNothing);
    await _end(tester);
  });

  testWidgets('the mental model card is hidden when absent', (tester) async {
    await _pump(tester, _app(_Repo(_mission(status: 'available'))));
    expect(find.text('MENTAL MODEL'), findsNothing);
    expect(find.byKey(const Key('mental-model-card')), findsNothing);
    await _end(tester);
  });

  testWidgets('the mental model card splits its title from the body', (
    tester,
  ) async {
    await _pump(
      tester,
      _app(
        _Repo(
          _mission(
            status: 'available',
            mentalModel: 'Owner’s lens: every page ends in a decision.',
          ),
        ),
      ),
    );
    expect(find.text('MENTAL MODEL'), findsOneWidget);
    expect(find.text('Owner’s lens'), findsOneWidget);
    expect(find.text('every page ends in a decision.'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('a bare mental model name is the card’s title', (tester) async {
    await _pump(
      tester,
      _app(_Repo(_mission(status: 'available', mentalModel: 'Inversion'))),
    );
    expect(find.text('MENTAL MODEL'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Inversion'));
    expect(title.style?.fontSize, 28);
    // No empty body line under it.
    expect(
      find.descendant(
        of: find.byKey(const Key('mental-model-card')),
        matching: find.byType(Text),
      ),
      findsNWidgets(2),
    );
    await _end(tester);
  });

  testWidgets('material_sheet_cta_by_access_type', (tester) async {
    const unavailable = BookGuideUnavailableException(
      status: 'failed_quality',
      message: 'No verified source',
    );
    final repo = _Repo(
      _mission(
        status: 'available',
        materials: [
          {
            'title': 'Owner’s handbook',
            'type': 'in_app_lesson',
            'content_markdown': '# Handbook\nThe basics.',
            'reason': 'Sets up the vocabulary.',
          },
          {
            'title': 'Meditations',
            'type': 'book',
            'author_or_creator': 'Marcus Aurelius',
            'canonical_key': 'book:marcus:meditations',
          },
          {
            'title': 'The Personal MBA',
            'type': 'book',
            'author_or_creator': 'Josh Kaufman',
            'canonical_key': 'book:josh_kaufman:the_personal_mba',
          },
          {
            'title': 'A field guide',
            'type': 'article',
            'url': 'https://example.org/field-guide',
          },
          {
            'title': 'A short talk',
            'type': 'video',
            'url': 'https://www.youtube.com/watch?v=abc123',
          },
          {
            'title': 'A rare book',
            'type': 'book',
            'canonical_key': 'book:rare:book',
          },
        ],
      ),
      access: const {
        'Meditations': BookReadingAccess(
          source: BookReadingSource(
            url: 'https://example.org/meditations',
            scope: 'full_text',
            description: 'Full text.',
          ),
          unavailable: unavailable,
        ),
        'The Personal MBA': BookReadingAccess(
          source: BookReadingSource(
            url: 'https://example.org/excerpt',
            scope: 'excerpt',
            description: 'Author excerpt.',
          ),
          unavailable: unavailable,
        ),
        'A rare book': BookReadingAccess(unavailable: unavailable),
      },
    );
    await _pump(tester, _app(repo));

    expect(find.text('Materials'), findsOneWidget);
    expect(
      find.text(
        'Required practice is solvable inside CMPYS. Materials are optional depth.',
      ),
      findsOneWidget,
    );
    for (final badge in [
      'Study guide',
      'Original · public domain',
      'Excerpt only',
      'Web source',
      'Video',
      'No readable edition',
    ]) {
      expect(find.text(badge), findsOneWidget, reason: badge);
    }

    final expected = <String, (AccessType, String?)>{
      'Owner’s handbook': (AccessType.guide, 'Open guide'),
      'Meditations': (AccessType.original, 'Read original'),
      'The Personal MBA': (AccessType.excerpt, 'Read excerpt'),
      'A field guide': (AccessType.web, 'Open source'),
      'A short talk': (AccessType.video, 'Watch'),
      'A rare book': (AccessType.none, null),
    };
    for (final MapEntry(key: title, value: (type, cta)) in expected.entries) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      final sheet = find.byKey(V3Sheet.panelKey);
      expect(sheet, findsOneWidget, reason: title);
      Finder inSheet(Finder finder) =>
          find.descendant(of: sheet, matching: finder);
      expect(inSheet(find.text(title)), findsOneWidget);
      expect(inSheet(find.text(accessCopy(type).note)), findsOneWidget);
      if (cta != null) {
        final button = tester.widget<V3Button>(
          find.ancestor(
            of: inSheet(find.text(cta)),
            matching: find.byType(V3Button),
          ),
        );
        expect(button.onPressed, isNotNull, reason: title);
        expect(inSheet(find.text('Not available to read')), findsNothing);
      } else {
        final button = tester.widget<V3Button>(
          find.ancestor(
            of: inSheet(find.text('Not available to read')),
            matching: find.byType(V3Button),
          ),
        );
        expect(button.disabled || button.onPressed == null, isTrue);
      }
      if (title == 'Owner’s handbook') {
        expect(inSheet(find.text('Why it’s here')), findsOneWidget);
        expect(inSheet(find.text('Sets up the vocabulary.')), findsOneWidget);
      }
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
    }
    await _end(tester);
  });

  group('material sheet waits for a book’s access check', () {
    const excerpt = BookReadingAccess(
      source: BookReadingSource(
        url: 'https://example.org/excerpt',
        scope: 'excerpt',
        description: 'Author excerpt.',
      ),
      unavailable: BookGuideUnavailableException(
        status: 'failed_quality',
        message: 'No verified source',
      ),
    );
    PlanItemDetailed keyOnlyBook() => _mission(
      status: 'available',
      materials: [
        {
          'title': 'The Personal MBA',
          'type': 'book',
          'canonical_key': 'book:josh_kaufman:the_personal_mba',
        },
      ],
    );

    testWidgets('a check landing in time opens the sheet on its answer', (
      tester,
    ) async {
      final check = Completer<BookReadingAccess>();
      await _pump(
        tester,
        _app(_Repo(keyOnlyBook(), pending: {'The Personal MBA': check})),
      );
      expect(find.text('Study guide'), findsOneWidget);

      await tester.tap(find.text('The Personal MBA'));
      await tester.pump();
      // Waiting: the row's spinner and no sheet yet.
      expect(find.byKey(V3Sheet.panelKey), findsNothing);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('The Personal MBA'),
            matching: find.byType(V3Pressable),
          ),
          matching: find.byType(V3Spinner),
        ),
        findsOneWidget,
      );

      check.complete(excerpt);
      await tester.pumpAndSettle();
      final sheet = find.byKey(V3Sheet.panelKey);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text('Read excerpt')),
        findsOneWidget,
      );
      expect(find.text('Open guide'), findsNothing);
      await _end(tester);
    });

    testWidgets('a check that lands after the learner moved on opens no '
        'sheet', (tester) async {
      final check = Completer<BookReadingAccess>();
      await _pump(
        tester,
        _app(_Repo(keyOnlyBook(), pending: {'The Personal MBA': check})),
      );
      await tester.tap(find.text('The Personal MBA'));
      await tester.pump();

      // Another page goes over the mission while the access check runs.
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Elsewhere')),
              ),
            ),
      );
      await tester.pumpAndSettle();
      check.complete(excerpt);
      await tester.pumpAndSettle();
      expect(find.text('Elsewhere'), findsOneWidget);
      expect(find.byKey(V3Sheet.panelKey), findsNothing);

      // The wait is over either way: back on the mission, the row is free.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(V3Sheet.panelKey), findsNothing);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('The Personal MBA'),
            matching: find.byType(V3Pressable),
          ),
          matching: find.byType(V3Spinner),
        ),
        findsNothing,
      );
      await _end(tester);
    });

    testWidgets('a slow check opens the sheet, which follows the answer', (
      tester,
    ) async {
      final check = Completer<BookReadingAccess>();
      await _pump(
        tester,
        _app(_Repo(keyOnlyBook(), pending: {'The Personal MBA': check})),
      );

      await tester.tap(find.text('The Personal MBA'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      // Bounded wait: the sheet opens on what is known.
      expect(find.byKey(V3Sheet.panelKey), findsOneWidget);
      expect(find.text('Open guide'), findsOneWidget);

      check.complete(excerpt);
      await tester.pumpAndSettle();
      expect(find.text('Open guide'), findsNothing);
      expect(find.text('Read excerpt'), findsOneWidget);
      expect(
        find.text('A verified excerpt. The full book is not included.'),
        findsOneWidget,
      );
      await _end(tester);
    });
  });

  group('each material CTA opens its viewer', () {
    _Repo repo() => _Repo(
      _mission(
        status: 'available',
        materials: [
          {
            'title': 'A field guide',
            'type': 'article',
            'url': 'https://example.org/field-guide',
          },
          {
            'title': 'A short talk',
            'type': 'video',
            'url': 'https://www.youtube.com/watch?v=abc123',
          },
          {
            'title': 'The Personal MBA',
            'type': 'book',
            'canonical_key': 'book:josh_kaufman:the_personal_mba',
          },
          {
            'title': 'Essays',
            'type': 'book',
            'content_resource_id': 'res-essays',
          },
        ],
      ),
      access: const {
        'The Personal MBA': BookReadingAccess(
          source: BookReadingSource(
            url: 'https://example.org/excerpt',
            scope: 'excerpt',
            description: 'Author excerpt.',
          ),
        ),
      },
    );

    Future<Widget> open(WidgetTester tester, String title, String cta) async {
      final opened = _Opened();
      await _pump(tester, _app(repo(), observer: opened));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(cta));
      await tester.pumpAndSettle();
      expect(opened.screens, hasLength(1), reason: cta);
      return opened.screens.single;
    }

    testWidgets('"Open source" opens the web viewer', (tester) async {
      final screen = await open(tester, 'A field guide', 'Open source');
      expect(screen, isA<MaterialWebScreen>());
      expect(
        (screen as MaterialWebScreen).url,
        'https://example.org/field-guide',
      );
      expect(screen.access, AccessType.web);
      expect(screen.openedFrom, startsWith('Mission · '));
      await _end(tester);
    });

    testWidgets('"Watch" opens the video viewer', (tester) async {
      final screen = await open(tester, 'A short talk', 'Watch');
      expect(screen, isA<MaterialVideoScreen>());
      expect((screen as MaterialVideoScreen).videoId, 'abc123');
      await _end(tester);
    });

    testWidgets('"Read excerpt" opens the web viewer on the source', (
      tester,
    ) async {
      final screen = await open(tester, 'The Personal MBA', 'Read excerpt');
      expect(screen, isA<MaterialWebScreen>());
      expect((screen as MaterialWebScreen).url, 'https://example.org/excerpt');
      expect(screen.sourceDescription, 'Author excerpt.');
      expect(screen.access, AccessType.excerpt);
      expect(screen.openedFrom, startsWith('Mission · '));
      await _end(tester);
    });

    testWidgets('"Open guide" opens the book reader', (tester) async {
      final screen = await open(tester, 'Essays', 'Open guide');
      expect(screen, isA<BookReaderScreen>());
      expect((screen as BookReaderScreen).resourceId, 'res-essays');
      await _end(tester);
    });
  });
}
