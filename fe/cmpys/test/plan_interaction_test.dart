import 'dart:async';

import 'package:cmpys/features/cmpys/presentation/plan_screen.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repository extends Fake implements PlanRepository {
  @override
  Future<BackendPlan?> getCurrentPlan() async => null;
  int calls = 0;
  final pending = Completer<bool>();
  @override
  Future<bool> toggleDailyTask(String itemId) {
    calls++;
    return pending.future;
  }
}

class _Plan extends CurrentPlanController {
  @override
  Future<void> refresh() async {}

  _Plan(PlanRepository repo) : super(repo: repo, readJobId: () => null) {
    state = CurrentPlanState(
      status: CurrentPlanStatus.ready,
      plan: BackendPlan(
        id: 'p',
        durationWeeks: 2,
        weeklyHours: 4,
        overallProgress: 0,
        items: const [],
      ),
    );
  }
}

const today = TodayView(
  items: [
    TodayTaskItem(
      id: 'habit',
      title: 'Reflect on your day',
      type: 'habit',
      estimatedHours: 1,
      completedToday: false,
    ),
  ],
  streak: 0,
  completedToday: 0,
  totalToday: 1,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'daily habits error offers retry instead of an endless skeleton',
    (tester) async {
      var loads = 0;
      final repo = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentPlanProvider.overrideWith((_) => _Plan(repo)),
            todayViewProvider.overrideWith((_) async {
              if (++loads == 1) throw StateError('offline');
              return today;
            }),
          ],
          child: const MaterialApp(home: CmpysPlanScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily habits'));
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load your daily habits.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Reflect on your day'), findsOneWidget);
      expect(loads, 2);
    },
  );

  testWidgets('rapid daily habit taps send only one pending change', (
    tester,
  ) async {
    final repo = _Repository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWithValue(repo),
          currentPlanProvider.overrideWith((_) => _Plan(repo)),
          todayViewProvider.overrideWith((_) async => today),
        ],
        child: const MaterialApp(home: CmpysPlanScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily habits'));
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('toggle-daily-habit'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
    expect(repo.calls, 1);
    repo.pending.complete(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
