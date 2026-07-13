import 'dart:convert';
import 'dart:typed_data';

import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseSseEvents preserves events split across byte chunks', () async {
    final chunks = <List<int>>[
      utf8.encode('data: {"type":"chunk","content":"Hel'),
      utf8.encode('lo"}\n\ndata: {"type":"done","turn":1}\n\n'),
    ];

    final events = await parseSseEvents(Stream.fromIterable(chunks)).toList();

    expect(events, [
      {'type': 'chunk', 'content': 'Hello'},
      {'type': 'done', 'turn': 1},
    ]);
  });

  test(
    'parseSseEvents preserves utf8 characters split across chunks',
    () async {
      final bytes = utf8.encode('data: {"type":"chunk","content":"Hi ✨"}\n\n');
      final chunks = <List<int>>[
        bytes.sublist(0, bytes.length - 2),
        bytes.sublist(bytes.length - 2),
      ];

      final events = await parseSseEvents(Stream.fromIterable(chunks)).toList();

      expect(events.single, {'type': 'chunk', 'content': 'Hi ✨'});
    },
  );

  test('parseSseEvents accepts Dio Uint8List stream chunks', () async {
    final chunks = <Uint8List>[
      Uint8List.fromList(
        utf8.encode('data: {"type":"chunk","content":"OK"}\n\n'),
      ),
    ];

    final events = await parseSseEvents(Stream.fromIterable(chunks)).toList();

    expect(events.single, {'type': 'chunk', 'content': 'OK'});
  });

  test('parseSseEvents reassembles a 3-way byte split of one event', () async {
    final bytes = utf8.encode('data: {"type":"chunk","content":"abcdef"}\n\n');
    final third = bytes.length ~/ 3;
    final chunks = <List<int>>[
      bytes.sublist(0, third),
      bytes.sublist(third, 2 * third),
      bytes.sublist(2 * third),
    ];

    final events = await parseSseEvents(Stream.fromIterable(chunks)).toList();

    expect(events.single, {'type': 'chunk', 'content': 'abcdef'});
  });

  test(
    'parseSseEvents skips a malformed data line without dropping valid ones',
    () async {
      final chunks = <List<int>>[
        utf8.encode('data: not-json\n\n'),
        utf8.encode('data: {"type":"chunk","content":"valid"}\n\n'),
      ];

      final events = await parseSseEvents(Stream.fromIterable(chunks)).toList();

      expect(events.single, {'type': 'chunk', 'content': 'valid'});
    },
  );

  test(
    'parseSseEvents handles an em-dash split across the chunk boundary',
    () async {
      // "—" is 3 UTF-8 bytes (e2 80 94); split it down the middle.
      final bytes = utf8.encode('data: {"type":"chunk","content":"a—b"}\n\n');
      final emDashStart = utf8
          .encode('data: {"type":"chunk","content":"a')
          .length;
      final chunks = <List<int>>[
        bytes.sublist(0, emDashStart + 1), // first byte of the em-dash
        bytes.sublist(emDashStart + 1), // remaining two bytes + rest
      ];

      final events = await parseSseEvents(Stream.fromIterable(chunks)).toList();

      expect(events.single, {'type': 'chunk', 'content': 'a—b'});
    },
  );

  test(
    'completed SSE stops at done without waiting for transport EOF',
    () async {
      Stream<List<int>> completedThenBroken() async* {
        yield utf8.encode(
          'data: {"type":"chunk","content":"Complete"}\n\n'
          'data: {"type":"done"}\n\n',
        );
        throw StateError('socket reset after completion');
      }

      final events = await parseCompletedSseEvents(
        completedThenBroken(),
      ).toList();

      expect(events, [
        {'type': 'chunk', 'content': 'Complete'},
        {'type': 'done'},
      ]);
    },
  );

  test(
    'completed SSE rejects a stream that ends without a terminal event',
    () async {
      final stream = Stream<List<int>>.value(
        utf8.encode('data: {"type":"chunk","content":"Partial"}\n\n'),
      );

      expect(
        parseCompletedSseEvents(stream).toList(),
        throwsA(isA<SseIncompleteException>()),
      );
    },
  );
}
