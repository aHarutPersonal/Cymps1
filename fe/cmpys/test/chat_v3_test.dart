import 'dart:async';

import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/chat_screen.dart';
import 'package:cmpys/features/cmpys/presentation/record_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store extends CmpysStore {
  _Store({
    int age = 24,
    String sessionId = 'session-1',
    CmpysChatThread? thread,
    List<CmpysChatThread> threads = const [],
  }) {
    state = state.copyWith(
      sessionId: sessionId,
      idol: defaultIdol(),
      user: CmpysUser(name: 'Ana', age: age),
      chatThread: thread,
      chatThreads: threads,
    );
  }

  /// The same device after a relaunch.
  factory _Store.after(_Store old) =>
      _Store(thread: old.state.chatThread, threads: old.state.chatThreads);
}

/// The server stores the user turn, then the stream fails (an SSE `error`
/// event): "Your message was saved."
class _StoredThenFail {
  const _StoredThenFail();
}

/// A fake guided-learning backend that keeps a transcript like the server:
/// each send stores the user turn (reusing a pending turn with the same
/// text), then takes the next outcome — a reply (stored), a [_StoredThenFail],
/// an exception thrown before the server is reached (nothing stored), or a
/// [Completer] whose reply arrives later.
class _Chat extends Fake implements SessionRepository {
  _Chat({List<Map<String, dynamic>>? history, List<Object> outcomes = const []})
    : history = [...?history],
      outcomes = [...outcomes];

  List<Map<String, dynamic>> history;
  final List<Object> outcomes;
  final sent = <String>[];

  /// Per call to [learningMessages]: true fails that call.
  final historyFails = <bool>[];
  int _ids = 100;

  @override
  Future<List<Map<String, dynamic>>> learningMessages(String sessionId) async {
    if (historyFails.isNotEmpty && historyFails.removeAt(0)) {
      throw const NetworkError();
    }
    return [...history];
  }

  @override
  Future<Session?> getLatestSession() async => throw const NetworkError();

  void _storeUser(String content) {
    final last = history.isEmpty ? null : history.last;
    if (last != null && last['role'] == 'user' && last['content'] == content) {
      return; // the server reuses the pending turn
    }
    history.add({'id': 'm${_ids++}', 'role': 'user', 'content': content});
  }

  @override
  Stream<Map<String, dynamic>> sendGuidedLearningMessage(
    String sessionId,
    String content,
  ) async* {
    sent.add(content);
    final next = outcomes.isEmpty ? 'Noted.' : outcomes.removeAt(0);
    if (next is Exception) throw next;
    _storeUser(content);
    yield {'type': 'status', 'message': 'thinking'};
    if (next is _StoredThenFail) {
      yield {
        'type': 'error',
        'message': 'The mentor reply could not be completed.',
      };
      return;
    }
    final reply = next is Completer<String>
        ? await next.future
        : next as String;
    history.add({'id': 'm${_ids++}', 'role': 'assistant', 'content': reply});
    yield {'type': 'chunk', 'content': reply};
    yield {'type': 'done'};
  }
}

class _Plans extends Fake implements PlanRepository {
  final saved = <Map<String, Object?>>[];

  @override
  Future<String?> saveAchievement({
    required String title,
    required String category,
    String? notes,
    String? evidenceLink,
    required String source,
    String? planId,
    String? planItemId,
    int cycleNumber = 1,
  }) async {
    saved.add({
      'title': title,
      'category': category,
      'notes': notes,
      'evidenceLink': evidenceLink,
      'source': source,
      'planId': planId,
      'planItemId': planItemId,
      'cycleNumber': cycleNumber,
    });
    return 'ach-chat-${saved.length}';
  }
}

class _Plan extends CurrentPlanController {
  _Plan(PlanRepository repo) : super(repo: repo, readJobId: () => null) {
    state = CurrentPlanState(
      status: CurrentPlanStatus.ready,
      plan: BackendPlan(
        id: 'plan-7',
        durationWeeks: 12,
        weeklyHours: 4,
        cycleNumber: 3,
        items: const [],
      ),
    );
  }

  @override
  Future<void> refresh() async {}
}

late _Store _store;

Future<void> _pump(
  WidgetTester tester,
  _Chat chat, {
  _Store? store,
  _Plans? plans,
  bool reducedMotion = false,
}) async {
  _store = store ?? _Store();
  final repo = plans ?? _Plans();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cmpysStoreProvider.overrideWith((ref) => _store),
        sessionRepositoryProvider.overrideWithValue(chat),
        planRepositoryProvider.overrideWithValue(repo),
        currentPlanProvider.overrideWith((ref) => _Plan(repo)),
      ],
      child: MaterialApp(
        builder: reducedMotion
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              )
            : null,
        home: const CmpysChatScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Closes the app (flushing the store) and opens it again on this device.
Future<void> _relaunch(WidgetTester tester, _Chat chat) async {
  final next = _Store.after(_store);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 400));
  await _pump(tester, chat, store: next);
  await _settle(tester, 800);
}

Future<void> _settle(WidgetTester tester, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _iconButton(String label) =>
    find.byWidgetPredicate((w) => w is V3IconButton && w.label == label);

/// A text in the transcript (the header repeats the thread title).
Finder _msg(String text) =>
    find.descendant(of: find.byType(ListView), matching: find.text(text));

Finder _pressable(String label) =>
    find.byWidgetPredicate((w) => w is V3Pressable && w.semanticLabel == label);

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(CmpysChatScreen),
      matching: find.byType(TextField),
    ),
    text,
  );
  await tester.pump();
  await tester.tap(find.byKey(CmpysChatScreen.sendKey));
  await tester.pump();
}

Future<void> _tapPrompt(WidgetTester tester, String prompt) async {
  await tester.ensureVisible(_msg(prompt));
  await tester.pump();
  await tester.tap(_msg(prompt));
  await tester.pump();
}

