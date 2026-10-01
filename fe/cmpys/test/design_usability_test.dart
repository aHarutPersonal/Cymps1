import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/app/theme.dart';
import 'package:cmpys/core/ui/cmpys/cmpys_primitives.dart';
import 'package:cmpys/core/ui/cmpys_button.dart' as legacy;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final values = [a.computeLuminance(), b.computeLuminance()]..sort();
  return (values.last + 0.05) / (values.first + 0.05);
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  double keyboard = 0,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(2),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('secondary text and primary actions have readable contrast', () {
    for (final surface in [AppColors.paper, AppColors.card]) {
      expect(_contrast(AppColors.ink3, surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.green2, surface), greaterThanOrEqualTo(4.5));
    }
    expect(
      _contrast(AppColors.green2, AppColors.greenSoft),
      greaterThanOrEqualTo(4.5),
    );
  });

  for (final oldButton in [false, true]) {
    testWidgets(
      'button keeps its whole label at 200% text (legacy: $oldButton)',
      (tester) async {
        var taps = 0;
        const label = 'Continue to your personalized learning plan';
        await _mount(
          tester,
          Center(
            child: SizedBox(
              width: 240,
              child: oldButton
                  ? legacy.CmpysButton(label: label, onPressed: () => taps++)
                  : CmpysButton(onTap: () => taps++, child: const Text(label)),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.text(label)).height, greaterThan(52));
        expect(tester.getSize(find.text(label)).width, lessThanOrEqualTo(240));
        await tester.tap(find.text(label));
        expect(taps, 1);
      },
    );
  }

  testWidgets('long toast fits a small screen with large text', (tester) async {
    await _mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showCmpysToast(
            context,
            'Your lesson was saved. You can return to it from your reading library.',
            icon: Icons.check,
          ),
          child: const Text('Save'),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Your lesson was saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'sheet content and final action are reachable above the keyboard',
    (tester) async {
      var confirmed = false;
      await _mount(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCmpysSheet(
              context,
              title: 'Review your progress',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 8; i++)
                    Text('Reflection $i: What helped you learn today?'),
                  CmpysButton(
                    onTap: () => confirmed = true,
                    child: const Text('Save reflection'),
                  ),
                ],
              ),
            ),
            child: const Text('Review'),
          ),
        ),
        keyboard: 220,
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final action = find.text('Save reflection');
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(action).dy, lessThanOrEqualTo(348));
      await tester.tap(action);
      expect(confirmed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
