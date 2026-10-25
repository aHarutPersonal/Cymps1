import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/intake_step.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/personalize_step.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _IntakeRepo extends Fake implements SessionRepository {
  @override
  Future<Session> getSession(String id) async => Session(
    id: id,
    phase: SessionPhase.interview,
    userAge: 27,
    userFinancialStatus: '',
    userInterests: const [],
  );

  @override
  Stream<Map<String, dynamic>> sendInterviewMessage(
    String id,
    String content, {
    bool isKickoff = false,
    String? questionId,
  }) async* {
    yield {'type': 'chunk', 'content': 'What would you like to learn first?'};
    yield {
      'type': 'done',
      'turn': 1,
      'max_turns': 9,
      'phase_transition': false,
      'question_id': 'goal',
      'response_ui': {'version': 1, 'kind': 'text'},
    };
  }
}

void main() {
  testWidgets('personalization shows restored name after navigating back', (
    tester,
  ) async {
    final draft = CmpysOnboardingDraft()..name = 'Taylor';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CmpysPersonalizeStep(
            draft: draft,
            onUpdate: (_) {},
            onDone: () {},
          ),
        ),
      ),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Taylor',
    );
    await tester.enterText(find.byType(TextField), 'Morgan');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Morgan',
    );
    expect(draft.name, 'Morgan');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'intake keeps question and composer usable with large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(_IntakeRepo()),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: CmpysIntakeChatStep(
                idol: defaultIdol(),
                draft: CmpysOnboardingDraft()..sessionId = 'session',
                onDone: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).autofocus,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'A clear writing process');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
