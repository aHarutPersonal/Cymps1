import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/session/models/content_resource.dart';

void main() {
  test('ContentResource parses user-specific progress state', () {
    final resource = ContentResource.fromJson({
      'id': 'resource-1',
      'kind': 'llm_book_summary',
      'canonicalKey': 'book:cal_newport:deep_work',
      'title': 'Deep Work',
      'licenseStatus': 'llm_summary',
      'isSaved': true,
      'savedAt': '2026-05-09T07:00:00Z',
      'progressPercent': 72,
      'cursorJson': {'scrollProgress': 0.72, 'section': 'rituals'},
      'completedAt': '2026-05-09T08:00:00Z',
    });

    expect(resource.isSaved, isTrue);
    expect(resource.progressPercent, 72);
    expect(resource.cursorJson, {'scrollProgress': 0.72, 'section': 'rituals'});
    expect(resource.savedAt, DateTime.parse('2026-05-09T07:00:00Z'));
    expect(resource.completedAt, DateTime.parse('2026-05-09T08:00:00Z'));
    expect(resource.isCompleted, isTrue);
  });

  test('ContentHighlight parses camelCase and snake_case API payloads', () {
    final camel = ContentHighlight.fromJson({
      'id': 'highlight-1',
      'contentResourceId': 'resource-1',
      'locatorJson': {'section': 'proof-loop'},
      'quoteText': 'Small wins compound.',
      'noteText': 'Use this in week 1.',
      'createdAt': '2026-05-09T08:00:00Z',
      'updatedAt': '2026-05-09T09:00:00Z',
    });

    final snake = ContentHighlight.fromJson({
      'id': 'highlight-2',
      'content_resource_id': 'resource-2',
      'locator_json': {'section': 'ritual'},
      'quote_text': 'Protect the first hour.',
      'note_text': 'Try tomorrow.',
      'created_at': '2026-05-09T10:00:00Z',
      'updated_at': '2026-05-09T11:00:00Z',
    });

    expect(camel.contentResourceId, 'resource-1');
    expect(camel.locatorJson, {'section': 'proof-loop'});
    expect(camel.quoteText, 'Small wins compound.');
    expect(camel.noteText, 'Use this in week 1.');
    expect(camel.createdAt, DateTime.parse('2026-05-09T08:00:00Z'));

    expect(snake.contentResourceId, 'resource-2');
    expect(snake.locatorJson, {'section': 'ritual'});
    expect(snake.quoteText, 'Protect the first hour.');
    expect(snake.noteText, 'Try tomorrow.');
    expect(snake.updatedAt, DateTime.parse('2026-05-09T11:00:00Z'));
  });

  test('ContentHighlight exposes note display text', () {
    final note = ContentHighlight.fromJson({
      'id': 'highlight-3',
      'contentResourceId': 'resource-3',
      'noteText': 'Rewatch the example at 04:20.',
      'quoteText': 'Fallback quote.',
      'createdAt': '2026-05-09T08:00:00Z',
      'updatedAt': '2026-05-09T08:00:00Z',
    });
    final quoteOnly = ContentHighlight.fromJson({
      'id': 'highlight-4',
      'contentResourceId': 'resource-3',
      'quoteText': 'Use constraints as a forcing function.',
      'createdAt': '2026-05-09T08:00:00Z',
      'updatedAt': '2026-05-09T08:00:00Z',
    });

    expect(note.displayText, 'Rewatch the example at 04:20.');
    expect(quoteOnly.displayText, 'Use constraints as a forcing function.');
  });
}
