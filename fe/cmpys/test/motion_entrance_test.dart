import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/motion/entrance.dart';

void main() {
  testWidgets('Entrance renders its child and settles', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Entrance(child: Text('hello'))),
    );
    expect(find.text('hello'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('Entrance renders under reduced motion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Entrance(child: Text('calm')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('calm'), findsOneWidget);
  });

  test('stagger delay is capped at index 6', () {
    expect(Entrance.delayFor(0), Duration.zero);
    expect(Entrance.delayFor(3), AppDurations.stagger * 3);
    expect(Entrance.delayFor(6), AppDurations.stagger * 6);
    expect(Entrance.delayFor(30), AppDurations.stagger * 6);
  });

  test('EntranceGroup.wrap wraps each child with its index', () {
    final wrapped = EntranceGroup.wrap([const Text('a'), const Text('b')]);
    expect(wrapped.length, 2);
    expect((wrapped[0] as Entrance).index, 0);
    expect((wrapped[1] as Entrance).index, 1);
  });

  test('EntranceGroup.wrap skips bare spacers without consuming a stagger index',
      () {
    final wrapped = EntranceGroup.wrap([
      const Text('a'),
      const SizedBox(height: 18), // bare spacer — no child
      const Text('b'),
      const SizedBox(height: 12), // bare spacer — no child
      const SizedBox(width: 8, child: Text('not a spacer')),
    ]);

    expect(wrapped.length, 5);
    // Spacers pass through unwrapped...
    expect(wrapped[1], isA<SizedBox>());
    expect(wrapped[1], isNot(isA<Entrance>()));
    expect(wrapped[3], isA<SizedBox>());
    expect(wrapped[3], isNot(isA<Entrance>()));
    // ...and non-spacer children (including a SizedBox that has a child)
    // keep contiguous stagger indices, unaffected by the spacers between them.
    expect((wrapped[0] as Entrance).index, 0);
    expect((wrapped[2] as Entrance).index, 1);
    expect((wrapped[4] as Entrance).index, 2);
  });

  // flutter_animate's FadeEffect renders a FadeTransition and its MoveEffect
  // renders a Transform.translate, so the tests below observe the effect
  // chain through plain Flutter widgets without importing flutter_animate
  // (which is only allowed inside lib/core/ui/motion/).
  testWidgets('Entrance plays once and does not re-trigger on parent rebuild',
      (tester) async {
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            // Deliberately non-const: each parent rebuild must hand the
            // element a new widget instance so Entrance really rebuilds.
            return Entrance(child: const Text('once'));
          },
        ),
      ),
    );

    final fadeInEntrance = find.descendant(
      of: find.byType(Entrance),
      matching: find.byType(FadeTransition),
    );

    // While animating, the fade effect wraps the child.
    expect(fadeInEntrance, findsOneWidget);

    await tester.pumpAndSettle();

    // Animation completed: _played flipped, the bare child renders with no
    // effect wrappers left in the subtree.
    expect(fadeInEntrance, findsNothing);
    expect(find.text('once'), findsOneWidget);

    // A parent rebuild must not re-trigger the entrance.
    rebuild(() {});
    await tester.pump();
    expect(fadeInEntrance, findsNothing);
    expect(find.text('once'), findsOneWidget);
  });

  testWidgets(
      'slide runs with motion enabled and is dropped under reduced motion',
      (tester) async {
    // Motion enabled: fade + slide (Transform.translate from the move effect).
    await tester.pumpWidget(
      const MaterialApp(home: Entrance(child: Text('moving'))),
    );
    expect(
      find.descendant(
        of: find.byType(Entrance),
        matching: find.byType(Transform),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    // Reduced motion: the fade still runs, but no Transform is in the subtree.
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Entrance(child: Text('calmly')),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(Entrance),
        matching: find.byType(FadeTransition),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Entrance),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(find.text('calmly'), findsOneWidget);
  });

  testWidgets(
      'EntranceScope: a child mounted after the visit window skips the '
      'entrance entirely (no FadeTransition/Transform)', (tester) async {
    // Duration.zero means the scope's visit window has already "elapsed" by
    // the time any later-mounted Entrance checks it, without needing to
    // fake the clock.
    late StateSetter rebuild;
    var showSecond = false;

    await tester.pumpWidget(
      MaterialApp(
        home: EntranceScope(
          visitWindow: Duration.zero,
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Column(
                children: [
                  const Entrance(index: 0, child: Text('first')),
                  if (showSecond)
                    const Entrance(index: 1, child: Text('second')),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Simulate a list-shape change on an already-visible screen: a new
    // trailing child appears well after the scope's visit window.
    showSecond = true;
    rebuild(() {});
    await tester.pump();

    expect(find.text('second'), findsOneWidget);
    final secondEntrance = find.ancestor(
      of: find.text('second'),
      matching: find.byType(Entrance),
    );
    expect(secondEntrance, findsOneWidget);
    expect(
      find.descendant(of: secondEntrance, matching: find.byType(FadeTransition)),
      findsNothing,
    );
    expect(
      find.descendant(of: secondEntrance, matching: find.byType(Transform)),
      findsNothing,
    );
  });

  testWidgets(
      'EntranceScope: within the visit window an Entrance still animates',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EntranceScope(
          child: const Entrance(child: Text('within window')),
        ),
      ),
    );

    // Still animating: the fade effect wraps the child.
    expect(
      find.descendant(
        of: find.byType(Entrance),
        matching: find.byType(FadeTransition),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.text('within window'), findsOneWidget);
  });

  testWidgets('Entrance with no ancestor EntranceScope still animates as before',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Entrance(child: Text('no scope'))),
    );
    expect(
      find.descendant(
        of: find.byType(Entrance),
        matching: find.byType(FadeTransition),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.text('no scope'), findsOneWidget);
  });

  testWidgets('reduced motion applies zero stagger delay (no wait before fade)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Entrance(index: 6, child: Text('instant')),
        ),
      ),
    );

    // With reduced motion, delay must be zero regardless of index — a single
    // pump (no time advance) is enough for the fade effect to be mounted and
    // already progressing (no stagger wait gating it).
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(Entrance),
        matching: find.byType(FadeTransition),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.text('instant'), findsOneWidget);
  });
}
