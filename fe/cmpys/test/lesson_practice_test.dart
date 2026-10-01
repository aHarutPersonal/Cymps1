import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cmpys/features/plan/data/practice_repository.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/lesson_reader_screen.dart';
import 'package:cmpys/features/plan/models/practice_models.dart';
import 'package:cmpys/features/plan/presentation/lesson_practice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only asset substitution: captures exercise layout without font downloads.
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as font_assets;

class _CaptureFonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
    for (final family in ['Inter', 'PlayfairDisplay', 'JetBrainsMono'])
      for (final variant in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
        'Italic',
        'BoldItalic',
      ])
        'capture/$family-$variant.ttf',
  ];
}

Map<String, dynamic> fixture() => {
  'state': 'ready',
  'revision': 1,
  'complete': false,
  'answers': <String, String>{},
  'attempts': <Map<String, dynamic>>[],
  'hints': <Map<String, dynamic>>[],
  'passed_activity_ids': <String>[],
  'workbook': {
    'title': 'Find the missing side',
    'activities': [
      for (final id in ['triangle', 'transfer'])
        {
          'id': id,
          'title': id == 'triangle' ? 'A right triangle' : 'A new triangle',
          'kind': id == 'triangle' ? 'practice' : 'transfer',
          'instructions':
              'A right triangle has legs of 3 cm and 4 cm. Find its hypotenuse and explain which assumption makes your calculation valid.',
          'minutes_min': 4,
          'minutes_max': 8,
          'data': [
            {'label': 'First leg', 'value': 3, 'unit': 'cm'},
            {'label': 'Second leg', 'value': 4, 'unit': 'cm'},
          ],
          'diagram': {
            'caption':
                'Triangle ABC has a right angle at B. The lengths are provided in the question.',
            'closed': true,
            'points': [
              {'label': 'A', 'x': 10, 'y': 10},
              {'label': 'B', 'x': 10, 'y': 90},
              {'label': 'C', 'x': 90, 'y': 90},
            ],
          },
          'fields': [
            {
              'id': 'length',
              'label': 'Hypotenuse',
              'kind': 'number',
              'unit': 'cm',
            },
            {
              'id': 'reason',
              'label': 'Why can you use this relationship?',
              'kind': 'text',
              'criteria': ['Explain why the right angle matters.'],
            },
            {
              'id': 'assumption',
              'label': 'Which fact is essential?',
              'kind': 'choice',
              'choices': [
                {'id': 'right', 'label': 'The triangle has a right angle'},
                {'id': 'drawn', 'label': 'The drawing looks accurate'},
              ],
            },
          ],
        },
    ],
  },
};

class FakePracticeRepository extends Fake implements PracticeRepository {
  Map<String, dynamic> data = fixture();
  int saves = 0, checks = 0, loads = 0, preparations = 0;
  bool failSave = false, failReview = false, failLoad = false;
  Completer<void>? holdSave;
  Completer<void>? holdPreparation;
  bool returnPreparing = false;
  @override
  Future<LessonPracticeState> load(
    String item,
    String step,
    String? artifact,
  ) async {
    loads++;
    if (failLoad) throw StateError('offline');
    return LessonPracticeState.fromJson(data);
  }

  @override
  Future<LessonPracticeState> prepare(
    String item,
    String step,
    String? artifact,
  ) async {
    preparations++;
    if (holdPreparation != null) await holdPreparation!.future;
    if (returnPreparing) {
      return LessonPracticeState.fromJson({'state': 'preparing'});
    }
    data = fixture();
    return LessonPracticeState.fromJson(data);
  }

  @override
  Future<LessonPracticeState> save(
    String item,
    String step,
    String? artifact,
    int revision,
    Map<String, String> answers,
  ) async {
    saves++;
    if (holdSave != null) await holdSave!.future;
    if (failSave) throw StateError('offline');
    if (revision != data['revision']) throw StateError('revision conflict');
    data = {...data, 'revision': revision + 1, 'answers': answers};
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
    if (action == 'submit') {
      checks++;
      if (failReview) throw StateError('review unavailable');
      final answers = data['answers'] as Map<String, String>;
      final passed = answers['$activity.length'] == '5';
      data = {
        ...data,
        'revision': revision + 1,
        'passed_activity_ids': [if (passed) activity],
        'attempts': [
          ...data['attempts'] as List,
          {
            'request_id': requestId,
            'activity_id': activity,
            'answers': {
              for (final field in ['length', 'reason', 'assumption'])
                field: answers['$activity.$field'],
            },
            'passed': passed,
            'assisted': false,
            'feedback': [
              {
                'field_id': 'length',
                'passed': passed,
                'feedback': passed
                    ? 'Your calculation is correct.'
                    : 'Check the sum of the squared leg lengths.',
              },
            ],
          },
        ],
      };
    } else {
      data = {
        ...data,
        'revision': revision + 1,
        'hints': [
          {
            'activity_id': activity,
            'kind': 'hint',
            'content': 'Start by squaring each leg length.',
          },
        ],
      };
    }
    return LessonPracticeState.fromJson(data);
  }
}

