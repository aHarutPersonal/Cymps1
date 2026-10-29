import 'package:cmpys/app/theme.dart';
import 'package:cmpys/app/router.dart';
import 'support/design_capture.dart';
import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/features/auth/presentation/auth_screen.dart';
import 'package:cmpys/features/cmpys/data/cmpys_ideas_provider.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/chat_screen.dart';
import 'package:cmpys/features/cmpys/presentation/compare_screen.dart';
import 'package:cmpys/features/cmpys/presentation/detail_screens.dart';
import 'package:cmpys/features/cmpys/presentation/plan_screen.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/onboarding_flow.dart';
import 'package:cmpys/features/cmpys/presentation/reels_screen.dart';
import 'package:cmpys/features/cmpys/presentation/record_screen.dart';
import 'package:cmpys/features/cmpys/presentation/today_screen.dart';
import 'package:cmpys/features/cmpys/presentation/you_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/cmpys/state/today_data.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/data/practice_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/models/practice_models.dart';
import 'package:cmpys/features/plan/presentation/lesson_practice_screen.dart';
import 'package:cmpys/features/plan/presentation/lesson_reader_screen.dart';
import 'package:cmpys/features/plan/presentation/reading_library_screen.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyPlanRepository implements PlanRepository {
  @override
  Future<BackendPlan?> getCurrentPlan() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BackendPlan _generatedPlan() => BackendPlan(
  id: 'plan-live',
  durationWeeks: 12,
  weeklyHours: 8,
  idolName: 'Alexander the Great',
  overallProgress: 34,
  createdAt: DateTime.now().subtract(const Duration(days: 5)),
  items: const [
    BackendPlanItem(
      id: 'mission-1',
      title: 'Build a leadership operating system for difficult decisions',
      type: 'project',
      description: 'A generated mission description.',
      weekStart: 1,
      weekEnd: 2,
      successMetric: 'Document and apply the system twice.',
      estimatedHours: 3,
      status: 'in_progress',
      progressPercent: 40,
    ),
    BackendPlanItem(
      id: 'habit-1',
      title: 'Review the day and write the next decisive action',
      type: 'habit',
      description: 'A generated daily rhythm.',
      weekStart: 1,
      weekEnd: 2,
      successMetric: 'Complete five reviews each week.',
      estimatedHours: 2,
      status: 'in_progress',
      progressPercent: 30,
    ),
  ],
);

/// The current mission's tutorials and materials, with long generated
/// titles so the NextUp card and the mission shelf are exercised too.
PlanItemDetailed _generatedMissionDetail() => PlanItemDetailed(
  item: _generatedPlan().items.first,
  detailsStatus: 'available',
  lessonFormat: 'tutorial_v1',
  steps: const [
    PlanStepDetail(
      id: 's1',
      title: 'Map every decision you made this week against its outcome',
      readingMinutes: 6,
      practiceMinutes: 8,
      lessonContent: '# One',
      lessonFormat: 'tutorial_v1',
    ),
    PlanStepDetail(
      id: 's2',
      title:
          'Separate reversible decisions from the irreversible ones before '
          'acting on them',
      readingMinutes: 5,
      practiceMinutes: 7,
      lessonContent: '# Two',
      lessonFormat: 'tutorial_v1',
    ),
    PlanStepDetail(id: 's3', title: 'Third', lessonFormat: 'tutorial_v1'),
  ],
  materials: const [
    PlanMaterialDetail(
      title: 'The Campaigns of Alexander, Book One',
      type: 'book',
      authorOrCreator: 'Arrian',
      contentResourceId: 'resource-1',
    ),
    PlanMaterialDetail(
      title: 'Decision journals in practice',
      type: 'article',
      url: 'https://example.com/decision-journals',
    ),
    PlanMaterialDetail(
      title: 'A recommended book with no readable edition',
      type: 'book',
      authorOrCreator: 'Unknown Author',
    ),
  ],
  completedStepIds: const {'s1'},
);

