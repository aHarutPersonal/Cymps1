import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/plan_item_detail_screen.dart';

/// Scripted repository: returns each queued result (value or error) in order,
/// repeating the last one when the queue runs out.
class _ScriptedRepo extends Fake implements PlanRepository {
  _ScriptedRepo(this._script);
  final List<Object> _script; // PlanItemDetailed | Exception
  int _calls = 0;

  @override
  Future<PlanItemDetailed> getPlanItemDetailed(String itemId) async {
    final step = _script[_calls.clamp(0, _script.length - 1)];
    _calls++;
    if (step is Exception) throw step;
    return step as PlanItemDetailed;
  }
}

PlanItemDetailed _pendingItem() => PlanItemDetailed(
      item: BackendPlanItem.fromJson(const {'id': 'x', 'title': 'Read a book'}),
      detailsStatus: 'pending',
    );

Widget _app(PlanRepository repo) => ProviderScope(
      overrides: [planRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: PlanItemDetailScreen(itemId: 'x')),
    );

void main() {
  testWidgets('network failure shows the connection error copy',
      (tester) async {
    await tester.pumpWidget(_app(_ScriptedRepo([const TimeoutError()])));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your connection'), findsOneWidget);
  });

  testWidgets('non-network failure shows a generic error, not connection copy',
      (tester) async {
    await tester.pumpWidget(
        _app(_ScriptedRepo([Exception('parse failure')])));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your connection'), findsNothing);
    expect(find.textContaining('Something went wrong'), findsOneWidget);
  });

  testWidgets('a failed background poll keeps the loaded content on screen',
      (tester) async {
    await tester
        .pumpWidget(_app(_ScriptedRepo([_pendingItem(), const TimeoutError()])));
    // Discrete pumps: the pending-details state animates a spinner, so
    // pumpAndSettle would never settle.
    await tester.pump();
    await tester.pump();
    expect(find.text('Read a book'), findsOneWidget);

    // First poll tick (4s) fails — content must survive, no error screen.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.text('Read a book'), findsOneWidget);
    expect(find.textContaining('Check your connection'), findsNothing);

    // Dispose the screen so the retry poll timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });
}