class _CompletionRepository extends Fake implements PlanRepository {
  int completions = 0;
  @override
  Future<({bool completed, bool itemCompleted})> toggleStepComplete(
    String itemId,
    String stepId, {
    String? artifactJobId,
  }) async {
    completions++;
    return (completed: true, itemCompleted: true);
  }
}

const screen = LessonPracticeScreen(
  itemId: 'item',
  stepId: 's1',
  artifactJobId: 'version',
  lessonTitle: 'Geometry: understand the relationship',
  lessonContent:
      '## The relationship\nUse the supplied right-angle assumption.',
);

Future<void> mount(
  WidgetTester tester,
  FakePracticeRepository repo, {
  bool dark = false,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [practiceRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: ThemeData(
          fontFamily: 'Roboto',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7151)),
        ),
        home: RepaintBoundary(
          key: const Key('practice-capture'),
          child: dark
              ? const LessonPracticeScreen(
                  itemId: 'item',
                  stepId: 's1',
                  lessonTitle: 'Geometry',
                  lessonContent: 'A geometry lesson.',
                  dark: true,
                )
              : screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String field, String value) async {
  final finder = find.byKey(ValueKey('answer-triangle.$field'));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fontDir = Platform.environment['PRACTICE_FONT_DIR'];
    if (Platform.environment['PRACTICE_CAPTURE'] != '1' || fontDir == null) {
      return;
    }
    final regular = await File('$fontDir/Roboto-Regular.ttf').readAsBytes();
    final icons = await File(
      '$fontDir/MaterialIcons-Regular.otf',
    ).readAsBytes();
    font_assets.assetManifest = _CaptureFonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final name = utf8.decode(message!.buffer.asUint8List());
          if (name.startsWith('capture/')) return regular.buffer.asByteData();
          final file = File('build/unit_test_assets/$name');
          return await file.exists()
              ? (await file.readAsBytes()).buffer.asByteData()
              : null;
        });
    for (final family in ['Roboto', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(regular.buffer.asByteData()))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(icons.buffer.asByteData()))).load();
  });
  testWidgets('answer-specific criteria appear only in submitted feedback', (
    tester,
  ) async {
    final repo = FakePracticeRepository();
    await mount(tester, repo);
    expect(
      find.textContaining('Explain why the right angle matters.'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    repo.data['attempts'] = [
      {
        'activity_id': 'triangle',
        'answers': <String, String>{},
        'passed': false,
        'feedback': [
          {
            'field_id': 'reason',
            'passed': false,
            'feedback': 'Explain the required assumption.',
            'score': 0,
            'max_score': 1,
            'criterion_met': [false],
            'criteria': ['A right angle is required.'],
          },
        ],
      },
    ];
    await mount(tester, repo);
    expect(find.textContaining('A right angle is required.'), findsOneWidget);
    expect(
      find.textContaining('Explain why the right angle matters.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'published practice opens automatically without a generation action',
    (tester) async {
      final repo = FakePracticeRepository()
        ..data = {'state': 'not_started', 'prepared_available': true};
      await mount(tester, repo);
      expect(repo.preparations, 1);
      expect(find.text('A right triangle'), findsOneWidget);
      expect(find.text('Prepare practice'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('geometry workspace fits a phone and saves numeric input', (
    tester,
  ) async {
    final repo = FakePracticeRepository();
    await mount(tester, repo);
    expect(find.text('Schematic · not to scale'), findsOneWidget);
    await enter(tester, 'length', '5');
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(repo.data['answers']['triangle.length'], '5');
    expect(find.text('All answers saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing while a save is in flight persists the latest edit', (
    tester,
  ) async {
    final repo = FakePracticeRepository()..holdSave = Completer<void>();
    await mount(tester, repo);
    await enter(tester, 'length', '4');
    await tester.pump(const Duration(seconds: 1));
    await enter(tester, 'length', '5');
    repo.holdSave!.complete();
    await tester.pumpAndSettle();
    expect(repo.saves, 2);
    expect(repo.data['answers']['triangle.length'], '5');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed autosave remains visible and retries without losing text',
    (tester) async {
      final repo = FakePracticeRepository()..failSave = true;
      await mount(tester, repo);
      await enter(tester, 'length', '4');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(repo.data['answers'], isEmpty);
      repo.failSave = false;
      await tester.ensureVisible(find.text('Retry save'));
      await tester.tap(find.text('Retry save'));
      await tester.pumpAndSettle();
      expect(repo.data['answers']['triangle.length'], '4');
      expect(find.text('All answers saved'), findsOneWidget);
    },
  );

  testWidgets('saved work restores and a failed answer can be corrected', (
    tester,
  ) async {
    final repo = FakePracticeRepository();
    repo.data['answers'] = {
      'triangle.length': '4',
      'triangle.reason': 'The triangle is right-angled.',
      'triangle.assumption': 'right',
    };
    await mount(tester, repo);
    await tester.ensureVisible(find.text('Check my work'));
    await tester.tap(find.text('Check my work'));
    await tester.pumpAndSettle();
    expect(find.text('Revise and try again'), findsOneWidget);
    await enter(tester, 'length', '5');
    await tester.ensureVisible(find.text('Check my work'));
    await tester.tap(find.text('Check my work'));
    await tester.pumpAndSettle();
    expect(repo.checks, 2);
    expect(find.text('This attempt meets the criteria'), findsOneWidget);
    await tester.ensureVisible(find.text('Continue to the next case'));
    await tester.tap(find.text('Continue to the next case'));
    await tester.pumpAndSettle();
    expect(find.text('A new triangle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review failure never displays successful completion', (
    tester,
  ) async {
    final repo = FakePracticeRepository()..failReview = true;
    repo.data['answers'] = {
      'triangle.length': '5',
      'triangle.reason': 'Right angle.',
      'triangle.assumption': 'right',
    };
    await mount(tester, repo);
    await tester.ensureVisible(find.text('Check my work'));
    await tester.tap(find.text('Check my work'));
    await tester.pumpAndSettle();
    expect(find.text('Finish lesson'), findsNothing);
    expect(find.textContaining('Could not finish this check'), findsOneWidget);
  });

  testWidgets('lesson reference is available without leaving the work', (
    tester,
  ) async {
    await mount(tester, FakePracticeRepository());
    await tester.tap(find.byTooltip('Refer to lesson'));
    await tester.pumpAndSettle();
    expect(find.text('Lesson reference'), findsOneWidget);
    expect(
      find.textContaining('Use the supplied right-angle assumption'),
      findsOneWidget,
    );
  });

  testWidgets('dark narrow screen and keyboard do not overflow', (
    tester,
  ) async {
    await mount(tester, FakePracticeRepository(), dark: true, width: 320);
    await enter(
      tester,
      'reason',
      'I use the right-angle assumption to justify the relationship.',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed practice is read-only and exposes finish action', (
    tester,
  ) async {
    final repo = FakePracticeRepository();
    repo.data = {
      ...repo.data,
      'complete': true,
      'passed_activity_ids': ['triangle', 'transfer'],
      'answers': {
        'triangle.length': '5',
        'triangle.reason': 'Right angle.',
        'triangle.assumption': 'right',
      },
    };
    await mount(tester, repo);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('answer-triangle.length')),
          )
          .enabled,
      isFalse,
    );
    await tester.ensureVisible(find.text('Finish lesson'));
    expect(find.text('Finish lesson'), findsOneWidget);
  });

  for (final status in ['transfer_without_hint', 'completed_with_support']) {
    testWidgets('completion explains evidence: $status', (tester) async {
      final repo = FakePracticeRepository();
      repo.data = {
        ...repo.data,
        'complete': true,
        'passed_activity_ids': ['triangle', 'transfer'],
        'learning_evidence': {'status': status},
      };
      await mount(tester, repo);
      await tester.ensureVisible(find.text('Finish lesson'));
      expect(
        find.textContaining(
          status == 'transfer_without_hint'
              ? 'New case passed without an in-app hint'
              : 'Practice completed with support on the new case',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('optional capture of the real rendered workspace', (
    tester,
  ) async {
    await mount(tester, FakePracticeRepository());
    if (Platform.environment['PRACTICE_CAPTURE'] == '1') {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('practice-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '../../docs/curriculum-research/practice-screen.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('reader finishes only after returning from completed practice', (
    tester,
  ) async {
    final repo = FakePracticeRepository();
    repo.data = {
      ...repo.data,
      'complete': true,
      'passed_activity_ids': ['triangle', 'transfer'],
    };
    final completion = _CompletionRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceRepositoryProvider.overrideWithValue(repo),
          planRepositoryProvider.overrideWithValue(completion),
        ],
        child: const MaterialApp(
          home: LessonReaderScreen(
            itemId: 'item',
            missionTitle: 'Geometry',
            step: PlanStepDetail(
              id: 's1',
              title: 'Triangle',
              lessonContent: '## Learn\nA triangle lesson.',
            ),
            stepNumber: 1,
            totalSteps: 1,
            materials: [],
            completed: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Practice & finish'));
    await tester.pumpAndSettle();
    expect(completion.completions, 0);
    expect(find.byType(LessonPracticeScreen), findsOneWidget);
    await tester.ensureVisible(find.text('Finish lesson'));
    await tester.tap(find.text('Finish lesson'));
    await tester.pumpAndSettle();
    expect(completion.completions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back navigation flushes a pending draft before leaving', (
    tester,
  ) async {
    final repo = FakePracticeRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [practiceRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(
                  c,
                ).push(MaterialPageRoute<void>(builder: (_) => screen)),
                child: const Text('Open exercise'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open exercise'));
    await tester.pumpAndSettle();
    await enter(tester, 'length', '5');
    await tester.tap(find.byTooltip('Back to lesson'));
    await tester.pumpAndSettle();
    expect(repo.data['answers']['triangle.length'], '5');
    expect(find.text('Open exercise'), findsOneWidget);
    expect(find.byType(LessonPracticeScreen), findsNothing);
  });

  Future<void> openUnpreparedPractice(
    WidgetTester tester,
    FakePracticeRepository repo,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [practiceRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => screen)),
                child: const Text('Open practice'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open practice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prepare practice'));
    await tester.pump();
  }

  testWidgets(
    'preparation keeps lesson reference and back navigation available',
    (tester) async {
      final repo = FakePracticeRepository()
        ..data = {'state': 'not_started'}
        ..holdPreparation = Completer<void>();
      await openUnpreparedPractice(tester, repo);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.arrow_back),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Refer to lesson'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Lesson reference'), findsOneWidget);
      await tester.tap(find.byTooltip('Close reference'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Back to lesson'));
      await tester.pumpAndSettle();
      expect(find.text('Open practice'), findsOneWidget);
      expect(find.byType(LessonPracticeScreen), findsNothing);

      // An HTTP response arriving after disposal cannot reopen practice, write
      // answers, or use a disposed widget/ref.
      repo.holdPreparation!.complete();
      await tester.pumpAndSettle();
      expect(repo.preparations, 1);
      expect(repo.saves, 0);
      expect(repo.checks, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'system back cancels preparation polling without saving answers',
    (tester) async {
      final repo = FakePracticeRepository()
        ..data = {'state': 'not_started'}
        ..returnPreparing = true;
      await openUnpreparedPractice(tester, repo);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Open practice'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(repo.loads, 1);
      expect(repo.saves, 0);
      expect(repo.checks, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('exhausted preparation can be manually retried after cooldown', (
    tester,
  ) async {
    final repo = FakePracticeRepository()
      ..data = {
        'state': 'failed',
        'can_retry_preparation': false,
        'retry_after_seconds': 1800,
      };
    await mount(tester, repo);
    expect(
      find.textContaining('Try again in about 30 minutes.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Try again later'),
          )
          .onPressed,
      isNull,
    );
    await tester.pump(const Duration(minutes: 31));
    expect(repo.preparations, 0);
    repo.data = {'state': 'failed', 'can_retry_preparation': true};
    await tester.tap(find.text('Check availability'));
    await tester.pumpAndSettle();
    expect(find.text('Prepare practice'), findsOneWidget);
    expect(repo.preparations, 0);
    await tester.tap(find.text('Prepare practice'));
    await tester.pumpAndSettle();
    expect(repo.preparations, 1);
    expect(find.text('A right triangle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reopening preparation polls beyond a minute without another POST',
    (tester) async {
      final repo = FakePracticeRepository()..data = {'state': 'preparing'};
      await tester.pumpWidget(
        ProviderScope(
          overrides: [practiceRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: screen),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 5));
      }
      expect(repo.loads, 16);
      expect(repo.preparations, 0);
      expect(find.text('Preparing exercises…'), findsOneWidget);
      repo.data = fixture();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('A right triangle'), findsOneWidget);
      expect(repo.preparations, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed reload retains the unsaved draft', (tester) async {
    final repo = FakePracticeRepository()..failSave = true;
    await mount(tester, repo);
    await enter(tester, 'length', '4');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    repo.failLoad = true;
    await tester.ensureVisible(find.text('Reload saved version'));
    await tester.tap(find.text('Reload saved version'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reload').last);
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('answer-triangle.length')),
          )
          .controller!
          .text,
      '4',
    );
  });
}
