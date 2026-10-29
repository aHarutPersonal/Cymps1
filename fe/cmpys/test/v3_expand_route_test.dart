import 'package:cmpys/app/design_tokens.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// `Expand` from `v3/core.jsx` as a page route: the page is clipped to the
// tapped card's rect (rounded 24) and grows to the full screen over .6 s on
// `--io`; closing reverses back into the card. Reduced motion fades instead.

const _card = Rect.fromLTWH(20, 300, 350, 200);

Future<void> _mount(WidgetTester tester, {bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fromRect(
              rect: _card,
              child: Builder(
                builder: (context) => GestureDetector(
                  onTap: () => Navigator.of(context).push<void>(
                    V3ExpandRoute<void>(
                      from: V3ExpandRoute.rectOf(context),
                      builder: (_) => const Center(child: Text('Preview body')),
                    ),
                  ),
                  child: const ColoredBox(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Taps the card and lets the route build its first frame (t = 0).
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byType(GestureDetector).first);
  // One frame inserts the route; the next builds it at animation value 0.
  await tester.pump();
  await tester.pump();
}

Rect _clip(WidgetTester tester) {
  final clip = tester.widget<ClipRRect>(find.byKey(V3ExpandRoute.clipKey));
  final size = tester.getSize(find.byKey(V3ExpandRoute.clipKey));
  return clip.clipper!.getClip(size).outerRect;
}

void main() {
  testWidgets('opens from the tapped rect to full screen in 0.6 s', (
    tester,
  ) async {
    await _mount(tester);
    await _open(tester);

    // First frame: exactly the card.
    expect(_clip(tester), _card);

    await tester.pump(const Duration(milliseconds: 300));
    final mid = _clip(tester);
    // `--io` is symmetric, so half way is half way between the two rects.
    expect(mid.left, closeTo(_card.left / 2, 0.5));
    expect(mid.top, closeTo(_card.top / 2, 0.5));
    expect(mid.right, closeTo((_card.right + 390) / 2, 0.5));
    expect(mid.bottom, closeTo((_card.bottom + 844) / 2, 0.5));

    await tester.pump(const Duration(milliseconds: 299));
    expect(_clip(tester), isNot(const Rect.fromLTWH(0, 0, 390, 844)));
    await tester.pumpAndSettle();
    expect(_clip(tester), const Rect.fromLTWH(0, 0, 390, 844));
    expect(find.text('Preview body'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the corner radius goes from 24 to 0', (tester) async {
    await _mount(tester);
    await _open(tester);
    final clipper = tester
        .widget<ClipRRect>(find.byKey(V3ExpandRoute.clipKey))
        .clipper!;
    final size = tester.getSize(find.byKey(V3ExpandRoute.clipKey));
    // A point 1 pt inside the card's top-left corner is cut off by a 24 pt
    // radius, but the card's edge mid-way along the top is not.
    final start = clipper.getClip(size);
    expect(start.contains(_card.topLeft + const Offset(1, 1)), isFalse);
    expect(start.contains(_card.topCenter + const Offset(0, 1)), isTrue);

    await tester.pumpAndSettle();
    final end = tester
        .widget<ClipRRect>(find.byKey(V3ExpandRoute.clipKey))
        .clipper!
        .getClip(size);
    expect(end.contains(const Offset(1, 1)), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing reverses back into the card', (tester) async {
    await _mount(tester);
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final mid = _clip(tester);
    expect(mid.left, closeTo(_card.left / 2, 0.5));
    expect(mid.bottom, closeTo((_card.bottom + 844) / 2, 0.5));

    await tester.pump(const Duration(milliseconds: 250));
    // Nearly closed, still a clip around the card.
    expect(_clip(tester).height, lessThan(_card.height + 40));
    await tester.pumpAndSettle();
    expect(find.text('Preview body'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps the page below visible while it opens', (tester) async {
    await _mount(tester);
    await _open(tester);
    await tester.pump(const Duration(milliseconds: 100));
    // The route is not opaque while it animates, so the card stays visible.
    expect(find.byType(Scaffold), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the route paints the night background by default', (
    tester,
  ) async {
    await _mount(tester);
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(V3ExpandRoute.clipKey),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, AppColors.night);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion fades instead of clipping', (tester) async {
    await _mount(tester, reduceMotion: true);
    await _open(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(V3ExpandRoute.clipKey), findsNothing);
    final fade = tester.widget<FadeTransition>(
      find.byKey(V3ExpandRoute.fadeKey),
    );
    expect(fade.opacity.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(find.text('Preview body'), findsOneWidget);
    expect(
      tester
          .widget<FadeTransition>(find.byKey(V3ExpandRoute.fadeKey))
          .opacity
          .value,
      1,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rectOf measures a widget inside the navigator', (tester) async {
    final key = GlobalKey();
    Rect? measured;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fromRect(
                rect: _card,
                child: Builder(
                  builder: (context) {
                    return GestureDetector(
                      key: key,
                      behavior: HitTestBehavior.opaque,
                      onTap: () => measured = V3ExpandRoute.rectOf(context),
                      child: const SizedBox.expand(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(key));
    expect(measured, _card);
  });
}
