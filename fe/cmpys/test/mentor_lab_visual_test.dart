import 'dart:io';

import 'package:cmpys/app/theme.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/mentor_lab_step.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_capture.dart';

class _SavedResults extends Fake implements SessionRepository {
  @override
  Stream<Map<String, dynamic>> generateResults(String sessionId) {
    throw StateError('Visual previews must never generate results.');
  }
}

class _PreviewPlan extends Fake implements PlanRepository {
  _PreviewPlan(this.status);
  final String status;

  @override
  Future<PlanJobStatus> getJobStatus(String id) async => PlanJobStatus(
    id: id,
    status: status,
    progressPercent: status == 'completed' ? 100 : 40,
    thinkingLine: 'Preparing your first week of lessons and practice…',
  );
}

void main() {
  setUpAll(prepareDesignCapture);

  for (final status in ['running', 'failed', 'completed']) {
    for (final largeText in [false, true]) {
      testWidgets('mentor lab $status ${largeText ? 'large text' : 'phone'}', (
        tester,
      ) async {
        tester.view.physicalSize = largeText
            ? const Size(320, 568)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final draft = CmpysOnboardingDraft()
          ..sessionId = 'preview-session'
          ..planJobId = 'preview-job'
          ..comparisonMd = 'Saved comparison'
          ..blueprintMd = 'Saved strategy';
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionRepositoryProvider.overrideWithValue(_SavedResults()),
              planRepositoryProvider.overrideWithValue(_PreviewPlan(status)),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(largeText ? 2 : 1),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: RepaintBoundary(
                key: designCaptureKey,
                child: CmpysMentorLabStep(
                  idol: cmpysIdols.firstWhere((idol) => idol.id == 'jobs'),
                  draft: draft,
                  onDone: () {},
                ),
              ),
            ),
          ),
        );
        if (Platform.environment['DESIGN_CAPTURE_DIR'] != null) {
          await tester.runAsync(() async {
            final context = tester.element(find.byType(CmpysMentorLabStep));
            await Future.wait([
              for (final asset in [
                'assets/images/mentors/sj.png',
                'assets/images/voices/seneca.jpg',
                'assets/images/voices/isaac_newton.jpg',
                'assets/images/voices/warren_buffett.jpg',
              ])
                precacheImage(AssetImage(asset), context),
            ]);
          });
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('%'), findsNothing);
        expect(find.byKey(const Key('mentor-voice-Seneca')), findsOneWidget);
        if (status == 'failed') {
          expect(find.byKey(const Key('mentor-lab-paused')), findsOneWidget);
          await tester.ensureVisible(find.text('Continue generation'));
        } else if (status == 'completed') {
          expect(find.text('Enter CMPYS'), findsOneWidget);
        } else {
          expect(find.text('Enter CMPYS'), findsNothing);
          // Reduced motion leaves the portrait stable even through another poll.
          await tester.pump(const Duration(seconds: 19));
          await tester.pumpAndSettle();
          expect(find.text('Seneca'), findsOneWidget);
        }
        await captureDesign(
          tester,
          'mentor-lab-$status-${largeText ? '200-text' : 'phone'}',
        );
        if (largeText) {
          final scrollable = find
              .descendant(
                of: find.byKey(const Key('mentor-lab-content')),
                matching: find.byType(Scrollable),
              )
              .first;
          final position = tester.state<ScrollableState>(scrollable).position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pump();
          expect(tester.takeException(), isNull);
          await captureDesign(tester, 'mentor-lab-$status-200-text-source');
        } else {
          await tester.tap(find.byTooltip('Next perspective'));
          await tester.pumpAndSettle();
          expect(find.text('Isaac Newton'), findsOneWidget);
          await captureDesign(tester, 'mentor-lab-$status-newton');
          await tester.tap(find.byTooltip('Next perspective'));
          await tester.pumpAndSettle();
          expect(find.text('Warren Buffett'), findsOneWidget);
          await captureDesign(tester, 'mentor-lab-$status-buffett');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
