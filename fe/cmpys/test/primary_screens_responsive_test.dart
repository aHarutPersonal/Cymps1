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
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
        'dimensions': [
          for (var i = 0; i < 5; i++)
            {
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

const _idea = CmpysIdea(
  id: 'live-idea',
  text: 'A generated idea that remains readable on every supported phone.',
  author: 'Mentor',
  tag: 'Focus',
  tone: AppColors.green,
  likes: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    'Settings': () => const CmpysSettingsScreen(),
    'Edit profile': () => const CmpysEditProfileScreen(),
    'Notes': () => const CmpysNotesScreen(),
    'Saved': () => const CmpysSavedScreen(),
    'Mentor picker': () => const CmpysMentorPickerScreen(),
  };
  final configurations = <({Size size, double textScale, String label})>[
    (size: const Size(320, 568), textScale: 1, label: 'narrow phone'),
    (size: const Size(390, 844), textScale: 1.3, label: 'large text'),
  ];

  for (final screen in screens.entries) {
    for (final config in configurations) {
      testWidgets('${screen.key} fits ${config.label}', (tester) async {
        await tester.binding.setSurfaceSize(config.size);
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
              cmpysIdeasProvider.overrideWith((ref) async => const [_idea]),
              currentPlanProvider.overrideWith(
                (ref) => CurrentPlanController(
                  repo: _EmptyPlanRepository(),
                  readJobId: () => null,
                ),
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(config.textScale)),
                child: child!,
              ),
              home: screen.value(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
      });
    }
  }

  final generatedScreens = <String, Widget Function()>{
    'Today generated content': () => const CmpysTodayScreen(),
    'Plan generated content': () => const CmpysPlanScreen(),
    'Profile generated metrics': () => const CmpysYouScreen(),
  };
  for (final screen in generatedScreens.entries) {
    for (final config in configurations) {
      testWidgets('${screen.key} fits ${config.label}', (tester) async {
        await tester.binding.setSurfaceSize(config.size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cmpysStoreProvider.overrideWith((ref) => _ResponsiveStore()),
              cmpysBackendSyncProvider.overrideWith((ref) async {}),
              cmpysIdeasProvider.overrideWith((ref) async => const [_idea]),
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
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(config.textScale)),
                child: child!,
              ),
              home: screen.value(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
