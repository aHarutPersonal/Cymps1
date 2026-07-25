import 'dart:async';
import 'dart:collection';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:markdown/markdown.dart' as md;

import '../../session/data/content_resources_repository.dart';

typedef BookNarrationProgressHandler =
    void Function(int start, int end, String word);
typedef BookNarrationErrorHandler = void Function(Object error);
typedef BookNarrationVoiceHandler = void Function(BookNarrationVoiceKind voice);

enum BookNarrationStyle {
  expressive(
    apiName: 'expressive',
    label: 'Expressive',
    description: 'Dynamic pacing and emotion that follow the meaning.',
  ),
  warm(
    apiName: 'warm',
    label: 'Warm',
    description: 'Intimate, encouraging, and softly expressive.',
  ),
  grounded(
    apiName: 'grounded',
    label: 'Grounded',
    description: 'Thoughtful, calm, and naturally varied.',
  );

  const BookNarrationStyle({
    required this.apiName,
    required this.label,
    required this.description,
  });

  final String apiName;
  final String label;
  final String description;
}

enum BookNarrationVoiceKind { expressiveAi, device }

/// Optional capability used by the reader to prepare upcoming sentences while
/// the current one plays, avoiding mechanical gaps between clips.
abstract interface class BookNarrationPreloader {
  Future<void> prepare(String text);
}

/// Optional controls implemented by the adaptive production narrator. Keeping
/// this separate leaves small test and accessibility narrators simple.
abstract interface class BookNarrationStyleController {
  BookNarrationStyle get style;

  BookNarrationVoiceKind get voiceKind;

  void setVoiceHandler(BookNarrationVoiceHandler? handler);

  Future<void> setStyle(BookNarrationStyle style);
}

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

/// Human-style narration backed by cached speech audio and precise word cues.
final class ExpressiveBookNarrator
    implements BookNarrator, BookNarrationPreloader {
  ExpressiveBookNarrator({
    required ContentResourcesRepository repository,
    required String resourceId,
  }) : _repository = repository,
       _resourceId = resourceId;

  final ContentResourcesRepository _repository;
  final String _resourceId;
  final LinkedHashMap<String, Future<BookNarrationAudio>> _prepared =
      LinkedHashMap();
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSubscription;
  BookNarrationProgressHandler? _progressHandler;
  BookNarrationErrorHandler? _errorHandler;
  BookNarrationStyle _style = BookNarrationStyle.expressive;
  double _speed = 1;
  int _playRun = 0;
  int _lastCueStart = -1;

  BookNarrationStyle get style => _style;

  @override
  void setProgressHandler(BookNarrationProgressHandler? handler) {
    _progressHandler = handler;
  }

  @override
  void setErrorHandler(BookNarrationErrorHandler? handler) {
    _errorHandler = handler;
  }

  Future<void> setStyle(BookNarrationStyle style) async {
    if (_style == style) return;
    _style = style;
    await stop();
  }

  @override
  Future<void> initialize({required double speed}) async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());
    _player ??= AudioPlayer();
    await setSpeed(speed);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _player?.setSpeed(speed);
  }

  @override
  Future<void> prepare(String text) async {
    await _load(text);
  }

  Future<BookNarrationAudio> _load(String text) {
    final key = '${_style.apiName}\u0000$text';
    final existing = _prepared.remove(key);
    if (existing != null) {
      _prepared[key] = existing;
      return existing;
    }
    if (_prepared.length >= 12) {
      _prepared.remove(_prepared.keys.first);
    }

    late final Future<BookNarrationAudio> request;
    request = () async {
      try {
        return await _repository.prepareNarration(
          _resourceId,
          text: text,
          style: _style.apiName,
        );
      } catch (_) {
        if (identical(_prepared[key], request)) _prepared.remove(key);
        rethrow;
      }
    }();
    _prepared[key] = request;
    return request;
  }

  @override
  Future<void> speak(String text) async {
    if (_player == null) await initialize(speed: _speed);
    final run = ++_playRun;
    _lastCueStart = -1;
    try {
      final audio = await _load(text);
      if (run != _playRun) return;
      final player = _player!;
      final loadedDuration = await player.setUrl(audio.audioUri.toString());
      if (run != _playRun) return;
      await player.setSpeed(_speed);
      final duration = loadedDuration ?? audio.duration ?? player.duration;
      await _positionSubscription?.cancel();
      _positionSubscription = player
          .createPositionStream(
            minPeriod: const Duration(milliseconds: 45),
            maxPeriod: const Duration(milliseconds: 100),
          )
          .listen((position) {
            if (run != _playRun) return;
            _emitProgress(
              text: text,
              position: position,
              duration: duration,
              alignment: audio.alignment,
            );
          });
      _emitProgress(
        text: text,
        position: Duration.zero,
        duration: duration,
        alignment: audio.alignment,
      );
      await player.play();
    } catch (error) {
      // An adaptive narrator suppresses this handler while it transparently
      // switches to the device voice. Direct consumers still receive it.
      _errorHandler?.call(error);
      rethrow;
    } finally {
      if (run == _playRun) {
        await _positionSubscription?.cancel();
        _positionSubscription = null;
      }
    }
  }

  void _emitProgress({
    required String text,
    required Duration position,
    required Duration? duration,
    required List<BookNarrationCue> alignment,
  }) {
    final cue = alignment.isNotEmpty
        ? _alignedCue(alignment, position)
        : _estimatedCue(text, position, duration);
    if (cue == null || cue.start == _lastCueStart) return;
    _lastCueStart = cue.start;
    _progressHandler?.call(
      cue.start,
      cue.end,
      text.substring(cue.start, cue.end),
    );
  }

  _LocalNarrationCue? _alignedCue(
    List<BookNarrationCue> alignment,
    Duration position,
  ) {
    var low = 0;
    var high = alignment.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final cue = alignment[middle];
      if (position < cue.startTime) {
        high = middle - 1;
      } else if (position >= cue.endTime) {
        low = middle + 1;
      } else {
        return _LocalNarrationCue(cue.start, cue.end);
      }
    }
    final nearest = (high < 0 ? 0 : high)
        .clamp(0, alignment.length - 1)
        .toInt();
    final cue = alignment[nearest];
    return _LocalNarrationCue(cue.start, cue.end);
  }

  _LocalNarrationCue? _estimatedCue(
    String text,
    Duration position,
    Duration? duration,
  ) {
    if (duration == null || duration <= Duration.zero) return null;
    final words = RegExp(r'\S+').allMatches(text).toList(growable: false);
    if (words.isEmpty) return null;
    final total = duration.inMicroseconds;
    final current = position.inMicroseconds.clamp(0, total);
    var totalWeight = 0;
    final weights = <int>[];
    for (final word in words) {
      final value = word.group(0)!;
      var weight = value.length.clamp(1, 14);
      if (RegExp(r'[,;:]$').hasMatch(value)) weight += 3;
      if (RegExp(r'[.!?]$').hasMatch(value)) weight += 6;
      weights.add(weight);
      totalWeight += weight;
    }
    var elapsedWeight = 0;
    for (var index = 0; index < words.length; index++) {
      elapsedWeight += weights[index];
      if (current * totalWeight <= total * elapsedWeight) {
        return _LocalNarrationCue(words[index].start, words[index].end);
      }
    }
    return _LocalNarrationCue(words.last.start, words.last.end);
  }

  @override
  Future<void> stop() async {
    _playRun++;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    _progressHandler = null;
    _errorHandler = null;
    await stop();
    await _player?.dispose();
    _player = null;
  }
}

