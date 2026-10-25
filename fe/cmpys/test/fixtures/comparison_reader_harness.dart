import 'dart:async';
import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/plan/presentation/book_reader_screen.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'learning_comparison_fixture.dart';

class ComparisonReaderRepository extends Fake
    implements ContentResourcesRepository {
  Map<String, dynamic>? cursor;
  String? savedQuote;
  @override
  Future<ContentHighlight> createHighlight(
    String id, {
    Map<String, dynamic>? locatorJson,
    String? quoteText,
    String? noteText,
  }) async {
    savedQuote = quoteText;
    return ContentHighlight(
      id: "fixture-note",
      contentResourceId: id,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      quoteText: quoteText,
      noteText: noteText,
      locatorJson: locatorJson,
    );
  }

  @override
  Future<ContentResource> getResource(String id) async => const ContentResource(
    id: 'comparison-fixture',
    kind: 'llm_book_summary',
    canonicalKey: 'comparison-fixture',
    title: 'The Intelligent Investor',
    licenseStatus: 'test_fixture',
    isSaved: false,
    progressPercent: 0,
    contentMarkdown:
        '## Investment Versus Speculation\n\n$investmentMarkdown\n\n## Putting It Into Practice\n\nCompare the evidence before you decide.',
  );
  @override
  Future<List<ContentHighlight>> listHighlights(String id) async => [];
  @override
  Future<ContentResource> updateProgress(
    String id, {
    required int progressPercent,
    Map<String, dynamic>? cursorJson,
    bool? completed,
  }) async {
    cursor = cursorJson;
    return getResource(id);
  }
}

/// Controlled speech callbacks test the real reader's selection/highlight path.
/// This does not pretend to produce or verify audible provider speech.
class ComparisonPreviewNarrator implements BookNarrator {
  BookNarrationProgressHandler? progress;
  String spoken = '';
  Completer<void>? pending;
  @override
  void setProgressHandler(BookNarrationProgressHandler? handler) =>
      progress = handler;
  @override
  void setErrorHandler(BookNarrationErrorHandler? handler) {}
  @override
  Future<void> initialize({required double speed}) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> speak(String text) {
    spoken = text;
    pending = Completer<void>();
    return pending!.future;
  }

  @override
  Future<void> stop() async {
    if (pending != null && !pending!.isCompleted) pending!.complete();
  }

  @override
  Future<void> dispose() => stop();
}

Widget comparisonReaderHarness(
  ComparisonReaderRepository repository,
  ComparisonPreviewNarrator narrator, {
  double scale = 1,
}) => ProviderScope(
  overrides: [contentResourcesRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: BookReaderScreen(
      resourceId: 'comparison-fixture',
      fallbackTitle: 'The Intelligent Investor',
      narrator: narrator,
    ),
  ),
);
