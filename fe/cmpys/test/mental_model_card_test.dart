// The mission's mental model card (SPEC §7, owner ruling 2026-10-29): the
// two farm images (crossfade every 6 s, slow zoom once seen) show only when
// the model is about a farm; every other model keeps the text-only card.

import 'package:cmpys/app/assets.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/mission_detail_data.dart';
import 'package:cmpys/features/plan/presentation/plan_item_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _farm =
    'The farm test: buy a business the way you would buy a farm, for what '
    'it yields.';
const _other = 'Owner’s lens: every page ends in a decision.';

PlanItemDetailed _mission(String mentalModel) => PlanItemDetailed.fromJson({
  'item': {
    'id': 'mission-1',
    'title': 'Write the owner’s memo',
    'type': 'project',
    'description': 'Turn the week’s reading into one page.',
    'weekStart': 3,
    'weekEnd': 3,
    'successMetric': 'A one-page memo that ends in one clear decision.',
    'estimatedHours': 2,
    'estimatedMinutes': 120,
    'status': 'in_progress',
  },
  'details_status': 'available',
  'artifact_job_id': 'artifact-1',
  'completed_step_ids': const <String>[],
  'details': {
    'lesson_format': 'tutorial_v1',
    'steps': const <Object?>[],
    'materials': const <Object?>[],
    'mental_model': mentalModel,
  },
});

class _Repo extends Fake implements PlanRepository {
  _Repo(this.detail);

  final PlanItemDetailed detail;

  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async => detail;
}

Future<void> _pump(
  WidgetTester tester,
  String mentalModel, {
  bool reduced = false,
  double height = 3200,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planRepositoryProvider.overrideWithValue(_Repo(_mission(mentalModel))),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: const PlanItemDetailScreen(itemId: 'mission-1'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

final _card = find.byKey(const Key('mental-model-card'));
final _area = find.byKey(const Key('mental-model-images'));
final _tag = find.byKey(const Key('mental-model-tag'));

Finder _images() => find.descendant(of: _card, matching: find.byType(Image));

/// Decodes the card's images for real (a widget test's fake clock never
/// finishes image decoding), then lets the card react.
Future<void> _loadImages(WidgetTester tester) async {
  final context = tester.element(_card);
  await tester.runAsync(() async {
    for (final image in tester.widgetList<Image>(_images())) {
      await precacheImage(image.image, context);
    }
  });
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

double _imageOpacity(WidgetTester tester, int i) => tester
    .widget<AnimatedOpacity>(find.byKey(ValueKey('mental-model-image-$i')))
    .opacity;

double _imageScale(WidgetTester tester, int i) => tester
    .widget<AnimatedScale>(
      find.descendant(
        of: find.byKey(ValueKey('mental-model-image-$i')),
        matching: find.byType(AnimatedScale),
      ),
    )
    .scale;

Future<void> _end(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
}

void main() {
  test('only a model about a farm gets the images', () {
    expect(
      mentalModelIsAboutFarm((title: 'The farm test', body: 'Yield first.')),
      isTrue,
    );
    expect(
      mentalModelIsAboutFarm((title: null, body: 'Own it like a FARM.')),
      isTrue,
    );
    expect(mentalModelIsAboutFarm((title: 'Farmland', body: '')), isTrue);
    expect(
      mentalModelIsAboutFarm((title: 'Owner’s lens', body: 'Decide first.')),
      isFalse,
    );
    expect(
      mentalModelIsAboutFarm((title: 'Margin of safety', body: '')),
      isFalse,
    );
  });

  testWidgets('another model keeps today’s text-only card, no images', (
    tester,
  ) async {
    await _pump(tester, _other);
    expect(find.text('MENTAL MODEL'), findsOneWidget);
    expect(find.text('Owner’s lens'), findsOneWidget);
    expect(find.text('every page ends in a decision.'), findsOneWidget);
    expect(_images(), findsNothing);
    expect(_area, findsNothing);
    expect(tester.widget<Text>(find.text('Owner’s lens')).style?.fontSize, 28);
    await _end(tester);
  });

  testWidgets('a farm model: text-only until an image loads, then the image '
      'area, the tag, and a crossfade every 6 s', (tester) async {
    await _pump(tester, _farm);
    // Not loaded yet: the text-only card.
    expect(find.text('MENTAL MODEL'), findsOneWidget);
    expect(tester.getSize(_area).height, 0);
    expect(
      tester
          .widgetList<Image>(_images())
          .map((i) => (i.image as AssetImage).assetName),
      [AppAssets.imageMentalModelFarmA, AppAssets.imageMentalModelFarmB],
    );

    await _loadImages(tester);
    await tester.pump(const Duration(milliseconds: 900));
    // 210 pt of images, the text overlapping their last 26 pt.
    expect(tester.getSize(_area).height, 184);
    expect(_tag, findsOneWidget);
    expect(find.text('Mental model'), findsOneWidget);
    expect(find.text('MENTAL MODEL'), findsNothing);
    expect(find.text('The farm test'), findsOneWidget);

    // Seen (on screen): the shown image settles to 1, the other to 1.08.
    expect(_imageOpacity(tester, 0), 1);
    expect(_imageOpacity(tester, 1), 0);
    expect(_imageScale(tester, 0), 1);
    expect(_imageScale(tester, 1), 1.08);

    await tester.pump(const Duration(seconds: 6));
    expect(_imageOpacity(tester, 0), 0);
    expect(_imageOpacity(tester, 1), 1);
    expect(_imageScale(tester, 1), 1);
    await tester.pump(const Duration(seconds: 6));
    expect(_imageOpacity(tester, 0), 1);
    await _end(tester);
  });

  testWidgets('before 30% of it is on screen the images wait at 1.15 and the '
      'text is hidden', (tester) async {
    await _pump(tester, _farm, height: 500);
    await _loadImages(tester);
    await tester.pump(const Duration(milliseconds: 900));
    expect(_imageScale(tester, 0), 1.15);
    final title = find.ancestor(
      of: find.text('The farm test'),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(title.first).opacity, 0);

    await tester.scrollUntilVisible(
      find.text('The farm test'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // The check runs after the frame that lays the scroll out; the reveal
    // starts on the next.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    expect(_imageScale(tester, 0), 1);
    expect(tester.widget<Opacity>(title.first).opacity, 1);
    await _end(tester);
  });

  testWidgets('reduced motion: one static image, no crossfade or zoom', (
    tester,
  ) async {
    await _pump(tester, _farm, reduced: true);
    expect(_images(), findsOneWidget);
    await _loadImages(tester);
    await tester.pump();
    expect(tester.getSize(_area).height, 184);
    expect(_imageOpacity(tester, 0), 1);
    expect(_imageScale(tester, 0), 1);
    expect(find.text('The farm test'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    expect(_imageOpacity(tester, 0), 1);
    expect(_images(), findsOneWidget);
    await _end(tester);
  });
}
