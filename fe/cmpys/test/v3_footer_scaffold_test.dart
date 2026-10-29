import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// `V3FooterScaffold`: a scroll body with a primary-button footer. Keyboard
// closed, the footer overlays the bottom on a paper gradient and the body
// scrolls clear of it. Keyboard open, the footer moves below the body so a
// focused field scrolls into the space above the footer and the keyboard.

const _keyboard = 336.0;
const _topBarHeight = 72.0;

const _nameKey = ValueKey('name');
const _goalKey = ValueKey('goal');
const _noteKey = ValueKey('note');
const _footerKey = ValueKey('footer-button');

Future<void> _mount(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.paper,
        body: V3FooterScaffold(
          topBar: const SizedBox(height: _topBarHeight),
          body: (context, bottomPadding) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 28, 24, bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 160),
                V3Field(key: _nameKey, label: 'First name'),
                const SizedBox(height: 120),
                V3Field(key: _goalKey, multiline: true, rows: 3),
                const SizedBox(height: 140),
                V3Field(key: _noteKey, multiline: true, rows: 3),
              ],
            ),
          ),
          footer: V3Button(
            key: _footerKey,
            full: true,
            onPressed: () {},
            child: const Text('Continue'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openKeyboard(WidgetTester tester) async {
  tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  for (final height in [667.0, 844.0]) {
    testWidgets(
      'focused field ends fully visible above the footer and keyboard (${height.toInt()} pt)',
      (tester) async {
        await _mount(tester, Size(390, height));
        for (final key in [_nameKey, _goalKey, _noteKey]) {
          // Focus first, then the keyboard slides up, as on a device.
          await tester.ensureVisible(find.byKey(key));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(TextField),
            ),
          );
          await tester.pump();
          await _openKeyboard(tester);

          final field = tester.getRect(find.byKey(key));
          final footerTop = tester.getTopLeft(find.byKey(_footerKey)).dy;
          expect(
            field.bottom,
            lessThanOrEqualTo(footerTop),
            reason:
                '$key bottom ${field.bottom} is under the footer ($footerTop)',
          );
          expect(field.top, greaterThanOrEqualTo(_topBarHeight));
          expect(footerTop, lessThan(height - _keyboard));
          expect(
            tester.getRect(find.byKey(_footerKey)).bottom,
            lessThanOrEqualTo(height - _keyboard),
            reason: 'the footer button sits above the keyboard',
          );

          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('keeping a field focused while the keyboard opens', (
    tester,
  ) async {
    await _mount(tester, const Size(390, 667));
    final input = find.descendant(
      of: find.byKey(_nameKey),
      matching: find.byType(TextField),
    );
    await tester.tap(input);
    await tester.pump();
    final node = tester.widget<TextField>(input).focusNode!;
    expect(node.hasFocus, isTrue);
    await tester.enterText(input, 'Ada');
    await _openKeyboard(tester);
    expect(node.hasFocus, isTrue, reason: 'the layout switch keeps focus');
    expect(tester.widget<TextField>(input).controller!.text, 'Ada');
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    expect(tester.widget<TextField>(input).controller!.text, 'Ada');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keyboard closed: the footer overlays and the body clears it', (
    tester,
  ) async {
    await _mount(tester, const Size(390, 844));
    final footer = tester.getRect(find.byKey(_footerKey));
    // The footer hugs the bottom (20 pt gradient padding + 40 pt below the
    // button), over the body, which still runs to the screen's bottom edge.
    expect(footer.bottom, closeTo(844 - 40, 0.5));
    final scroll = tester.getRect(find.byType(SingleChildScrollView));
    expect(scroll.top, _topBarHeight);
    expect(scroll.bottom, 844);

    // The last field scrolls up clear of the footer, not hidden behind it.
    await tester.ensureVisible(find.byKey(_noteKey));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    final note = tester.getRect(find.byKey(_noteKey));
    final overlay = tester
        .getRect(
          find
              .ancestor(
                of: find.byKey(_footerKey),
                matching: find.byType(DecoratedBox),
              )
              .first,
        )
        .top;
    expect(note.bottom, lessThanOrEqualTo(overlay));
    await tester.pumpWidget(const SizedBox());
  });
}
