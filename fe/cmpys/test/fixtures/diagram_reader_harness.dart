import 'package:cmpys/features/session/models/content_resource.dart';
import 'comparison_reader_harness.dart';
import 'live_learning_diagrams.dart';

class DiagramReaderRepository extends ComparisonReaderRepository {
  DiagramReaderRepository(this.fixture);
  final int fixture;

  @override
  Future<ContentResource> getResource(String id) async => ContentResource(
    id: 'comparison-fixture',
    kind: 'llm_book_summary',
    canonicalKey: 'diagram-fixture-$fixture',
    title: fixture >= 8
        ? 'Achievement Deconstruction Canvas'
        : 'The Intelligent Investor',
    licenseStatus: 'test_fixture',
    isSaved: false,
    progressPercent: 0,
    cursorJson: cursor,
    contentMarkdown:
        '## ${fixture >= 8 ? "Designing Transferable Operational Playbooks" : "Mr. Market and Emotional Discipline"}\n\n${liveLearningDiagrams[fixture]}\n\n## Next chapter\nContinue reading.',
  );
}