/// Deterministic data for the Today tab's own providers (no network).
List<Override> _todayOverrides() => [
  todayStreakProvider.overrideWith(
    (ref) async => StreakSummary(
      current: 4,
      longest: 9,
      lastActive: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ),
  todayContinueReadingProvider.overrideWith(
    (ref) async => const ContentResource(
      id: 'book-1',
      kind: 'llm_book_summary',
      canonicalKey: 'book:arrian:campaigns',
      title: 'The Campaigns of Alexander and the Making of an Empire',
      authorOrCreator: 'Arrian',
      licenseStatus: 'llm_summary',
      isSaved: false,
      progressPercent: 42,
    ),
  ),
  todayMissionDetailProvider.overrideWith(
    (ref, itemId) async => _generatedMissionDetail(),
  ),
];

class _ReadyPlanController extends CurrentPlanController {
  _ReadyPlanController()
    : super(repo: _EmptyPlanRepository(), readJobId: () => null) {
    state = CurrentPlanState(
      status: CurrentPlanStatus.ready,
      plan: _generatedPlan(),
    );
  }

  @override
  Future<void> refresh() async {}
}

class _ResponsiveStore extends CmpysStore {
  _ResponsiveStore() {
    state = state.copyWith(
      user: CmpysUser(name: 'Alexandria Montgomery', age: 24),
      idol: const CmpysIdol(
        id: 'alexander',
        slug: '__llm__',
        name: 'Alexander the Great',
        short: 'Alexander',
        initials: 'AG',
        title: 'King of Macedon',
        era: '356–323 BCE',
        field: 'Leadership',
        color: AppColors.blue,
        tint: AppColors.blueSoft,
        tag: 'Strategist',
        blurb: '',
        quote: '',
      ),
      comparisonMd: List.filled(
        8,
        'A generated comparison paragraph with enough detail to exercise the responsive preview.',
      ).join('\n\n'),
      liveComparisonScores: {
        'version': 2,
        'methodology': 'like_for_like_evidence',
        'dimensions': [
          for (var i = 0; i < 5; i++)
            {
              'status': const [
                'comparable',
                'comparable',
                'comparable',
                'different_basis',
                'insufficient_user_evidence',
              ][i],
              'comparison_basis':
                  'A generated note on why these two records can or cannot '
                  'be compared like for like.',
              'id': ['capital', 'knowledge', 'habits', 'network', 'clarity'][i],
              'label': [
                'Capital at work',
                'Knowledge base',
                'Daily discipline',
                'Trusted network',
                'Strategic clarity',
              ][i],
              'you': 35 + i * 6,
              'idol': 68 + i * 4,
              'you_note': 'Generated assessment of the user.',
              'idol_note': 'Generated assessment of the mentor.',
            },
        ],
        'milestones': [
          {'id': 'm1', 'label': 'Completed a generated milestone'},
        ],
      },
    );
  }
}

/// Edit profile is a sheet body (`v3/you.jsx`); host it in the sheet panel,
/// bottom-aligned and inset 8 pt, as `showV3Sheet` does.
class _InSheet extends StatelessWidget {
  const _InSheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    body: Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: V3Sheet(title: title, child: child),
      ),
    ),
  );
}

const _idea = CmpysIdea(
  id: 'live-idea',
  text: 'A generated idea that remains readable on every supported phone.',
  author: 'Mentor',
  tag: 'Focus',
  tone: AppColors.green,
  likes: 0,
);

/// The Library's shelves, with long generated titles; no network.
class _LibraryRepository extends Fake implements ContentResourcesRepository {
  static ContentResource _book(
    String id,
    String title,
    String author, {
    int progress = 0,
    bool saved = false,
    bool completed = false,
  }) => ContentResource(
    id: id,
    kind: 'llm_book_summary',
    canonicalKey: 'book:$id',
    title: title,
    authorOrCreator: author,
    licenseStatus: 'llm_summary',
    isSaved: saved,
    progressPercent: progress,
    completedAt: completed ? DateTime(2026, 10, 1) : null,
    contentMarkdown: '## One\n\nA readable chapter for $title.',
  );

