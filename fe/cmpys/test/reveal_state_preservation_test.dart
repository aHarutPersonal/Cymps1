import 'package:cmpys/core/ui/motion/entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final feedback in [false, true]) {
    testWidgets(
      '${feedback ? 'FeedbackReveal' : 'Entrance'} preserves editing state and focus',
      (tester) async {
        late StateSetter rebuild;
        var reduced = false;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                const field = TextField();
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduced),
                  child: Scaffold(
                    body: feedback
                        ? const FeedbackReveal(child: field)
                        : const Entrance(child: field),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(find.byType(TextField), 'Keep this draft');
        final original = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        await tester.pumpAndSettle();
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(original),
        );
        expect(find.text('Keep this draft'), findsOneWidget);
        expect(original.widget.focusNode.hasFocus, isTrue);
        reduced = true;
        rebuild(() {});
        await tester.pumpAndSettle();
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(original),
        );
        expect(find.text('Keep this draft'), findsOneWidget);
        reduced = false;
        rebuild(() {});
        await tester.pumpAndSettle();
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(original),
        );
        expect(original.widget.focusNode.hasFocus, isTrue);
      },
    );
  }
}
