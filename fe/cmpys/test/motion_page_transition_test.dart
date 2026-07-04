import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/core/ui/motion/page_transition.dart';

void main() {
  testWidgets('CmpysPageRoute pushes and completes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              CmpysPageRoute<void>(builder: (_) => const Text('detail')),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    // And back.
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('CmpysSheetRoute pushes and completes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              CmpysSheetRoute<void>(builder: (_) => const Text('sheet')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
  });
}
