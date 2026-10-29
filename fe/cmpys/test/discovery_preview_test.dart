import 'dart:async';

import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/discovery_step.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/idol_preview_step.dart';
import 'package:cmpys/features/cmpys/presentation/onboarding/onboarding_flow.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// CMPYS v3 mentor discovery and preview (`v3/onboard2.jsx` Discovery +
// MentorPreview, `v3/core.jsx` Expand): a search field, a "Best match"
// portrait card, an "Also relevant" list, the no-results "Prepare profile"
// card (POST /idols/import) and the clip-path expand into a preview with the
// documented timeline.

class _Repo extends Fake implements SessionRepository {
  List<IdolSuggestion> suggestions = [
    IdolSuggestion.fromJson({
      'name': 'John D. Rockefeller',
      'era': '1839–1937',
      'relevance_summary': 'Known for meticulous bookkeeping and cost control.',
      'domains': ['business', 'operations'],
      'confidence': 0.95,
    }),
    IdolSuggestion.fromJson({
      'name': 'Warren Buffett',
      'era': 'b. 1930',
      'relevance_summary': 'His method is learnable.',
      'domains': ['investing'],
      'confidence': 0.8,
    }),
  ];
  List<Map<String, dynamic>> discovered = [];
  final queries = <String>[];

  final imported = <String>[];
  Completer<IdolImportResult>? importGate;
  final importErrors = <Object>[];
  IdolImportResult importResult = const IdolImportResult(
    idolId: 'idol-1',
    jobId: 'job-1',
    status: 'queued',
  );

  List<IdolTimelineEntry> timeline = const [];
  Object? timelineError;
  final timelineCalls = <String>[];

  @override
  Future<List<IdolSuggestion>> suggestIdols(String id) async => suggestions;

  @override
  Future<List<Map<String, dynamic>>> discoverMentors(String query) async {
    queries.add(query);
    return discovered;
  }

  @override
  Future<IdolImportResult> importIdol(String name) async {
    imported.add(name);
    if (importErrors.isNotEmpty) throw importErrors.removeAt(0);
    final gate = importGate;
    return gate == null ? importResult : gate.future;
  }

