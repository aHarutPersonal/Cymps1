import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/material_video_screen.dart';
import 'package:cmpys/features/plan/presentation/material_web_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'support/fake_web_platforms.dart';

// E4 (`v3/library.jsx` WebViewer and VideoViewer): the URL pill with a lock,
// the load hairline, the access banner, the bottom toolbar, and the night
// video page with the 16:9 player and the "Why it’s here" card.
//
// The web viewer runs its real WebViewController and NavigationDelegate on a
// fake WebViewPlatform, so these tests fire the platform's own callbacks.
// The YouTube player starts a ready-timeout timer that never resolves in a
// test, so the video screen keeps its player stand-in.

late FakeWebViewPlatform _web;
late FakeUrlLauncher _launcher;

const _page = ColoredBox(
  key: ValueKey('test-page'),
  color: Colors.white,
  child: SizedBox.expand(),
);

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump();
}

Finder _banner() => find.byKey(MaterialWebScreen.bannerKey);
Finder _pill() => find.byKey(MaterialWebScreen.urlPillKey);
Finder _toolbar() => find.byKey(MaterialWebScreen.toolbarKey);

Color? _bannerColor(WidgetTester tester) =>
    tester.widget<Container>(_banner()).color;

/// The pill's lock icon, or null when it shows none.
V3Icons? _pillLock(WidgetTester tester) {
  final icons = find.descendant(of: _pill(), matching: find.byType(V3Icon));
  if (icons.evaluate().isEmpty) return null;
  return tester.widget<V3Icon>(icons).icon;
}

Finder _hairline() => find.byKey(MaterialWebScreen.progressKey);

double _hairlineOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(of: _hairline(), matching: find.byType(AnimatedOpacity)),
    )
    .opacity;

AnimatedFractionallySizedBox _hairlineBox(WidgetTester tester) =>
    tester.widget<AnimatedFractionallySizedBox>(
      find.ancestor(
        of: _hairline(),
        matching: find.byType(AnimatedFractionallySizedBox),
      ),
    );

Future<void> _tapTool(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: _toolbar(), matching: find.bySemanticsLabel(label)),
  );
  await tester.pump();
}

PlanMaterialDetail _video({String? reason}) => PlanMaterialDetail.fromJson({
  'type': 'video',
  'title': 'How compounding works',
  'author_or_creator': 'Khan Academy',
  'url': 'https://www.youtube.com/watch?v=abc123',
  'reason': ?reason,
});

