import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/ui/cmpys/cmpys_primitives.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/chat_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ChatStore extends CmpysStore {
  _ChatStore() {
    state = state.copyWith(sessionId: 'session-1', idol: defaultIdol());
  }
}

class _ScriptedChatRepository extends Fake implements SessionRepository {
  int sends = 0;

  @override
  Future<Session?> getLatestSession() async => throw const NetworkError();

  @override
  Stream<Map<String, dynamic>> sendGuidedLearningMessage(
    String sessionId,
    String content,
  ) async* {
    sends++;
    if (sends == 1) {
      yield {'type': 'chunk', 'content': 'Start with one useful proof.'};
      yield {'type': 'done'};
      return;
    }
    throw const NetworkError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('cached-session stream failure is not automatically reposted', (
    tester,
  ) async {
    final repository = _ScriptedChatRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cmpysStoreProvider.overrideWith((ref) => _ChatStore()),
          sessionRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: CmpysChatScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('What should I focus on first?'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Start with one useful proof.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'What comes next?');
    await tester.pump();
    final sendAction = find.byWidgetPredicate(
      (widget) =>
          widget is CmpysPressable && widget.semanticLabel == 'Send message',
    );
    expect(sendAction, findsOneWidget);
    expect(tester.widget<CmpysPressable>(sendAction).onTap, isNotNull);
    await tester.tap(sendAction);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.sends, 2);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pump();
    expect(
      find.text('Couldn’t reach Buffett. Check your connection and tap retry.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('composer is centered and provides reliable keyboard dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cmpysStoreProvider.overrideWith((ref) => _ChatStore()),
          sessionRepositoryProvider.overrideWithValue(
            _ScriptedChatRepository(),
          ),
        ],
        child: const MaterialApp(home: CmpysChatScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final fieldFinder = find.byType(TextField);
    var field = tester.widget<TextField>(fieldFinder);
    final hasDragDismiss = tester
        .widgetList<ListView>(find.byType(ListView))
        .any(
          (list) =>
              list.keyboardDismissBehavior ==
              ScrollViewKeyboardDismissBehavior.onDrag,
        );

    expect(scaffold.resizeToAvoidBottomInset, isTrue);
    expect(field.textAlignVertical, TextAlignVertical.center);
    expect(field.onTapOutside, isNotNull);
    expect(hasDragDismiss, isTrue);

    await tester.tap(fieldFinder);
    await tester.pump(const Duration(milliseconds: 250));
    field = tester.widget<TextField>(fieldFinder);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.byIcon(Icons.keyboard_hide_rounded), findsOneWidget);

    final hideKeyboardAction = find.byWidgetPredicate(
      (widget) =>
          widget is CmpysPressable && widget.semanticLabel == 'Hide keyboard',
    );
    expect(hideKeyboardAction, findsOneWidget);
    await tester.tap(hideKeyboardAction);
    await tester.pump(const Duration(milliseconds: 250));
    field = tester.widget<TextField>(fieldFinder);
    expect(field.focusNode!.hasFocus, isFalse);

    await tester.pumpWidget(const SizedBox());
  });
}