/// Uses expressive narration whenever the network/provider is available and
/// silently preserves listening with the installed device voice otherwise.
final class AdaptiveBookNarrator
    implements
        BookNarrator,
        BookNarrationPreloader,
        BookNarrationStyleController {
  AdaptiveBookNarrator({
    required ExpressiveBookNarrator expressive,
    required SystemBookNarrator device,
  }) : _expressive = expressive,
       _device = device {
    _expressive.setProgressHandler((start, end, word) {
      if (!_usingDevice) _progressHandler?.call(start, end, word);
    });
    _device.setProgressHandler((start, end, word) {
      if (_usingDevice) _progressHandler?.call(start, end, word);
    });
    // Primary errors are handled by switching sources in speak().
    _expressive.setErrorHandler(null);
    _device.setErrorHandler((error) => _errorHandler?.call(error));
  }

  final ExpressiveBookNarrator _expressive;
  final SystemBookNarrator _device;
  BookNarrationProgressHandler? _progressHandler;
  BookNarrationErrorHandler? _errorHandler;
  BookNarrationVoiceHandler? _voiceHandler;
  bool _usingDevice = false;
  bool _expressiveReady = false;
  bool _deviceReady = false;
  double _speed = 1;

  @override
  BookNarrationStyle get style => _expressive.style;

  @override
  BookNarrationVoiceKind get voiceKind => _usingDevice
      ? BookNarrationVoiceKind.device
      : BookNarrationVoiceKind.expressiveAi;

  @override
  void setProgressHandler(BookNarrationProgressHandler? handler) {
    _progressHandler = handler;
  }

  @override
  void setErrorHandler(BookNarrationErrorHandler? handler) {
    _errorHandler = handler;
  }

  @override
  void setVoiceHandler(BookNarrationVoiceHandler? handler) {
    _voiceHandler = handler;
  }

  @override
  Future<void> initialize({required double speed}) async {
    _speed = speed;
    try {
      await _expressive.initialize(speed: speed);
      _expressiveReady = true;
    } catch (_) {
      await _switchToDevice();
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (_expressiveReady) await _expressive.setSpeed(speed);
    if (_deviceReady) await _device.setSpeed(speed);
  }

  @override
  Future<void> setStyle(BookNarrationStyle style) async {
    await _expressive.setStyle(style);
    if (_usingDevice) {
      _usingDevice = false;
      _voiceHandler?.call(voiceKind);
    }
  }

  @override
  Future<void> prepare(String text) async {
    if (_usingDevice) return;
    try {
      await _expressive.prepare(text);
    } catch (_) {
      // speak() performs the visible, deterministic fallback. A speculative
      // prefetch failure should not interrupt the sentence already playing.
    }
  }

  @override
  Future<void> speak(String text) async {
    if (!_usingDevice) {
      try {
        if (!_expressiveReady) {
          await _expressive.initialize(speed: _speed);
          _expressiveReady = true;
        }
        await _expressive.speak(text);
        return;
      } catch (_) {
        await _expressive.stop();
        await _switchToDevice();
      }
    }
    await _device.speak(text);
  }

  Future<void> _switchToDevice() async {
    if (!_deviceReady) {
      await _device.initialize(speed: _speed);
      _deviceReady = true;
    }
    if (!_usingDevice) {
      _usingDevice = true;
      _voiceHandler?.call(voiceKind);
    }
  }

  @override
  Future<void> stop() async {
    await Future.wait<void>([_expressive.stop(), _device.stop()]);
  }

  @override
  Future<void> dispose() async {
    _progressHandler = null;
    _errorHandler = null;
    _voiceHandler = null;
    await Future.wait<void>([_expressive.dispose(), _device.dispose()]);
  }
}

final class _LocalNarrationCue {
  const _LocalNarrationCue(this.start, this.end);

  final int start;
  final int end;
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