/// Drives the win sheet to "Check and send".
Future<void> _winToCheck(
  WidgetTester tester, {
  String note = 'It took two evenings',
}) async {
  await tester.tap(_iconButton('Report a win'));
  await _settle(tester, 600);
  await tester.enterText(
    find.byKey(WinSheet.textFieldKey),
    'Read a full annual report',
  );
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await _settle(tester, 600);
  await tester.tap(find.text('Practice'));
  await _settle(tester, 900);
  await tester.tap(find.text('Solid step'));
  await tester.pump();
  await tester.enterText(
    find.descendant(of: find.byType(V3Field), matching: find.byType(TextField)),
    note,
  );
  await tester.enterText(
    find.byKey(WinSheet.linkFieldKey),
    'https://example.com/notes',
  );
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await _settle(tester, 600);
}

/// Drives the four steps of the win sheet up to "Added to your record".
Future<void> _reportWin(WidgetTester tester) async {
  await _winToCheck(tester);
  await tester.tap(find.text('Send to Buffett'));
  await _settle(tester, 1600);
}

/// Drives a standalone [WinSheet] to "Check and send".
Future<void> _sheetToCheck(WidgetTester tester, String dim) async {
  await tester.enterText(find.byKey(WinSheet.textFieldKey), 'Read a filing');
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await _settle(tester, 600);
  await tester.tap(find.text(dim));
  await _settle(tester, 900);
  await tester.tap(find.text('Small step'));
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await _settle(tester, 600);
}

Widget _sheetApp(Widget sheet, {double textScale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(800, 600),
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: sheet,
      ),
    ),
  ),
);

