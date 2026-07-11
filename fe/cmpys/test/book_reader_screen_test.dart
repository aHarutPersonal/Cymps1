import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/plan/presentation/book_reader_screen.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeContentResourcesRepository extends ContentResourcesRepository {
  _FakeContentResourcesRepository()
    : super(dioClient: DioClient(tokenStore: TokenStore()));

  final resource = const ContentResource(
    id: 'book-1',
    kind: 'llm_book_summary',
    canonicalKey: 'book:author:decision_systems',
    title: 'Decision Systems',
    authorOrCreator: 'A. Author',
    licenseStatus: 'llm_summary',
    contentMarkdown: '''
## Decision Systems

A useful decision starts by separating a reversible choice from an irreversible one. **Speed belongs to the first category; care belongs to the second.**

### Practice This
1. Label one decision as reversible or irreversible.
2. Write the smallest useful next step.

## Attention Loops

Attention improves when unfinished work has an explicit return point. Record the next action before changing contexts.

### Practice This
1. Close one loop before opening another.
2. Record what changed.

## Closing Synthesis

Combine the decision label and return point in one daily review.
''',
    durationMinutes: 18,
    isSaved: true,
    progressPercent: 0,
  );

  @override
  Future<ContentResource> getResource(String resourceId) async => resource;

  @override
  Future<List<ContentHighlight>> listHighlights(String resourceId) async =>
      const [];

  @override
  Future<ContentResource> updateProgress(
    String resourceId, {
    required int progressPercent,
    Map<String, dynamic>? cursorJson,
    bool? completed,
  }) async => resource;
}

void main() {
  testWidgets('reader exposes chapters, notes, and typography controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeContentResourcesRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentResourcesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: BookReaderScreen(
            resourceId: 'book-1',
            fallbackTitle: 'Fallback',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CHAPTER 01 OF 03'), findsOneWidget);
    expect(find.text('Decision Systems'), findsWidgets);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.format_size_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Reading settings'), findsOneWidget);
    expect(find.text('Warm'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('Reading settings'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Contents'), findsOneWidget);
    expect(find.text('Attention Loops'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
