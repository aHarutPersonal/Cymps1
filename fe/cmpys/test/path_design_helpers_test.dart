import 'package:cmpys/features/plans/models/plan_models.dart';
import 'package:cmpys/features/plans/presentation/widgets/path_design_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('path item subtitle compacts whitespace-heavy generated text', () {
    const item = PlanItem(
      id: 'item-1',
      title: 'Read one article',
      type: 'study',
      successMetric: '   \n\nSummarize   key\t\tideas\n\n\nin one page.   ',
    );

    expect(pathItemSubtitle(item), 'Summarize key ideas in one page.');
  });

  test('blank generated plan items are not renderable week cards', () {
    const item = PlanItem(
      id: 'item-blank',
      title: '\u200B \n\t',
      type: 'study',
      description: '\u200B',
      successMetric: '   ',
    );

    expect(pathItemHasRenderableContent(item), isFalse);
  });
}
