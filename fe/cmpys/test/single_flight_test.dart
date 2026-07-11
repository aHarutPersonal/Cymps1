import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/core/network/single_flight.dart';

void main() {
  test('concurrent callers share one operation', () async {
    final flight = SingleFlight<bool>();
    final completer = Completer<bool>();
    var calls = 0;

    Future<bool> operation() {
      calls++;
      return completer.future;
    }

    final first = flight.run(operation);
    final second = flight.run(operation);
    final third = flight.run(operation);

    expect(calls, 1);
    completer.complete(true);
    expect(await Future.wait([first, second, third]), [true, true, true]);
  });

  test('a new operation can start after completion', () async {
    final flight = SingleFlight<int>();
    var calls = 0;

    expect(await flight.run(() async => ++calls), 1);
    await Future<void>.delayed(Duration.zero);
    expect(await flight.run(() async => ++calls), 2);
  });
}
