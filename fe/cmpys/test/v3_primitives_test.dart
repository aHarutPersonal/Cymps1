import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// CMPYS v3 primitives (`v3/core.jsx`). These pin the behaviour later screen
// tasks rely on: press/disabled handling, the Seg thumb, sheet drag-to-dismiss,
// the CheckDot burst, word-by-word streaming and the ACCESS copy.

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduced = false,
  bool center = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: app!,
      ),
      home: Scaffold(
        backgroundColor: AppColors.paper,
        body: center ? Center(child: child) : child,
      ),
    ),
  );
}

// A 1×1 transparent PNG, enough for image-backed primitives to build.
final Uint8List _pixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  // ── The six behaviours named in the task brief ──────────────────────────

  testWidgets('disabled_button_ignores_tap', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          V3Button(
            key: const ValueKey('disabled'),
            disabled: true,
            onPressed: () => taps++,
            child: const Text('Disabled'),
          ),
          V3Button(
            key: const ValueKey('loading'),
            loading: true,
            onPressed: () => taps++,
            child: const Text('Loading'),
          ),
          V3Button(
            key: const ValueKey('enabled'),
            onPressed: () => taps++,
            child: const Text('Enabled'),
          ),
        ],
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('disabled')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const ValueKey('loading')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(taps, 0);

    // Disabled reads as disabled and fades to the design's .38.
    expect(
      tester.getSemantics(find.byKey(const ValueKey('disabled'))),
      containsSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    final fade = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(const ValueKey('disabled')),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(fade.opacity, 0.38);
    // Loading swaps the label for the spinner.
    expect(find.text('Loading'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('loading')),
        matching: find.byType(V3Spinner),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('enabled')));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('seg_moves_thumb_on_change', (tester) async {
    var value = 'all';
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => SizedBox(
          width: 300,
          child: V3Seg<String>(
            items: const [
              V3SegItem('all', 'All'),
              V3SegItem('saved', 'Saved'),
              V3SegItem('done', 'Completed'),
            ],
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );

    final thumb = find.byKey(V3Seg.thumbKey);
    final before = tester.getRect(thumb);
    // Thumb is one third of the track minus the 4 px padding each side.
    expect(before.width, closeTo((300 - 8) / 3, 0.5));

    await tester.tap(find.text('Completed'));
    await tester.pump();
    expect(value, 'done');
    await tester.pump(const Duration(milliseconds: 120));
    final moving = tester.getRect(thumb);
    expect(moving.left, greaterThan(before.left));

    await tester.pumpAndSettle();
    final after = tester.getRect(thumb);
    expect(after.left - before.left, closeTo(2 * (300 - 8) / 3, 0.5));

    // Selected state reaches semantics.
    expect(
      tester.getSemantics(find.text('Completed')),
      containsSemantics(
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('All')),
      containsSemantics(
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );
  });

  testWidgets('sheet_dismisses_on_drag_over_90', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showV3Sheet<void>(
            context,
            title: 'Reading settings',
            builder: (_) => const Text('Sheet body'),
          ),
          child: const Text('Open'),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Sheet body'), findsOneWidget);
    expect(find.text('Reading settings'), findsOneWidget);
    // Title row carries a labelled close button.
    expect(find.bySemanticsLabel('Close'), findsOneWidget);

    // A short drag springs back.
    await tester.drag(find.byKey(V3Sheet.handleKey), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(find.text('Sheet body'), findsOneWidget);
    final rested = tester.getRect(find.byKey(V3Sheet.panelKey));

    // While dragging, the sheet follows the finger.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(V3Sheet.handleKey)),
    );
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(
      tester.getRect(find.byKey(V3Sheet.panelKey)).top,
      closeTo(rested.top + 40, 0.5),
    );
    // Past 90 px it dismisses on release.
    await gesture.moveBy(const Offset(0, 70));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Sheet body'), findsNothing);
  });

  testWidgets('checkdot_bursts_only_on_mark_done', (tester) async {
    var done = false;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => V3CheckDot(
          done: done,
          onPressed: () => setState(() => done = !done),
        ),
      ),
    );
    expect(find.byType(V3Burst), findsNothing);
    expect(find.bySemanticsLabel('Mark done'), findsOneWidget);

    await tester.tap(find.byType(V3CheckDot));
    await tester.pump();
    expect(done, isTrue);
    expect(find.byType(V3Burst), findsOneWidget);
    expect(find.bySemanticsLabel('Mark not done'), findsOneWidget);

    // The burst plays once (.6 s) and clears itself.
    await tester.pumpAndSettle();
    expect(find.byType(V3Burst), findsNothing);

    // Un-marking never bursts.
    await tester.tap(find.byType(V3CheckDot));
    await tester.pump();
    expect(done, isFalse);
    expect(find.byType(V3Burst), findsNothing);
    await tester.pumpAndSettle();

    // A dot that is already done when it first builds does not burst.
    await _pump(tester, const V3CheckDot(key: ValueKey('fresh'), done: true));
    await tester.pump();
    expect(find.byType(V3Burst), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('stream_reveals_text_then_calls_onDone', (tester) async {
    var doneCalls = 0;
    await _pump(
      tester,
      V3Stream(
        text: 'One two three four',
        speed: const Duration(milliseconds: 28),
        onDone: () => doneCalls++,
      ),
    );

    // Nothing yet, then two tokens (a word and its space) per tick.
    expect(find.textContaining('One'), findsNothing);
    await tester.pump(const Duration(milliseconds: 28));
    expect(find.textContaining('One'), findsOneWidget);
    expect(find.textContaining('two'), findsNothing);
    await tester.pump(const Duration(milliseconds: 28));
    expect(find.textContaining('One two'), findsOneWidget);
    expect(find.textContaining('three'), findsNothing);
    expect(doneCalls, 0);

    await tester.pump(const Duration(milliseconds: 28));
    await tester.pump(const Duration(milliseconds: 28));
    await tester.pump();
    expect(find.textContaining('One two three four'), findsOneWidget);
    expect(doneCalls, 1);

    // onDone fires once.
    await tester.pump(const Duration(seconds: 1));
    expect(doneCalls, 1);
  });

  testWidgets('access_badge_labels_match_design', (tester) async {
    // `ACCESS` in v3/core.jsx, verbatim (curly apostrophe included).
    const expected = <AccessType, (String, String?, String)>{
      AccessType.guide: (
        'Study guide',
        'Open guide',
        'A CMPYS-written guide to the book, not the author’s full text.',
      ),
      AccessType.original: (
        'Original · public domain',
        'Read original',
        'Full original text, verified source.',
      ),
      AccessType.excerpt: (
        'Excerpt only',
        'Read excerpt',
        'A verified excerpt. The full book is not included.',
      ),
      AccessType.web: (
        'Web source',
        'Open source',
        'Opens the verified page in the in-app viewer.',
      ),
      AccessType.video: ('Video', 'Watch', 'Plays in the in-app video viewer.'),
      AccessType.none: (
        'No readable edition',
        null,
        'Recommended reading. CMPYS has no readable edition of this title.',
      ),
    };
    expect(AccessType.values, hasLength(expected.length));

    for (final entry in expected.entries) {
      await _pump(tester, V3AccessBadge(type: entry.key));
      expect(find.text(entry.value.$1), findsOneWidget);
      final copy = accessCopy(entry.key);
      expect(copy.label, entry.value.$1);
      expect(copy.cta, entry.value.$2);
      expect(copy.note, entry.value.$3);
    }

    // Colours and icons follow the design's tag pairs.
    expect(accessCopy(AccessType.guide).color, AppColors.iris2);
    expect(accessCopy(AccessType.guide).background, AppColors.irisSoft);
    expect(accessCopy(AccessType.original).color, AppColors.sage2);
    expect(accessCopy(AccessType.excerpt).background, AppColors.goldSoft);
    expect(accessCopy(AccessType.video).color, AppColors.ember2);
    expect(accessCopy(AccessType.none).icon, V3Icons.lock);
    expect(accessCopy(AccessType.web).icon, V3Icons.external);
  });

  // ── Supporting behaviour ────────────────────────────────────────────────

  test('icon set covers every IP glyph plus play and pause', () {
    // 66 stroked paths in `IP` + the filled play/pause glyphs.
    expect(V3Icons.values, hasLength(68));
    for (final icon in V3Icons.values) {
      if (icon == V3Icons.play || icon == V3Icons.pause) {
        expect(icon.path, isNull);
      } else {
        expect(icon.path, isNotEmpty, reason: icon.name);
      }
    }
    expect(V3Icons.check.path, 'M20 6 9 17l-5-5');
    expect(V3Icons.fromName('arrowR'), V3Icons.arrowR);
    // Unknown names fall back to `info`, as `IP[n] || IP.info` does.
    expect(V3Icons.fromName('nope'), V3Icons.info);
    expect(V3Icons.fromName(null), V3Icons.info);

    final svg = V3Icon.svg(
      V3Icons.check,
      color: AppColors.ink,
      strokeWidth: 2.6,
    );
    expect(svg, contains('d="M20 6 9 17l-5-5"'));
    expect(svg, contains('stroke="#17151A"'));
    expect(svg, contains('stroke-width="2.6"'));
    expect(svg, contains('stroke-linecap="round"'));
    expect(svg, contains('stroke-linejoin="round"'));
    expect(svg, contains('fill="none"'));
    final filled = V3Icon.svg(
      V3Icons.flame,
      color: AppColors.ember,
      fill: AppColors.emberSoft,
    );
    expect(filled, contains('fill="#FFE4D3"'));
    final play = V3Icon.svg(V3Icons.play, color: Colors.white);
    expect(play, contains('fill="#FFFFFF"'));
    expect(play, isNot(contains('stroke=')));
  });

  testWidgets('icon buttons keep a 44 pt tap target and a label', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      V3IconButton(
        icon: V3Icons.x,
        size: 34,
        label: 'Close',
        onPressed: () => taps++,
      ),
    );
    final box = tester.getSize(find.byType(V3IconButton));
    expect(box.width, greaterThanOrEqualTo(44));
    expect(box.height, greaterThanOrEqualTo(44));
    // The visible disc stays at the design's 34.
    expect(
      tester.getSize(find.byKey(V3IconButton.discKey)),
      const Size(34, 34),
    );
    expect(find.bySemanticsLabel('Close'), findsOneWidget);

    // A tap just outside the 34 pt disc, inside the 44 pt target, counts.
    final center = tester.getCenter(find.byType(V3IconButton));
    await tester.tapAt(center + const Offset(20, 0));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('keyboard focus rings the pressable without remounting it', (
    tester,
  ) async {
    var mounts = 0;
    var taps = 0;
    await _pump(
      tester,
      V3Pressable(
        onTap: () => taps++,
        child: _MountProbe(onMount: () => mounts++),
      ),
    );
    expect(mounts, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final ring = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(V3Pressable),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((ring.decoration as BoxDecoration).border, isNotNull);
    expect(mounts, 1);
    // Enter activates it like a tap.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('chip exposes its selected state and draws the check', (
    tester,
  ) async {
    await _pump(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          V3Chip(on: true, onPressed: () {}, child: const Text('Mornings')),
          V3Chip(
            on: false,
            icon: V3Icons.clock,
            onPressed: () {},
            child: const Text('Evenings'),
          ),
        ],
      ),
    );
    expect(
      tester.getSemantics(find.text('Mornings')),
      containsSemantics(
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Evenings')),
      containsSemantics(
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );
    final icons = tester.widgetList<V3Icon>(find.byType(V3Icon)).toList();
    expect(icons.map((i) => i.icon), [V3Icons.check, V3Icons.clock]);
    expect(tester.getSize(find.byType(V3Chip).first).height, 44);
    await tester.pumpAndSettle();
  });

  testWidgets('bar animates from 0 to its value after its delay', (
    tester,
  ) async {
    await _pump(
      tester,
      const SizedBox(
        width: 200,
        child: V3Bar(value: 0.6, delay: Duration(milliseconds: 100)),
      ),
    );
    double factor() => tester
        .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .widthFactor!;
    expect(factor(), 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(factor(), 0); // 80 ms + delay not yet elapsed
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(factor(), allOf(greaterThan(0), lessThan(0.6)));
    await tester.pumpAndSettle();
    expect(factor(), closeTo(0.6, 1e-9));
  });

  testWidgets('count-up eases out to its target', (tester) async {
    await _pump(tester, const V3CountUp(to: 120));
    expect(find.text('0'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    final mid = int.parse(tester.widget<Text>(find.byType(Text)).data!);
    // Ease-out cubic: past the linear midpoint at half time.
    expect(mid, greaterThan(60));
    expect(mid, lessThan(120));
    await tester.pumpAndSettle();
    expect(find.text('120'), findsOneWidget);
  });

  testWidgets('reduced motion jumps primitives to their end state', (
    tester,
  ) async {
    var doneCalls = 0;
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          V3Stream(text: 'All at once', onDone: () => doneCalls++),
          const SizedBox(width: 200, child: V3Bar(value: 0.4)),
          const V3CountUp(to: 42),
          const SizedBox(width: 60, height: 60, child: V3Burst()),
        ],
      ),
      reduced: true,
    );
    await tester.pump();
    expect(find.textContaining('All at once'), findsOneWidget);
    expect(doneCalls, 1);
    expect(
      tester
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .widthFactor,
      0.4,
    );
    expect(find.text('42'), findsOneWidget);
    // A burst's end state is invisible, so nothing is painted.
    expect(
      find.descendant(
        of: find.byType(V3Burst),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('toast shows, replaces the current one and auto-hides', (
    tester,
  ) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => showV3Toast(context, 'Tutorial 2 is ready'),
              child: const Text('First'),
            ),
            TextButton(
              onPressed: () => showV3Toast(
                context,
                'Achievement saved',
                icon: V3Icons.trophy,
                tone: V3ToastTone.warn,
              ),
              child: const Text('Second'),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('First'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Tutorial 2 is ready'), findsOneWidget);
    // The root overlay has no Material text theme: no debug underline.
    final label = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(V3Toast.pillKey),
        matching: find.byType(RichText),
      ),
    );
    expect(label.text.style?.decoration, TextDecoration.none);
    // Top pill at 58 pt.
    expect(tester.getRect(find.byKey(V3Toast.pillKey)).top, closeTo(58, 0.5));

    await tester.tap(find.text('Second'));
    await tester.pump();
    expect(find.text('Tutorial 2 is ready'), findsNothing);
    expect(find.text('Achievement saved'), findsOneWidget);

    // 2.2 s after the latest toast it hides.
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('Achievement saved'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Achievement saved'), findsNothing);
  });

  // ── Fix round 1 ─────────────────────────────────────────────────────────

  testWidgets('two toasts in one frame leave exactly one pill', (tester) async {
    late BuildContext ctx;
    await _pump(
      tester,
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox();
        },
      ),
    );

    showV3Toast(ctx, 'First');
    showV3Toast(ctx, 'Second');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(V3Toast.pillKey), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);

    // Auto-hide, then a later single toast is still a single pill.
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pumpAndSettle();
    expect(find.byKey(V3Toast.pillKey), findsNothing);
    showV3Toast(ctx, 'Third');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(V3Toast.pillKey), findsOneWidget);
    // And it still hides on its own timer.
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pumpAndSettle();
    expect(find.byKey(V3Toast.pillKey), findsNothing);
  });

  testWidgets('a disposing old toast layer never cancels the new toast', (
    tester,
  ) async {
    late BuildContext ctx;
    // Reduced motion: the exit completes synchronously, so the old entry is
    // removed while its layer is still mounted for one more frame.
    await _pump(
      tester,
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox();
        },
      ),
      reduced: true,
    );
    showV3Toast(ctx, 'Old');
    await tester.pump();
    hideV3Toast(ctx);
    // Let the exit's completion callback remove the old entry (microtasks
    // only, no frame), so its layer is still mounted when the next toast
    // inserts a fresh entry.
    for (var i = 0; i < 5; i++) {
      await Future<void>.value();
    }
    showV3Toast(ctx, 'New');
    await tester.pump(); // the old layer disposes here
    await tester.pump();
    expect(find.text('New'), findsOneWidget);
    expect(find.byKey(V3Toast.pillKey), findsOneWidget);
    // The new toast's 2.2 s timer survived the old layer's dispose.
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pumpAndSettle();
    expect(find.text('New'), findsNothing);
  });

  testWidgets('section link has a 44 pt hit box and moves nothing', (
    tester,
  ) async {
    Widget sections({required bool action}) => SizedBox(
      width: 400,
      child: V3Section(
        title: 'Up next',
        action: action ? 'See all' : null,
        onAction: () {},
        child: const SizedBox(key: ValueKey('body'), height: 20),
      ),
    );
    await _pump(tester, sections(action: false), center: false);
    final plainTitle = tester.getRect(find.text('Up next'));

    await _pump(tester, sections(action: true), center: false);
    final linkBox = tester.getRect(
      find.ancestor(
        of: find.text('See all'),
        matching: find.byType(V3Pressable),
      ),
    );
    expect(linkBox.height, greaterThanOrEqualTo(44));
    // The title renders exactly where it does without a link (its box is
    // only narrower, as the link takes the end of the row).
    final linkedTitle = tester.getRect(find.text('Up next'));
    expect(linkedTitle.topLeft, plainTitle.topLeft);
    expect(linkedTitle.height, plainTitle.height);
    // The link's text shares the title's baseline row as before the lift.
    final linkText = tester.getRect(find.text('See all'));
    expect(linkText.top, greaterThan(plainTitle.top));
    expect(linkText.bottom, lessThanOrEqualTo(plainTitle.bottom + 0.01));
    // The hit box reaches from above the title to under the header.
    expect(linkBox.top, lessThan(plainTitle.top));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('body'))).dy,
      greaterThanOrEqualTo(linkBox.bottom - 0.01),
    );
    // Text sits on the title's baseline row, 30 pt section spacing kept.
    expect(plainTitle.top, closeTo(30, 0.01));
  });

  testWidgets('sheet with scrollable: false hosts a ListView body', (
    tester,
  ) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showV3Sheet<void>(
            context,
            title: 'Conversations',
            scrollable: false,
            noPad: true,
            builder: (_) => ListView.builder(
              itemCount: 100,
              itemBuilder: (_, i) =>
                  SizedBox(height: 40, child: Text('Row $i')),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Row 0'), findsOneWidget);
    expect(find.text('Row 99'), findsNothing);
    // Bounded by the 86% max height of the 600 pt test screen.
    expect(
      tester.getSize(find.byKey(V3Sheet.panelKey)).height,
      lessThanOrEqualTo(600 * 0.86 + 0.01),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsNothing);
  });

  testWidgets('stream defers onDone past build so it may setState', (
    tester,
  ) async {
    var text = 'a b';
    var doneCalls = 0;
    late StateSetter rebuild;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return V3Stream(
            text: text,
            speed: const Duration(milliseconds: 10),
            // Chat appends a message here: a parent setState.
            onDone: () => setState(() => doneCalls++),
          );
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    expect(doneCalls, 1);

    // A shorter text arrives in a rebuild: already complete, so the stream
    // finishes from didUpdateWidget, which runs during build.
    rebuild(() => text = 'a');
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(doneCalls, 2);
  });

  testWidgets('a vetoed drag-dismiss springs the sheet back', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showV3Sheet<void>(
            context,
            title: 'Leave practice?',
            builder: (_) =>
                const PopScope(canPop: false, child: Text('Locked body')),
          ),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final rested = tester.getRect(find.byKey(V3Sheet.panelKey));

    await tester.drag(find.byKey(V3Sheet.handleKey), const Offset(0, 140));
    await tester.pumpAndSettle();
    expect(find.text('Locked body'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(V3Sheet.panelKey)).top,
      closeTo(rested.top, 0.5),
    );
  });

  testWidgets('top bar keeps the design 10 pt gap before right', (
    tester,
  ) async {
    await _pump(
      tester,
      const V3TopBar(
        title: 'Plan',
        topInset: 0,
        right: SizedBox(key: ValueKey('right'), width: 20, height: 20),
      ),
      center: false,
    );
    final right = tester.getRect(find.byKey(const ValueKey('right')));
    final titleColumn = tester.getRect(
      find.ancestor(of: find.text('Plan'), matching: find.byType(Column)).first,
    );
    expect(right.left - titleColumn.right, closeTo(10, 0.01));
    expect(800 - right.right, closeTo(16, 0.01));
  });

  testWidgets('a long chip label ellipsizes inside a narrow Wrap at large '
      'text, and a chip still builds in an unbounded row', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const long = 'Long-form investigative journalism and public records';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(3)),
          child: app!,
        ),
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    V3Chip(
                      key: const Key('wrapped'),
                      onPressed: () {},
                      child: const Text(long),
                    ),
                  ],
                ),
              ),
              // A horizontal scroller gives the chip unbounded width.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    V3Chip(
                      key: const Key('scrolling'),
                      icon: V3Icons.sparkle,
                      onPressed: () {},
                      child: const Text(long),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final wrapped = find.byKey(const Key('wrapped'));
    expect(tester.getTopRight(wrapped).dx, lessThanOrEqualTo(320 - 16));
    // The pill grows with its text instead of clipping it: at least 38 pt.
    final pill = find.descendant(
      of: wrapped,
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(pill).height, greaterThanOrEqualTo(38));
    final label = find.descendant(of: wrapped, matching: find.text(long));
    expect(
      tester.getTopRight(label).dx,
      lessThanOrEqualTo(tester.getTopRight(pill).dx),
    );
    final style = tester.widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(of: label, matching: find.byType(AnimatedDefaultTextStyle))
          .first,
    );
    expect(style.overflow, TextOverflow.ellipsis);
    expect(style.maxLines, 1);
    // The label's text stops growing at 2×, inside the primitive.
    expect(
      MediaQuery.textScalerOf(tester.element(label)).scale(10),
      closeTo(20, 0.001),
    );
    expect(find.byKey(const Key('scrolling')), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('button and seg labels stop growing at 2× text', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(3)),
          child: app!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              V3Button(onPressed: () {}, child: const Text('Continue')),
              V3Seg<int>(
                items: const [V3SegItem(0, 'Roadmap'), V3SegItem(1, 'Daily')],
                value: 0,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    for (final text in ['Continue', 'Roadmap', 'Daily']) {
      expect(
        MediaQuery.textScalerOf(tester.element(find.text(text))).scale(10),
        closeTo(20, 0.001),
        reason: text,
      );
    }
    await tester.pumpAndSettle();
  });

  testWidgets('top bar fits a 320 pt phone at 2.0 text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const sub = 'Chapter 12 of 24 · Decisions under uncertainty';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: app!,
        ),
        home: Scaffold(
          body: V3TopBar(
            onBack: () {},
            topInset: 0,
            title: 'Decision Systems for Ambitious Builders',
            sub: sub,
            right: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                V3IconButton(
                  icon: V3Icons.type,
                  label: 'Reading settings',
                  onPressed: () {},
                ),
                const SizedBox(width: 8),
                V3IconButton(
                  icon: V3Icons.more,
                  label: 'Book menu',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(V3TopBar)).height, 52);
    final subText = tester.widget<Text>(find.text(sub));
    expect(subText.maxLines, 1);
    expect(subText.overflow, TextOverflow.ellipsis);
    expect(
      MediaQuery.textScalerOf(tester.element(find.text(sub))).scale(10),
      closeTo(12, 0.001),
    );
  });

  testWidgets('burst and confetti repaint without rebuilding', (tester) async {
    await _pump(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 40, height: 40, child: V3Burst()),
          SizedBox(width: 200, height: 120, child: V3Confetti(seed: 3)),
        ],
      ),
    );
    CustomPaint paintOf(Type type) => tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(type),
        matching: find.byType(CustomPaint),
      ),
    );
    final burst = paintOf(V3Burst);
    final confetti = paintOf(V3Confetti);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    // Same widget instances: frames repaint via the painter's listenable.
    expect(identical(paintOf(V3Burst), burst), isTrue);
    expect(identical(paintOf(V3Confetti), confetti), isTrue);
    expect(burst.painter, isNotNull);
    expect(
      find.descendant(
        of: find.byType(V3Confetti),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('field shows label, focus border and error', (tester) async {
    String? typed;
    await _pump(
      tester,
      Padding(
        padding: const EdgeInsets.all(20),
        child: V3Field(
          label: 'Email',
          placeholder: 'you@example.com',
          error: 'Enter a valid email',
          onChanged: (v) => typed = v,
        ),
      ),
    );
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('you@example.com'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'a@b.co');
    expect(typed, 'a@b.co');
    expect(find.bySemanticsLabel(RegExp('Email')), findsWidgets);
  });

  // ── Smoke: every primitive pumps once without throwing ─────────────────

  testWidgets('smoke: every v3 primitive builds', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final image = MemoryImage(_pixel);
    await _pump(
      tester,
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const V3TopBar(title: 'Library', sub: 'Week 3'),
          V3TopBar(onBack: () {}, title: 'Dark', dark: true, solid: true),
          Wrap(
            spacing: 4,
            children: [
              for (final icon in V3Icons.values) V3Icon(icon, size: 16),
            ],
          ),
          for (final kind in V3ButtonKind.values)
            for (final size in V3Size.values)
              V3Button(
                kind: kind,
                size: size,
                icon: V3Icons.plus,
                iconRight: V3Icons.arrowR,
                onPressed: () {},
                child: Text('${kind.name} ${size.name}'),
              ),
          V3Button(full: true, loading: true, onPressed: () {}),
          Row(
            children: [
              V3IconButton(icon: V3Icons.left, label: 'Back', onPressed: () {}),
              V3IconButton(
                icon: V3Icons.history,
                label: 'Chat history',
                size: 38,
                badge: true,
                onPressed: () {},
              ),
              Container(
                color: AppColors.night,
                child: V3IconButton(
                  icon: V3Icons.up,
                  label: 'Up',
                  dark: true,
                  size: 48,
                  onPressed: () {},
                ),
              ),
              const V3Spinner(),
            ],
          ),
          Wrap(
            children: [
              V3Chip(on: true, onPressed: () {}, child: const Text('On')),
              V3Chip(onPressed: () {}, child: const Text('Off')),
              V3Chip(
                dark: true,
                on: true,
                onPressed: () {},
                child: const Text('Dark'),
              ),
              const V3Tag(icon: V3Icons.info, child: Text('Tag')),
              for (final type in AccessType.values) V3AccessBadge(type: type),
            ],
          ),
          V3Seg<String>(
            items: const [V3SegItem('a', 'A'), V3SegItem('b', 'A+')],
            value: 'b',
            dark: true,
            onChanged: (_) {},
          ),
          const Row(
            children: [
              V3Ring(value: 0.4, child: Text('40')),
              V3Ring(value: 1, size: 64, strokeWidth: 6, color: AppColors.sage),
              V3CountUp(to: 7),
            ],
          ),
          const V3Bar(value: 0.3, height: 4, color: AppColors.iris),
          Row(
            children: [
              V3CheckDot(done: false, onPressed: () {}),
              const V3CheckDot(done: true),
              const SizedBox(width: 40, height: 40, child: V3Burst(count: 14)),
              const V3Typing(),
            ],
          ),
          const SizedBox(height: 120, child: V3Confetti(seed: 7)),
          const V3Stream(text: 'Streaming words appear one by one.'),
          const V3Skel(height: 36, width: 200),
          Container(
            color: AppColors.night,
            child: const V3Skel(dark: true, height: 14),
          ),
          V3Field(
            label: 'Goal',
            value: 'Write daily',
            multiline: true,
            rows: 2,
            onChanged: (_) {},
          ),
          Container(
            color: AppColors.night,
            child: V3Field(
              placeholder: 'Search',
              dark: true,
              right: const V3Icon(V3Icons.search, size: 17),
              onChanged: (_) {},
            ),
          ),
          V3Section(
            title: 'Up next',
            action: 'See all',
            onAction: () {},
            child: Container(height: 60, decoration: v3Card()),
          ),
          Row(
            children: [
              const V3Avatar(initials: 'MA', tint: AppColors.goldSoft),
              V3Avatar(
                image: image,
                name: 'Maya',
                gray: true,
                ring: AppColors.ember,
              ),
              const V3Cover(
                title: 'Deep Work',
                author: 'Cal Newport',
                background: AppColors.night2,
                foreground: AppColors.gold,
              ),
            ],
          ),
          V3Portrait(
            image: image,
            height: 150,
            radius: 22,
            child: const Align(
              alignment: Alignment.bottomLeft,
              child: Text('Portrait'),
            ),
          ),
          const V3Rise(
            delay: Duration(milliseconds: 100),
            child: Text('Rises in'),
          ),
          SizedBox(
            height: 260,
            child: V3Sheet(
              title: 'Inline sheet',
              onClose: () {},
              child: const Text('Inline body'),
            ),
          ),
          SizedBox(
            height: 200,
            child: V3Sheet(
              dark: true,
              onClose: () {},
              child: const Text('Dark body'),
            ),
          ),
        ],
      ),
      center: false,
    );

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Library'), findsOneWidget);
  });

  // ── V3Field keyboard behaviour ─────────────────────────────────────────

  group('V3Field keyboard behaviour', () {
    TextField inputOf(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField));

    testWidgets('autocorrect and suggestions follow the kind of field', (
      tester,
    ) async {
      Future<TextField> mount(V3Field field) async {
        await _pump(tester, SizedBox(width: 320, child: field));
        return inputOf(tester);
      }

      // Plain text keeps the platform defaults.
      var input = await mount(const V3Field(label: 'Note'));
      expect(input.autocorrect, isTrue);
      expect(input.enableSuggestions, isTrue);

      // An address, a visible password and a hidden password are never
      // "corrected" or offered back.
      input = await mount(
        const V3Field(label: 'Email', keyboardType: TextInputType.emailAddress),
      );
      expect(input.autocorrect, isFalse);
      expect(input.enableSuggestions, isFalse);

      input = await mount(
        const V3Field(
          label: 'Code',
          keyboardType: TextInputType.visiblePassword,
        ),
      );
      expect(input.autocorrect, isFalse);
      expect(input.enableSuggestions, isFalse);

      input = await mount(const V3Field(label: 'Password', obscureText: true));
      expect(input.autocorrect, isFalse);
      expect(input.enableSuggestions, isFalse);

      // The caller can still decide.
      input = await mount(
        const V3Field(
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
          autocorrect: true,
          enableSuggestions: true,
        ),
      );
      expect(input.autocorrect, isTrue);
      expect(input.enableSuggestions, isTrue);
      input = await mount(
        const V3Field(
          label: 'Name',
          autocorrect: false,
          enableSuggestions: false,
        ),
      );
      expect(input.autocorrect, isFalse);
      expect(input.enableSuggestions, isFalse);
    });

    testWidgets('a tap outside dismisses the keyboard, not on the accessory', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await _pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 320,
              child: V3Field(
                label: 'Email',
                focusNode: focus,
                right: GestureDetector(
                  key: const ValueKey('accessory'),
                  onTap: () {},
                  child: const SizedBox(width: 30, height: 30),
                ),
              ),
            ),
            const SizedBox(height: 40),
            const Text('Elsewhere'),
          ],
        ),
      );
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);

      // The accessory belongs to the field: the keyboard stays up.
      await tester.tap(find.byKey(const ValueKey('accessory')));
      await tester.pump();
      expect(focus.hasFocus, isTrue);

      await tester.tap(find.text('Elsewhere'));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
    });

    testWidgets('a caller can replace the tap-outside behaviour', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var outside = 0;
      await _pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 320,
              child: V3Field(
                label: 'Note',
                focusNode: focus,
                onTapOutside: (_) => outside++,
              ),
            ),
            const SizedBox(height: 40),
            const Text('Elsewhere'),
          ],
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.tap(find.text('Elsewhere'));
      await tester.pump();
      expect(outside, 1);
      expect(focus.hasFocus, isTrue);
    });
  });
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.onMount});

  final VoidCallback onMount;

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 60, height: 40);
}
