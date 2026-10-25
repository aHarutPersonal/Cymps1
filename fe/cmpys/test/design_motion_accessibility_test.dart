import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:cmpys/app/theme.dart';
import 'package:cmpys/core/ui/cmpys/cmpys_primitives.dart';
import 'package:cmpys/features/cmpys/data/cmpys_ideas_provider.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/reels_screen.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/analysis_step.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/plan_gen_step.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/design_capture.dart';

class _WaitingSession extends Fake implements SessionRepository {
  final events = StreamController<Map<String, dynamic>>();
  @override
  Stream<Map<String, dynamic>> generateResults(String id) => events.stream;
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  bool reduced = true,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: RepaintBoundary(
        key: designCaptureKey,
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  setUpAll(prepareDesignCapture);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'typing feedback stays visible and stops ticking when motion is reduced',
    (tester) async {
      late StateSetter rebuild;
      var reduced = false;
      await _mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: const CmpysTypingDots(),
            );
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      reduced = true;
      rebuild(() {});
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      final opacities = tester.widgetList<Opacity>(
        find.descendant(
          of: find.byType(CmpysTypingDots),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacities.length, 3);
      expect(opacities.every((dot) => dot.opacity == 0.65), isTrue);
      reduced = false;
      rebuild(() {});
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'toast is a live announcement without translation under reduced motion',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _mount(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCmpysToast(context, 'Idea saved'),
            child: const Text('Save'),
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final announcement = find.bySemanticsLabel('Idea saved');
      expect(
        tester.getSemantics(announcement).flagsCollection.isLiveRegion,
        isTrue,
      );
      final translation = tester.widget<Transform>(
        find
            .ancestor(
              of: find.text('Idea saved'),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(translation.transform.getTranslation().y, 0);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Idea saved'), findsNothing);
      semantics.dispose();
    },
  );

  for (final analysis in [true, false]) {
    testWidgets(
      '${analysis ? 'analysis' : 'blueprint'} waiting screen stops decorative loops',
      (tester) async {
        final draft = CmpysOnboardingDraft()..sessionId = 'motion-test';
        final repo = _WaitingSession();
        await _mount(
          tester,
          ProviderScope(
            overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
            child: analysis
                ? CmpysAnalysisStep(
                    idol: cmpysIdols.first,
                    draft: draft,
                    onDone: () {},
                  )
                : CmpysPlanGenStep(
                    idol: cmpysIdols.first,
                    draft: draft,
                    onDone: () {},
                  ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
        if (analysis) {
          await repo.events.close();
          await tester.pump();
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Ideas actions announce labels and toggle state and support keyboard activation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      const idea = CmpysIdea(
        id: 'accessibility-idea',
        text: 'A useful idea for a focused day.',
        author: 'Test mentor',
        tag: 'Focus',
        tone: Color(0xFF255844),
        likes: 7,
        comments: [],
      );
      final container = ProviderContainer(
        overrides: [
          cmpysIdeasProvider.overrideWith((ref) async => const [idea]),
        ],
      );
      addTearDown(container.dispose);
      await _mount(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: const CmpysReelsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      final like = find.bySemanticsLabel('Like idea');
      final save = find.bySemanticsLabel('Save idea');
      final comments = find.bySemanticsLabel('Comments');
      expect(tester.getSemantics(like).flagsCollection.isButton, isTrue);
      expect(
        tester.getSemantics(like).flagsCollection.isToggled != Tristate.none,
        isTrue,
      );
      expect(
        tester.getSemantics(like).flagsCollection.isToggled == Tristate.isTrue,
        isFalse,
      );
      Focus.of(
        tester.element(find.byIcon(PhosphorIconsRegular.heart)),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        container.read(cmpysStoreProvider).ideaState[idea.id]?.liked,
        isTrue,
      );
      expect(
        tester.getSemantics(like).flagsCollection.isToggled == Tristate.isTrue,
        isTrue,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(save).flagsCollection.isToggled == Tristate.isTrue,
        isTrue,
      );
      expect(
        tester.getSemantics(comments).flagsCollection.isToggled !=
            Tristate.none,
        isFalse,
      );
      await tester.tap(comments);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );
  for (final largeText in [true, false]) {
    testWidgets(
      'Ideas reading and actions stay separate in ${largeText ? "200% text" : "landscape"}',
      (tester) async {
        tester.view.physicalSize = largeText
            ? const Size(320, 568)
            : const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const first = CmpysIdea(
          id: 'read-first',
          text:
              'A generated idea that remains readable on every supported phone, with the entire thought available even when large text takes more space.',
          author: 'First mentor',
          tag: 'Focus',
          tone: Color(0xFF255844),
          likes: 7,
        );
        const second = CmpysIdea(
          id: 'read-second',
          text: 'The next complete thought.',
          author: 'Second mentor',
          tag: 'Practice',
          tone: Color(0xFF255844),
          likes: 3,
        );
        await _mount(
          tester,
          ProviderScope(
            overrides: [
              cmpysIdeasProvider.overrideWith(
                (ref) async => const [first, second],
              ),
            ],
            child: const CmpysReelsScreen(),
          ),
          textScale: largeText ? 2 : 1,
          reduced: largeText,
        );
        await tester.pumpAndSettle();
        final reading = find.byKey(const ValueKey('idea-reading-read-first'));
        final header = tester.getRect(find.text('For you · 1 of 2'));
        final viewport = tester.getRect(reading);
        final actions = tester.getRect(find.byTooltip('Like idea').first);
        expect(viewport.top, greaterThan(header.bottom));
        expect(viewport.bottom, lessThan(actions.top));
        expect(tester.widget<Text>(find.text(first.text)).maxLines, isNull);
        final scroll = find.descendant(
          of: reading,
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text('Next idea'),
          160,
          scrollable: scroll,
        );
        await tester.pumpAndSettle();
        await captureDesign(
          tester,
          'ideas-${largeText ? "200-text" : "landscape"}-reading-end',
        );
        expect(find.text('Next idea').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Next idea'));
        await tester.pumpAndSettle();
        expect(find.text('For you · 2 of 2'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Previous idea'),
          160,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('idea-reading-read-second')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.text('Previous idea'));
        await tester.pumpAndSettle();
        expect(find.text('For you · 1 of 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
