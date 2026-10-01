import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/onboarding_flow.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SavedSessionRepo extends Fake implements SessionRepository {
  bool fail = false;
  bool abandoned = false;
  int reads = 0;
  String? resumedId;
  String? resumedMentorId;
  int resultsStarts = 0;
  @override
  Future<Session?> getLatestSession() async {
    reads++;
    if (fail) throw StateError('offline');
    if (abandoned) {
      return const Session(
        id: 'abandoned',
        phase: SessionPhase.completed,
        userAge: 27,
        userFinancialStatus: '',
        userInterests: [],
      );
    }
    return const Session(
      id: 'saved-session',
      phase: SessionPhase.blueprint,
      userAge: 27,
      userFinancialStatus: '',
      userInterests: ['investing'],
      selectedIdol: SelectedIdolInfo(id: 'mentor', name: 'John D. Rockefeller'),
      comparisonOutput: 'Saved comparison',
      blueprintOutput: 'Saved blueprint',
    );
  }

  @override
  Stream<Map<String, dynamic>> generateResults(String sessionId) async* {
    resultsStarts++;
    resumedId = sessionId;
    // A deliberate provider outage leaves a terminal retry rather than timers.
    throw StateError('provider unavailable');
  }
}

class _ResumedPlanRepo extends Fake implements PlanRepository {
  _ResumedPlanRepo(this.sessions);
  final _SavedSessionRepo sessions;

  @override
  Future<String> generatePlan({
    required String idolId,
    required int targetAge,
    String? sessionId,
    int durationWeeks = 12,
    int weeklyHours = 10,
  }) async {
    sessions.resumedId = sessionId;
    sessions.resumedMentorId = idolId;
    return 'restored-job';
  }

  @override
  Future<PlanJobStatus> getJobStatus(String jobId) async =>
      PlanJobStatus(id: jobId, status: 'failed', progressPercent: 0);
}

void main() {
  Future<void> mount(WidgetTester tester, _SavedSessionRepo repo) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          planRepositoryProvider.overrideWithValue(_ResumedPlanRepo(repo)),
          currentUserProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: CmpysOnboardingFlow()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cold start resumes the saved results stage and session', (
    tester,
  ) async {
    final repo = _SavedSessionRepo();
    await mount(tester, repo);
    expect(repo.reads, 1);
    expect(repo.resumedId, 'saved-session');
    expect(repo.resumedMentorId, 'mentor');
    expect(repo.resultsStarts, 0);
    expect(find.text('What should we call you?'), findsNothing);
    expect(find.text('Continue generation'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('abandoned incomplete session starts fresh without generation', (
    tester,
  ) async {
    final repo = _SavedSessionRepo()..abandoned = true;
    await mount(tester, repo);
    expect(repo.resumedId, isNull);
    expect(find.text('What should we call you?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'offline restoration offers retry without starting another session',
    (tester) async {
      final repo = _SavedSessionRepo()..fail = true;
      await mount(tester, repo);
      expect(repo.resumedId, isNull);
      expect(
        find.text('Could not restore your saved onboarding.'),
        findsOneWidget,
      );
      expect(find.text('What should we call you?'), findsNothing);
      repo.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(repo.reads, 2);
      expect(repo.resumedId, 'saved-session');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