const _v2WinPrompt =
    'I want to report a win I just achieved: "Read a filing". React briefly in your own voice — does it move my trajectory?';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('failed_reply_retry_resends', (tester) async {
    final chat = _Chat(
      outcomes: [const NetworkError(), 'Start with one useful proof.'],
    );
    await _pump(tester, chat);

    await _type(tester, 'What should I do today?');
    await _settle(tester, 500);

    expect(find.text('The reply didn’t finish'), findsOneWidget);
    // The request never reached the server: no "saved" claim.
    expect(
      find.text('Couldn’t reach Buffett. Check your connection and tap retry.'),
      findsOneWidget,
    );
    expect(find.text('Your message was saved. Try again.'), findsNothing);
    expect(find.text('Retry reply'), findsOneWidget);
    expect(_msg('What should I do today?'), findsOneWidget);

    await tester.tap(find.text('Retry reply'));
    await tester.pump();
    await _settle(tester);

    expect(chat.sent, ['What should I do today?', 'What should I do today?']);
    expect(_msg('What should I do today?'), findsOneWidget);
    expect(find.text('Start with one useful proof.'), findsOneWidget);
    expect(find.text('Retry reply'), findsNothing);
    expect(find.text('Tap a reply to save it as a note'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a restored unanswered message retries without a new bubble', (
    tester,
  ) async {
    final chat = _Chat(
      history: [
        {'id': 'm1', 'role': 'user', 'content': 'Is Costco too big?'},
      ],
      outcomes: ['Size doesn’t matter. Simplicity does.'],
    );
    await _pump(tester, chat);
    expect(find.text('Your message was saved. Try again.'), findsOneWidget);

    await tester.tap(find.text('Retry reply'));
    await tester.pump();
    await _settle(tester);

    expect(chat.sent, ['Is Costco too big?']);
    expect(chat.history.where((m) => m['role'] == 'user'), hasLength(1));
    expect(find.text('Is Costco too big?'), findsOneWidget);
    expect(find.text('Size doesn’t matter. Simplicity does.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('error copy', () {
    testWidgets('a stored turn whose stream failed says it was saved', (
      tester,
    ) async {
      await _pump(tester, _Chat(outcomes: [const _StoredThenFail()]));
      await _type(tester, 'Is Costco too big?');
      await _settle(tester, 500);
      expect(find.text('The reply didn’t finish'), findsOneWidget);
      expect(find.text('Your message was saved. Try again.'), findsOneWidget);
      expect(find.text('Retry reply'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a refused (422) message says it wasn’t sent, no retry', (
      tester,
    ) async {
      final chat = _Chat(outcomes: [ApiError.fromStatusCode(422)]);
      await _pump(tester, chat);
      await _type(tester, 'A very long message');
      await _settle(tester, 500);

      expect(find.text('Your message wasn’t sent'), findsOneWidget);
      expect(
        find.text('It may be too long. Shorten it and send it again.'),
        findsOneWidget,
      );
      expect(find.text('Your message was saved. Try again.'), findsNothing);
      expect(find.text('Retry reply'), findsNothing);
      expect(_msg('A very long message'), findsNothing);
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(CmpysChatScreen),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, 'A very long message');
      // The caret sits at the end of the returned text.
      expect(
        field.controller!.selection,
        const TextSelection.collapsed(offset: 'A very long message'.length),
      );
      expect(chat.history, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      '400 is not sent; 404 retries; a stored turn never “wasn’t sent”',
      (tester) async {
        final chat = _Chat(
          history: [
            {'id': 'm1', 'role': 'user', 'content': 'Stored question'},
          ],
          outcomes: [
            ApiError.fromStatusCode(422), // Retry reply of the stored turn
            ApiError.fromStatusCode(404),
            ApiError.fromStatusCode(400),
          ],
        );
        await _pump(tester, chat);

        // A retry of a turn the server already holds.
        await tester.tap(find.text('Retry reply'));
        await tester.pump();
        await _settle(tester, 500);
        expect(find.text('Your message wasn’t sent'), findsNothing);
        expect(find.text('Retry reply'), findsOneWidget);
        expect(_msg('Stored question'), findsOneWidget);

        // A 404 on a new message: a retry-style line.
        await _type(tester, 'Second question');
        await _settle(tester, 500);
        expect(
          find.text('Couldn’t reach your conversation. Try again.'),
          findsOneWidget,
        );
        expect(find.text('Your message wasn’t sent'), findsNothing);
        expect(find.text('Retry reply'), findsOneWidget);
        expect(_msg('Second question'), findsOneWidget);

        // A 400: not sent, edit and send again, no retry.
        await _type(tester, 'Third question');
        await _settle(tester, 500);
        expect(find.text('Your message wasn’t sent'), findsOneWidget);
        expect(find.text('Edit it and send it again.'), findsOneWidget);
        expect(find.text('Retry reply'), findsNothing);
        expect(_msg('Third question'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  testWidgets('an offline failure keeps the old tail as the boundary', (
    tester,
  ) async {
    final chat = _Chat(
      history: [
        {'id': 'm1', 'role': 'user', 'content': 'Earlier question'},
        {'id': 'm2', 'role': 'assistant', 'content': 'Earlier answer'},
      ],
      outcomes: [const NetworkError(), 'Online answer'],
    );
    // The first load works; the boundary lookup after New chat is offline.
    chat.historyFails.addAll([false, true]);
    await _pump(tester, chat);
    await _type(tester, 'Offline question');
    await _settle(tester, 500);
    expect(find.text('Retry reply'), findsOneWidget);

    await tester.tap(_iconButton('New chat'));
    await _settle(tester, 600);
    expect(_store.state.chatThread?.afterId, 'm2');
    await _type(tester, 'Online question');
    await _settle(tester);

    // Back online for the relaunch (the offline lookup may not have been
    // needed: the old tail's id is still known).
    chat.historyFails.clear();
    await _relaunch(tester, chat);
    expect(_msg('Online question'), findsOneWidget);
    expect(find.text('Online answer'), findsOneWidget);
    expect(_msg('Earlier question'), findsNothing);
    expect(_msg('Earlier answer'), findsNothing);
    await _settle(tester, 1500);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after a failed reply, History lists only this session', (
    tester,
  ) async {
    final now = DateTime.now();
    final store = _Store(
      threads: [
        CmpysChatThread(
          id: 'th-x',
          title: 'Earlier session thread',
          startedAt: now,
          updatedAt: now,
          msgs: const [CmpysChatMsg(me: true, text: 'x')],
          sessionId: 'old-session',
        ),
        CmpysChatThread(
          id: 'th-y',
          title: 'This session thread',
          startedAt: now,
          updatedAt: now,
          msgs: const [CmpysChatMsg(me: true, text: 'y')],
          sessionId: 'session-1',
        ),
      ],
    );
    await _pump(tester, _Chat(outcomes: [const NetworkError()]), store: store);
    await _type(tester, 'Hello?');
    await _settle(tester, 500);
    expect(find.text('Retry reply'), findsOneWidget);

    await tester.tap(_iconButton('Chat history'));
    await _settle(tester, 600);
    expect(find.text('This session thread'), findsOneWidget);
    expect(find.text('Earlier session thread'), findsNothing);

    // A New chat from here archives this conversation under this session.
    await tester.tap(_pressable('New chat').last);
    await _settle(tester, 600);
    expect(
      _store.state.chatThreads.firstWhere((t) => t.title == 'Hello?').sessionId,
      'session-1',
    );
    expect(_store.state.chatThread?.sessionId, 'session-1');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'the mentor gets clipped evidence; the achievement keeps it all',
    (tester) async {
      final chat = _Chat(outcomes: ['Good.']);
      final plans = _Plans();
      await _pump(tester, chat, plans: plans);
      await _winToCheck(tester, note: 'n' * 1500);
      await tester.ensureVisible(find.text('Send to Buffett'));
      await tester.pump();
      await tester.tap(find.text('Send to Buffett'));
      await _settle(tester, 1600);
      await tester.ensureVisible(find.text('See the reply'));
      await tester.pump();
      await tester.tap(find.text('See the reply'));
      await tester.pump();
      await _settle(tester, 1500);

      expect(plans.saved.single['notes'], 'n' * 1500);
      final prompt = chat.sent.single;
      expect(prompt, contains('- Evidence: ${'n' * 1000}…'));
      expect(prompt, isNot(contains('n' * 1001)));
      expect(parseWinPrompt(prompt), 'Read a full annual report');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('win_sheet_four_steps_then_reply', (tester) async {
    final chat = _Chat(
      outcomes: ['That counts. Write down what nearly stopped you.'],
    );
    final plans = _Plans();
    await _pump(tester, chat, plans: plans);

    await tester.tap(_iconButton('Report a win'));
    await _settle(tester, 600);

    // Step 1: what you did, with rotating examples and the counter.
    expect(find.text('REPORT A WIN · 1 OF 4'), findsOneWidget);
    expect(find.text('What did you do?'), findsOneWidget);
    expect(
      find.text('e.g. Read Coca-Cola’s 10-K cover to cover'),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.text('e.g. Computed owner earnings for a real company'),
      findsOneWidget,
    );
    expect(find.text('0/120'), findsOneWidget);
    expect(find.text('OR START FROM'), findsOneWidget);
    await tester.enterText(find.byKey(WinSheet.textFieldKey), 'x' * 130);
    await tester.pump();
    expect(find.text('120/120'), findsOneWidget);
    await tester.enterText(
      find.byKey(WinSheet.textFieldKey),
      'Read a full annual report',
    );
    await tester.pump();
    expect(find.text('25/120'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await _settle(tester, 600);

    // Step 2: the dimension rows; a pick moves on by itself.
    expect(find.text('REPORT A WIN · 2 OF 4'), findsOneWidget);
    expect(find.text('What does it show?'), findsOneWidget);
    for (final label in [
      'Knowledge',
      'Practice',
      'Capital',
      'Network',
      'Judgment',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Work you did and can show'), findsOneWidget);
    await tester.tap(find.text('Practice'));
    await _settle(tester, 900);

    // Step 3: size bars and evidence.
    expect(find.text('How big was it?'), findsOneWidget);
    expect(find.text('Small step'), findsOneWidget);
    expect(find.text('Milestone'), findsOneWidget);
    expect(find.text('EVIDENCE · OPTIONAL'), findsOneWidget);
    await tester.tap(find.text('Solid step'));
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byType(V3Field),
        matching: find.byType(TextField),
      ),
      'It took two evenings',
    );
    await tester.enterText(
      find.byKey(WinSheet.linkFieldKey),
      'https://example.com/notes',
    );
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _settle(tester, 600);

    // Step 4: check and send.
    expect(find.text('Check and send'), findsOneWidget);
    expect(find.text('Age 24'), findsOneWidget);
    expect(find.text('Buffett will reply in chat'), findsOneWidget);
    expect(
      find.text(
        'Saved to Your record on this device. A reported win isn’t a verified achievement.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Send to Buffett'));
    await tester.pump(const Duration(milliseconds: 500));
    // The card is flying out while the win saves.
    expect(find.byKey(WinSheet.cardKey), findsOneWidget);
    await _settle(tester, 1200);

    expect(find.text('Added to your record'), findsOneWidget);
    expect(
      find.text('Filed under Practice at age 24. Buffett is reading it now.'),
      findsOneWidget,
    );
    expect(find.text('Writing a reply'), findsOneWidget);
    expect(chat.sent, isEmpty);

    await tester.tap(find.text('See the reply'));
    await tester.pump();
    await _settle(tester, 2500);

    // The mentor gets the win with its dimension, size and evidence.
    final prompt = chat.sent.single;
    expect(
      prompt,
      startsWith(
        'I want to report a win I just achieved: "Read a full annual report". React briefly in your own voice — does it move my trajectory?\n\nWin details:\n',
      ),
    );
    expect(
      prompt,
      contains('- Dimension: Practice (Work you did and can show)'),
    );
    expect(prompt, contains('- Size: Solid step (Harder than last time)'));
    expect(prompt, contains('- Evidence: It took two evenings'));
    expect(prompt, contains('- Link: https://example.com/notes'));
    expect(_msg('Read a full annual report'), findsOneWidget);
    expect(find.text('Win reported'), findsOneWidget);
    expect(
      find.text('That counts. Write down what nearly stopped you.'),
      findsOneWidget,
    );
    final win = _store.state.achievements.single;
    expect(win.idolNote, 'That counts. Write down what nearly stopped you.');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a reported win is saved as manual with plan and cycle', (
    tester,
  ) async {
    final plans = _Plans();
    await _pump(tester, _Chat(outcomes: ['Good.']), plans: plans);
    await _reportWin(tester);

    expect(plans.saved, [
      {
        'title': 'Read a full annual report',
        'category': 'impact',
        'notes': 'It took two evenings',
        'evidenceLink': 'https://example.com/notes',
        'source': 'manual',
        'planId': 'plan-7',
        'planItemId': null,
        'cycleNumber': 3,
      },
    ]);
    final win = _store.state.achievements.single;
    expect(win.title, 'Read a full annual report');
    expect(win.dim, 'practice');
    expect(win.source, 'chat');
    expect(win.impact, 2);
    expect(win.age, 24);
    expect(win.assessed, isFalse);
    expect(win.note, 'It took two evenings · https://example.com/notes');

    await tester.tap(find.text('See the reply'));
    await tester.pump();
    await _settle(tester, 1500);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a learner with no age gets the win under Undated', (
    tester,
  ) async {
    final plans = _Plans();
    await _pump(
      tester,
      _Chat(outcomes: ['Good.']),
      store: _Store(age: 0),
      plans: plans,
    );
    await tester.tap(_iconButton('Report a win'));
    await _settle(tester, 600);
    await _sheetToCheck(tester, 'Knowledge');
    expect(find.textContaining('Age'), findsNothing);
    await tester.tap(find.text('Send to Buffett'));
    await _settle(tester, 1600);

    expect(
      find.text('Filed under Knowledge. Buffett is reading it now.'),
      findsOneWidget,
    );
    expect(plans.saved.single['category'], 'learning');
    // Kept at age 0 on this device, so the Record files it under Undated.
    final win = _store.state.achievements.single;
    expect(win.age, 0);
    expect(win.synced, isTrue);
    final entry = recordTimeline(_store.state).singleWhere((e) => e.mine);
    expect(entry.id, win.id);
    expect(entry.age, isNull);

    await tester.tap(find.text('See the reply'));
    await tester.pump();
    await _settle(tester, 1500);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the sheet can’t be dismissed while the win is saving', (
    tester,
  ) async {
    final chat = _Chat(outcomes: ['Good.']);
    await _pump(tester, chat);
    await _winToCheck(tester);
    await tester.tap(find.text('Send to Buffett'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.widget<V3IconButton>(_iconButton('Close')).onPressed, isNull);
    expect(tester.widget<V3IconButton>(_iconButton('Back')).onPressed, isNull);
    // Scrim tap, then the system back gesture.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(WinSheet), findsOneWidget);

    await _settle(tester, 1500);
    expect(find.text('Added to your record'), findsOneWidget);
    await tester.tap(find.text('See the reply'));
    await tester.pump();
    await _settle(tester, 1500);
    expect(_msg('Read a full annual report'), findsOneWidget);
    expect(find.text('Good.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the WinSheet in record mode skips the chat reply', (
    tester,
  ) async {
    V3Win? done;
    V3Win? saved;
    await tester.pumpWidget(
      _sheetApp(
        WinSheet(
          mode: WinSheetMode.record,
          mentorShort: 'Buffett',
          age: 31,
          onSave: (w) async => saved = w,
          onDone: (w) => done = w,
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(WinSheet.textFieldKey),
      'Asked an expert a question',
    );
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _settle(tester, 600);
    await tester.tap(find.text('Network'));
    await _settle(tester, 900);
    await tester.tap(find.text('Milestone'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _settle(tester, 600);

    expect(find.text('Buffett adds a short note'), findsNothing);
    expect(find.text('Buffett will reply in chat'), findsNothing);
    await tester.tap(find.text('Send to Buffett'));
    await _settle(tester, 1600);

    expect(saved?.dim, 'network');
    expect(find.text('Added to your record'), findsOneWidget);
    expect(find.text('Filed under Network at age 31.'), findsOneWidget);
    expect(find.text('Saved to your record.'), findsOneWidget);
    expect(find.text('Mentor note saved with the entry.'), findsNothing);
    expect(find.text('Writing a reply'), findsNothing);
    expect(find.text('See the reply'), findsNothing);
    expect(done, isNull);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(done?.text, 'Asked an expert a question');
    expect(done?.dim, 'network');
    expect(done?.size, 3);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the card keeps its pop-in state through the send', (
    tester,
  ) async {
    final save = Completer<void>();
    await tester.pumpWidget(
      _sheetApp(
        WinSheet(
          mentorShort: 'Buffett',
          onSave: (_) => save.future,
          onDone: (_) {},
        ),
      ),
    );
    await tester.pump();
    await _sheetToCheck(tester, 'Capital');
    final pop = find
        .ancestor(
          of: find.byKey(WinSheet.cardKey),
          matching: find.byType(V3Pop),
        )
        .first;
    final before = tester.state(pop);

    await tester.tap(find.text('Send to Buffett'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.state(pop), same(before));
    save.complete();
    await _settle(tester, 1600);
    expect(find.text('Added to your record'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed win save stays on the check step', (tester) async {
    V3Win? done;
    await tester.pumpWidget(
      _sheetApp(
        WinSheet(
          mentorShort: 'Buffett',
          onSave: (_) async => throw const NetworkError(),
          onDone: (w) => done = w,
        ),
      ),
    );
    await tester.pump();
    await _sheetToCheck(tester, 'Judgment');
    await tester.tap(find.text('Send to Buffett'));
    await _settle(tester, 1600);

    expect(find.text('Check and send'), findsOneWidget);
    expect(find.text('Added to your record'), findsNothing);
    expect(find.text('Couldn’t save your win. Try again.'), findsOneWidget);
    expect(done, isNull);
    await _settle(tester, 3000);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the step-1 counter never covers the text at 2× text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sheetApp(WinSheet(mentorShort: 'Buffett', onDone: (_) {}), textScale: 2),
    );
    await tester.pump();
    await tester.enterText(find.byKey(WinSheet.textFieldKey), 'word ' * 24);
    await tester.pump();
    final field = tester.getRect(find.byKey(WinSheet.textFieldKey));
    final counter = tester.getRect(find.byKey(WinSheet.counterKey));
    expect(counter.top, greaterThanOrEqualTo(field.bottom));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  group('reduced motion', () {
    testWidgets('the reply appears at once and joins the transcript', (
      tester,
    ) async {
      await _pump(
        tester,
        _Chat(outcomes: ['Start with one useful proof.']),
        reducedMotion: true,
      );
      await _type(tester, 'Where do I start?');
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Start with one useful proof.'), findsOneWidget);
      expect(find.text('Tap a reply to save it as a note'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Send skips the fly-out and its wait', (tester) async {
      await _pump(tester, _Chat(outcomes: ['Good.']), reducedMotion: true);
      await _winToCheck(tester);
      await tester.tap(find.text('Send to Buffett'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Added to your record'), findsOneWidget);
      await tester.tap(find.text('See the reply'));
      await tester.pump();
      await _settle(tester, 500);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('the streaming reply stays scrolled into view', (tester) async {
    final reply = List.filled(400, 'word').join(' ');
    await _pump(tester, _Chat(outcomes: [reply]));
    await _type(tester, 'Explain owner earnings in detail');
    final scrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    ScrollPosition position() =>
        tester.state<ScrollableState>(scrollable).position;
    for (var i = 0; i < 150 && position().maxScrollExtent < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Still revealing (not yet in the transcript), and following it.
    expect(position().maxScrollExtent, greaterThanOrEqualTo(120));
    expect(find.text('Tap a reply to save it as a note'), findsNothing);
    expect(position().pixels, closeTo(position().maxScrollExtent, 1));
    final before = position().maxScrollExtent;
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(position().maxScrollExtent, greaterThan(before));
    expect(position().pixels, closeTo(position().maxScrollExtent, 1));
    await _settle(tester, 6000);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('History and New chat wait while a reply is in flight', (
    tester,
  ) async {
    final pending = Completer<String>();
    await _pump(tester, _Chat(outcomes: [pending]));
    await _type(tester, 'What now?');
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<V3IconButton>(_iconButton('Chat history')).onPressed,
      isNull,
    );
    expect(
      tester.widget<V3IconButton>(_iconButton('New chat')).onPressed,
      isNull,
    );
    pending.complete('Ten pages today.');
    await _settle(tester, 1000);
    expect(
      tester.widget<V3IconButton>(_iconButton('Chat history')).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('history_search_filters', (tester) async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final lastWeek = DateTime(monday.year, monday.month, monday.day - 3, 12);
    final chat = _Chat(
      history: [
        {'id': 'm1', 'role': 'user', 'content': 'How do I read a 10-K?'},
        {'id': 'm2', 'role': 'assistant', 'content': 'Start with the letter.'},
      ],
    );
    final store = _Store(
      threads: [
        CmpysChatThread(
          id: 'th-a',
          title: 'Picking a first company to study',
          startedAt: now,
          updatedAt: now,
          msgs: const [
            CmpysChatMsg(me: true, text: 'I use Costco every week.'),
            CmpysChatMsg(me: false, text: 'Start there.'),
          ],
        ),
        CmpysChatThread(
          id: 'th-b',
          title: 'I missed two days of habits',
          startedAt: lastWeek,
          updatedAt: lastWeek,
          msgs: const [CmpysChatMsg(me: true, text: 'I missed two days.')],
        ),
        CmpysChatThread(
          id: 'th-c',
          title: 'What to read before week 3',
          startedAt: now.subtract(const Duration(days: 40)),
          updatedAt: now.subtract(const Duration(days: 40)),
          msgs: const [CmpysChatMsg(me: true, text: 'Which letter first?')],
        ),
      ],
    );
    await _pump(tester, chat, store: store);

    await tester.tap(_iconButton('Chat history'));
    await _settle(tester, 600);

    expect(find.text('Conversations'), findsOneWidget);
    expect(find.text('CURRENT'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('LAST WEEK'), findsOneWidget);
    expect(find.text('EARLIER'), findsOneWidget);
    expect(find.text('Picking a first company to study'), findsOneWidget);
    expect(find.text('I missed two days of habits'), findsOneWidget);
    expect(find.text('What to read before week 3'), findsOneWidget);
    expect(find.text('You: Which letter first?'), findsOneWidget);

    final search = find.descendant(
      of: find.byType(V3Field),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, 'costco');
    await tester.pump();
    expect(find.text('Picking a first company to study'), findsOneWidget);
    expect(find.text('What to read before week 3'), findsNothing);
    expect(find.text('I missed two days of habits'), findsNothing);
    expect(find.text('CURRENT'), findsNothing);
    expect(find.text('LAST WEEK'), findsNothing);
    expect(find.text('EARLIER'), findsNothing);

    await tester.enterText(search, 'zzz');
    await tester.pump();
    expect(find.text('No conversations match “zzz”.'), findsOneWidget);

    await tester.enterText(search, '');
    await tester.pump();
    await tester.ensureVisible(_pressable('Delete conversation').last);
    await tester.pump();
    await tester.tap(_pressable('Delete conversation').last);
    await tester.pump();
    expect(find.text('Conversation deleted'), findsOneWidget);
    expect(find.text('What to read before week 3'), findsNothing);
    expect(_store.state.chatThreads.map((t) => t.id), ['th-a', 'th-b']);

    // Opening an archived conversation restores it and archives this one.
    await tester.tap(find.text('Picking a first company to study'));
    await _settle(tester, 800);
    expect(find.text('I use Costco every week.'), findsOneWidget);
    expect(find.text('Conversation restored · Today'), findsOneWidget);
    expect(find.text('How do I read a 10-K?'), findsNothing);
    expect(_store.state.chatThread?.id, 'th-a');
    expect(
      _store.state.chatThreads.first.msgs.first.text,
      'How do I read a 10-K?',
    );

    await _settle(tester, 3000);
    await tester.pumpWidget(const SizedBox());
  });

  group('thread boundary', () {
    testWidgets(
      'new chat starts empty and the restore skips archived messages',
      (tester) async {
        final chat = _Chat(
          history: [
            {'id': 'm1', 'role': 'user', 'content': 'How do I read a 10-K?'},
            {
              'id': 'm2',
              'role': 'assistant',
              'content': 'Start with the letter.',
            },
          ],
          outcomes: ['Pick a railway.'],
        );
        await _pump(tester, chat);
        expect(find.text('Conversation restored'), findsOneWidget);

        await tester.tap(_iconButton('New chat'));
        await _settle(tester, 800);
        expect(find.text('New conversation'), findsOneWidget);
        expect(find.text('What should I focus on this week?'), findsOneWidget);
        expect(find.text('Review my owner-earnings answer'), findsOneWidget);
        expect(find.text('What should I read next?'), findsOneWidget);
        expect(find.text('I only have 20 minutes today'), findsOneWidget);
        expect(_store.state.chatThread?.afterId, 'm2');
        expect(_store.state.chatThreads.single.msgs.length, 2);

        await _tapPrompt(tester, 'What should I read next?');
        await _settle(tester);
        expect(find.text('Pick a railway.'), findsOneWidget);
        expect(_msg('What should I read next?'), findsOneWidget);
        expect(_store.state.chatThread?.title, 'What should I read next?');
        // Suggestion chips appear once there is a reply.
        expect(
          find.text('How do I estimate maintenance capex?'),
          findsOneWidget,
        );

        await _relaunch(tester, chat);
        expect(find.text('Pick a railway.'), findsOneWidget);
        expect(find.text('Start with the letter.'), findsNothing);
        expect(find.text('Conversation restored · Today'), findsOneWidget);
        expect(_msg('What should I read next?'), findsOneWidget);
        await _settle(tester, 1500);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a reply with outer whitespace still ends the old thread', (
      tester,
    ) async {
      final chat = _Chat(outcomes: ['  The cash left years ago.  \n', 'A2.']);
      // The boundary lookup after New chat fails: only its text is known.
      chat.historyFails.addAll([false, true]);
      await _pump(tester, chat);
      await _type(tester, 'Why does depreciation matter?');
      await _settle(tester);
      expect(find.text('The cash left years ago.'), findsOneWidget);

      await tester.tap(_iconButton('New chat'));
      await _settle(tester, 600);
      expect(_store.state.chatThread?.afterId, isNull);
      await _type(tester, 'What next?');
      await _settle(tester);

      await _relaunch(tester, chat);
      expect(_msg('What next?'), findsOneWidget);
      expect(find.text('A2.'), findsOneWidget);
      expect(_msg('Why does depreciation matter?'), findsNothing);
      expect(find.text('The cash left years ago.'), findsNothing);
      await _settle(tester, 1500);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a reopened thread shows no duplicated transcript', (
      tester,
    ) async {
      final chat = _Chat(
        history: [
          {'id': 'm1', 'role': 'user', 'content': 'Q1 about moats'},
          {'id': 'm2', 'role': 'assistant', 'content': 'A1 about moats'},
        ],
        outcomes: ['A2 about filings'],
      );
      await _pump(tester, chat);
      await tester.tap(_iconButton('New chat'));
      await _settle(tester, 600);
      await _type(tester, 'Q2 about filings');
      await _settle(tester);

      await tester.tap(_iconButton('Chat history'));
      await _settle(tester, 600);
      await tester.tap(find.text('Conversation'));
      await _settle(tester, 800);
      expect(_msg('Q1 about moats'), findsOneWidget);
      // The server id of the reopen boundary is looked up.
      expect(_store.state.chatThread?.afterId, chat.history.last['id']);

      await _relaunch(tester, chat);
      expect(_msg('Q1 about moats'), findsOneWidget);
      expect(_msg('A1 about moats'), findsOneWidget);
      expect(_msg('Q2 about filings'), findsNothing);
      expect(_msg('A2 about filings'), findsNothing);
      await _settle(tester, 1500);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a re-sent pending question stays in the new thread', (
      tester,
    ) async {
      final chat = _Chat(
        outcomes: [const _StoredThenFail(), 'Pick a railway.'],
      );
      await _pump(tester, chat);
      await _tapPrompt(tester, 'What should I read next?');
      await _settle(tester, 500);
      expect(find.text('Your message was saved. Try again.'), findsOneWidget);

      await tester.tap(_iconButton('New chat'));
      await _settle(tester, 600);
      await _tapPrompt(tester, 'What should I read next?');
      await _settle(tester);
      expect(find.text('Pick a railway.'), findsOneWidget);
      // The server reused the pending turn: one question in its transcript.
      expect(chat.history.where((m) => m['role'] == 'user'), hasLength(1));

      await _relaunch(tester, chat);
      expect(_msg('What should I read next?'), findsOneWidget);
      expect(find.text('Pick a railway.'), findsOneWidget);
      await _settle(tester, 1500);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a failed history load never overwrites the stored thread', (
    tester,
  ) async {
    final thread = CmpysChatThread(
      id: 'th-b',
      title: 'Picking a company',
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      msgs: const [
        CmpysChatMsg(me: true, text: 'Carried question'),
        CmpysChatMsg(me: false, text: 'Carried answer'),
      ],
      afterId: 'm2',
      sessionId: 'session-1',
    );
    final chat = _Chat(
      history: [
        {'id': 'm1', 'role': 'user', 'content': 'Old question'},
        {'id': 'm2', 'role': 'assistant', 'content': 'Old answer'},
        {'id': 'm3', 'role': 'user', 'content': 'Later question'},
        {'id': 'm4', 'role': 'assistant', 'content': 'Later answer'},
      ],
      outcomes: [const NetworkError()],
    );
    chat.historyFails.add(true);
    await _pump(tester, chat, store: _Store(thread: thread));

    expect(
      find.text('Couldn’t restore your conversation. Retry to load it.'),
      findsOneWidget,
    );
    expect(find.textContaining('Conversation restored'), findsNothing);
    expect(find.text('New conversation'), findsNothing);
    expect(
      tester.widget<V3IconButton>(_iconButton('Chat history')).onPressed,
      isNull,
    );
    expect(
      tester.widget<V3IconButton>(_iconButton('New chat')).onPressed,
      isNull,
    );

    await _type(tester, 'Hello?');
    await _settle(tester, 500);
    expect(find.text('Retry reply'), findsOneWidget);
    final kept = _store.state.chatThread!;
    expect(kept.id, 'th-b');
    expect(kept.afterId, 'm2');
    expect(kept.msgs.map((m) => m.text), [
      'Carried question',
      'Carried answer',
    ]);

    await _relaunch(tester, chat);
    expect(_msg('Carried question'), findsOneWidget);
    expect(_msg('Later answer'), findsOneWidget);
    expect(_msg('Old question'), findsNothing);
    expect(find.text('Conversation restored · Today'), findsOneWidget);
    await _settle(tester, 1500);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('threads from an earlier session stay hidden', (tester) async {
    final now = DateTime.now();
    final store = _Store(
      thread: CmpysChatThread(
        id: 'th-old',
        title: 'Old mentor talk',
        startedAt: now,
        updatedAt: now,
        msgs: const [CmpysChatMsg(me: true, text: 'Old mentor question')],
        sessionId: 'old-session',
      ),
      threads: [
        CmpysChatThread(
          id: 'th-x',
          title: 'Earlier session thread',
          startedAt: now,
          updatedAt: now,
          msgs: const [CmpysChatMsg(me: true, text: 'x')],
          sessionId: 'old-session',
        ),
        CmpysChatThread(
          id: 'th-y',
          title: 'This session thread',
          startedAt: now,
          updatedAt: now,
          msgs: const [CmpysChatMsg(me: true, text: 'y')],
          sessionId: 'session-1',
        ),
      ],
    );
    await _pump(
      tester,
      _Chat(
        history: [
          {'id': 'm1', 'role': 'user', 'content': 'New mentor question'},
          {'id': 'm2', 'role': 'assistant', 'content': 'New mentor answer'},
        ],
      ),
      store: store,
    );
    expect(_msg('Old mentor question'), findsNothing);
    expect(_msg('New mentor question'), findsOneWidget);

    await tester.tap(_iconButton('Chat history'));
    await _settle(tester, 600);
    expect(find.text('This session thread'), findsOneWidget);
    expect(find.text('Earlier session thread'), findsNothing);
    await _settle(tester, 1000);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a restored win report shows as the win, old and new', (
    tester,
  ) async {
    final chat = _Chat(
      history: [
        {'id': 'm1', 'role': 'user', 'content': _v2WinPrompt},
        {'id': 'm2', 'role': 'assistant', 'content': 'That counts.'},
        {
          'id': 'm3',
          'role': 'user',
          'content': winPrompt(
            const V3Win(
              text: 'Wrote my own analysis',
              dim: 'judgment',
              size: 3,
            ),
          ),
        },
        {'id': 'm4', 'role': 'assistant', 'content': 'Good.'},
      ],
    );
    await _pump(tester, chat);
    expect(find.text('Read a filing'), findsOneWidget);
    expect(find.text('Wrote my own analysis'), findsOneWidget);
    expect(find.text('Win reported'), findsNWidgets(2));
    expect(find.textContaining('Win details'), findsNothing);
    await _settle(tester, 1500);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a reply saves as a note, by tap or keyboard', (tester) async {
    final chat = _Chat(
      history: [
        {'id': 'm1', 'role': 'user', 'content': 'Is Costco too big?'},
        {
          'id': 'm2',
          'role': 'assistant',
          'content': 'Size doesn’t matter. Simplicity does.',
        },
      ],
    );
    await _pump(tester, chat);
    expect(find.text('Tap a reply to save it as a note'), findsOneWidget);
    expect(
      tester.getSemantics(
        find
            .ancestor(
              of: find.text('Size doesn’t matter. Simplicity does.'),
              matching: find.byType(V3Pressable),
            )
            .first,
      ),
      containsSemantics(
        label: 'Size doesn’t matter. Simplicity does.',
        isButton: true,
        hasTapAction: true,
        onTapHint: 'Save to notes',
      ),
    );

    await tester.tap(find.text('Size doesn’t matter. Simplicity does.'));
    await _settle(tester, 600);
    expect(find.text('Notes are saved on this device.'), findsOneWidget);
    await tester.tap(find.text('Save to notes'));
    await tester.pump();
    await _settle(tester, 600);

    final note = _store.state.notes.single;
    expect(note.kind, 'chat');
    expect(note.body, 'Size doesn’t matter. Simplicity does.');
    expect(note.title, 'Buffett · Chat');
    expect(note.from, 'Buffett');
    expect(find.text('Saved to notes'), findsOneWidget);
    await _settle(tester, 3000);

    // Keyboard: focus the reply and press Enter.
    Focus.of(
      tester.element(find.text('Size doesn’t matter. Simplicity does.')),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester, 600);
    expect(find.text('Notes are saved on this device.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settle(tester, 600);
    await tester.pumpWidget(const SizedBox());
  });

  test('thread groups and dates', () {
    final now = DateTime(2026, 10, 29, 12); // a Thursday
    expect(chatThreadDay(DateTime(2026, 10, 26, 8), now: now), 'This week');
    expect(chatThreadDay(DateTime(2026, 10, 25, 23), now: now), 'Last week');
    expect(chatThreadDay(DateTime(2026, 10, 19), now: now), 'Last week');
    expect(chatThreadDay(DateTime(2026, 10, 18, 23), now: now), 'Earlier');
    expect(chatThreadWhen(DateTime(2026, 10, 29, 7), now: now), 'Today');
    expect(chatThreadWhen(DateTime(2026, 10, 26), now: now), 'Mon');
    expect(chatThreadWhen(DateTime(2026, 10, 12), now: now), '12 Oct');
  });

  test('old and new win prompts both parse, within the request limit', () {
    expect(parseWinPrompt(_v2WinPrompt), 'Read a filing');
    const win = V3Win(
      text: 'Read a "full" filing',
      dim: 'practice',
      size: 2,
      note: 'Line one.\nLine two with ". React briefly in your own voice',
      link: 'https://example.com',
    );
    expect(parseWinPrompt(winPrompt(win)), 'Read a "full" filing');
    expect(parseWinPrompt('Read a filing'), isNull);

    final biggest = V3Win(
      text: 'x' * winMaxLength,
      dim: 'knowledge',
      size: 3,
      note: 'n' * 5000,
      link: 'l' * 2048,
    );
    expect(winPrompt(biggest).length, lessThanOrEqualTo(chatMaxContent));
    expect(parseWinPrompt(winPrompt(biggest)), 'x' * winMaxLength);
    // Evidence is clipped to 1,000 characters each in the prompt.
    expect(winPrompt(biggest), contains('- Evidence: ${'n' * 1000}…'));
    expect(winPrompt(biggest), contains('- Link: ${'l' * 1000}…'));
    expect(winPrompt(biggest).length, lessThan(2600));
  });

  test('thread boundaries', () {
    final at = DateTime(2026, 10, 1);
    CmpysChatThread t({String? id, String? text}) => CmpysChatThread(
      id: 't',
      title: 't',
      startedAt: at,
      updatedAt: at,
      afterId: id,
      afterText: text,
    );
    final msgs = [
      {'id': 'a', 'role': 'user', 'content': 'Q'},
      {'id': 'b', 'role': 'assistant', 'content': ' A \n'},
      {'id': 'c', 'role': 'user', 'content': 'Q2'},
    ];
    expect(chatThreadStart(msgs, t()), 0);
    expect(chatThreadStart(msgs, t(id: 'b')), 2);
    expect(chatThreadStart(msgs, t(text: 'A')), 2);
    // A known id that scrolled out wins over a matching text.
    expect(chatThreadStart(msgs, t(id: 'gone', text: 'A')), 0);
    // A pending turn at the boundary that got answered was re-sent here.
    final reused = [
      {'id': 'a', 'role': 'user', 'content': 'Q'},
      {'id': 'b', 'role': 'assistant', 'content': 'A'},
    ];
    expect(chatThreadStart(reused, t(id: 'a')), 0);
    final abandoned = [
      {'id': 'a', 'role': 'user', 'content': 'Q'},
      {'id': 'c', 'role': 'user', 'content': 'Other'},
    ];
    expect(chatThreadStart(abandoned, t(id: 'a')), 1);
  });

  test('the store caps conversations and skips malformed ones', () async {
    final store = CmpysStore();
    await store.ready;
    final base = DateTime(2026, 10, 1);
    store.setChat(
      archived: [
        for (var i = 0; i < 40; i++)
          CmpysChatThread(
            id: 't$i',
            title: 'T$i',
            startedAt: base,
            updatedAt: base.add(Duration(hours: i)),
            msgs: [
              for (var k = 0; k < 150; k++)
                CmpysChatMsg(me: k.isEven, text: 'm$k'),
            ],
          ),
      ],
    );
    expect(store.state.chatThreads, hasLength(cmpysMaxChatThreads));
    expect(store.state.chatThreads.first.id, 't39');
    expect(store.state.chatThreads.first.msgs, hasLength(cmpysMaxChatMsgs));
    expect(store.state.chatThreads.first.msgs.first.text, 'm50');
    store.dispose();

    final json = CmpysState.initial().toJson()
      ..['notes'] = [
        {'id': 'n1', 'kind': 'chat', 'title': 'Kept', 'body': 'b'},
      ]
      ..['chatThread'] = {'title': 'no id'}
      ..['chatThreads'] = [
        'garbage',
        {'id': 5},
        {
          'id': 'ok',
          'title': 'Fine',
          'updatedAt': 'not a number',
          'msgs': [
            1,
            {'me': true, 't': 'hello'},
          ],
        },
      ];
    final state = CmpysState.fromJson(json);
    expect(state.notes.single.title, 'Kept');
    expect(state.chatThread, isNull);
    expect(state.chatThreads.single.id, 'ok');
    expect(state.chatThreads.single.msgs.single.text, 'hello');
  });
}
