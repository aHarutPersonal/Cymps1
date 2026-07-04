import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/motion/skeleton.dart';

void main() {
  testWidgets('block renders a paper2 container of the given height',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CmpysSkeleton.block(height: 96)),
    );
    // One pump only — the shimmer loops forever, pumpAndSettle would hang.
    await tester.pump(const Duration(milliseconds: 100));
    final box = tester.widget<Container>(find.descendant(
      of: find.byType(CmpysSkeleton),
      matching: find.byType(Container),
    ));
    expect((box.decoration as BoxDecoration).color, AppColors.paper2);
  });

  testWidgets('renders statically under reduced motion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const CmpysSkeleton.block(height: 96),
        ),
      ),
    );
    // Static skeleton must settle (no looping animation).
    await tester.pumpAndSettle();
    expect(find.byType(Container), findsOneWidget);
  });
}