  @override
  Future<List<IdolTimelineEntry>> idolTimeline(String idolName) async {
    timelineCalls.add(idolName);
    final error = timelineError;
    if (error != null) throw error;
    return timeline;
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Repo repo, {
  Widget? child,
  ValueChanged<CmpysIdol>? onPick,
  int age = 24,
  Set<String> interests = const {'Investing', 'Business', 'Writing'},
  // Tall, because the test font is much wider than the real ones and wraps
  // the display titles onto many lines.
  Size size = const Size(390, 1800),
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body:
              child ??
              CmpysDiscoveryStep(
                age: age,
                interests: interests,
                existingSessionId: 'session',
                onPick: onPick ?? (_) {},
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpAndSettle();
}

Finder _prepareButton() => find.widgetWithText(V3Button, 'Prepare profile');

Color? _dotColor(WidgetTester tester, int index) {
  final dot = tester.widget<Container>(
    find.byKey(ValueKey('timeline-dot-$index')),
  );
  return (dot.decoration as BoxDecoration).color;
}

Color? _ageColor(WidgetTester tester, int index) => tester
    .widget<Text>(find.byKey(ValueKey('timeline-age-$index')))
    .style
    ?.color;

void main() {
  group('discovery', () {
    testWidgets('lays out the kicker, title, search, best match and list', (
      tester,
    ) async {
      final repo = _Repo();
      await _mount(tester, repo);

      expect(find.text('MENTOR DISCOVERY'), findsOneWidget);
      expect(find.text('Who would you'), findsOneWidget);
      expect(find.text('like to learn from?'), findsOneWidget);
      expect(
        find.text('Suggested from Investing and Business.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search people or fields'), findsOneWidget);

      // The top suggestion is the 330 pt "Best match" portrait card.
      expect(find.text('Best match'), findsOneWidget);
      expect(tester.getSize(find.byType(V3Portrait)).height, 330);
      expect(find.text('John D. Rockefeller'), findsOneWidget);
      expect(find.text('Preview mentor'), findsOneWidget);

      // The rest sit under "ALSO RELEVANT" with 56 pt grey avatars.
      expect(find.text('ALSO RELEVANT'), findsOneWidget);
      final avatar = tester.widget<V3Avatar>(find.byType(V3Avatar));
      expect(avatar.size, 56);
      expect(avatar.gray, isTrue);
      expect(tester.getSize(find.byType(V3Tag)).height, 24);
      expect(find.text('Warren Buffett'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('falls back to "your interests" without any', (tester) async {
      await _mount(tester, _Repo(), interests: const {});
      expect(find.text('Suggested from your interests.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('empty_search_shows_prepare_profile', (tester) async {
      final repo = _Repo();
      await _mount(tester, repo);

      await _search(tester, 'Zed Nobody');

      expect(repo.queries, ['Zed Nobody']);
      expect(
        find.text('“Zed Nobody” isn’t in the library yet'),
        findsOneWidget,
      );
      expect(
        find.text(
          'We can research this person and prepare a profile from documented sources.',
        ),
        findsOneWidget,
      );
      expect(_prepareButton(), findsOneWidget);
      // No portrait or list while nothing matches.
      expect(find.byType(V3Portrait), findsNothing);
      expect(find.text('ALSO RELEVANT'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed search does not offer to prepare a profile', (
      tester,
    ) async {
      await _mount(tester, _FailingSearchRepo());

      await _search(tester, 'Zed Nobody');

      expect(
        find.text('Search could not finish. Try the name again.'),
        findsOneWidget,
      );
      expect(_prepareButton(), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('prepare profile researches, then queues the profile', (
      tester,
    ) async {
      final repo = _Repo()..importGate = Completer<IdolImportResult>();
      await _mount(tester, repo);
      await _search(tester, 'Zed Nobody');

      await tester.tap(_prepareButton());
      await tester.pump(const Duration(milliseconds: 500));

      // The request runs: iris bar, design copy, no fabricated percentage.
      expect(repo.imported, ['Zed Nobody']);
      expect(find.text('Researching Zed Nobody'), findsOneWidget);
      expect(
        find.text('Finding sources · checking timeline · drafting domains'),
        findsOneWidget,
      );
      final bar = tester.widget<V3Bar>(find.byType(V3Bar));
      expect(bar.color, AppColors.iris);
      expect(bar.value, lessThan(1));
      expect(_prepareButton(), findsNothing);

      // The bar only eases while the request runs; it never claims to be done.
      await tester.pump(const Duration(seconds: 8));
      final later = tester.widget<V3Bar>(find.byType(V3Bar)).value;
      expect(later, greaterThan(bar.value));
      expect(later, lessThan(0.9));

      repo.importGate!.complete(repo.importResult);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Queued for review'), findsOneWidget);
      expect(
        find.text(
          'Profiles are checked before publishing. Pick a suggested mentor to continue now.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<V3Bar>(find.byType(V3Bar)).value, 1);
      expect(find.text('Researching Zed Nobody'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a published import joins the list for preview', (
      tester,
    ) async {
      final repo = _Repo()
        ..importResult = const IdolImportResult(
          idolId: 'idol-9',
          jobId: 'job-9',
          status: 'published',
        );
      await _mount(tester, repo);
      await _search(tester, 'Zed Nobody');

      await tester.tap(_prepareButton());
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Queued for review'), findsNothing);
      expect(find.text('“Zed Nobody” isn’t in the library yet'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(V3Portrait),
          matching: find.text('Zed Nobody'),
        ),
        findsOneWidget,
      );
      expect(find.text('Best match'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed import says so honestly and can be retried '
        '(R1-I6)', (tester) async {
      final repo = _Repo()
        ..importResult = const IdolImportResult(
          idolId: 'idol-9',
          jobId: 'job-9',
          status: 'failed',
        );
      await _mount(tester, repo);
      await _search(tester, 'Zed Nobody');
      await tester.tap(_prepareButton());
      await tester.pump();
      await tester.pumpAndSettle();

      // Never "queued": the profile wasn't prepared.
      expect(find.text('Queued for review'), findsNothing);
      expect(
        find.text('Couldn’t prepare this profile. Try again later.'),
        findsOneWidget,
      );
      expect(find.text('“Zed Nobody” isn’t in the library yet'), findsOne);

      // Retyping the name doesn't show it as queued either.
      await _search(tester, 'Someone Else');
      await _search(tester, 'Zed Nobody');
      expect(find.text('Queued for review'), findsNothing);

      // The learner can try again; a later answer reads as before.
      repo.importResult = const IdolImportResult(
        idolId: 'idol-9',
        jobId: 'job-10',
        status: 'queued',
      );
      await tester.tap(_prepareButton());
      await tester.pump();
      await tester.pumpAndSettle();
      expect(repo.imported, ['Zed Nobody', 'Zed Nobody']);
      expect(find.text('Queued for review'), findsOneWidget);
      expect(find.textContaining('Try again later'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('other import statuses keep the queued copy', (tester) async {
      for (final status in ['completed', 'running', 'pending']) {
        final repo = _Repo()
          ..importResult = IdolImportResult(
            idolId: 'idol-9',
            jobId: 'job-9',
            status: status,
          );
        await _mount(tester, repo);
        await _search(tester, 'Zed Nobody');
        await tester.tap(_prepareButton());
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Queued for review'), findsOneWidget, reason: status);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('an import error shows a short inline message and can retry', (
      tester,
    ) async {
      final repo = _Repo()
        ..importErrors.addAll([
          const NetworkError(),
          const ApiError(message: 'Too many requests', statusCode: 429),
          const ApiError(message: 'Name is required', statusCode: 400),
        ]);
      await _mount(tester, repo);
      await _search(tester, 'Zed Nobody');

      Future<void> prepare() async {
        await tester.tap(_prepareButton());
        await tester.pump();
        await tester.pumpAndSettle();
      }

      await prepare();
      expect(
        find.text(
          'Couldn’t reach the library. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      // The card is back to its offer, so the user can retry.
      expect(
        find.text('“Zed Nobody” isn’t in the library yet'),
        findsOneWidget,
      );
      expect(find.text('Researching Zed Nobody'), findsNothing);

      await prepare();
      expect(
        find.text(
          'You’ve prepared today’s limit of new profiles. Pick a prepared '
          'mentor or try again tomorrow.',
        ),
        findsOneWidget,
      );

      await prepare();
      expect(
        find.text(
          'We couldn’t prepare that profile. Check the name and try again.',
        ),
        findsOneWidget,
      );

      await prepare();
      expect(find.text('Queued for review'), findsOneWidget);
      expect(find.textContaining('Check the name'), findsNothing);
      expect(repo.imported, [
        'Zed Nobody',
        'Zed Nobody',
        'Zed Nobody',
        'Zed Nobody',
      ]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('editing the search resets a finished import card', (
      tester,
    ) async {
      final repo = _Repo();
      await _mount(tester, repo);
      await _search(tester, 'Zed Nobody');
      await tester.tap(_prepareButton());
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Queued for review'), findsOneWidget);

      await _search(tester, 'Zed Nobodyy');

      expect(find.text('Queued for review'), findsNothing);
      expect(
        find.text('“Zed Nobodyy” isn’t in the library yet'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('retyping a queued name never queues it again', (tester) async {
      final repo = _Repo();
      await _mount(tester, repo);
      await _search(tester, 'Zed Nobody');
      await tester.tap(_prepareButton());
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Queued for review'), findsOneWidget);

      await _search(tester, 'Someone Else');
      expect(_prepareButton(), findsOneWidget);

      // The same name again, typed differently: already queued on this
      // screen, so no second paid research job.
      await _search(tester, '  zed   NOBODY ');
      expect(find.text('Queued for review'), findsOneWidget);
      expect(_prepareButton(), findsNothing);
      expect(repo.imported, ['Zed Nobody']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a name still being researched is not requested twice', (
      tester,
    ) async {
      final repo = _Repo()..importGate = Completer<IdolImportResult>();
      await _mount(tester, repo);
      await _search(tester, 'Zed Nobody');
      await tester.tap(_prepareButton());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Researching Zed Nobody'), findsOneWidget);

      // Away and back while the first request is still running.
      await _search(tester, 'Someone Else');
      await tester.enterText(find.byType(TextField), 'Zed Nobody');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      await tester.tap(_prepareButton());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Researching Zed Nobody'), findsOneWidget);
      expect(repo.imported, ['Zed Nobody']);

      repo.importGate!.complete(repo.importResult);
      await tester.pumpAndSettle();
      expect(find.text('Queued for review'), findsOneWidget);
      expect(repo.imported, ['Zed Nobody']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'an import answer that lands after the query changed is ignored',
      (tester) async {
        final repo = _Repo()..importGate = Completer<IdolImportResult>();
        await _mount(tester, repo);
        await _search(tester, 'Zed Nobody');
        await tester.tap(_prepareButton());
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Researching Zed Nobody'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Someone Else');
        await tester.pump(const Duration(milliseconds: 450));
        repo.importGate!.complete(repo.importResult);
        await tester.pumpAndSettle();

        expect(find.text('Queued for review'), findsNothing);
        expect(
          find.text('“Someone Else” isn’t in the library yet'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('reduced motion opens the preview with a fade', (tester) async {
      await _mount(tester, _Repo(), reduceMotion: true);

      await tester.tap(find.text('John D. Rockefeller'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(V3ExpandRoute.clipKey), findsNothing);
      expect(find.byKey(V3ExpandRoute.fadeKey), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Begin intake with Rockefeller'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tapping a mentor expands the preview; Begin intake picks', (
      tester,
    ) async {
      final repo = _Repo()
        ..timeline = const [IdolTimelineEntry(age: 24, text: 'Joins a firm.')];
      CmpysIdol? picked;
      await _mount(tester, repo, onPick: (idol) => picked = idol);

      await tester.tap(find.text('John D. Rockefeller'));
      await tester.pump();
      await tester.pump();
      // The route is clipped to the tapped card, then grows to full screen.
      expect(find.byKey(V3ExpandRoute.clipKey), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.text('AI interpretation · not Rockefeller'), findsOneWidget);
      expect(find.text('Begin intake with Rockefeller'), findsOneWidget);
      expect(picked, isNull);
      expect(repo.timelineCalls, ['John D. Rockefeller']);

      await tester.tap(find.text('Begin intake with Rockefeller'));
      await tester.pumpAndSettle();
      expect(picked?.name, 'John D. Rockefeller');
      // The preview is gone, back on discovery.
      expect(find.text('Begin intake with Rockefeller'), findsNothing);
      expect(find.text('MENTOR DISCOVERY'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('closing the preview returns to discovery without a pick', (
      tester,
    ) async {
      CmpysIdol? picked;
      await _mount(tester, _Repo(), onPick: (idol) => picked = idol);

      await tester.tap(find.text('Warren Buffett'));
      await tester.pumpAndSettle();
      expect(find.text('Begin intake with Buffett'), findsOneWidget);

      await tester.tap(find.byType(V3IconButton));
      await tester.pumpAndSettle();

      expect(picked, isNull);
      expect(find.text('Begin intake with Buffett'), findsNothing);
      expect(find.text('MENTOR DISCOVERY'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('in the onboarding flow', () {
    testWidgets(
      'the preview opens over discovery, and Begin intake starts it',
      (tester) async {
        final repo = _FlowRepo()
          ..timeline = const [
            IdolTimelineEntry(age: 20, text: 'Studies law.'),
            IdolTimelineEntry(age: 31, text: 'Builds a trust.'),
          ];
        tester.view.physicalSize = const Size(390, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionRepositoryProvider.overrideWithValue(repo),
              currentUserProvider.overrideWithValue(null),
            ],
            child: const MaterialApp(home: CmpysOnboardingFlow()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('MENTOR DISCOVERY'), findsOneWidget);

        await tester.tap(find.text('John D. Rockefeller'));
        await tester.pumpAndSettle();
        // The age on the saved session (31) is the highlighted node.
        expect(_dotColor(tester, 1), AppColors.ember);
        expect(_dotColor(tester, 0), AppColors.night3);

        await tester.tap(find.text('Begin intake with Rockefeller'));
        await tester.pumpAndSettle();

        // The mentor goes to select-idol, and neither screen is left over.
        expect(repo.selected, 'John D. Rockefeller');
        expect(find.text('MENTOR DISCOVERY'), findsNothing);
        expect(find.text('Begin intake with Rockefeller'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('preview', () {
    final buffett = cmpysIdols.firstWhere((i) => i.id == 'buffett');
    const timeline = [
      IdolTimelineEntry(age: 11, text: 'Buys his first stock.'),
      IdolTimelineEntry(age: 19, text: 'Reads The Intelligent Investor.'),
      IdolTimelineEntry(age: 24, text: 'Joins Graham-Newman as an analyst.'),
      IdolTimelineEntry(age: 26, text: 'Starts Buffett Partnership.'),
    ];

    Widget previewOf({
      required CmpysIdol idol,
      int age = 24,
      ValueChanged<CmpysIdol>? onChoose,
      VoidCallback? onBack,
    }) => CmpysIdolPreviewStep(
      idol: idol,
      age: age,
      onBack: onBack ?? () {},
      onChoose: onChoose ?? (_) {},
    );

    testWidgets('preview_shows_timeline_and_cta', (tester) async {
      final repo = _Repo()..timeline = timeline;
      CmpysIdol? chosen;
      await _mount(
        tester,
        repo,
        child: previewOf(idol: buffett, onChoose: (i) => chosen = i),
      );

      expect(find.text('AI interpretation · not Buffett'), findsOneWidget);
      expect(find.text('Warren Buffett'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Warren Buffett')).style?.fontSize,
        52,
      );
      expect(find.text('Wealth · b. 1930'), findsOneWidget);
      expect(find.text(buffett.blurb), findsOneWidget);
      expect(tester.widget<Text>(find.text(buffett.blurb)).style?.fontSize, 17);
      for (final domain in buffett.pillars) {
        expect(find.text(domain), findsOneWidget);
        // Domain tags are the design's larger 30 pt pills.
        final tag = find.ancestor(
          of: find.text(domain),
          matching: find.byType(V3Tag),
        );
        expect(tester.getSize(tag).height, 30);
      }

      // Documented timeline from the API, in order.
      expect(find.text('DOCUMENTED TIMELINE'), findsOneWidget);
      expect(repo.timelineCalls, ['Warren Buffett']);
      for (final e in timeline) {
        expect(find.text('Age ${e.age}'), findsOneWidget);
        expect(find.text(e.text), findsOneWidget);
      }

      // The node for the user's age (24) is the only ember one.
      expect(_dotColor(tester, 2), AppColors.ember);
      for (final other in [0, 1, 3]) {
        expect(_dotColor(tester, other), AppColors.night3);
      }
      expect(_ageColor(tester, 2), isNot(AppColors.nink3));
      expect(_ageColor(tester, 0), AppColors.nink3);

      final cta = find.widgetWithText(V3Button, 'Begin intake with Buffett');
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      expect(chosen?.id, 'buffett');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the highlighted node follows the real age, not 24', (
      tester,
    ) async {
      final repo = _Repo()..timeline = timeline;
      await _mount(tester, repo, child: previewOf(idol: buffett, age: 26));

      expect(_dotColor(tester, 3), AppColors.ember);
      expect(_dotColor(tester, 2), AppColors.night3);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('without an event at the age, no node is highlighted', (
      tester,
    ) async {
      final repo = _Repo()..timeline = timeline;
      await _mount(tester, repo, child: previewOf(idol: buffett, age: 40));

      for (var i = 0; i < timeline.length; i++) {
        expect(_dotColor(tester, i), AppColors.night3);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an idol without a documented timeline says so', (
      tester,
    ) async {
      await _mount(tester, _Repo(), child: previewOf(idol: buffett));

      expect(find.text('DOCUMENTED TIMELINE'), findsOneWidget);
      expect(find.text('No documented timeline yet.'), findsOneWidget);
      // Choosing never waits on the timeline.
      expect(find.text('Begin intake with Buffett'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a timeline error is inline and retryable', (tester) async {
      final repo = _Repo()..timelineError = const NetworkError();
      await _mount(tester, repo, child: previewOf(idol: buffett));

      expect(find.text('Couldn’t load the timeline.'), findsOneWidget);
      expect(find.text('Begin intake with Buffett'), findsOneWidget);

      repo
        ..timelineError = null
        ..timeline = timeline;
      await tester.tap(find.widgetWithText(V3Button, 'Try again'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Couldn’t load the timeline.'), findsNothing);
      expect(find.text('Age 24'), findsOneWidget);
      expect(repo.timelineCalls, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the hero uses the API image and falls back to initials', (
      tester,
    ) async {
      final withUrl = buffett.withSuggestionIdentity(
        imageUrl: 'https://example.com/wb.jpg',
      );
      await _mount(tester, _Repo(), child: previewOf(idol: withUrl));
      final portrait = tester.widget<V3Portrait>(find.byType(V3Portrait));
      expect(portrait.image, isA<NetworkImage>());
      expect(
        (portrait.image as NetworkImage).url,
        'https://example.com/wb.jpg',
      );
      expect(tester.getSize(find.byType(V3Portrait)).height, 470);
      await tester.pumpWidget(const SizedBox());

      // A seeded mentor without an API image keeps their bundled portrait.
      await _mount(tester, _Repo(), child: previewOf(idol: buffett));
      expect(
        tester.widget<V3Portrait>(find.byType(V3Portrait)).image,
        isA<AssetImage>(),
      );
      await tester.pumpWidget(const SizedBox());

      final llm = cmpysIdolFromSuggestion(
        name: 'Zed Nobody',
        era: '',
        summary: 'Someone.',
        domains: const ['writing'],
      );
      await _mount(tester, _Repo(), child: previewOf(idol: llm));
      expect(tester.widget<V3Portrait>(find.byType(V3Portrait)).image, isNull);
      // No era: the field stands alone, without the `—` placeholder. (The
      // same word is also the one domain tag.)
      expect(find.text('Writing'), findsNWidgets(2));
      expect(find.textContaining('—'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// A saved session that is waiting for a mentor, so the flow resumes on
/// discovery.
class _FlowRepo extends _Repo {
  String? selected;

  static const _session = Session(
    id: 'saved',
    phase: SessionPhase.idolSelection,
    userAge: 31,
    userFinancialStatus: '',
    userInterests: ['Investing'],
  );

  @override
  Future<Session?> getLatestSession() async => _session;

  @override
  Future<Session> getSession(String sessionId) async => _session;

  @override
  Future<Session> selectIdol(
    String sessionId,
    SelectIdolRequest request,
  ) async {
    selected = request.idolName;
    throw StateError('stop here');
  }
}

class _FailingSearchRepo extends _Repo {
  @override
  Future<List<Map<String, dynamic>>> discoverMentors(String query) async {
    throw const NetworkError();
  }
}
