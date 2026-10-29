import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/compare_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// SPEC §6: you fly in from the left and the mentor from the right (.9 s
// spring at .15 s); the shared age pops at .85 s with two ember rings
// rippling out once. Reduced motion: fades only.

class _Store extends CmpysStore {
  _Store() {
    state = state.copyWith(
      sessionId: 'session-1',
      idol: cmpysIdols.first,
      user: CmpysUser(name: 'Ana', age: 24),
    );
  }
}

Future<void> _mount(WidgetTester tester, {bool reduced = false}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(390, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cmpysStoreProvider.overrideWith((ref) => _Store()),
        cmpysBackendSyncProvider.overrideWith((ref) async {}),
        cmpysComparisonScoresSyncProvider.overrideWith(
          (ref) async => ComparisonScoresSyncResult.ready,
        ),
        idolTimelineProvider.overrideWith((ref, name) async => const []),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: const CmpysCompareScreen(),
      ),
    ),
  );
}

const _you = Key('compare-fly-you');
const _mentor = Key('compare-fly-mentor');
const _age = Key('compare-age-disc');

/// The opacity the closest [Opacity] above [of] (inside [within]) applies.
double _opacity(WidgetTester tester, Key within) => tester
    .widget<Opacity>(
      find
          .descendant(of: find.byKey(within), matching: find.byType(Opacity))
          .first,
    )
    .opacity;

double _dx(WidgetTester tester, Key within) {
  final translate = find.descendant(
    of: find.byKey(within),
    matching: find.byType(Transform),
  );
  if (translate.evaluate().isEmpty) return 0;
  return tester.widget<Transform>(translate.first).transform.getTranslation().x;
}

Finder _rings() => find.descendant(
  of: find.byKey(const Key('compare-age-rings')),
  matching: find.byType(CustomPaint),
);

void main() {
  testWidgets('the faces fly in, then the age pops with two rings', (
    tester,
  ) async {
    await _mount(tester);
    final you = tester.widget<V3Fly>(find.byKey(_you));
    final mentor = tester.widget<V3Fly>(find.byKey(_mentor));
    expect(you.from, V3FlyFrom.left);
    expect(mentor.from, V3FlyFrom.right);
    for (final fly in [you, mentor]) {
      expect(fly.duration, const Duration(milliseconds: 900));
      expect(fly.delay, const Duration(milliseconds: 150));
    }
    final pop = tester.widget<V3Pop>(
      find.ancestor(of: find.byKey(_age), matching: find.byType(V3Pop)),
    );
    expect(pop.duration, const Duration(milliseconds: 600));
    expect(pop.delay, const Duration(milliseconds: 850));
    final shocks = tester.widgetList<V3Shock>(find.byType(V3Shock)).toList();
    expect(shocks.map((s) => (s.duration, s.delay)), [
      (const Duration(milliseconds: 900), const Duration(milliseconds: 850)),
      (const Duration(milliseconds: 1100), const Duration(milliseconds: 1000)),
    ]);
    expect(shocks.every((s) => s.color == AppColors.ember), isTrue);

    // Before .15 s: both hidden.
    await tester.pump(const Duration(milliseconds: 100));
    expect(_opacity(tester, _you), 0);
    expect(_opacity(tester, _mentor), 0);

    // Mid-flight: you from the left, the mentor from the right.
    await tester.pump(const Duration(milliseconds: 250));
    expect(_dx(tester, _you), lessThan(0));
    expect(_dx(tester, _mentor), greaterThan(0));
    expect(_rings(), findsNothing);

    // ~.95 s: the age is popping and the first ring rippling.
    await tester.pump(const Duration(milliseconds: 600));
    expect(_rings(), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(_rings(), findsNWidgets(2));

    // Both rings play once and are gone; the faces rest in place.
    await tester.pump(const Duration(seconds: 2));
    expect(_rings(), findsNothing);
    expect(_opacity(tester, _you), 1);
    expect(_dx(tester, _you), 0);
    expect(_dx(tester, _mentor), 0);
    expect(find.byKey(_age), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('reduced motion: fades only, no flight, pop or rings', (
    tester,
  ) async {
    await _mount(tester, reduced: true);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    // Fading, never moving.
    expect(_opacity(tester, _you), inExclusiveRange(0, 1));
    expect(_dx(tester, _you), 0);
    expect(find.byType(V3Pop), findsNothing);
    expect(find.byKey(const Key('compare-age-fade')), findsOneWidget);
    expect(find.byKey(const Key('compare-age-rings')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(_opacity(tester, _you), 1);
    expect(find.byKey(_age), findsOneWidget);
    // The honest headline is unchanged.
    expect(
      find.textContaining('both at 24.', findRichText: true),
      findsOneWidget,
    );
  });
}
