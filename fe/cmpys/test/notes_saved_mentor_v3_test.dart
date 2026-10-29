import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/app/router.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/cmpys/data/cmpys_ideas_provider.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/detail_screens.dart';
import 'package:cmpys/features/cmpys/presentation/idol_detail_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// F6 (`v3/you.jsx` ListScreen and MentorScreen): the Notes and Saved lists
// kept on the device, their empty-state CTAs, delete, and the night mentor
// context screen with the disclaimer and the age-highlighted timeline.

class _Store extends CmpysStore {
  _Store({
    List<CmpysNote> notes = const [],
    List<CmpysSavedItem> saved = const [],
    int age = 24,
  }) {
    state = state.copyWith(
      notes: notes,
      saved: saved,
      user: CmpysUser(name: 'Ana', age: age),
    );
  }
}

class _Repo extends Fake implements SessionRepository {
  _Repo(this.timeline);
  final List<IdolTimelineEntry> timeline;
  final calls = <String>[];

  @override
  Future<List<IdolTimelineEntry>> idolTimeline(String idolName) async {
    calls.add(idolName);
    return timeline;
  }
}

const _buffett = CmpysIdol(
  id: 'buffett',
  slug: '__llm__',
  name: 'Warren Buffett',
  short: 'Buffett',
  initials: 'WB',
  title: 'Investor',
  era: 'b. 1930',
  field: 'Wealth',
  color: AppColors.iris,
  tint: AppColors.irisSoft,
  tag: 'Investor',
  blurb: 'Compounding, patience and a written record of every decision.',
  quote: 'Rule No. 1: never lose money.',
  atYourAge: 'At 26 he opened his first investment partnership.',
  pillars: ['Investing', 'Writing'],
);

const _buffettIdea = CmpysIdea(
  id: 'idea-1',
  text: 'Price is what you pay; value is what you get.',
  author: 'Warren Buffett',
  tag: 'Value',
  tone: AppColors.iris,
  likes: 12,
);

/// A verified quotation of this mentor's: the only kind put in quotation
/// marks (R3-M4).
const _verifiedIdea = CmpysIdea(
  id: 'idea-3',
  text: 'Rule No. 1 is never lose money.',
  author: 'Warren Buffett',
  tag: 'Risk',
  tone: AppColors.gold,
  likes: 5,
  isSourced: true,
  isVerified: true,
  verificationLevel: 'verified',
  quoteType: 'sourced',
);

const _otherIdea = CmpysIdea(
  id: 'idea-2',
  text: 'An idea from someone else.',
  author: 'Charlie Munger',
  tag: 'Models',
  tone: AppColors.sage,
  likes: 3,
);