  static final books = [
    _book(
      'essays',
      'The Essays of Warren Buffett: Lessons for Corporate America',
      'Lawrence A. Cunningham',
      progress: 42,
      saved: true,
    ),
    _book('artofwar', 'The Art of War', 'Sun Tzu'),
    _book(
      'wealth',
      'An Inquiry into the Nature and Causes of the Wealth of Nations',
      'Adam Smith',
      progress: 100,
      completed: true,
    ),
    _book('blindness', 'Blindness', 'José Saramago'),
  ];

  @override
  Future<List<ContentResource>> listLibraryResources({
    String? kind,
    String? query,
    String? sort,
    int limit = 50,
    int offset = 0,
  }) async => books;

  @override
  Future<ContentResource?> getContinueReading() async => books.first;
}

/// A tutorial that uses every v3 fence, with long generated headings.
const _tutorialMarkdown = """
# Separating reversible decisions from the irreversible ones before acting

## Why This Matters
Reported profit is not the cash an owner can take out, and a decision that
cannot be undone deserves a different standard of evidence than one that can.

## Core Framework
Owner earnings adjust reported profit for what the business really consumes.

```formula
title: Owner earnings
= Owner earnings
+ Net income
- Maintenance capex
```

## Worked Example
Take a company that reports 80 of net income.

```chart
type: waterfall
title: Reported to owner earnings
Net | 80
D&A | 12
Maint. | -24
= Owner | 68
```

```steps
title: Harbor Tools
Start from net income | 80 | The reported profit.
Add back D&A | 12 | A non-cash charge.
Subtract maintenance capex | -24 | Spending that keeps the lights on.
= Owner earnings | 68
```

## Failure Modes
- Treating growth capex as maintenance and flattering the result.
- Ignoring working capital that the business has to keep funding.

## Check Your Understanding
```check
Q: What are the owner earnings here?
- [ ] 80
- [x] 68
- [ ] 92
- [ ] 56
Why: 80 plus 12 minus 24 is 68.
```

## References
- Start With Why
""";

PlanStepDetail _readerStep() => const PlanStepDetail(
  id: 's2',
  title: 'Separate reversible decisions from the irreversible ones',
  readingMinutes: 6,
  practiceMinutes: 12,
  resources: ['Start With Why'],
  lessonContent: _tutorialMarkdown,
  lessonFormat: 'tutorial_v1',
);

Map<String, dynamic> _practiceField(
  String id,
  String label,
  String kind, {
  String unit = '',
  String? prefix,
  List<List<String>> choices = const [],
}) => {
  'id': id,
  'label': label,
  'kind': kind,
  'unit': unit,
  if (prefix != null) 'prefix': prefix,
  'choices': [
    for (final c in choices) {'id': c[0], 'label': c[1]},
  ],
  'rubric_criterion': label,
};

