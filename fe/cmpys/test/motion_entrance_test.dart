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
            return const Entrance(child: Text('once'));
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
}