/// Notes or Saved pushed over a "You" page, with the chat tab and the idea
/// reels as real routes, so the CTAs' destinations are observable.
Future<void> _mountList(
  WidgetTester tester, {
  required Widget screen,
  required CmpysStore store,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: AppRoutes.profile,
    routes: [
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => screen)),
              child: const Text('open list'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.chat,
        builder: (_, _) => const Scaffold(body: Text('CHAT TAB')),
      ),
      GoRoute(
        path: AppRoutes.ideas,
        builder: (_, _) => const Scaffold(body: Text('IDEA REELS')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [cmpysStoreProvider.overrideWith((ref) => store)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open list'));
  await tester.pumpAndSettle();
}

Future<void> _mountMentor(
  WidgetTester tester, {
  required _Repo repo,
  int age = 26,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cmpysStoreProvider.overrideWith((ref) => _Store(age: age)),
        sessionRepositoryProvider.overrideWithValue(repo),
        cmpysIdeasProvider.overrideWith(
          (ref) async => const [_buffettIdea, _otherIdea, _verifiedIdea],
        ),
      ],
      child: const MaterialApp(home: CmpysIdolDetailScreen(idol: _buffett)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Long enough that its first line runs the full card width.
const _longNote =
    'Write down why you bought it, what would make you sell it, and what '
    'you expect the business to earn in ten years before you buy a share.';

Color? _ageColor(WidgetTester tester, int index) => tester
    .widget<Text>(find.byKey(ValueKey('timeline-age-$index')))
    .style
    ?.color;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Notes and Saved', () {
    testWidgets('both lists say they live on this device', (tester) async {
      await _mountList(
        tester,
        screen: const CmpysNotesScreen(),
        store: _Store(),
      );
      expect(find.text('LIBRARY · ON THIS DEVICE'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await _mountList(
        tester,
        screen: const CmpysSavedScreen(),
        store: _Store(),
      );
      expect(find.text('LIBRARY · ON THIS DEVICE'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('empty_notes_cta_opens_chat', (tester) async {
      await _mountList(
        tester,
        screen: const CmpysNotesScreen(),
        store: _Store(),
      );

      expect(find.text('No notes yet'), findsOneWidget);
      expect(
        find.text('Tap any mentor reply in Chat to save it here.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(V3Button, 'Open chat'));
      await tester.pumpAndSettle();

      expect(find.text('CHAT TAB'), findsOneWidget);
      expect(find.text('No notes yet'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('empty Saved CTA opens the idea reels', (tester) async {
      await _mountList(
        tester,
        screen: const CmpysSavedScreen(),
        store: _Store(),
      );

      expect(find.text('Nothing saved yet'), findsOneWidget);
      expect(
        find.text('Save ideas from the reels. Saved books live in Reading.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(V3Button, 'Browse ideas'));
      await tester.pumpAndSettle();

      expect(find.text('IDEA REELS'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('delete removes a note from the device store', (tester) async {
      final store = _Store(
        notes: [
          CmpysNote(
            id: 'n1',
            kind: 'chat',
            title: 'From Buffett',
            body: 'Write down why you bought it.',
            from: 'Buffett',
          ),
          CmpysNote(
            id: 'n2',
            kind: 'chat',
            title: 'From Buffett',
            body: 'Stay inside your circle of competence.',
            from: 'Buffett',
          ),
        ],
      );
      await _mountList(tester, screen: const CmpysNotesScreen(), store: store);

      expect(find.text('Write down why you bought it.'), findsOneWidget);
      expect(find.text('FROM BUFFETT · JUST NOW'), findsNWidgets(2));
      await tester.tap(find.bySemanticsLabel('Remove note').first);
      await tester.pumpAndSettle();

      expect(find.text('Write down why you bought it.'), findsNothing);
      expect(
        find.text('Stay inside your circle of competence.'),
        findsOneWidget,
      );
      expect(store.state.notes.map((n) => n.id), ['n2']);
      expect(find.text('Note deleted'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a note shows when it was saved (R3-M5)', (tester) async {
      final now = DateTime.now();
      final store = _Store(
        notes: [
          CmpysNote(
            id: 'n1',
            kind: 'chat',
            title: 'From Buffett',
            body: 'Recent note.',
            at: now
                .subtract(const Duration(minutes: 10))
                .millisecondsSinceEpoch,
          ),
          // An older build's note keeps the label it stored.
          CmpysNote(
            id: 'n2',
            kind: 'chat',
            title: 'From Buffett',
            body: 'Old note.',
            when: 'Just now',
          ),
        ],
      );
      await _mountList(tester, screen: const CmpysNotesScreen(), store: store);
      expect(find.text('FROM BUFFETT · 10 MIN AGO'), findsOneWidget);
      expect(find.text('FROM BUFFETT · JUST NOW'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    test('cmpysNoteWhen reads relative to now', () {
      final now = DateTime(2026, 10, 29, 15); // a Thursday
      String at(DateTime t) => cmpysNoteWhen(
        CmpysNote(
          id: 'n',
          kind: 'chat',
          title: '',
          body: '',
          at: t.millisecondsSinceEpoch,
        ),
        now: now,
      );
      expect(at(now.subtract(const Duration(seconds: 20))), 'Just now');
      expect(at(now.subtract(const Duration(minutes: 1))), '1 min ago');
      expect(at(now.subtract(const Duration(minutes: 59))), '59 min ago');
      expect(at(DateTime(2026, 10, 29, 9)), '6 h ago');
      expect(at(DateTime(2026, 10, 28, 23)), 'Yesterday');
      expect(at(DateTime(2026, 10, 26, 8)), 'Mon');
      expect(at(DateTime(2026, 10, 12, 8)), '12 Oct');
      expect(at(DateTime(2025, 10, 12, 8)), '12 Oct 2025');
      // A clock that moved backwards never reads as the future.
      expect(at(now.add(const Duration(minutes: 5))), 'Just now');
      // No timestamp: the stored label.
      expect(
        cmpysNoteWhen(
          CmpysNote(id: 'n', kind: 'chat', title: '', body: '', when: 'Saved'),
          now: now,
        ),
        'Saved',
      );
    });

    testWidgets('a saved item from an older build that has no reader opens '
        'nothing and stays (R3-M10)', (tester) async {
      final store = _Store(
        saved: [
          CmpysSavedItem(id: 'r1', kind: 'read', title: 'Old reading'),
        ],
      );
      await _mountList(tester, screen: const CmpysSavedScreen(), store: store);
      await tester.tap(find.text('Old reading'));
      await tester.pumpAndSettle();
      expect(find.text('Old reading'), findsOneWidget);
      expect(find.text('IDEA REELS'), findsNothing);
      expect(store.state.saved, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('delete removes a saved item', (tester) async {
      final store = _Store(
        saved: [
          CmpysSavedItem(
            id: 's1',
            kind: 'idea',
            title: 'Margin of safety',
            sub: 'Graham',
          ),
        ],
      );
      await _mountList(tester, screen: const CmpysSavedScreen(), store: store);

      expect(find.text('Margin of safety'), findsOneWidget);
      expect(find.text('Graham'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Remove from saved'));
      await tester.pumpAndSettle();

      expect(store.state.saved, isEmpty);
      expect(find.text('Removed from saved'), findsOneWidget);
      // The list empties into the empty state.
      expect(find.text('Nothing saved yet'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('removing a saved idea clears its reels bookmark', (
      tester,
    ) async {
      final store = _Store();
      store.toggleIdeaSave(
        id: 'idea-1',
        title: 'Margin of safety',
        author: 'Graham',
      );
      expect(store.state.ideaState['idea-1']!.saved, isTrue);
      expect(store.state.saved.single.kind, 'idea');
      await _mountList(tester, screen: const CmpysSavedScreen(), store: store);

      await tester.tap(find.bySemanticsLabel('Remove from saved'));
      await tester.pumpAndSettle();

      expect(store.state.saved, isEmpty);
      expect(store.ideaOf('idea-1').saved, isFalse);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Remove has a 44 pt hit box that covers no text', (
      tester,
    ) async {
      final store = _Store(
        notes: [
          CmpysNote(
            id: 'n1',
            kind: 'chat',
            title: 'From Buffett',
            body: _longNote,
          ),
        ],
      );
      await _mountList(tester, screen: const CmpysNotesScreen(), store: store);

      final hit = tester.getRect(find.byKey(const ValueKey('library-remove')));
      expect(hit.width, greaterThanOrEqualTo(44));
      expect(hit.height, greaterThanOrEqualTo(44));
      final kick = tester.getRect(find.text('FROM BUFFETT · JUST NOW'));
      final body = tester.getRect(find.text(_longNote));
      expect(hit.overlaps(body), isFalse);
      expect(hit.overlaps(kick), isFalse);
      // The header is not a 44 pt row: border 1 + padding 16 + header 20 +
      // gap 8, just below the 44 pt box.
      expect(body.top - hit.top, closeTo(45, 0.5));
      // The icon stays level with the kick line.
      final icon = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('library-remove')),
          matching: find.byType(V3Icon),
        ),
      );
      expect(icon.center.dy, closeTo(kick.center.dy, 0.5));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a tap on the first line’s right end does not delete', (
      tester,
    ) async {
      final store = _Store(
        notes: [
          CmpysNote(
            id: 'n1',
            kind: 'chat',
            title: 'From Buffett',
            body: _longNote,
          ),
        ],
      );
      await _mountList(tester, screen: const CmpysNotesScreen(), store: store);

      final body = tester.getRect(find.text(_longNote));
      await tester.tapAt(Offset(body.right - 3, body.top + 3));
      await tester.pumpAndSettle();
      expect(store.state.notes, hasLength(1));
      expect(find.text('Note deleted'), findsNothing);

      // The button itself still deletes.
      await tester.tap(find.bySemanticsLabel('Remove note'));
      await tester.pumpAndSettle();
      expect(store.state.notes, isEmpty);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tapping a saved idea opens the reels', (tester) async {
      final store = _Store(
        saved: [
          CmpysSavedItem(
            id: 'idea-1',
            kind: 'idea',
            title: 'Margin of safety',
            sub: 'Graham',
          ),
        ],
      );
      await _mountList(tester, screen: const CmpysSavedScreen(), store: store);

      await tester.tap(find.text('Margin of safety'));
      await tester.pumpAndSettle();

      expect(find.text('IDEA REELS'), findsOneWidget);
      // Opening is not removing.
      expect(store.state.saved, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Mentor context', () {
    const timeline = [
      IdolTimelineEntry(age: 11, text: 'Buys his first stock.'),
      IdolTimelineEntry(age: 26, text: 'Starts his first partnership.'),
      IdolTimelineEntry(age: 39, text: 'Closes the partnership.'),
    ];

    testWidgets('night ground with the verbatim disclaimer', (tester) async {
      await _mountMentor(tester, repo: _Repo(timeline));

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, AppColors.night);
      expect(find.text('AI interpretation · not Buffett'), findsOneWidget);
      expect(find.text('Warren Buffett'), findsOneWidget);
      expect(
        find.text(
          'Replies in Chat are generated from Buffett’s documented writing, '
          'interviews and biographies. They are not messages from Buffett.',
        ),
        findsOneWidget,
      );
      expect(find.text('TIMELINE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the timeline highlights the user’s age', (tester) async {
      final repo = _Repo(timeline);
      await _mountMentor(tester, repo: repo, age: 26);

      expect(repo.calls, ['Warren Buffett']);
      expect(find.text('Starts his first partnership.'), findsOneWidget);
      expect(_ageColor(tester, 1), const Color(0xFFFFA37F));
      expect(_ageColor(tester, 0), AppColors.nink3);
      expect(_ageColor(tester, 2), AppColors.nink3);
      // Screen readers hear the highlight, not just see it.
      expect(find.bySemanticsLabel('Age 26, your age'), findsOneWidget);
      expect(find.bySemanticsLabel('Age 11'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Age 11, your age')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the screen keeps its at-your-age, quote, pillar and idea '
        'data', (tester) async {
      await _mountMentor(tester, repo: _Repo(timeline));

      expect(find.text('AT YOUR AGE'), findsOneWidget);
      expect(
        find.text('At 26 he opened his first investment partnership.'),
        findsOneWidget,
      );
      expect(find.text('“Rule No. 1: never lose money.”'), findsOneWidget);
      expect(find.text(_buffett.blurb), findsOneWidget);
      expect(find.text('PILLARS YOU WORK ON TOGETHER'), findsOneWidget);
      expect(find.text('Investing'), findsOneWidget);
      expect(find.text('Writing'), findsOneWidget);
      // Only ideas attributed to this mentor.
      expect(find.text('IDEAS FROM BUFFETT'), findsOneWidget);
      expect(
        find.text('Price is what you pay; value is what you get.'),
        findsOneWidget,
      );
      expect(find.textContaining('An idea from someone else.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('only verified or exact quotations are quoted; other ideas '
        'name their provenance (R3-M4)', (tester) async {
      await _mountMentor(tester, repo: _Repo(timeline));

      // A generated insight is plain text, labelled as such.
      expect(
        find.text('“Price is what you pay; value is what you get.”'),
        findsNothing,
      );
      expect(
        find.text('Price is what you pay; value is what you get.'),
        findsOneWidget,
      );
      expect(find.text('Generated insight'), findsOneWidget);
      // A verified quotation keeps its quotation marks and says so.
      expect(find.text('“Rule No. 1 is never lose money.”'), findsOneWidget);
      expect(find.text('Verified quotation'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no entry at the user’s age highlights nothing', (
      tester,
    ) async {
      await _mountMentor(tester, repo: _Repo(timeline), age: 40);

      for (var i = 0; i < timeline.length; i++) {
        expect(_ageColor(tester, i), AppColors.nink3);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}
