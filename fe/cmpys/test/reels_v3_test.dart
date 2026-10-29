// Task F5: v3 idea reels (design `ReelsScreen` in v3/you.jsx).

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/app/theme.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/auth/models/me_models.dart';
import 'package:cmpys/features/cmpys/data/cmpys_ideas_provider.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/detail_screens.dart';
import 'package:cmpys/features/cmpys/presentation/reels_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _verified = CmpysIdea(
  id: 'idea-verified',
  text: 'Price is what you pay; value is what you get.',
  author: 'Warren Buffett',
  tag: 'Investing',
  tone: AppColors.iris,
  likes: 4,
  isSourced: true,
  isVerified: true,
  quoteType: 'sourced',
  verificationLevel: 'verified',
  sourceReference: '2008 shareholder letter',
);
const _exact = CmpysIdea(
  id: 'idea-exact',
  text: 'Know the enemy and know yourself.',
  author: 'Sun Tzu',
  tag: 'Strategy',
  tone: AppColors.sage,
  likes: 0,
  isSourced: true,
  quoteType: 'sourced',
  verificationLevel: 'source_backed',
);
const _generated = CmpysIdea(
  id: 'idea-generated',
  text: 'Owner earnings ask one question.',
  author: 'CMPYS insight',
  tag: 'Investing',
  tone: AppColors.ember,
  likes: 0,
);

class _EmptyPlanRepository implements PlanRepository {
  @override
  Future<BackendPlan?> getCurrentPlan() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlanController extends CurrentPlanController {
  _PlanController(BackendPlan? plan, {CurrentPlanStatus? status})
    : super(repo: _EmptyPlanRepository(), readJobId: () => null) {
    state = CurrentPlanState(
      status:
          status ??
          (plan == null ? CurrentPlanStatus.empty : CurrentPlanStatus.ready),
      plan: plan,
    );
  }

  @override
  Future<void> refresh() async {}
}

class _Store extends CmpysStore {
  _Store() {
    state = state.copyWith(user: CmpysUser(name: 'Ada', age: 24));
  }
}

typedef _Page = ({List<Map<String, Object?>> items, bool hasMore});

/// `/feed` stand-in: records each read as `p<page>` or `refresh`.
class _FeedClient extends Fake implements DioClient {
  _FeedClient(this.respond);

  Future<_Page> Function(int page, bool refresh) respond;
  final reads = <String>[];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    bool skipAuth = false,
    Duration? receiveTimeout,
  }) async {
    final refresh = queryParameters?['refresh'] == true;
    final page = queryParameters?['page'] as int? ?? 1;
    reads.add(refresh ? 'refresh' : 'p$page');
    final r = await respond(page, refresh);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: {'items': r.items, 'has_more': r.hasMore} as T,
    );
  }
}

Map<String, Object?> _item(String id, String text) => {
  'id': id,
  'type': 'quote',
  'content': text,
  'speaker': 'Mentor',
  'category': 'Focus',
};

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  List<CmpysIdea> ideas = const [_verified, _exact, _generated],
  Future<List<CmpysIdea>> Function()? load,
  BackendPlan? plan,
  CurrentPlanStatus? planStatus,
  DioClient? dio,
  bool reduced = true,
  Size size = const Size(402, 874),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      cmpysStoreProvider.overrideWith((ref) => _Store()),
      cmpysIdeasProvider.overrideWith(
        (ref) => load != null ? load() : Future.value(ideas),
      ),
      cmpysIdeasClockProvider.overrideWithValue(
        () => tester.binding.clock.now(),
      ),
      currentPlanProvider.overrideWith(
        (ref) => _PlanController(plan, status: planStatus),
      ),
      if (dio != null) dioClientProvider.overrideWithValue(dio),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const CmpysReelsScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return container;
}

Color? _segmentColor(WidgetTester tester, int k) {
  final box = tester.widget<AnimatedContainer>(
    find.byKey(ValueKey('reels-segment-$k')),
  );
  return (box.decoration as BoxDecoration?)?.color;
}

V3IconButton _iconButton(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate((w) => w is V3IconButton && w.label == label),
);

bool? _liked(ProviderContainer c, String id) =>
    c.read(cmpysStoreProvider).ideaState[id]?.liked;

