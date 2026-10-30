// Native fixture flow; no account, backend writes or provider calls.
import 'dart:io';

import 'package:cmpys/features/cmpys/state/today_data.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/data/practice_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/models/practice_models.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:cmpys/features/plan/presentation/plan_item_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Habit smoke must not use the network.');
}

class _Practice extends Fake implements PracticeRepository {
  int checks = 0;
  String? loadedStep;
  Map<String, dynamic> data = {
    'state': 'ready',
    'revision': 1,
    'lesson_version': 'fixture-review',
    'answers': <String, String>{},
    'attempts': [],
    'hints': [],
    'workbook': {
      'title': 'Practice and review',
      'purpose': 'review',
      'activities': [
        {
          'id': 'case',
          'title': 'A familiar remainder',
          'kind': 'transfer',
          'instructions':
              'Recall the subtraction rule. Use the supplied amounts to find the remaining units.',
          'minutes_min': 3,
          'minutes_max': 6,
          'data': [
            {'id': 'received', 'label': 'Received', 'value': 12},
            {'id': 'spent', 'label': 'Spent', 'value': 5},
          ],
          'fields': [
            {'id': 'remaining', 'label': 'Units remaining', 'kind': 'number'},
          ],
        },
      ],
    },
  };

  @override
  Future<LessonPracticeState> load(
    String item,
    String step,
    String? artifact,
  ) async {
    loadedStep = step;
    return LessonPracticeState.fromJson(data);
  }

  @override
  Future<LessonPracticeState> save(
    String item,
    String step,
    String? artifact,
    int revision,
    Map<String, String> answers, {
    List<PracticeActivity> activities = const [],
  }) async {
    expect(revision, data['revision']);
    data = {
      ...data,
      'revision': revision + 1,
      'answers': Map<String, String>.from(answers),
    };
    return LessonPracticeState.fromJson(data);
  }

  @override
  Future<LessonPracticeState> act(
    String item,
    String step,
    String? artifact, {
    required String action,
    required int revision,
    required String activity,
    required String requestId,
    bool solution = false,
  }) async {
    expect(revision, data['revision']);
    final answers = data['answers'] as Map<String, String>;
    if (action == 'submit') {
      checks++;
      final passed = answers['case.remaining'] == '7';
      data = {
        ...data,
        'revision': revision + 1,
        'complete': passed,
        'passed_activity_ids': [if (passed) activity],
        'attempts': [
          ...data['attempts'] as List,
          {
            'request_id': requestId,
            'activity_id': activity,
            'answers': {'remaining': answers['case.remaining']},
            'passed': passed,
            'assisted': (data['hints'] as List).isNotEmpty,
            'feedback': [
              {
                'field_id': 'remaining',
                'passed': passed,
                'feedback': passed
                    ? 'Seven units remain.'
                    : 'Subtract five from twelve; check your subtraction.',
              },
            ],
          },
        ],
      };
    } else {
      expect(action, 'hint');
      expect(solution, isTrue);
      data = {
        ...data,
        'revision': revision + 1,
        'hints': [
          {
            'activity_id': activity,
            'kind': 'solution',
            'content':
                'Subtract the five spent units from twelve received units: seven remain.',
          },
        ],
      };
    }
    return LessonPracticeState.fromJson(data);
  }
}

class _Plan extends Fake implements PlanRepository {
  _Plan(this.practice);
  final _Practice practice;
  bool completed = false;
  String note = '';
  int completions = 0;

  @override
  Future<PlanItemDetailed> getPlanItemDetailed(
    String itemId,
  ) async => PlanItemDetailed(
    item: const BackendPlanItem(
      id: 'native-habit',
      title: 'Review a taught method',
      type: 'practice',
      description: 'Recall and apply the method from your lesson.',
      weekStart: 1,
      weekEnd: 1,
      estimatedHours: 1,
      estimatedMinutes: 60,
      successMetric: 'Save a checked attempt.',
      status: 'in_progress',
      progressPercent: 0,
    ),
    detailsStatus: 'available',
    sessionMinutes: 20,
    completedToday: completed,
    dailyReflection: note,
    dailyInstructions:
        'Recall, attempt, check, correct and save an error note. Stop at the session cap.',
    habitSchedule: {
      'weekdays': [0, 2, 4],
      'label': 'Mon, Wed, Fri · 20 min',
      'scheduled_today': true,
      'cue': 'After breakfast',
    },
    habitReview: {
      'date': '2026-10-30',
      'step_id': 'review_2026-10-30',
      'available': true,
      'attempted': practice.checks > 0,
      'checked': practice.checks > 0,
      'needs_correction':
          practice.checks > 0 && practice.data['complete'] != true,
    },
  );

  @override
  Future<DailyStatus> getDailyStatus(String itemId) async =>
      DailyStatus(itemId: itemId, days: []);

  @override
  Future<bool> toggleDailyTask(String itemId) async {
    expect(practice.checks, 2);
    completed = !completed;
    completions++;
    return completed;
  }

  @override
  Future<void> saveReviewReflection(
    String itemId,
    String text,
    String date,
  ) async {
    expect(date, '2026-10-30');
    note = text;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  setUpAll(() async {
    await GoogleFonts.pendingFonts([
      GoogleFonts.instrumentSerif(),
      GoogleFonts.instrumentSerif(fontStyle: FontStyle.italic),
      GoogleFonts.literata(),
      GoogleFonts.playfairDisplay(),
      GoogleFonts.playfairDisplay(fontStyle: FontStyle.italic),
      GoogleFonts.playfairDisplay(fontWeight: FontWeight.w600),
      GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700),
      for (final weight in [
        FontWeight.w300,
        FontWeight.w500,
        FontWeight.w600,
        FontWeight.w700,
      ])
        GoogleFonts.jetBrainsMono(fontWeight: weight),
    ]).timeout(const Duration(seconds: 30));
    GoogleFonts.config.allowRuntimeFetching = false;
    HttpOverrides.global = _NoNetwork();
  });

  testWidgets(
    'native review checks, corrects, saves and logs without completing a lesson',
    (tester) async {
      final practice = _Practice();
      final plan = _Plan(practice);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planRepositoryProvider.overrideWithValue(plan),
            practiceRepositoryProvider.overrideWithValue(practice),
            todayViewProvider.overrideWith((ref) async => null),
            todayStreakProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const PlanItemDetailScreen(itemId: 'native-habit'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mon, Wed, Fri · 20 min'), findsOneWidget);
      await tester.tap(find.text('Start review'));
      await tester.pumpAndSettle();
      expect(practice.loadedStep, 'review_2026-10-30');
      expect(find.text('Independent'), findsNothing);
      final answer = find.byKey(const ValueKey('answer-case.remaining'));
      await tester.ensureVisible(answer);
      await tester.enterText(answer, '8');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit for checking'));
      await tester.pumpAndSettle();
      expect(practice.checks, 1);
      expect(find.text('Revise answer'), findsOneWidget);
      await tester.ensureVisible(find.text('Show worked solution'));
      await tester.tap(find.text('Show worked solution'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Subtract the five spent units from twelve received units: seven remain.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Revise answer'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(answer);
      await tester.enterText(answer, '7');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit for checking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish session'));
      await tester.pumpAndSettle();
      expect(find.text('Log practice session'), findsOneWidget);
      await tester.tap(find.text('Log practice session'));
      await tester.pumpAndSettle();
      expect(plan.completions, 1);
      expect(plan.completed, isTrue);
      expect(practice.data['answers'], {'case.remaining': '7'});
      expect((practice.data['attempts'] as List).length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
