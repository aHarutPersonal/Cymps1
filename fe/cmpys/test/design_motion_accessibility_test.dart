import 'dart:ui' show Tristate;

import 'package:cmpys/app/theme.dart';
import 'package:cmpys/core/ui/cmpys/cmpys_primitives.dart';
import 'package:cmpys/features/cmpys/data/cmpys_ideas_provider.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/reels_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/design_capture.dart';

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

class _NoPlanRepository implements PlanRepository {
  @override
  Future<BackendPlan?> getCurrentPlan() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The reels read the plan's focus week; these tests have no plan.
class _NoPlanController extends CurrentPlanController {
  _NoPlanController()
    : super(repo: _NoPlanRepository(), readJobId: () => null) {
    state = const CurrentPlanState(status: CurrentPlanStatus.empty);
  }

  @override
  Future<void> refresh() async {}
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
          currentPlanProvider.overrideWith((ref) => _NoPlanController()),
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
      // No plan: the bar reads "Ideas", without a week.
      expect(find.text('Ideas'), findsOneWidget);
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
        tester.element(
          find.byWidgetPredicate(
            (widget) => widget is V3Icon && widget.icon == V3Icons.heart,
          ),
        ),
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
              currentPlanProvider.overrideWith((ref) => _NoPlanController()),
            ],
            child: const CmpysReelsScreen(),
          ),
          textScale: largeText ? 2 : 1,
          reduced: largeText,
        );
        // With motion on, the v3 page light drifts forever (design `drift
        // 9s infinite`), so settle with timed pumps.
        Future<void> settle() async {
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
        }
        await settle();
        final reading = find.byKey(const ValueKey('idea-reading-read-first'));
        // No plan: the bar reads "Ideas", without a week.
        expect(find.text('Ideas'), findsOneWidget);
        final header = tester.getRect(find.text('Ideas'));
        final viewport = tester.getRect(reading);
        final actions = tester.getRect(
          find.bySemanticsLabel('Like idea').first,
        );
        expect(viewport.top, greaterThan(header.bottom));
        expect(viewport.bottom, lessThan(actions.top));
        expect(tester.widget<Text>(find.text(first.text)).maxLines, isNull);
        final scroll = find.descendant(
          of: reading,
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text('First mentor'),
          160,
          scrollable: scroll,
        );
        await settle();
        await captureDesign(
          tester,
          'ideas-${largeText ? "200-text" : "landscape"}-reading-end',
        );
        expect(find.text('First mentor').hitTestable(), findsOneWidget);
        // The v3 top bar's up/down buttons page between ideas.
        await tester.tap(find.bySemanticsLabel('Next'));
        await settle();
        expect(
          find.byKey(const ValueKey('idea-reading-read-second')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.bySemanticsLabel('Previous'));
        await settle();
        expect(reading.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
