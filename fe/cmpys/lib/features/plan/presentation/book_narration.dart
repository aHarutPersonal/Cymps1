import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:markdown/markdown.dart' as md;

typedef BookNarrationProgressHandler =
    void Function(int start, int end, String word);
typedef BookNarrationErrorHandler = void Function(Object error);

/// Small boundary around the platform speech engine so the reader can be
/// exercised without a native plugin in widget tests.
abstract interface class BookNarrator {
  void setProgressHandler(BookNarrationProgressHandler? handler);

  void setErrorHandler(BookNarrationErrorHandler? handler);

  Future<void> initialize({required double speed});

  Future<void> setSpeed(double speed);

  /// Completes when [text] has finished speaking.
  Future<void> speak(String text);

  Future<void> stop();

  Future<void> dispose();
}

/// Device-local narration using the installed system voices. No network or
/// generated audio is required.
final class SystemBookNarrator implements BookNarrator {
  SystemBookNarrator({FlutterTts? flutterTts})
    : _flutterTts = flutterTts ?? FlutterTts() {
    _flutterTts.setProgressHandler((_, start, end, word) {
      _progressHandler?.call(start, end, word);
    });
    _flutterTts.setErrorHandler((message) {
      _errorHandler?.call(StateError(message.toString()));
    });
  }

  final FlutterTts _flutterTts;
  BookNarrationProgressHandler? _progressHandler;
  BookNarrationErrorHandler? _errorHandler;
  bool _initialized = false;

  @override
  void setProgressHandler(BookNarrationProgressHandler? handler) {
    _progressHandler = handler;
  }

  @override
  void setErrorHandler(BookNarrationErrorHandler? handler) {
    _errorHandler = handler;
  }

  @override
  Future<void> initialize({required double speed}) async {
    if (!_initialized) {
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.setVolume(1);
      await _flutterTts.setPitch(1);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          const [],
          IosTextToSpeechAudioMode.spokenAudio,
        );
      }
      _initialized = true;
    }
    await setSpeed(speed);
  }

  @override
  Future<void> setSpeed(double speed) async {
    // flutter_tts exposes a normalized 0…1 platform rate. In both supported
    // native readers, 0.5 is the natural system speaking rate.
    final platformRate = (speed * 0.5).clamp(0.25, 1.0).toDouble();
    await _flutterTts.setSpeechRate(platformRate);
  }

  @override
  Future<void> speak(String text) async {
    await _flutterTts.speak(text, focus: true);
  }

  @override
  Future<void> stop() async {
    await _flutterTts.stop();
  }

  @override
  Future<void> dispose() async {
    _progressHandler = null;
    _errorHandler = null;
    await stop();
  }
}

enum BookNarrationBlockKind { paragraph, heading, listItem, quote, code }

@immutable
class BookNarrationBlock {
  const BookNarrationBlock({
    required this.text,
    required this.kind,
    required this.firstSegmentIndex,
    required this.segmentCount,
    this.headingLevel = 0,
    this.listMarker,
  });

  final String text;
  final BookNarrationBlockKind kind;
  final int firstSegmentIndex;
  final int segmentCount;
  final int headingLevel;
  final String? listMarker;

  bool get containsSpeech => segmentCount > 0;
}

@immutable
class BookNarrationSegment {
  const BookNarrationSegment({
    required this.index,
    required this.blockIndex,
    required this.start,
    required this.end,
    required this.text,
  });

  final int index;
  final int blockIndex;
  final int start;
  final int end;
  final String text;
}

/// A speech-friendly view of the same Markdown used by the visual reader.
/// Segments are intentionally sentence-sized: this avoids native TTS input
/// limits and gives the UI a stable, precise unit to highlight and skip.
@immutable
class BookNarrationDocument {
  const BookNarrationDocument({required this.blocks, required this.segments});

  factory BookNarrationDocument.fromMarkdown(String markdown) {
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
    ).parse(markdown);
    final drafts = <_NarrationBlockDraft>[];

    void appendNode(md.Node node, {String? listMarker}) {
      if (node is md.Text) {
        final text = _readableText(node);
        if (text.isNotEmpty) {
          drafts.add(
            _NarrationBlockDraft(
              text: text,
              kind: BookNarrationBlockKind.paragraph,
            ),
          );
        }
        return;
      }
      if (node is! md.Element) return;

      switch (node.tag) {
        case 'hr':
          return;
        case 'ul':
        case 'ol':
          final ordered = node.tag == 'ol';
          var ordinal = int.tryParse(node.attributes['start'] ?? '') ?? 1;
          for (final child in node.children ?? const <md.Node>[]) {
            if (child is! md.Element || child.tag != 'li') continue;
            appendNode(child, listMarker: ordered ? '${ordinal++}.' : '•');
          }
          return;
        case 'li':
          final nestedLists = <md.Element>[];
          final visibleChildren = <md.Node>[];
          for (final child in node.children ?? const <md.Node>[]) {
            if (child is md.Element &&
                (child.tag == 'ul' || child.tag == 'ol')) {
              nestedLists.add(child);
            } else {
              visibleChildren.add(child);
            }
          }
          final text = _readableNodes(visibleChildren);
          if (text.isNotEmpty) {
            drafts.add(
              _NarrationBlockDraft(
                text: text,
                kind: BookNarrationBlockKind.listItem,
                listMarker: listMarker ?? '•',
              ),
            );
          }
          for (final nested in nestedLists) {
            appendNode(nested);
          }
          return;
        case 'blockquote':
          final text = _readableText(node);
          if (text.isNotEmpty) {
            drafts.add(
              _NarrationBlockDraft(
                text: text,
                kind: BookNarrationBlockKind.quote,
              ),
            );
          }
          return;
        case 'pre':
          final text = _readableText(node);
          if (text.isNotEmpty) {
            drafts.add(
              _NarrationBlockDraft(
                text: text,
                kind: BookNarrationBlockKind.code,
              ),
            );
          }
          return;
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          final text = _readableText(node);
          if (text.isNotEmpty) {
            drafts.add(
              _NarrationBlockDraft(
                text: text,
                kind: BookNarrationBlockKind.heading,
                headingLevel: int.parse(node.tag.substring(1)),
              ),
            );
          }
          return;
        case 'p':
          final text = _readableText(node);
          if (text.isNotEmpty) {
            drafts.add(
              _NarrationBlockDraft(
                text: text,
                kind: BookNarrationBlockKind.paragraph,
              ),
            );
          }
          return;
        default:
          final children = node.children ?? const <md.Node>[];
          final containsBlocks = children.any(
            (child) => child is md.Element && _blockTags.contains(child.tag),
          );
          if (containsBlocks) {
            for (final child in children) {
              appendNode(child);
            }
          } else {
            final text = _readableText(node);
            if (text.isNotEmpty) {
              drafts.add(
                _NarrationBlockDraft(
                  text: text,
                  kind: BookNarrationBlockKind.paragraph,
                ),
              );
            }
          }
      }
    }