/// A ready workbook: a guided case with a data table and every field kind,
/// then an independent one; no network.
class _PracticeRepo extends Fake implements PracticeRepository {
  @override
  Future<LessonPracticeState> load(String item, String step, String? a) async =>
      LessonPracticeState.fromJson({
        'state': 'ready',
        'revision': 1,
        'lesson_version': 'v1',
        'complete': false,
        'answers': <String, String>{},
        'attempts': <Map<String, dynamic>>[],
        'hints': <Map<String, dynamic>>[],
        'passed_activity_ids': <String>[],
        'workbook': {
          'title': 'Owner earnings',
          'activities': [
            {
              'id': 'guided',
              'title': 'Owner earnings at Harbor Tools and its subsidiaries',
              'kind': 'practice',
              'instructions':
                  'Harbor Tools reported net income of 120. Work out what '
                  'its owners really earned this year, and say why the '
                  'reported figure misleads.',
              'minutes_min': 6,
              'minutes_max': 10,
              'data': [
                {'id': 'ni', 'label': 'Net income', 'value': 120, 'unit': 'm'},
                {'id': 'capex', 'label': 'Capital expenditure', 'value': 70},
                {
                  'id': 'wh',
                  'label': '… of which new warehouse and distribution hub',
                  'value': 25.0,
                },
              ],
              'fields': [
                _practiceField(
                  'oe',
                  'Owner earnings',
                  'number',
                  unit: 'm',
                  prefix: r'$',
                ),
                _practiceField(
                  'lines',
                  'Which lines are maintenance?',
                  'multi_choice',
                  choices: [
                    ['repairs', 'Repairs'],
                    ['warehouse', 'New warehouse'],
                    ['fleet', 'Fleet replacement'],
                  ],
                ),
                _practiceField(
                  'buy',
                  'Is it worth 1.2bn?',
                  'choice',
                  choices: [
                    ['no', 'No'],
                    ['yes', 'Yes'],
                  ],
                ),
                _practiceField(
                  'why',
                  'Why does net income mislead here?',
                  'text',
                ),
              ],
            },
            {
              'id': 'independent',
              'title': 'Owner earnings at Delta Foods',
              'kind': 'transfer',
              'instructions':
                  'Delta Foods reported net income of 64. Work out owner '
                  'earnings on your own.',
              'minutes_min': 6,
              'minutes_max': 10,
              'data': <Map<String, dynamic>>[],
              'fields': [
                _practiceField(
                  'oe',
                  'Owner earnings',
                  'number',
                  unit: 'm',
                  prefix: r'$',
                ),
              ],
            },
          ],
        },
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(prepareDesignCapture);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final screens = <String, Widget Function()>{
    'Auth': () => const AuthScreen(),
    'Onboarding': () => const CmpysOnboardingFlow(),
    'Today': () => const CmpysTodayScreen(),
    'Plan': () => const CmpysPlanScreen(),
    'Chat': () => const CmpysChatScreen(),
    'Compare': () => const CmpysCompareScreen(),
    'You': () => const CmpysYouScreen(),
    'Ideas': () => const CmpysReelsScreen(),
    'Record': () => const CmpysRecordScreen(),
    'Edit profile': () =>
        const _InSheet(title: 'Edit profile', child: CmpysEditProfileScreen()),
    'Notes': () => const CmpysNotesScreen(),
    'Saved': () => const CmpysSavedScreen(),
  };
  final configurations = <({Size size, double textScale, String label})>[
    (size: const Size(320, 568), textScale: 1, label: 'narrow phone'),
    (size: const Size(390, 844), textScale: 1.3, label: 'large text'),
    (
      size: const Size(320, 568),
      textScale: 2,
      label: 'narrow phone at 200% text',
    ),
    (size: const Size(844, 390), textScale: 1, label: 'landscape'),
  ];

  for (final screen in screens.entries) {
    for (final config in configurations) {
      testWidgets('${screen.key} fits ${config.label}', (tester) async {
        tester.view.physicalSize = config.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          FlutterError.dumpErrorToConsole(details);
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cmpysStoreProvider.overrideWith((ref) => _ResponsiveStore()),
              cmpysBackendSyncProvider.overrideWith((ref) async {}),
              // No network: Record falls back to the seeded ledger.
              idolTimelineProvider.overrideWith((ref, name) async => const []),
              cmpysIdeasProvider.overrideWith((ref) async => const [_idea]),
              ..._todayOverrides(),
              currentPlanProvider.overrideWith(
                (ref) => CurrentPlanController(
                  repo: _EmptyPlanRepository(),
                  readJobId: () => null,
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(config.textScale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: designCaptureKey,
                child: screen.value(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        await captureDesign(tester, '${screen.key}-${config.label}');
        final lists = find.byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.vertical,
        );
        if (lists.evaluate().isNotEmpty) {
          final scrollable = find
              .descendant(of: lists.first, matching: find.byType(Scrollable))
              .first;
          for (var i = 0; i < 20; i++) {
            final position = tester.state<ScrollableState>(scrollable).position;
            if (position.pixels >= position.maxScrollExtent) break;
            position.jumpTo(
              (position.pixels + 400).clamp(0.0, position.maxScrollExtent),
            );
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
          }
        }
        if (screen.key == 'Compare') {
          // Both Compare sheets: the written perspective and a dimension.
          final scrollable = find
              .descendant(of: lists.first, matching: find.byType(Scrollable))
              .first;
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pump(const Duration(milliseconds: 300));
          Future<void> openAndClose(Finder target) async {
            await tester.scrollUntilVisible(
              target,
              200,
              scrollable: scrollable,
            );
            await tester.pump(const Duration(milliseconds: 300));
            await tester.tap(target, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            expect(find.byKey(V3Sheet.panelKey), findsOneWidget);
            expect(tester.takeException(), isNull);
            Navigator.of(tester.element(find.byKey(V3Sheet.panelKey))).pop();
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            expect(tester.takeException(), isNull);
          }

          await openAndClose(
            find.byKey(const Key('compare-perspective-card')),
          );
          await openAndClose(
            find.byKey(const ValueKey('compare-dim-row')).first,
          );
          expect(
            find.byKey(const ValueKey('compare-dim-row')),
            findsNWidgets(5),
          );
          await openAndClose(
            find.byKey(const ValueKey('compare-dim-row')).at(3),
          );
        }
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Today shows the feed’s first idea and the reels share it', (
    tester,
  ) async {
    var quoteLoads = 0;
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const CmpysTodayScreen()),
        GoRoute(
          path: AppRoutes.ideas,
          builder: (_, _) => const CmpysReelsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cmpysStoreProvider.overrideWith((ref) => _ResponsiveStore()),
          cmpysBackendSyncProvider.overrideWith((ref) async {}),
          cmpysIdeasProvider.overrideWith((ref) async {
            quoteLoads++;
            return const [_idea];
          }),
          ..._todayOverrides(),
          currentPlanProvider.overrideWith((ref) => _ReadyPlanController()),
          todayViewProvider.overrideWith(
            (ref) async => const TodayView(
              items: [
                TodayTaskItem(
                  id: 'habit-1',
                  title: 'Write the next decisive action',
                  type: 'habit',
                  estimatedHours: 1,
                  completedToday: false,
                  dailyInstructions: 'Choose one concrete next action.',
                ),
              ],
              streak: 0,
              completedToday: 0,
              totalToday: 1,
            ),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    // NextUp breathes and pulses forever, so pump instead of settling.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Write the next decisive action'), findsWidgets);
    expect(find.text('Idea for today'), findsOneWidget);
    expect(find.text('“${_idea.text}”'), findsOneWidget);
    expect(quoteLoads, 1);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is V3IconButton && widget.label == 'Idea reels',
      ),
    );
    // The Ideas screen has a repeating swipe cue; let the route and content
    // appear without waiting for that intentionally continuous animation.
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CmpysReelsScreen), findsOneWidget);
    expect(find.text(_idea.text), findsOneWidget);
    // Today and the reels share one feed load.
    expect(quoteLoads, 1);
    expect(tester.takeException(), isNull);
  });

  final generatedScreens = <String, Widget Function()>{
    'Today generated content': () => const CmpysTodayScreen(),
    'Plan generated content': () => const CmpysPlanScreen(),
    'Profile generated metrics': () => const CmpysYouScreen(),
  };
  for (final screen in generatedScreens.entries) {
    for (final config in configurations) {
      testWidgets('${screen.key} fits ${config.label}', (tester) async {
        tester.view.physicalSize = config.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cmpysStoreProvider.overrideWith((ref) => _ResponsiveStore()),
              cmpysBackendSyncProvider.overrideWith((ref) async {}),
              cmpysIdeasProvider.overrideWith((ref) async => const [_idea]),
              ..._todayOverrides(),
              currentPlanProvider.overrideWith((ref) => _ReadyPlanController()),
              todayViewProvider.overrideWith(
                (ref) async => const TodayView(
                  items: [
                    TodayTaskItem(
                      id: 'habit-1',
                      title:
                          'Review the day and write the next decisive action',
                      type: 'habit',
                      estimatedHours: 2,
                      completedToday: false,
                      dailyInstructions:
                          'Write one observation and one concrete next action.',
                    ),
                  ],
                  streak: 4,
                  completedToday: 0,
                  totalToday: 1,
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(config.textScale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: designCaptureKey,
                child: screen.value(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await captureDesign(tester, '${screen.key}-${config.label}');
        final lists = find.byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.vertical,
        );
        if (lists.evaluate().isNotEmpty) {
          final scrollable = find
              .descendant(of: lists.first, matching: find.byType(Scrollable))
              .first;
          for (var i = 0; i < 20; i++) {
            final position = tester.state<ScrollableState>(scrollable).position;
            if (position.pixels >= position.maxScrollExtent) break;
            position.jumpTo(
              (position.pixels + 400).clamp(0.0, position.maxScrollExtent),
            );
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
          }
        }
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  // The Library, the tutorial reader and the practice workbook: each is
  // mounted with fake repositories (no network) and scrolled end to end.
  final readingScreens = <String, Widget Function()>{
    'Library': () => const ReadingLibraryScreen(),
    'Tutorial reader': () => LessonReaderScreen(
      itemId: 'mission-1',
      missionTitle: 'Build a leadership operating system',
      step: _readerStep(),
      stepNumber: 2,
      totalSteps: 5,
      week: '3',
      materials: const [
        PlanMaterialDetail(
          title: 'Start With Why',
          type: 'book',
          authorOrCreator: 'Simon Sinek',
          contentResourceId: 'book-1',
        ),
      ],
      completed: false,
      nextTitle: 'Separate reversible decisions from irreversible ones',
    ),
    'Practice workbook': () => const LessonPracticeScreen(
      itemId: 'item',
      stepId: 's2',
      lessonTitle: 'Separate reversible decisions from the irreversible ones',
      lessonContent: '## Owner earnings\nAdd back D&A.',
      isTutorial: true,
      tutorialNumber: 2,
    ),
  };
  // Proof each mount reached its content, not an error or loading state.
  final readingMarkers = <String, Finder Function()>{
    'Library': () => find.textContaining('Essays of Warren Buffett'),
    'Tutorial reader': () => find.text('TUTORIAL 2 OF 5 · WEEK 3'),
    'Practice workbook': () =>
        find.textContaining('Owner earnings at Harbor Tools'),
  };
  // Known v3 defects this coverage found (reported in task G1, not fixed
  // there); un-skip once the widgets are fixed.
  const knownOverflows = <String, String>{};
  for (final screen in readingScreens.entries) {
    for (final config in configurations) {
      testWidgets('${screen.key} fits ${config.label}', (tester) async {
        final known = knownOverflows['${screen.key}|${config.label}'];
        if (known != null) {
          markTestSkipped(known);
          return;
        }
        tester.view.physicalSize = config.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cmpysStoreProvider.overrideWith((ref) => _ResponsiveStore()),
              cmpysBackendSyncProvider.overrideWith((ref) async {}),
              currentPlanProvider.overrideWith((ref) => _ReadyPlanController()),
              contentResourcesRepositoryProvider.overrideWithValue(
                _LibraryRepository(),
              ),
              practiceRepositoryProvider.overrideWithValue(_PracticeRepo()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(config.textScale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: designCaptureKey,
                child: screen.value(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(readingMarkers[screen.key]!(), findsWidgets);
        await captureDesign(tester, '${screen.key}-${config.label}');
        // Scroll the screen's main vertical scrollable to its end.
        final scrollables = find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.vertical,
        );
        expect(scrollables, findsWidgets);
        final scrollable = scrollables.first;
        for (var i = 0; i < 40; i++) {
          final position = tester.state<ScrollableState>(scrollable).position;
          if (position.pixels >= position.maxScrollExtent) break;
          position.jumpTo(
            (position.pixels + 400).clamp(0.0, position.maxScrollExtent),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        }
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
