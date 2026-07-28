import 'dart:async';

import 'package:cmpys/app/router.dart';
import 'package:cmpys/features/auth/presentation/splash_screen.dart';
import 'package:cmpys/features/plan/presentation/book_narration_checkpoint.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _checkpoint = BookNarrationCheckpoint(
  chapterIndex: 1,
  segmentIndex: 3,
  characterOffset: 47,
  updatedAtEpochMs: 1722000000000,
);

const _activeResume = ActiveBookNarrationResume(
  ownerId: 'account-a',
  resourceId: 'book-one',
  fallbackTitle: 'A Book & Its Ideas',
  branchIndex: ActiveBookNarrationResume.planBranchIndex,
  checkpoint: _checkpoint,
  wasPlaying: true,
  updatedAtEpochMs: 1722000000100,
);

final class _MemoryResumeStore implements ActiveBookNarrationResumeStore {
  _MemoryResumeStore(this.value, {this.failWrites = false});

  ActiveBookNarrationResume? value;
  final bool failWrites;
  int writes = 0;

  @override
  Future<void> clear(String ownerId) async {
    if (value?.ownerId == ownerId) value = null;
  }

  @override
  Future<ActiveBookNarrationResume?> read(String ownerId) async =>
      value?.ownerId == ownerId ? value : null;

  @override
  Future<void> write(ActiveBookNarrationResume value) async {
    writes += 1;
    if (failWrites) throw StateError('preference unavailable');
    this.value = value;
  }
}

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

  test('ready session defaults home when no active book exists', () {
    expect(
      splashRouteForReadySession(resume: null, isWeb: false),
      AppRoutes.home,
    );
  });

  test('router nests book readers in the Plan and Profile branches', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    addTearDown(router.dispose);
    final shell = router.configuration.routes
        .whereType<StatefulShellRoute>()
        .single;
    final planRoute = shell.branches[1].routes.single as GoRoute;
    final profileRoute = shell.branches[4].routes.single as GoRoute;

    expect(planRoute.path, AppRoutes.plan);
    expect(planRoute.routes.single, isA<GoRoute>());
    expect(
      (planRoute.routes.single as GoRoute).path,
      AppRoutes.bookRouteSegment,
    );
    expect(profileRoute.path, AppRoutes.profile);
    expect(profileRoute.routes.single, isA<GoRoute>());
    expect(
      (profileRoute.routes.single as GoRoute).path,
      AppRoutes.bookRouteSegment,
    );
  });

  test('native prior-playing session restores its nested Plan route', () {
    final location = splashRouteForReadySession(
      resume: _activeResume,
      isWeb: false,
    );
    final uri = Uri.parse(location);

    expect(uri.pathSegments, ['plan', 'book', 'book-one']);
    expect(uri.queryParameters['title'], 'A Book & Its Ideas');
    expect(uri.queryParameters['autoplay'], '1');
  });

  test('Profile resume uses its shell branch and web remains manual', () {
    final location = splashRouteForReadySession(
      resume: _activeResume.copyWith(
        branchIndex: ActiveBookNarrationResume.profileBranchIndex,
      ),
      isWeb: true,
    );
    final uri = Uri.parse(location);

    expect(uri.pathSegments, ['profile', 'book', 'book-one']);
    expect(uri.queryParameters['title'], 'A Book & Its Ideas');
    expect(uri.queryParameters.containsKey('autoplay'), isFalse);
  });

  test('paused native session restores at its checkpoint without autoplay', () {
    final location = splashRouteForReadySession(
      resume: _activeResume.copyWith(wasPlaying: false),
      isWeb: false,
    );

    expect(
      Uri.parse(location).queryParameters.containsKey('autoplay'),
      isFalse,
    );
  });

  test(
    'prior-playing signal is persisted as consumed before routing',
    () async {
      final store = _MemoryResumeStore(_activeResume);

      final restored = await consumeActiveBookNarrationResume(
        store: store,
        ownerId: 'account-a',
      );

      expect(restored, _activeResume);
      expect(restored!.wasPlaying, isTrue);
      expect(store.value!.wasPlaying, isFalse);
      expect(store.value!.checkpoint, _checkpoint);
      expect(store.writes, 1);

      final secondRestore = await consumeActiveBookNarrationResume(
        store: store,
        ownerId: 'account-a',
      );
      expect(secondRestore!.wasPlaying, isFalse);
      expect(store.writes, 1);
    },
  );

  test('failed one-shot write falls back to manual restoration', () async {
    final store = _MemoryResumeStore(_activeResume, failWrites: true);

    final restored = await consumeActiveBookNarrationResume(
      store: store,
      ownerId: 'account-a',
    );

    expect(restored, isNotNull);
    expect(restored!.wasPlaying, isFalse);
    expect(store.writes, 1);
  });
}
