import 'package:cmpys/features/cmpys/presentation/onboarding/discovery_step.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _DiscoveryRepo extends Fake implements SessionRepository {
  final queries = <String>[];
  int creations = 0;
  int abandons = 0;
  bool failSuggestions = false;

  @override
  Future<void> abandonCurrentSession() async {
    abandons++;
  }

  @override
  Future<Session> createSession(SessionCreateRequest request) async {
    creations++;
    return const Session(
      id: 'new-session',
      phase: SessionPhase.idolSelection,
      userAge: 24,
      userFinancialStatus: '',
      userInterests: ['investing'],
    );
  }

  @override
  Future<List<IdolSuggestion>> suggestIdols(String id) async {
    if (failSuggestions) throw StateError('unavailable');
    return [
      IdolSuggestion.fromJson({
        'name': 'John D. Rockefeller',
        'domains': ['business'],
        'confidence': 0.95,
      }),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> discoverMentors(String query) async {
    queries.add(query);
    return [
      {
        'name': 'Warren Buffett',
        'externalId': 'Q47213',
        'description': 'Investor',
        'occupations': ['investor'],
      },
    ];
  }
}

void main() {
  testWidgets('suggestion retry keeps the newly created session', (
    tester,
  ) async {
    final repo = _DiscoveryRepo()..failSuggestions = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: CmpysDiscoveryStep(
              age: 24,
              interests: const {'investing'},
              onPick: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.creations, 1);
    repo.failSuggestions = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(repo.creations, 1);
    expect(repo.abandons, 1);
    expect(find.text('John D. Rockefeller'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('search keeps the featured mentor when their name matches', (
    tester,
  ) async {
    final repo = _DiscoveryRepo();
    String? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: CmpysDiscoveryStep(
              age: 24,
              interests: const {'investing'},
              existingSessionId: 'session',
              onPick: (idol) => picked = idol.name,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Rockefeller');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('John D. Rockefeller').last);
    expect(picked, 'John D. Rockefeller');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('search finds a mentor outside the initial suggestions', (
    tester,
  ) async {
    final repo = _DiscoveryRepo();
    String? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: CmpysDiscoveryStep(
              age: 24,
              interests: const {'investing'},
              existingSessionId: 'session',
              onPick: (idol) => picked = idol.name,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('95%'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Warren Buffett');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(repo.queries, ['Warren Buffett']);
    expect(find.text('Warren Buffett'), findsWidgets);
    await tester.tap(find.text('Warren Buffett').last);
    expect(picked, 'Warren Buffett');
    await tester.pumpWidget(const SizedBox());
  });
}
