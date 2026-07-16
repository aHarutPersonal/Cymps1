import 'package:cmpys/core/ui/cmpys/cmpys_primitives.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pressable scales down while pressed and restores on release', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: CmpysPressable(
            onTap: () {},
            child: const SizedBox(
              key: ValueKey('target'),
              width: 80,
              height: 48,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    await tester.pump();

    var scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 0.975);

    await gesture.up();
    await tester.pump();
    scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1);
  });

  testWidgets('pressable removes scale motion when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Center(
            child: CmpysPressable(
              onTap: () {},
              child: const SizedBox(
                key: ValueKey('calm-target'),
                width: 80,
                height: 48,
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('calm-target'))),
    );
    await tester.pump();

    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1);
    expect(scale.duration, Duration.zero);

    await gesture.up();
  });
}
