import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/learning_support.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/book_companion_screen.dart';
import 'package:cmpys/features/plan/presentation/learning_support_section.dart';
import 'package:cmpys/features/plan/presentation/material_video_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/learning_support_fixture.dart';

class _Repo extends Fake implements PlanRepository {
  LearningSupport support = readySupport();
  bool fail = false;
  final prepares = <bool>[];
  @override
  Future<LearningSupport> getLearningSupport(
    String itemId, {
    String? stepId,
    String? bookTitle,
    bool prepare = false,
  }) async {
    prepares.add(prepare);
    if (fail) throw StateError('Offline');
    return support;
  }
}

Widget _harness(_Repo repo, Widget child) => ProviderScope(
  overrides: [planRepositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('matching idea opens short tutorials and their self-check', (
    tester,
  ) async {
    final repo = _Repo();
    await tester.pumpWidget(
      _harness(
        repo,
        const Scaffold(
          body: SingleChildScrollView(
            child: LearningSupportSection(itemId: 'mission', stepId: 'step_1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.prepares, [true]);
    expect(find.text('From A useful book'), findsOneWidget);
    expect(find.text('Watch video'), findsOneWidget);
    await tester.tap(find.text('Explore book tutorials'));
    await tester.pumpAndSettle();
    expect(find.byType(BookCompanionScreen), findsOneWidget);
    await tester.tap(find.text('Choose a concrete cue'));
    await tester.pumpAndSettle();
    expect(find.byType(BookTutorialScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('After breakfast, write one line.').last,
      200,
    );
    await tester.tap(find.text('After breakfast, write one line.').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'After breakfast gives a recognizable cue;',
        findRichText: true,
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Next tutorial'), 200);
    await tester.tap(find.text('Next tutorial'));
    await tester.pumpAndSettle();
    expect(find.text('Make the action smaller'), findsOneWidget);
  });

  testWidgets('pending support polls read-only and stops after disposal', (
    tester,
  ) async {
    final repo = _Repo()
      ..support = LearningSupport.fromJson(supportFixture(status: 'checking'));
    await tester.pumpWidget(
      _harness(
        repo,
        const BookCompanionScreen(
          itemId: 'mission',
          material: PlanMaterialDetail(title: 'A useful book', type: 'book'),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Preparing short tutorials'), findsOneWidget);
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
    expect(repo.prepares, [true, false]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
    expect(repo.prepares, [true, false]);
  });

  testWidgets('failed support never blocks the tutorial', (tester) async {
    await tester.pumpWidget(
      _harness(
        _Repo()..fail = true,
        const Scaffold(
          body: Column(
            children: [
              Text('The main tutorial remains available'),
              LearningSupportSection(itemId: 'mission', stepId: 'step_1'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The main tutorial remains available'), findsOneWidget);
    expect(find.text('Watch video'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'video provides provenance and an active follow-up without awarding completion',
    (tester) async {
      final video = readySupport().videos.single;
      await tester.pumpWidget(
        MaterialApp(
          home: MaterialVideoScreen(
            material: video.material,
            videoId: video.id,
            tryAfter: video.tryAfter,
            verification: video.verification,
            playerOverride: const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Try after watching'), 150);
      expect(find.text(video.tryAfter), findsOneWidget);
      expect(
        find.text(
          'Optional practice · watching does not complete your mission.',
        ),
        findsOneWidget,
      );
    },
  );
}
