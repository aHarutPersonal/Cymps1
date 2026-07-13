import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/intake_step.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SelectionRetryRepository extends Fake implements SessionRepository {
  int selectionAttempts = 0;
  int interviewSends = 0;
  SelectIdolRequest? selectedRequest;

  Session _session(SessionPhase phase) => Session(
        id: 'session-1',
        phase: phase,
        userAge: 28,
        userFinancialStatus: 'employed',
        userInterests: const ['Technology'],
      );

  @override
  Future<Session> getSession(String sessionId) async {
    return _session(SessionPhase.idolSelection);
  }

  @override
  Future<Session> selectIdol(
    String sessionId,
    SelectIdolRequest request,
  ) async {
    selectionAttempts++;
    selectedRequest = request;
    if (selectionAttempts == 1) {
      throw const ApiError(message: 'Selection failed', statusCode: 500);
    }
    return _session(SessionPhase.interview);
  }

  @override
  Stream<Map<String, dynamic>> sendInterviewMessage(
    String sessionId,
    String content, {
    bool isKickoff = false,
  }) async* {
    interviewSends++;
    yield {'type': 'chunk', 'content': 'What will you build first?'};
    yield {
      'type': 'done',
      'turn': 1,
      'max_turns': 5,
      'phase_transition': false,
    };
  }
}

void main() {
  testWidgets(
    'selection failure retries setup before sending interview kickoff',
    (tester) async {
      final repository = _SelectionRetryRepository();
      final draft = CmpysOnboardingDraft()..sessionId = 'session-1';
      final idol = defaultIdol().withWikidataId('Q47213');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sessionRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: CmpysIntakeChatStep(
                idol: idol,
                draft: draft,
                onDone: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repository.selectionAttempts, 1);
      expect(repository.interviewSends, 0);
      expect(find.textContaining('Couldn’t prepare'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repository.selectionAttempts, 2);
      expect(repository.interviewSends, 1);
      expect(repository.selectedRequest?.wikidataId, 'Q47213');
      expect(find.text('What will you build first?'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );
}