Future<void> _toLast(WidgetTester tester, int count) async {
  for (var i = 1; i < count; i++) {
    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('double_tap_likes', (tester) async {
    final container = await _mount(tester, reduced: false);
    final page = find.byKey(const ValueKey('reel-idea-verified'));
    expect(page, findsOneWidget);
    expect(find.byKey(const ValueKey('reels-heart-burst')), findsNothing);

    await tester.tap(page);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(page);
    await tester.pump(const Duration(milliseconds: 100));

    expect(_liked(container, 'idea-verified'), isTrue);
    expect(find.byKey(const ValueKey('reels-heart-burst')), findsOneWidget);
    // The burst plays out (heart .9s) and leaves.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('reels-heart-burst')), findsNothing);

    // A fresh pair, well after the first, on a liked idea: the burst
    // replays and the like stays.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(page);
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(const ValueKey('reels-heart-burst')), findsNothing);
    await tester.tap(page);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_liked(container, 'idea-verified'), isTrue);
    expect(find.byKey(const ValueKey('reels-heart-burst')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));

    // The rail heart toggles the like off.
    await tester.tap(find.bySemanticsLabel('Like idea').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_liked(container, 'idea-verified'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a single tap, or two slow taps, do not like', (tester) async {
    final container = await _mount(tester, reduced: false);
    final page = find.byKey(const ValueKey('reel-idea-verified'));
    await tester.tap(page);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_liked(container, 'idea-verified'), isNot(isTrue));
    // The second tap lands 400 ms after the first: not a double-tap.
    await tester.tap(page);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_liked(container, 'idea-verified'), isNot(isTrue));
    expect(find.byKey(const ValueKey('reels-heart-burst')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('double-tap with reduced motion likes without a burst', (
    tester,
  ) async {
    final container = await _mount(tester);
    final page = find.byKey(const ValueKey('reel-idea-verified'));
    await tester.tap(page);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(page);
    await tester.pump();
    expect(_liked(container, 'idea-verified'), isTrue);
    expect(find.byKey(const ValueKey('reels-heart-burst')), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('save_adds_to_saved_list', (tester) async {
    final container = await _mount(tester);
    await tester.tap(find.bySemanticsLabel('Save idea').first);
    await tester.pump();

    final store = container.read(cmpysStoreProvider);
    expect(store.ideaState['idea-verified']?.saved, isTrue);
    expect(store.saved.single.id, 'idea-verified');
    expect(store.saved.single.kind, 'idea');
    expect(store.saved.single.title, _verified.text);
    expect(store.saved.single.sub, _verified.author);
    expect(find.text('Idea saved'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Save idea').first)
          .flagsCollection
          .isToggled,
      Tristate.isTrue,
    );

    // The F6 Saved list shows it.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const CmpysSavedScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Price is what you pay'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('saving again removes it from Saved', (tester) async {
    final container = await _mount(tester);
    await tester.tap(find.bySemanticsLabel('Save idea').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.bySemanticsLabel('Save idea').first);
    await tester.pump();
    expect(container.read(cmpysStoreProvider).saved, isEmpty);
    expect(find.text('Removed from saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  group('provenance', () {
    CmpysIdea idea({
      bool sourced = true,
      bool verified = false,
      String? type,
      String? level,
    }) => CmpysIdea(
      id: 'p',
      text: 't',
      author: 'a',
      tag: 'g',
      tone: AppColors.ink,
      likes: 0,
      isSourced: sourced,
      isVerified: verified,
      quoteType: type,
      verificationLevel: level,
    );

    test('maps the feed fields to the four design labels', () {
      expect(
        ideaProvenanceOf(
          idea(verified: true, type: 'sourced', level: 'verified'),
        ),
        IdeaProvenance.verified,
      );
      expect(
        ideaProvenanceOf(idea(type: 'sourced', level: 'source_backed')),
        IdeaProvenance.exact,
      );
      // Inconclusive verification never claims an exact quotation.
      expect(
        ideaProvenanceOf(idea(type: 'sourced', level: 'inconclusive')),
        IdeaProvenance.sourced,
      );
      expect(
        ideaProvenanceOf(idea(type: 'attributed', level: 'inconclusive')),
        IdeaProvenance.sourced,
      );
      expect(
        ideaProvenanceOf(idea(type: 'paraphrase', level: 'source_backed')),
        IdeaProvenance.sourced,
      );
      expect(ideaProvenanceOf(idea(sourced: false)), IdeaProvenance.generated);
      expect(IdeaProvenance.verified.label, 'Verified quotation');
      expect(IdeaProvenance.exact.label, 'Exact quotation');
      expect(IdeaProvenance.sourced.label, 'Sourced attribution');
      expect(IdeaProvenance.generated.label, 'Generated insight');
    });

    test('unknown or missing values fall back to Generated insight', () {
      expect(
        ideaProvenanceOf(idea(type: 'misquote', level: 'source_backed')),
        IdeaProvenance.generated,
      );
      expect(ideaProvenanceOf(idea()), IdeaProvenance.generated);
      expect(ideaProvenanceOf(idea(type: 'sourced')), IdeaProvenance.generated);
      expect(
        ideaProvenanceOf(idea(type: 'sourced', level: 'pending')),
        IdeaProvenance.generated,
      );
      expect(
        ideaProvenanceOf(idea(type: 'sourced', level: 'rejected')),
        IdeaProvenance.generated,
      );
      // Not linked to a catalog quote: never claims a quotation.
      expect(
        ideaProvenanceOf(idea(sourced: false, type: 'sourced')),
        IdeaProvenance.generated,
      );
    });

    testWidgets('each page shows its tag and the big quote mark', (
      tester,
    ) async {
      await _mount(tester);
      expect(find.text('Verified quotation'), findsOneWidget);
      expect(find.text('“'), findsWidgets);
      expect(find.text('Warren Buffett'), findsOneWidget);
      expect(find.text('2008 shareholder letter'), findsOneWidget);
      expect(
        find.text('Double-tap to like · swipe for the next idea'),
        findsOneWidget,
      );
      expect(find.byType(V3Grain), findsWidgets);
      await tester.tap(find.bySemanticsLabel('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Exact quotation'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Generated insight'), findsOneWidget);
    });
  });

  testWidgets('comments persist locally', (tester) async {
    final container = await _mount(tester);
    await tester.tap(find.bySemanticsLabel('Comments').first);
    await tester.pumpAndSettle();
    expect(find.text('Comments'), findsWidgets);
    expect(
      find.text('No comments yet. Add a thought you want to remember.'),
      findsOneWidget,
    );
    final post = find.widgetWithText(V3Button, 'Post');
    expect(tester.widget<V3Button>(post).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '  Margin of safety  ');
    await tester.pump();
    await tester.tap(post);
    await tester.pumpAndSettle();

    final comments = container
        .read(cmpysStoreProvider)
        .ideaState['idea-verified']!
        .comments;
    expect(comments.single.text, 'Margin of safety');
    expect(comments.single.who, 'Ada');
    expect(find.text('Ada Margin of safety'), findsOneWidget);
    expect(
      find.text('No comments yet. Add a thought you want to remember.'),
      findsNothing,
    );

    // Close and reopen: still there; the rail shows the count.
    Navigator.of(tester.element(find.byKey(V3Sheet.panelKey))).pop();
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Comments').first);
    await tester.pumpAndSettle();
    expect(find.text('Ada Margin of safety'), findsOneWidget);
  });

  testWidgets('progress segments follow the page', (tester) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester);
    expect(_segmentColor(tester, 0), Colors.white);
    expect(_segmentColor(tester, 1), isNot(Colors.white));
    expect(_segmentColor(tester, 2), isNot(Colors.white));
    expect(find.bySemanticsLabel('Idea 1 of 3'), findsOneWidget);

    // Up/down keep a 44 pt hit target.
    final next = find.bySemanticsLabel('Next');
    final rect = tester.getRect(next);
    expect(rect.width, greaterThanOrEqualTo(44));
    expect(rect.height, greaterThanOrEqualTo(44));

    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(_segmentColor(tester, 1), Colors.white);
    expect(_segmentColor(tester, 2), isNot(Colors.white));
    expect(find.bySemanticsLabel('Idea 2 of 3'), findsOneWidget);

    // A swipe snaps to the next page.
    await tester.fling(
      find.byKey(const ValueKey('reel-idea-exact')),
      const Offset(0, -500),
      1500,
    );
    await tester.pumpAndSettle();
    expect(_segmentColor(tester, 2), Colors.white);
    expect(find.bySemanticsLabel('Idea 3 of 3'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Previous'));
    await tester.pumpAndSettle();
    expect(_segmentColor(tester, 1), Colors.white);
    expect(_segmentColor(tester, 2), isNot(Colors.white));
    semantics.dispose();
  });

  testWidgets('up and down are disabled at the ends', (tester) async {
    await _mount(tester);
    expect(_iconButton(tester, 'Previous').onPressed, isNull);
    expect(_iconButton(tester, 'Next').onPressed, isNotNull);
    await _toLast(tester, 3);
    expect(_iconButton(tester, 'Previous').onPressed, isNotNull);
    expect(_iconButton(tester, 'Next').onPressed, isNull);
  });

  group('share', () {
    test('verified and exact ideas copy a quotation', () {
      expect(
        ideaShareText(_verified),
        '“Price is what you pay; value is what you get.” — Warren Buffett, '
        '2008 shareholder letter',
      );
      expect(
        ideaShareText(_exact),
        '“Know the enemy and know yourself.” — Sun Tzu',
      );
    });

    test('a generated idea copies plain text with its provenance', () {
      expect(
        ideaShareText(_generated),
        'Owner earnings ask one question. — CMPYS insight (Generated insight)',
      );
    });

    test('the source link follows on its own line', () {
      const attributed = CmpysIdea(
        id: 'a',
        text: 'Risk comes from not knowing what you’re doing.',
        author: 'Warren Buffett',
        tag: 'Investing',
        tone: AppColors.ink,
        likes: 0,
        isSourced: true,
        quoteType: 'attributed',
        verificationLevel: 'source_backed',
        sourceTitle: 'Interview',
        sourceUrl: ' https://example.org/q ',
      );
      expect(
        ideaShareText(attributed),
        'Risk comes from not knowing what you’re doing. — Warren Buffett, '
        'Interview (Sourced attribution)\nhttps://example.org/q',
      );
    });

    testWidgets('the rail copies the share text with a toast', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _mount(tester, ideas: const [_generated]);
      await tester.tap(find.bySemanticsLabel('Share idea').first);
      await tester.pump();
      await tester.pump();
      expect(copied, ideaShareText(_generated));
      expect(copied, isNot(startsWith('“')));
      expect(find.text('Copied quote'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  testWidgets('shows the loading skeleton until the ideas arrive', (
    tester,
  ) async {
    final pending = Completer<List<CmpysIdea>>();
    await _mount(tester, load: () => pending.future);
    expect(find.byType(V3Skel), findsNWidgets(4));
    expect(find.text(_verified.text), findsNothing);
    pending.complete(const [_verified]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(V3Skel), findsNothing);
    expect(find.text(_verified.text), findsOneWidget);
  });

  testWidgets('a failed load shows the error and Try again reloads', (
    tester,
  ) async {
    var loads = 0;
    await _mount(
      tester,
      load: () async {
        loads++;
        if (loads == 1) throw StateError('offline');
        return const [_verified];
      },
    );
    expect(
      find.text(
        'Couldn’t load your ideas. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Double-tap to like · swipe for the next idea'),
      findsNothing,
    );
    await tester.tap(find.widgetWithText(V3Button, 'Try again'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(loads, 2);
    expect(find.text(_verified.text), findsOneWidget);
  });

  group('title', () {
    testWidgets('names the plan’s focus week', (tester) async {
      await _mount(
        tester,
        plan: BackendPlan(
          id: 'plan',
          durationWeeks: 3,
          weeklyHours: 4,
          items: const [],
        ),
      );
      expect(find.text('Ideas for week 3'), findsOneWidget);
    });

    testWidgets('reads Ideas without a plan', (tester) async {
      await _mount(tester);
      expect(find.text('Ideas'), findsOneWidget);
      expect(find.textContaining('week'), findsNothing);
    });

    testWidgets('holds a skeleton, not a guess, while the plan loads', (
      tester,
    ) async {
      await _mount(tester, planStatus: CurrentPlanStatus.loading);
      expect(
        find.byKey(const ValueKey('reels-title-skeleton')),
        findsOneWidget,
      );
      expect(find.text('Ideas'), findsNothing);
      final loadingTop = tester
          .getRect(find.byKey(const ValueKey('idea-reading-idea-verified')))
          .top;

      await _mount(
        tester,
        plan: BackendPlan(
          id: 'plan',
          durationWeeks: 3,
          weeklyHours: 4,
          items: const [],
        ),
      );
      final readyTop = tester
          .getRect(find.byKey(const ValueKey('idea-reading-idea-verified')))
          .top;
      // The quote does not jump when the week appears.
      expect(readyTop, loadingTop);
    });
  });

  testWidgets('the hint never overlaps the quote at large text', (
    tester,
  ) async {
    for (final scale in [1.3, 1.5, 1.7]) {
      await _mount(tester, size: const Size(390, 844), textScale: scale);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('idea-reading-idea-verified')),
      );
      final hint = tester.getRect(find.byKey(const ValueKey('reels-hint')));
      expect(viewport.bottom, lessThanOrEqualTo(hint.top), reason: '$scale');
    }
  });

  group('load new ideas', () {
    testWidgets('the last idea loads new ideas with the skeleton', (
      tester,
    ) async {
      final gate = Completer<void>();
      final client = _FeedClient((page, refresh) async {
        await gate.future;
        return (
          items: [_item('n1', 'A brand new idea.'), _item('n2', 'Another.')],
          hasMore: true,
        );
      });
      await _mount(tester, dio: client);
      expect(find.text('You’re all caught up'), findsNothing);
      await _toLast(tester, 3);
      expect(find.text('You’re all caught up'), findsOneWidget);

      await tester.tap(find.widgetWithText(V3Button, 'Load new ideas'));
      await tester.pump();
      expect(client.reads, ['p2']);
      expect(find.byType(V3Skel), findsNWidgets(4));

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(V3Skel), findsNothing);
      expect(find.text('A brand new idea.'), findsOneWidget);
      expect(find.byKey(const ValueKey('reels-segment-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('reels-segment-2')), findsNothing);
      expect(_segmentColor(tester, 0), Colors.white);
      expect(_segmentColor(tester, 1), isNot(Colors.white));
    });

    testWidgets('a failed load keeps the ideas and says so', (tester) async {
      final client = _FeedClient(
        (page, refresh) async => throw StateError('down'),
      );
      await _mount(tester, dio: client);
      await _toLast(tester, 3);
      await tester.tap(find.widgetWithText(V3Button, 'Load new ideas'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Couldn’t refresh your feed'), findsOneWidget);
      expect(find.byType(V3Skel), findsNothing);
      expect(find.text(_generated.text), findsOneWidget);
      expect(_segmentColor(tester, 2), Colors.white);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('with has_more true it pages on and never generates', (
      tester,
    ) async {
      final client = _FeedClient(
        (page, refresh) async => (
          items: [
            _item('p$page-a', 'Page $page first.'),
            _item('p$page-b', 'Page $page second.'),
          ],
          hasMore: true,
        ),
      );
      await _mount(tester, dio: client);
      await _toLast(tester, 3);
      await tester.tap(find.widgetWithText(V3Button, 'Load new ideas'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 first.'), findsOneWidget);
      await _toLast(tester, 2);
      await tester.tap(find.widgetWithText(V3Button, 'Load new ideas'));
      await tester.pumpAndSettle();
      expect(find.text('Page 3 first.'), findsOneWidget);
      expect(client.reads, ['p2', 'p3']);
      expect(client.reads, isNot(contains('refresh')));
    });

    testWidgets('with has_more false it generates exactly once', (
      tester,
    ) async {
      final client = _FeedClient(
        (page, refresh) async => refresh
            ? (items: [_item('g1', 'Freshly written.')], hasMore: true)
            : (items: [_item('last', 'The final feed idea.')], hasMore: false),
      );
      await _mount(tester, dio: client);
      await _toLast(tester, 3);
      // Page 2 still exists but is the last one: shown, no generation yet.
      await tester.tap(find.widgetWithText(V3Button, 'Load new ideas'));
      await tester.pumpAndSettle();
      expect(find.text('The final feed idea.'), findsOneWidget);
      expect(client.reads, ['p2']);
      // Now the feed is done: one refresh=true read.
      await tester.tap(find.widgetWithText(V3Button, 'Load new ideas'));
      await tester.pumpAndSettle();
      expect(find.text('Freshly written.'), findsOneWidget);
      expect(client.reads, ['p2', 'refresh']);
    });

    testWidgets('an empty last page goes straight to one generation', (
      tester,
    ) async {
      final client = _FeedClient(
        (page, refresh) async => refresh
            ? (items: [_item('g1', 'Freshly written.')], hasMore: false)
            : (items: const <Map<String, Object?>>[], hasMore: false),
      );
      await _mount(tester, dio: client);
      await _toLast(tester, 3);
      await tester.tap(find.widgetWithText(V3Button, 'Load new ideas'));
      await tester.pumpAndSettle();
      expect(client.reads, ['p2', 'refresh']);
      expect(find.text('Freshly written.'), findsOneWidget);
    });

    testWidgets('two taps in the same frame make a single read', (
      tester,
    ) async {
      final gate = Completer<void>();
      final client = _FeedClient((page, refresh) async {
        await gate.future;
        return (items: [_item('n1', 'A brand new idea.')], hasMore: true);
      });
      await _mount(tester, dio: client);
      await _toLast(tester, 3);
      final button = find.widgetWithText(V3Button, 'Load new ideas');
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      expect(client.reads, ['p2']);
      gate.complete();
      await tester.pumpAndSettle();
      expect(client.reads, ['p2']);
    });

    testWidgets('screen readers skip the covered ideas while loading', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final gate = Completer<void>();
      final client = _FeedClient((page, refresh) async {
        await gate.future;
        return (items: [_item('n1', 'A brand new idea.')], hasMore: true);
      });
      await _mount(tester, dio: client);
      await _toLast(tester, 3);
      expect(find.semantics.byLabel('Like idea'), findsWidgets);
      await tester.tap(find.widgetWithText(V3Button, 'Load new ideas'));
      await tester.pump();
      expect(find.semantics.byLabel('Like idea'), findsNothing);
      expect(find.semantics.byLabel('Loading ideas'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel('Like idea'), findsWidgets);
      semantics.dispose();
    });

    testWidgets('a provider reload restarts at idea 1 and drops the new set', (
      tester,
    ) async {
      var loads = 0;
      final client = _FeedClient(
        (page, refresh) async => (
          items: [
            _item('n1', 'Loaded one.'),
            _item('n2', 'Loaded two.'),
            _item('n3', 'Loaded three.'),
          ],
          hasMore: true,
        ),
      );
      final container = await _mount(
        tester,
        dio: client,
        load: () async {
          loads++;
          return loads == 1
              ? const [_verified, _exact, _generated]
              : const [_generated, _exact];
        },
      );
      await _toLast(tester, 3);
      await tester.tap(find.widgetWithText(V3Button, 'Load new ideas'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Loaded two.'), findsOneWidget);
      expect(_segmentColor(tester, 1), Colors.white);

      // The shared feed reloads (a new day on resume).
      container.invalidate(cmpysIdeasProvider);
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(find.text('Loaded two.'), findsNothing);
      expect(find.text(_generated.text), findsOneWidget);
      expect(find.byKey(const ValueKey('reels-segment-2')), findsNothing);
      expect(_segmentColor(tester, 0), Colors.white);
      expect(_segmentColor(tester, 1), isNot(Colors.white));
      expect(_iconButton(tester, 'Previous').onPressed, isNull);

      // Paging through the feed starts over at page 2 too.
      await _toLast(tester, 2);
      await tester.tap(find.widgetWithText(V3Button, 'Load new ideas'));
      await tester.pumpAndSettle();
      expect(client.reads, ['p2', 'p2']);
    });
  });

  testWidgets('the feed reloads on resume when the local day changed', (
    tester,
  ) async {
    var day = DateTime(2026, 10, 28, 23, 50);
    final client = _FeedClient(
      (page, refresh) async => (
        items: [_item('q${day.day}', 'Idea for day ${day.day}.')],
        hasMore: false,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        dioClientProvider.overrideWithValue(client),
        cmpysIdeasClockProvider.overrideWithValue(() => day),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(cmpysIdeasProvider, (_, _) {});
    addTearDown(sub.close);
    expect((await container.read(cmpysIdeasProvider.future)).single.id, 'q28');

    void cycle() {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    // Same day: no reload.
    day = DateTime(2026, 10, 28, 23, 59);
    cycle();
    await tester.pump(const Duration(seconds: 1));
    expect(client.reads, ['p1']);

    // Past midnight: one plain reload (never refresh=true).
    day = DateTime(2026, 10, 29, 0, 5);
    cycle();
    await tester.pump(const Duration(seconds: 1));
    expect((await container.read(cmpysIdeasProvider.future)).single.id, 'q29');
    expect(client.reads, ['p1', 'p1']);
  });

  testWidgets('a new-day reload that failed offline retries on resume', (
    tester,
  ) async {
    var day = DateTime(2026, 10, 28, 22);
    var online = true;
    final client = _FeedClient((page, refresh) async {
      if (!online) throw StateError('offline');
      return (
        items: [_item('q${day.day}', 'Idea for day ${day.day}.')],
        hasMore: false,
      );
    });
    final container = ProviderContainer(
      overrides: [
        dioClientProvider.overrideWithValue(client),
        cmpysIdeasClockProvider.overrideWithValue(() => day),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(cmpysIdeasProvider, (_, _) {});
    addTearDown(sub.close);
    expect((await container.read(cmpysIdeasProvider.future)).single.id, 'q28');

    void resume() {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    // After midnight, offline: the reload fails and yesterday's list stays.
    day = DateTime(2026, 10, 29, 7);
    online = false;
    resume();
    await tester.pump(const Duration(seconds: 1));
    expect(client.reads, ['p1', 'p1']);
    expect(container.read(cmpysIdeasProvider).hasError, isTrue);
    expect(container.read(cmpysIdeasProvider).valueOrNull?.single.id, 'q28');

    // Online again, still the same (new) day: the next resume reloads.
    online = true;
    resume();
    await tester.pump(const Duration(seconds: 1));
    expect(client.reads, ['p1', 'p1', 'p1']);
    expect((await container.read(cmpysIdeasProvider.future)).single.id, 'q29');

    // Loaded fine today: a further resume the same day reads nothing.
    resume();
    await tester.pump(const Duration(seconds: 1));
    expect(client.reads, ['p1', 'p1', 'p1']);
  });

  test('the feed reloads for a different account (R3-M3)', () async {
    var account = 'a';
    final client = _FeedClient(
      (page, refresh) async => (
        items: [_item('q-$account', 'Idea for $account.')],
        hasMore: false,
      ),
    );
    final user = StateProvider<Me?>(
      (ref) => const Me(id: 'account-a', email: 'a@example.test'),
    );
    final container = ProviderContainer(
      overrides: [
        dioClientProvider.overrideWithValue(client),
        currentUserProvider.overrideWith((ref) => ref.watch(user)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(cmpysIdeasProvider, (_, _) {});
    addTearDown(sub.close);
    expect((await container.read(cmpysIdeasProvider.future)).single.id, 'q-a');

    // A profile refresh for the same account keeps the loaded feed.
    container.read(user.notifier).state = const Me(
      id: 'account-a',
      email: 'a@example.test',
      fullName: 'Ana',
    );
    await container.read(cmpysIdeasProvider.future);
    expect(client.reads, ['p1']);

    // Another account never sees the previous one's feed.
    account = 'b';
    container.read(user.notifier).state = const Me(
      id: 'account-b',
      email: 'b@example.test',
    );
    expect((await container.read(cmpysIdeasProvider.future)).single.id, 'q-b');
    expect(client.reads, ['p1', 'p1']);
  });

  testWidgets('close pops the reels', (tester) async {
    await _mount(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(builder: (_) => const CmpysReelsScreen()));
    await tester.pumpAndSettle();
    expect(nav.canPop(), isTrue);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(nav.canPop(), isFalse);
  });
}
