import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/presentation/detail_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cmpys/core/ui/cmpys/cmpys_primitives.dart';
import 'package:cmpys/core/ui/cmpys_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('small pressable has a 48px target and keyboard activation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CmpysPressable(
              semanticLabel: 'Complete task',
              toggled: false,
              onTap: () => taps++,
              child: const SizedBox(width: 26, height: 26),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(CmpysPressable)), const Size(48, 48));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(taps, 2);
    final rect = tester.getRect(find.byType(CmpysPressable));
    await tester.tapAt(rect.topLeft + const Offset(2, 2));
    expect(taps, 3);
    expect(find.bySemanticsLabel('Complete task'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'password visibility is labelled, keyboard accessible and disabled with the field',
    (tester) async {
      Future<void> build(bool enabled) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CmpysTextField(
              label: 'Password',
              obscureText: true,
              enabled: enabled,
            ),
          ),
        ),
      );
      await build(true);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await build(false);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
    },
  );

  testWidgets('field label and error belong to the accessible input', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CmpysTextField(
            label: 'Email address',
            errorText: 'Enter a valid email address.',
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel(RegExp('Email address')), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.errorText,
      'Enter a valid email address.',
    );
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('sheet handle drags closed and Escape restores opener focus', (
    tester,
  ) async {
    final opener = FocusNode();
    addTearDown(opener.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              focusNode: opener,
              onPressed: () => showCmpysSheet<void>(
                context,
                title: 'Settings',
                child: const Text('Options'),
              ),
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    );
    opener.requestFocus();
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.showDragHandle, isTrue);
    final top = tester.getTopLeft(find.byType(BottomSheet));
    await tester.dragFrom(Offset(400, top.dy + 20), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.text('Options'), findsNothing);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Options'), findsNothing);
    expect(opener.hasFocus, isTrue);
  });
  testWidgets('profile sheet drags closed when clean and guards unsaved edits', (
    tester,
  ) async {
    // v3: Edit profile is a sheet (`v3/you.jsx` EditProfile). A clean sheet
    // drags closed; a dirty one stops at the Save / Discard / Keep editing
    // guard.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCmpysEditProfileSheet(context),
                child: const Text('Open profile'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(V3Sheet.handleKey), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(CmpysEditProfileScreen), findsNothing);
    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Unsaved name');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.drag(find.byKey(V3Sheet.handleKey), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(CmpysEditProfileScreen), findsOneWidget);
    expect(find.text('You have unsaved changes.'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved name'), findsOneWidget);
    await tester.drag(find.byKey(V3Sheet.handleKey), const Offset(0, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(CmpysEditProfileScreen), findsNothing);
    expect(find.text('Open profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