void main() {
  late UrlLauncherPlatform previousLauncher;

  setUp(() {
    _web = useFakeWebViewPlatform();
    previousLauncher = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = _launcher = FakeUrlLauncher();
  });

  tearDown(() => UrlLauncherPlatform.instance = previousLauncher);

  group('Web viewer banner', () {
    testWidgets('excerpt_banner_copy', (tester) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Self-Editing for Fiction Writers',
          url:
              'https://www.editorialdepartment.com/self-editing-for-fiction-writers/',
          sourceDescription:
              'Chapter 12 excerpt on the coauthor’s website. Full book not included.',
          initialSectionTitle: 'Excerpt from Chapter 12',
          access: AccessType.excerpt,
          openedFrom: 'Mission · Learn to self-edit',
        ),
      );

      expect(
        find.descendant(
          of: _banner(),
          matching: find.text(
            'Chapter 12 excerpt on the coauthor’s website. Full book not included.',
          ),
        ),
        findsOneWidget,
      );
      expect(_bannerColor(tester), accessCopy(AccessType.excerpt).background);
      final icon = tester.widget<V3Icon>(
        find.descendant(of: _banner(), matching: find.byType(V3Icon)),
      );
      expect(icon.icon, V3Icons.file);
      // A book source states its scope, not where it was opened from.
      expect(find.textContaining('Opened from'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an excerpt with no description uses the ACCESS note', (
      tester,
    ) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Into the Woods',
          url:
              'https://www.johnyorkestory.com/2017/01/into-the-woods-preface-to-the-us-edition/',
          access: AccessType.excerpt,
        ),
      );
      expect(
        find.descendant(
          of: _banner(),
          matching: find.text(
            'A verified excerpt. The full book is not included.',
          ),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('without access, a Gutenberg source falls back to original', (
      tester,
    ) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Meditations',
          url: '  https://www.gutenberg.org/ebooks/2680  ',
          sourceDescription: 'Full public-domain text from Project Gutenberg.',
        ),
      );
      expect(
        find.descendant(
          of: _banner(),
          matching: find.text(
            'Full public-domain text from Project Gutenberg.',
          ),
        ),
        findsOneWidget,
      );
      expect(_bannerColor(tester), accessCopy(AccessType.original).background);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a web page says where it was opened from, with a link icon', (
      tester,
    ) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
          openedFrom: 'Mission · Find what the business really earns',
        ),
      );
      expect(
        find.descendant(
          of: _banner(),
          matching: find.text(
            'Opened from Mission · Find what the business really earns',
          ),
        ),
        findsOneWidget,
      );
      expect(_bannerColor(tester), AppColors.paper);
      expect(
        tester
            .widget<V3Icon>(
              find.descendant(of: _banner(), matching: find.byType(V3Icon)),
            )
            .icon,
        V3Icons.link,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a web page opened from nowhere in particular has no banner', (
      tester,
    ) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      expect(_banner(), findsNothing);
      expect(find.text(accessCopy(AccessType.web).note), findsNothing);
      expect(find.byKey(const ValueKey('fake-web-view')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Web viewer URL pill', () {
    testWidgets('the pill shows the verified link’s host behind a padlock', (
      tester,
    ) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://www.fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      expect(_web.controller.loaded.single.host, 'www.fs.blog');
      expect(
        find.descendant(of: _pill(), matching: find.text('fs.blog')),
        findsOneWidget,
      );
      expect(_pillLock(tester), V3Icons.lock);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);
      expect(find.bySemanticsLabel('Reload'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('navigating to another host updates the pill; http shows no '
        'padlock', (tester) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );

      _web.controller.navigate('http://example.org/next');
      await tester.pump();
      expect(
        find.descendant(of: _pill(), matching: find.text('example.org')),
        findsOneWidget,
      );
      expect(find.text('fs.blog'), findsNothing);
      expect(_pillLock(tester), isNull);

      _web.controller.navigate('https://www.berkshirehathaway.com/letters');
      await tester.pump();
      expect(
        find.descendant(
          of: _pill(),
          matching: find.text('berkshirehathaway.com'),
        ),
        findsOneWidget,
      );
      expect(_pillLock(tester), V3Icons.lock);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a link that is not verified keeps the error state, with no '
        'lock and no Reload', (tester) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Unsafe',
          url: 'https://localhost/x',
          access: AccessType.web,
        ),
      );
      expect(
        find.text('This resource does not have a verified direct link.'),
        findsOneWidget,
      );
      expect(_web.controllers, isEmpty);
      expect(_pillLock(tester), isNull);
      expect(find.bySemanticsLabel('Reload'), findsNothing);
      expect(_toolbar(), findsNothing);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Web viewer failed navigation', () {
    testWidgets('an empty URL from page started keeps the pill', (
      tester,
    ) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      _web.controller.delegate!.onPageStarted!('');
      await tester.pump();
      expect(
        find.descendant(of: _pill(), matching: find.text('fs.blog')),
        findsOneWidget,
      );
      expect(_pillLock(tester), V3Icons.lock);
      // The start still restarts the hairline.
      expect(_hairlineOpacity(tester), 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed navigation after a loaded page finishes the bar, '
        'restores the pill and keeps paging', (tester) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      final controller = _web.controller;
      controller.navigate('https://fs.blog/owner-earnings/');
      await tester.pumpAndSettle();

      // iOS: page started, a main-frame error, and no page finished. The
      // web view stays on the loaded page.
      controller.failNavigation('https://unreachable.example/');
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: _pill(), matching: find.text('fs.blog')),
        findsOneWidget,
      );
      expect(find.text('unreachable.example'), findsNothing);
      expect(_hairlineOpacity(tester), 0);
      expect(_hairlineBox(tester).widthFactor, 1);
      expect(find.byKey(const ValueKey('fake-web-view')), findsOneWidget);
      await _tapTool(tester, 'Next page');
      await tester.pumpAndSettle();
      expect(controller.scrolls, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a first-load failure says so and recovers through Reload', (
      tester,
    ) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
          openedFrom: 'Mission · Find what the business really earns',
        ),
      );
      final controller = _web.controller;
      expect(controller.loaded, hasLength(1));
      controller.url = null;
      controller.failNavigation('https://fs.blog/owner-earnings/');
      await tester.pumpAndSettle();

      // Its own copy: the link is verified, the page just did not load.
      expect(find.text('Couldn’t load this page.'), findsOneWidget);
      expect(
        find.text('This resource does not have a verified direct link.'),
        findsNothing,
      );
      expect(_banner(), findsNothing);
      expect(_hairlineOpacity(tester), 0);
      expect(_pillLock(tester), isNull);
      expect(
        find.descendant(of: _pill(), matching: find.text('fs.blog')),
        findsOneWidget,
      );

      // The cover absorbs taps, hides the page underneath from screen
      // readers, and announces itself.
      fakeWebViewTaps = 0;
      await tester.tap(find.text('Couldn’t load this page.'));
      await tester.pump();
      expect(fakeWebViewTaps, 0);
      expect(_pageCovered(tester), isTrue);
      expect(
        find.ancestor(
          of: find.text('Couldn’t load this page.'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );

      // Android follows the error with page finished; the failure stays.
      controller.delegate!.onPageFinished!('https://fs.blog/owner-earnings/');
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load this page.'), findsOneWidget);

      // "Open in browser" still works.
      await _tapTool(tester, 'Open in browser');
      await tester.pumpAndSettle();
      expect(_launcher.launched.single.url, 'https://fs.blog/owner-earnings/');
      expect(
        _launcher.launched.single.mode,
        PreferredLaunchMode.externalApplication,
      );

      // Reload requests the verified link again (nothing loaded to reload),
      // and the page shows once it finishes.
      await tester.tap(find.bySemanticsLabel('Reload'));
      await tester.pump();
      expect(controller.loaded, hasLength(2));
      expect(
        controller.loaded.last.toString(),
        'https://fs.blog/owner-earnings/',
      );
      expect(find.text('Couldn’t load this page.'), findsNothing);
      // A plain cover hides the platform's own error page until the new
      // page arrives.
      expect(find.byKey(const Key('web-retry-cover')), findsOneWidget);
      expect(_pageCovered(tester), isTrue);
      controller.navigate('https://fs.blog/owner-earnings/');
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load this page.'), findsNothing);
      expect(find.byKey(const Key('web-retry-cover')), findsNothing);
      expect(_pageCovered(tester), isFalse);
      expect(find.byKey(const ValueKey('fake-web-view')), findsOneWidget);
      expect(_banner(), findsOneWidget);
      expect(_pillLock(tester), V3Icons.lock);
      await _tapTool(tester, 'Next page');
      await tester.pumpAndSettle();
      expect(controller.scrolls, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the next page start after a failure clears it', (
      tester,
    ) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      final controller = _web.controller;
      controller.failNavigation('https://fs.blog/owner-earnings/');
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load this page.'), findsOneWidget);

      controller.delegate!.onPageStarted!('https://fs.blog/owner-earnings/');
      await tester.pump();
      expect(find.text('Couldn’t load this page.'), findsNothing);
      expect(_hairlineOpacity(tester), 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a cancelled navigation (-999) is not a failure', (
      tester,
    ) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      final delegate = _web.controller.delegate!;
      delegate.onProgress!(30);
      await tester.pumpAndSettle();
      // WebKit cancels a navigation that a newer one supersedes.
      delegate.onWebResourceError!(
        const WebResourceError(
          errorCode: -999,
          description: 'cancelled',
          isForMainFrame: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load this page.'), findsNothing);
      expect(_hairlineOpacity(tester), 1);
      expect(_hairlineBox(tester).widthFactor, closeTo(.3, .001));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a sub-frame error changes nothing', (tester) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      final delegate = _web.controller.delegate!;
      delegate.onProgress!(40);
      await tester.pumpAndSettle();
      delegate.onWebResourceError!(
        const WebResourceError(
          errorCode: 404,
          description: 'ad frame',
          isForMainFrame: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(_hairlineOpacity(tester), 1);
      expect(find.byKey(const ValueKey('fake-web-view')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Web viewer loading', () {
    testWidgets('in landscape the hairline runs edge to edge', (tester) async {
      await _pump(
        tester,
        const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(left: 44, right: 44),
          ),
          child: MaterialWebScreen(
            title: 'Owner earnings',
            url: 'https://fs.blog/owner-earnings/',
            access: AccessType.web,
          ),
        ),
      );
      _web.controller.delegate!.onProgress!(50);
      await tester.pumpAndSettle();
      final bar = tester.getRect(_hairline());
      expect(bar.left, 0);
      expect(bar.width, closeTo(195, .5));
      // The bar row itself clears the inset.
      expect(
        tester.getRect(find.bySemanticsLabel('Close')).left,
        greaterThan(44),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the ember hairline follows progress and fades at 100', (
      tester,
    ) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      final delegate = _web.controller.delegate!;
      expect(
        (tester.widget<Container>(_hairline()).decoration as BoxDecoration)
            .color,
        AppColors.ember,
      );
      expect(_hairlineOpacity(tester), 1);

      delegate.onProgress!(40);
      await tester.pumpAndSettle();
      expect(_hairlineBox(tester).widthFactor, closeTo(.4, .001));
      expect(_hairlineOpacity(tester), 1);

      delegate.onProgress!(100);
      await tester.pumpAndSettle();
      expect(_hairlineOpacity(tester), 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a new page restarts the hairline without sweeping back', (
      tester,
    ) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      final delegate = _web.controller.delegate!;
      delegate.onProgress!(100);
      await tester.pumpAndSettle();

      delegate.onPageStarted!('https://fs.blog/next/');
      await tester.pump();
      final box = _hairlineBox(tester);
      expect(box.widthFactor, 0);
      expect(box.duration, Duration.zero);
      expect(_hairlineOpacity(tester), 1);

      // Forward progress sweeps again.
      delegate.onProgress!(30);
      await tester.pump();
      expect(_hairlineBox(tester).duration, const Duration(milliseconds: 250));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Reload does not strand the hairline at 0: page finished '
        'completes it', (tester) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      final controller = _web.controller;
      controller.navigate('https://fs.blog/owner-earnings/');
      await tester.pumpAndSettle();
      expect(_hairlineOpacity(tester), 0);

      await tester.tap(find.bySemanticsLabel('Reload'));
      await tester.pump();
      expect(controller.reloadCalls, 1);

      // The reload fires page started and page finished, but no progress.
      controller.delegate!.onPageStarted!('https://fs.blog/owner-earnings/');
      await tester.pump();
      expect(_hairlineOpacity(tester), 1);
      controller.delegate!.onPageFinished!('https://fs.blog/owner-earnings/');
      await tester.pumpAndSettle();
      expect(_hairlineOpacity(tester), 0);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Web viewer toolbar', () {
    testWidgets('Back enables once the web view can go back', (tester) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      final controller = _web.controller;
      await _tapTool(tester, 'Back');
      expect(controller.goBackCalls, 0);

      controller.canGoBackValue = true;
      controller.navigate('https://fs.blog/next/');
      await tester.pumpAndSettle();
      await _tapTool(tester, 'Back');
      expect(controller.goBackCalls, 1);
      // Forward stays off until the web view says it can go forward.
      await _tapTool(tester, 'Forward');
      expect(controller.goForwardCalls, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('page turns wait for the page, then scroll it', (tester) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      final controller = _web.controller;
      await _tapTool(tester, 'Next page');
      expect(controller.scrolls, isEmpty);

      controller.navigate('https://fs.blog/owner-earnings/');
      await tester.pumpAndSettle();
      await _tapTool(tester, 'Next page');
      await tester.pumpAndSettle();
      await _tapTool(tester, 'Previous page');
      await tester.pumpAndSettle();
      expect(controller.scrolls, hasLength(2));
      expect(controller.scrolls.first, greaterThan(0));
      expect(controller.scrolls.last, -controller.scrolls.first);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"Open in browser" launches the verified current URL '
        'externally', (tester) async {
      await _pump(
        tester,
        const MaterialWebScreen(
          title: 'Owner earnings',
          url: 'https://fs.blog/owner-earnings/',
          access: AccessType.web,
        ),
      );
      final controller = _web.controller;
      controller.navigate('https://fs.blog/letters/2024/');
      await tester.pumpAndSettle();

      await _tapTool(tester, 'Open in browser');
      await tester.pumpAndSettle();
      expect(_launcher.launched, hasLength(1));
      expect(_launcher.launched.single.url, 'https://fs.blog/letters/2024/');
      expect(
        _launcher.launched.single.mode,
        PreferredLaunchMode.externalApplication,
      );

      // A page that fails verification falls back to the verified link.
      controller.url = 'https://localhost/admin';
      await _tapTool(tester, 'Open in browser');
      await tester.pumpAndSettle();
      expect(_launcher.launched.last.url, 'https://fs.blog/owner-earnings/');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Video viewer', () {
    testWidgets('a 16:9 player on night with the "Why it’s here" card', (
      tester,
    ) async {
      await _pump(
        tester,
        MaterialVideoScreen(
          material: _video(reason: 'It shows compounding on one chart.'),
          videoId: 'abc123',
          playerOverride: _page,
        ),
      );
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.night);
      final ratio = tester.widget<AspectRatio>(
        find.ancestor(
          of: find.byKey(const ValueKey('test-page')),
          matching: find.byType(AspectRatio),
        ),
      );
      expect(ratio.aspectRatio, 16 / 9);
      expect(find.text('Video'), findsWidgets);
      expect(find.byType(V3AccessBadge), findsOneWidget);
      expect(find.text('How compounding works'), findsOneWidget);
      expect(find.text('Khan Academy'), findsOneWidget);
      expect(find.text('Why it’s here'), findsOneWidget);
      expect(find.text('It shows compounding on one chart.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no reason hides the "Why it’s here" card', (tester) async {
      await _pump(
        tester,
        MaterialVideoScreen(
          material: _video(),
          videoId: 'abc123',
          playerOverride: _page,
        ),
      );
      expect(find.text('How compounding works'), findsOneWidget);
      expect(find.text('Why it’s here'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      await _pump(
        tester,
        MaterialVideoScreen(
          material: _video(reason: '   '),
          videoId: 'abc123',
          playerOverride: _page,
        ),
      );
      expect(find.text('Why it’s here'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// Whether the mounted page is cut off from pointers and screen readers.
bool _pageCovered(WidgetTester tester) {
  final page = find.byKey(const ValueKey('fake-web-view'));
  final ignore = tester.widget<IgnorePointer>(
    find.ancestor(of: page, matching: find.byType(IgnorePointer)).first,
  );
  final exclude = tester.widget<ExcludeSemantics>(
    find.ancestor(of: page, matching: find.byType(ExcludeSemantics)).first,
  );
  return ignore.ignoring && exclude.excluding;
}
