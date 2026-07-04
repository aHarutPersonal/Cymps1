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
}
