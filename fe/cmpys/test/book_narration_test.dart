import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('markdown becomes ordered, sentence-sized narration segments', () {
    final document = BookNarrationDocument.fromMarkdown('''
First sentence. **Second sentence stays readable.**

### Practice This

1. Start with one action.
2. Record what changed!

> A quoted idea remains part of the narration.
''');

    expect(document.segments.map((segment) => segment.text), [
      'First sentence.',
      'Second sentence stays readable.',
      'Practice This',
      'Start with one action.',
      'Record what changed!',
      'A quoted idea remains part of the narration.',
    ]);
    expect(document.blocks.map((block) => block.kind), [
      BookNarrationBlockKind.paragraph,
      BookNarrationBlockKind.heading,
      BookNarrationBlockKind.listItem,
      BookNarrationBlockKind.listItem,
      BookNarrationBlockKind.quote,
    ]);
    expect(document.blocks[2].listMarker, '1.');
    expect(document.blocks[3].listMarker, '2.');
  });

  test('sentence offsets map exactly back to the visible block', () {
    final document = BookNarrationDocument.fromMarkdown(
      'Read this first. Then keep going?',
    );

    final block = document.blocks.single;
    for (final segment in document.segments) {
      expect(block.text.substring(segment.start, segment.end), segment.text);
    }
  });

  test('common abbreviations do not create false narration jumps', () {
    final document = BookNarrationDocument.fromMarkdown(
      'Use a small cue, e.g. a card by the door. Then begin.',
    );

    expect(document.segments.map((segment) => segment.text), [
      'Use a small cue, e.g. a card by the door.',
      'Then begin.',
    ]);
  });

  test(
    'paragraph-aware chunks stay bounded and preserve sentence navigation',
    () {
      final paragraph = List.generate(
        34,
        (index) =>
            'Sentence $index carries enough context for natural narration.',
      ).join(' ');
      final document = BookNarrationDocument.fromMarkdown(
        '$paragraph\n\n$paragraph',
      );

      expect(document.chunks.length, greaterThan(1));
      expect(
        document.chunks.every((chunk) => chunk.text.length <= 1800),
        isTrue,
      );
      expect(document.chunks.any((chunk) => chunk.text.length >= 600), isTrue);
      for (final chunk in document.chunks) {
        for (final slice in chunk.segments) {
          final segment = document.segments[slice.segmentIndex];
          expect(
            chunk.text.substring(slice.start, slice.end),
            segment.text.substring(slice.segmentStart, slice.segmentEnd),
          );
        }
      }
    },
  );

  test('ordered-list narration chunks stay inside rendered blocks', () {
    final document = BookNarrationDocument.fromMarkdown('''
Keep the introduction intentionally short.

1. Begin with one concrete action.
2. Review what changed after the action.

Finish with a brief reflection.
''');

    expect(document.chunks, hasLength(4));
    for (final chunk in document.chunks) {
      final blockIndexes = chunk.segments
          .map((slice) => document.segments[slice.segmentIndex].blockIndex)
          .toSet();
      expect(blockIndexes, hasLength(1));
    }
  });

  test('headings, paragraphs, and quotes use separate synthesis chunks', () {
    final document = BookNarrationDocument.fromMarkdown('''
### A Short Principle

Choose the smallest useful step.

> Progress becomes visible through repetition.
''');

    expect(document.blocks.map((block) => block.kind), [
      BookNarrationBlockKind.heading,
      BookNarrationBlockKind.paragraph,
      BookNarrationBlockKind.quote,
    ]);
    expect(document.chunks, hasLength(3));
    expect(
      document.chunks.map(
        (chunk) =>
            document.segments[chunk.segments.single.segmentIndex].blockIndex,
      ),
      [0, 1, 2],
    );
  });

  test('only classified transient narration loads are retried', () {
    final request = RequestOptions(path: '/narration');
    DioException wrapped(Object error, {int? statusCode}) => DioException(
      requestOptions: request,
      response: statusCode == null
          ? null
          : Response<void>(requestOptions: request, statusCode: statusCode),
      error: error,
    );

    expect(
      isTransientBookNarrationLoadError(wrapped(const NetworkError())),
      isTrue,
    );
    expect(
      isTransientBookNarrationLoadError(
        wrapped(
          const ApiError(message: 'Busy', statusCode: 429),
          statusCode: 429,
        ),
      ),
      isTrue,
    );
    expect(
      isTransientBookNarrationLoadError(
        wrapped(
          const ApiError(message: 'Unavailable', statusCode: 503),
          statusCode: 503,
        ),
      ),
      isTrue,
    );
    expect(
      isTransientBookNarrationLoadError(
        wrapped(
          const ApiError(message: 'Invalid passage', statusCode: 422),
          statusCode: 422,
        ),
      ),
      isFalse,
    );
  });

  test(
    'append failures surface only after wanted playback exhausts its queue',
    () {
      expect(
        shouldSurfaceBookNarrationAppendError(
          hasError: true,
          wantsPlayback: true,
          queueIsExhausted: false,
        ),
        isFalse,
      );
      expect(
        shouldSurfaceBookNarrationAppendError(
          hasError: true,
          wantsPlayback: false,
          queueIsExhausted: true,
        ),
        isFalse,
      );
      expect(
        shouldSurfaceBookNarrationAppendError(
          hasError: true,
          wantsPlayback: true,
          queueIsExhausted: true,
        ),
        isTrue,
      );
    },
  );

  test('an overlong sentence splits without joining or losing words', () {
    final sentence = List.generate(430, (index) => 'token$index').join(' ');
    final document = BookNarrationDocument.fromMarkdown(sentence);

    expect(document.segments, hasLength(1));
    expect(document.chunks.length, greaterThan(1));
    expect(document.chunks.every((chunk) => chunk.text.length <= 1800), isTrue);
    final reconstructed = document.chunks
        .map((chunk) => chunk.text)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    expect(reconstructed, sentence);
  });

  test('exact cue lookup clears highlights during every silence interval', () {
    const cues = [
      BookNarrationCue(
        start: 0,
        end: 5,
        startTime: Duration(milliseconds: 200),
        endTime: Duration(milliseconds: 400),
      ),
      BookNarrationCue(
        start: 6,
        end: 10,
        startTime: Duration(milliseconds: 700),
        endTime: Duration(milliseconds: 900),
      ),
    ];

    expect(activeBookNarrationCueAt(cues, Duration.zero), isNull);
    expect(
      activeBookNarrationCueAt(cues, const Duration(milliseconds: 250)),
      same(cues.first),
    );
    expect(
      activeBookNarrationCueAt(cues, const Duration(milliseconds: 500)),
      isNull,
    );
    expect(
      activeBookNarrationCueAt(cues, const Duration(milliseconds: 750)),
      same(cues.last),
    );
    expect(
      activeBookNarrationCueAt(cues, const Duration(milliseconds: 900)),
      isNull,
    );
  });

  test('legacy code-point offsets convert safely to Dart UTF-16 offsets', () {
    final cue = BookNarrationCue.fromJson(
      const {'start': 2, 'end': 3, 'startMs': 0, 'endMs': 100},
      sourceText: '💡 A',
      offsetEncoding: 'unicode_codepoints',
    );

    expect(cue.start, 3);
    expect(cue.end, 4);
    expect(
      BookNarrationAlignmentGranularity.fromApi(
        'provider_segment',
        hasAlignment: true,
      ),
      BookNarrationAlignmentGranularity.phrase,
    );
  });

  test('resume character offset seeks to the nearest aligned cue', () {
    const chunk = BookNarrationChunk(
      index: 0,
      text: 'Alpha beta gamma',
      segments: [
        BookNarrationChunkSegment(
          segmentIndex: 3,
          start: 0,
          end: 16,
          segmentStart: 0,
          segmentEnd: 16,
        ),
      ],
    );
    final audio = BookNarrationAudio(
      audioUri: Uri.parse('https://example.com/narration.mp3'),
      style: 'expressive',
      voice: 'voice',
      duration: const Duration(milliseconds: 1600),
      alignment: const [
        BookNarrationCue(
          start: 0,
          end: 5,
          startTime: Duration.zero,
          endTime: Duration(milliseconds: 400),
        ),
        BookNarrationCue(
          start: 6,
          end: 10,
          startTime: Duration(milliseconds: 500),
          endTime: Duration(milliseconds: 900),
        ),
        BookNarrationCue(
          start: 11,
          end: 16,
          startTime: Duration(milliseconds: 1000),
          endTime: Duration(milliseconds: 1500),
        ),
      ],
      isAiGenerated: true,
    );

    expect(
      bookNarrationPositionForCharacterOffset(
        audio: audio,
        chunk: chunk,
        segmentIndex: 3,
        characterOffset: 8,
      ),
      const Duration(milliseconds: 500),
    );
    expect(
      bookNarrationPositionForCharacterOffset(
        audio: audio,
        chunk: chunk,
        segmentIndex: 3,
        characterOffset: 14,
      ),
      const Duration(milliseconds: 1000),
    );
  });

  test('resume character offset uses proportional fallback without cues', () {
    const chunk = BookNarrationChunk(
      index: 0,
      text: '0123456789',
      segments: [
        BookNarrationChunkSegment(
          segmentIndex: 0,
          start: 0,
          end: 10,
          segmentStart: 0,
          segmentEnd: 10,
        ),
      ],
    );
    final audio = BookNarrationAudio(
      audioUri: Uri.parse('https://example.com/narration.mp3'),
      style: 'expressive',
      voice: 'voice',
      duration: const Duration(seconds: 10),
      alignment: const [],
      isAiGenerated: true,
    );

    expect(
      bookNarrationPositionForCharacterOffset(
        audio: audio,
        chunk: chunk,
        segmentIndex: 0,
        characterOffset: 4,
      ),
      const Duration(seconds: 4),
    );
  });

  test(
    'unaligned track estimates segment-relative highlights across slices',
    () {
      const chunk = BookNarrationChunk(
        index: 0,
        text: 'alpha beta gamma delta',
        segments: [
          BookNarrationChunkSegment(
            segmentIndex: 3,
            start: 0,
            end: 10,
            segmentStart: 10,
            segmentEnd: 20,
          ),
          BookNarrationChunkSegment(
            segmentIndex: 4,
            start: 11,
            end: 22,
            segmentStart: 20,
            segmentEnd: 31,
          ),
        ],
      );

      final first = estimateBookNarrationTrackHighlight(
        chunk: chunk,
        position: const Duration(milliseconds: 100),
        duration: const Duration(milliseconds: 1900),
      );
      expect(first?.segmentIndex, 3);
      expect(first?.highlightStart, 10);
      expect(first?.highlightEnd, 15);

      final second = estimateBookNarrationTrackHighlight(
        chunk: chunk,
        position: const Duration(milliseconds: 1500),
        duration: const Duration(milliseconds: 1900),
      );
      expect(second?.segmentIndex, 4);
      expect(second?.highlightStart, 26);
      expect(second?.highlightEnd, 31);
    },
  );

  test(
    'unaligned track highlight clamps time and rejects missing duration',
    () {
      const chunk = BookNarrationChunk(
        index: 0,
        text: 'alpha beta',
        segments: [
          BookNarrationChunkSegment(
            segmentIndex: 0,
            start: 0,
            end: 10,
            segmentStart: 0,
            segmentEnd: 10,
          ),
        ],
      );

      expect(
        estimateBookNarrationTrackHighlight(
          chunk: chunk,
          position: const Duration(seconds: 20),
          duration: const Duration(seconds: 10),
        )?.highlightStart,
        6,
      );
      expect(
        estimateBookNarrationTrackHighlight(
          chunk: chunk,
          position: Duration.zero,
          duration: null,
        ),
        isNull,
      );
    },
  );

  test('unaligned track projects a source-only separator to a valid slice', () {
    const chunk = BookNarrationChunk(
      index: 0,
      text: 'alpha / beta',
      segments: [
        BookNarrationChunkSegment(
          segmentIndex: 0,
          start: 0,
          end: 5,
          segmentStart: 0,
          segmentEnd: 5,
        ),
        BookNarrationChunkSegment(
          segmentIndex: 1,
          start: 8,
          end: 12,
          segmentStart: 0,
          segmentEnd: 4,
        ),
      ],
    );

    final estimate = estimateBookNarrationTrackHighlight(
      chunk: chunk,
      position: const Duration(milliseconds: 550),
      duration: const Duration(seconds: 1),
    );

    expect(estimate?.segmentIndex, 0);
    expect(estimate?.highlightStart, 4);
    expect(estimate?.highlightEnd, 5);
  });

  test('resume offset selects the owning chunk of a split sentence', () {
    final sentence = List.generate(430, (index) => 'token$index').join(' ');
    final document = BookNarrationDocument.fromMarkdown(sentence);

    expect(document.segments, hasLength(1));
    expect(document.chunks.length, greaterThan(1));
    expect(
      bookNarrationInitialChunkIndex(
        document: document,
        segmentIndex: 0,
        characterOffset: sentence.length,
      ),
      document.chunks.length - 1,
    );
  });
}