    for (final node in nodes) {
      appendNode(node);
    }

    final blocks = <BookNarrationBlock>[];
    final segments = <BookNarrationSegment>[];
    for (var blockIndex = 0; blockIndex < drafts.length; blockIndex++) {
      final draft = drafts[blockIndex];
      final ranges = _sentenceRanges(draft.text);
      final firstSegment = segments.length;
      for (final range in ranges) {
        segments.add(
          BookNarrationSegment(
            index: segments.length,
            blockIndex: blockIndex,
            start: range.start,
            end: range.end,
            text: draft.text.substring(range.start, range.end),
          ),
        );
      }
      blocks.add(
        BookNarrationBlock(
          text: draft.text,
          kind: draft.kind,
          firstSegmentIndex: firstSegment,
          segmentCount: ranges.length,
          headingLevel: draft.headingLevel,
          listMarker: draft.listMarker,
        ),
      );
    }
    return BookNarrationDocument(blocks: blocks, segments: segments);
  }

  final List<BookNarrationBlock> blocks;
  final List<BookNarrationSegment> segments;
}

const _blockTags = <String>{
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'blockquote',
  'pre',
  'table',
};

String _readableText(md.Node node) => _readableNodes([node]);

String _readableNodes(List<md.Node> nodes) {
  final buffer = StringBuffer();

  void writeNode(md.Node node) {
    if (node is md.Text) {
      buffer.write(node.text);
      return;
    }
    if (node is! md.Element) return;
    if (node.tag == 'br') {
      buffer.write(' ');
      return;
    }
    if (node.tag == 'img') {
      buffer.write(node.attributes['alt'] ?? '');
      return;
    }
    final separatesText = const {
      'p',
      'div',
      'td',
      'th',
      'tr',
    }.contains(node.tag);
    if (separatesText && buffer.isNotEmpty) buffer.write(' ');
    for (final child in node.children ?? const <md.Node>[]) {
      writeNode(child);
    }
    if (separatesText) buffer.write(' ');
  }

  for (final node in nodes) {
    writeNode(node);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<_TextRange> _sentenceRanges(String text) {
  final ranges = <_TextRange>[];
  var start = 0;

  bool isTerminator(String character) => '.!?…。！？'.contains(character);
  bool isClosingMark(String character) => '”’"\')]}'.contains(character);

  bool isAbbreviation(int end) {
    final start = (end - 8).clamp(0, end).toInt();
    final prefix = text.substring(start, end).toLowerCase();
    return const [
      'e.g.',
      'i.e.',
      'mr.',
      'mrs.',
      'ms.',
      'dr.',
      'prof.',
      'vs.',
    ].any(prefix.endsWith);
  }

  void addRange(int rawStart, int rawEnd) {
    var rangeStart = rawStart;
    var rangeEnd = rawEnd;
    while (rangeStart < rangeEnd && _isWhitespace(text[rangeStart])) {
      rangeStart++;
    }
    while (rangeEnd > rangeStart && _isWhitespace(text[rangeEnd - 1])) {
      rangeEnd--;
    }
    if (rangeStart < rangeEnd) {
      ranges.add(_TextRange(rangeStart, rangeEnd));
    }
  }

  for (var index = 0; index < text.length; index++) {
    if (!isTerminator(text[index])) continue;
    var end = index + 1;
    while (end < text.length && isTerminator(text[end])) {
      end++;
    }
    while (end < text.length && isClosingMark(text[end])) {
      end++;
    }
    if (end < text.length && !_isWhitespace(text[end])) continue;
    if (end < text.length && isAbbreviation(end)) continue;
    addRange(start, end);
    start = end;
  }
  addRange(start, text.length);

  if (ranges.isEmpty && text.trim().isNotEmpty) {
    final first = text.indexOf(text.trimLeft());
    ranges.add(_TextRange(first, first + text.trim().length));
  }
  return ranges;
}

bool _isWhitespace(String character) => character.trim().isEmpty;

final class _NarrationBlockDraft {
  const _NarrationBlockDraft({
    required this.text,
    required this.kind,
    this.headingLevel = 0,
    this.listMarker,
  });

  final String text;
  final BookNarrationBlockKind kind;
  final int headingLevel;
  final String? listMarker;
}

final class _TextRange {
  const _TextRange(this.start, this.end);

  final int start;
  final int end;
}
