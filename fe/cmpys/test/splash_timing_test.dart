import 'dart:async';

import 'package:cmpys/features/auth/presentation/splash_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first visit keeps the brand sequence and return visits are short', () {
    expect(
      splashMinimumForVisit(hasSeenSplash: false),
      splashFirstVisitMinimum,
    );
    expect(
      splashMinimumForVisit(hasSeenSplash: true),
      splashReturningVisitMinimum,
    );
    expect(splashReturningVisitMinimum, const Duration(milliseconds: 600));
    expect(splashFirstVisitMinimum, greaterThan(splashReturningVisitMinimum));
  });

  test('preference lookup time is deducted from the minimum', () {
    expect(
      splashRemainingDelay(
        hasSeenSplash: true,
        elapsed: const Duration(milliseconds: 250),
      ),
      const Duration(milliseconds: 350),
    );
    expect(
      splashRemainingDelay(
        hasSeenSplash: true,
        elapsed: const Duration(seconds: 1),
      ),
      Duration.zero,
    );
  });

  test('splash gate waits for initialization and delay in parallel', () async {
    final initialization = Completer<void>();
    final delay = Completer<void>();
    Duration? requestedDelay;
    var completed = false;

    final gate = waitForSplashGate(
      initialization: initialization.future,
      minimumDelay: splashReturningVisitMinimum,
      delay: (duration) {
        requestedDelay = duration;
        return delay.future;
      },
    )..then((_) => completed = true);

    await pumpEventQueue();
    expect(requestedDelay, splashReturningVisitMinimum);
    expect(completed, isFalse);

    delay.complete();
    await pumpEventQueue();
    expect(completed, isFalse);

    initialization.complete();
    await gate;
    expect(completed, isTrue);
  });
}
