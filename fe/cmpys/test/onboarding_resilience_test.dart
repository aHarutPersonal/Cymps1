import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/mentor_lab_step.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sessions extends Fake implements SessionRepository {
  int starts = 0;
  bool failRead = false;

  @override
  Future<Session> getSession(String sessionId) async {
    if (failRead) {
      throw const ApiError(message: 'Server error', statusCode: 500);
    }
    return Session(
      id: sessionId,
      phase: SessionPhase.completed,
      userAge: 27,
      userFinancialStatus: '',
      userInterests: const ['writing'],
      selectedIdol: const SelectedIdolInfo(id: 'mentor-1', name: 'Seneca'),
    );
  }

  @override
  Stream<Map<String, dynamic>> generateResults(String sessionId) async* {
    starts++;
    yield {'type': 'section', 'section': 'comparison'};
    yield {'type': 'chunk', 'content': 'Saved comparison'};
    yield {'type': 'section', 'section': 'blueprint'};
    yield {'type': 'chunk', 'content': 'Saved blueprint'};
    yield {'type': 'plan_job', 'job_id': 'job-1'};
    yield {'type': 'done'};
  }
}

class _Plans extends Fake implements PlanRepository {
  String status = 'running';
  bool offline = false;
  int polls = 0;
  int restarts = 0;
  String? restartedSession;

  @override
  Future<BackendPlan?> getCurrentPlan() async => null;

  @override
  Future<PlanJobStatus> getJobStatus(String jobId) async {
    polls++;
    if (offline) throw const NetworkError();
    return PlanJobStatus(id: jobId, status: status, progressPercent: 50);
  }

  @override
  Future<String> generatePlan({
    required String idolId,
    required int targetAge,
    String? sessionId,
    int durationWeeks = 12,
    int weeklyHours = 10,
  }) async {
    restarts++;
    restartedSession = sessionId;
    status = 'completed';
    return 'job-1';
  }
}

CmpysOnboardingDraft _savedDraft() => CmpysOnboardingDraft()
  ..sessionId = 'session-1'
  ..planJobId = 'job-1'
  ..comparisonMd = 'Saved comparison'
  ..blueprintMd = 'Saved blueprint';

Future<void> _mount(
  WidgetTester tester,
  _Sessions sessions,
  _Plans plans, {
  double textScale = 1,
  Size size = const Size(390, 844),
  CmpysOnboardingDraft? draft,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(sessions),
        planRepositoryProvider.overrideWithValue(plans),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: CmpysMentorLabStep(
          idol: defaultIdol(),
          draft: draft ?? _savedDraft(),
          onDone: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('saved results resume their job without regenerating documents', (
    tester,
  ) async {
    final sessions = _Sessions();
    final plans = _Plans()..status = 'completed';
    await _mount(tester, sessions, plans);
    expect(sessions.starts, 0);
    expect(plans.polls, 1);
    expect(find.text('Enter CMPYS'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed onboarding plan restarts its saved session explicitly', (
    tester,
  ) async {
    final sessions = _Sessions();
    final plans = _Plans()..status = 'failed';
    await _mount(tester, sessions, plans);
    expect(find.text('Plan paused. Your progress is saved.'), findsOneWidget);
    expect(find.byKey(const Key('mentor-lab-paused')), findsOneWidget);
    expect(find.text('62%'), findsNothing);
    await tester.tap(find.text('Continue generation'));
    await tester.pumpAndSettle();
    expect(plans.restarts, 1);
    expect(plans.restartedSession, 'session-1');
    expect(sessions.starts, 0);
    expect(find.text('Enter CMPYS'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('perspective composition stays compact on tall phones', (
    tester,
  ) async {
    await _mount(tester, _Sessions(), _Plans(), size: const Size(430, 1000));
    final card = find.byKey(const Key('mentor-lab-perspective-Seneca'));
    expect(tester.getSize(card).height, lessThanOrEqualTo(538));
    expect(tester.getTopLeft(card).dy, greaterThan(140));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('retry explains a failed session read before plan dispatch', (
    tester,
  ) async {
    final sessions = _Sessions()..failRead = true;
    final plans = _Plans()..status = 'failed';
    await _mount(tester, sessions, plans);
    await tester.tap(find.text('Continue generation'));
    await tester.pumpAndSettle();
    expect(plans.restarts, 0);
    expect(
      find.text(
        'Your saved session couldn’t be loaded. Your answers are safe. Try again.',
      ),
      findsOneWidget,
    );
    sessions.failRead = false;
    await tester.tap(find.text('Continue generation'));
    await tester.pumpAndSettle();
    expect(plans.restarts, 1);
    expect(find.text('Enter CMPYS'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cached server mentor restarts without a session read', (
    tester,
  ) async {
    final sessions = _Sessions()..failRead = true;
    final plans = _Plans()..status = 'failed';
    await _mount(
      tester,
      sessions,
      plans,
      draft: _savedDraft()..backendIdolId = 'mentor-1',
    );
    await tester.tap(find.text('Continue generation'));
    await tester.pumpAndSettle();
    expect(plans.restarts, 1);
    expect(plans.restartedSession, 'session-1');
    expect(find.text('Enter CMPYS'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'complete results recover a missing job without repeating results',
    (tester) async {
      final sessions = _Sessions()..failRead = true;
      final plans = _Plans();
      await _mount(
        tester,
        sessions,
        plans,
        draft: _savedDraft()
          ..backendIdolId = 'mentor-1'
          ..planJobId = null,
      );
      expect(plans.restarts, 1);
      expect(sessions.starts, 0);
      expect(find.text('Enter CMPYS'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('repeated offline polling becomes a reconnect action', (
    tester,
  ) async {
    final plans = _Plans()..offline = true;
    await _mount(tester, _Sessions(), plans);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Continue generation'), findsOneWidget);
    expect(plans.polls, 3);
    await tester.pump(const Duration(seconds: 30));
    expect(plans.polls, 3);
    plans.offline = false;
    plans.status = 'completed';
    await tester.tap(find.text('Continue generation'));
    await tester.pumpAndSettle();
    expect(find.text('Enter CMPYS'), findsOneWidget);
    expect(plans.restarts, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('plan recovery fits small phones at 200 percent text', (
    tester,
  ) async {
    await _mount(
      tester,
      _Sessions(),
      _Plans()..status = 'failed',
      textScale: 2,
      size: const Size(320, 568),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Continue generation'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('main plan retry requeues a failed stored job', (tester) async {
    final plans = _Plans()..status = 'failed';
    var requests = 0;
    final controller = CurrentPlanController(
      repo: plans,
      readJobId: () => 'job-1',
      requestGeneration: () async {
        requests++;
        plans.status = 'running';
        return 'job-1';
      },
    );
    await tester.pump();
    expect(controller.state.status, CurrentPlanStatus.failed);
    await controller.retry();
    await tester.pump();
    expect(requests, 1);
    expect(controller.state.status, CurrentPlanStatus.generating);
    controller.dispose();
  });

  testWidgets('completed job without a visible plan stops waiting', (
    tester,
  ) async {
    final plans = _Plans()..status = 'completed';
    final controller = CurrentPlanController(
      repo: plans,
      readJobId: () => 'job-1',
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(controller.state.status, CurrentPlanStatus.failed);
    final polls = plans.polls;
    await tester.pump(const Duration(seconds: 30));
    expect(plans.polls, polls);
    controller.dispose();
  });
}
