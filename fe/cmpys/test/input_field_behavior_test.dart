import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/cmpys_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('single-line fields center text and keep focus neutral', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CmpysTextField(focusNode: focusNode, hint: 'Email'),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final focusedBorder =
        field.decoration!.focusedBorder! as OutlineInputBorder;

    expect(field.textAlignVertical, TextAlignVertical.center);
    expect(focusedBorder.borderSide.color, AppColors.borderFocus);
    expect(focusedBorder.borderSide.color, isNot(AppColors.green));
    expect(field.onTapOutside, isNotNull);

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    field.onTapOutside!(const PointerDownEvent());
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
  });

  testWidgets('multiline fields remain top-aligned', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CmpysTextArea(hint: 'Longer note')),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textAlignVertical, TextAlignVertical.top);
  });
}
