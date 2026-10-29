// Owner decision 1: the Record restores the account's synced wins from
// `GET /achievements` on sign-in and on a signed-in cold start.
//
// - Merged by `serverId`, never duplicated.
// - A legacy synced win without a `serverId` that matches a server
//   achievement (same title, same date) adopts its id.
// - New wins: synced, assessed, filed under the category's dimension (or
//   Practice), at the learner's age (Undated when unknown).
// - A failed fetch is silent and leaves the Record as it was.
// - Device-only notes are untouched.

import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/auth/models/me_models.dart';
import 'package:cmpys/features/cmpys/data/cmpys_record_data.dart';
import 'package:cmpys/features/cmpys/data/record_restore.dart';
import 'package:cmpys/features/cmpys/state/cmpys_backend_sync.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _savedAt = DateTime(2026, 10, 20, 10, 30);

ServerAchievement _ach(
  String id, {
  String title = 'Wrote the owner’s memo',
  String category = 'finance',
  String source = 'manual',
  String? notes,
  DateTime? createdAt,
  DateTime? achievementDate,
}) => ServerAchievement(
  id: id,
  title: title,
  category: category,
  source: source,
  notes: notes,
  createdAt: (createdAt ?? _savedAt).toUtc(),
  achievementDate: achievementDate,
);

/// A win as the Record stores it; a device win's id is `w` + the
/// microseconds it was saved at.
CmpysWin _win(
  String title, {
  DateTime? at,
  String? id,
  bool synced = true,
  String? serverId,
  String source = 'manual',
  String dim = 'capital',
  String? idolNote,
}) => CmpysWin(
  id: id ?? 'w${(at ?? _savedAt).microsecondsSinceEpoch}',
  title: title,
  dim: dim,
  age: 27,
  impact: 3,
  source: source,
  assessed: false,
  note: 'mine',
  idolNote: idolNote,
  synced: synced,
  serverId: serverId,
);

class _Plans extends Fake implements PlanRepository {
  _Plans(this.list);

  Future<List<ServerAchievement>> Function() list;
  int calls = 0;

  @override
  Future<List<ServerAchievement>> listAchievements({
    int pageSize = 200,
    int maxPages = 10,
  }) {
    calls++;
    return list();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('merge', () {
    test('a server achievement the Record lacks joins it, synced and '
        'assessed', () {
      final merged = mergeServerAchievements(const [], [
        _ach('a1', category: 'finance', source: 'plan_item'),
        _ach('a2', title: 'Shipped a demo', category: 'other', notes: 'Live'),
        _ach('a3', title: 'Met a founder', category: 'career'),
      ], age: 27)!;
      expect(merged, hasLength(3));
      final first = merged[0];
      expect(first.serverId, 'a1');
      expect(first.title, 'Wrote the owner’s memo');
      expect(first.synced, isTrue);
      expect(first.assessed, isTrue);
      expect(first.dim, 'capital');
      expect(first.age, 27);
      expect(first.source, 'auto'); // a mission's achievement
      expect(first.idolNote, isNull);
      expect(merged[1].dim, 'practice'); // `other` has no dimension
      expect(merged[1].source, 'manual');
      expect(merged[1].note, 'Live');
      expect(merged[2].dim, 'network');
      expect(merged.map((w) => w.id).toSet(), hasLength(3));
    });

    test('an unknown age files the win under Undated', () {
      expect(
        mergeServerAchievements(const [], [_ach('a1')], age: 0)!.single.age,
        0,
      );
      expect(
        mergeServerAchievements(const [], [_ach('a1')], age: -3)!.single.age,
        0,
      );
    });

    test('a win already on the Record (same serverId) is never duplicated or '
        'changed', () {
      final mine = _win('My wording', serverId: 'a1', idolNote: 'Good.');
      final merged = mergeServerAchievements([mine], [_ach('a1')], age: 27);
      expect(merged, isNull); // nothing to change
    });

    test('a legacy synced win with the same title and date adopts the id', () {
      final legacy = _win(' wrote the owner’s memo ');
      final merged = mergeServerAchievements([legacy], [_ach('a1')], age: 27)!;
      expect(merged, hasLength(1));
      final adopted = merged.single;
      expect(adopted.serverId, 'a1');
      // Everything else stays the learner's own.
      expect(adopted.id, legacy.id);
      expect(adopted.title, legacy.title);
      expect(adopted.note, 'mine');
      expect(adopted.impact, 3);
      expect(adopted.dim, 'capital');
      expect(adopted.assessed, isFalse);

      // The user's own date counts too.
      final dated = mergeServerAchievements(
        [_win('Wrote the owner’s memo', at: DateTime(2026, 9, 1, 8))],
        [_ach('a1', achievementDate: DateTime(2026, 9, 1))],
        age: 27,
      )!;
      expect(dated.single.serverId, 'a1');
    });

    test('a different date, a device-only win or a claimed legacy win is not '
        'adopted', () {
      final otherDay = _win(
        'Wrote the owner’s memo',
        at: _savedAt.subtract(const Duration(days: 3)),
      );
      final deviceOnly = _win(
        'Wrote the owner’s memo',
        id: 'w${_savedAt.microsecondsSinceEpoch + 1}',
        synced: false,
      );
      final merged = mergeServerAchievements(
        [otherDay, deviceOnly],
        [_ach('a1')],
        age: 27,
      )!;
      expect(merged, hasLength(3));
      expect(merged[0].serverId, isNull);
      expect(merged[1].serverId, isNull);
      expect(merged[2].serverId, 'a1');

      // One legacy win adopts one server achievement only.
      final twice = mergeServerAchievements(
        [_win('Wrote the owner’s memo')],
        [_ach('a1'), _ach('a2')],
        age: 27,
      )!;
      expect(twice.map((w) => w.serverId), ['a1', 'a2']);
      expect(twice, hasLength(2));
    });

    test('merging the same list again changes nothing', () {
      final server = [_ach('a1'), _ach('a2', title: 'Other')];
      final once = mergeServerAchievements([_win('Device')], server, age: 27)!;
      expect(mergeServerAchievements(once, server, age: 27), isNull);
    });
  });

  group('restore', () {
    late CmpysStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = CmpysStore();
      await store.openAccount('acct-a', unkeyedOwner: 'acct-a');
      store.updateUser(age: 27);
      store.addWin(title: 'Device win', dim: 'practice', age: 27);
      store.saveNote(kind: 'read', title: 'Device note', body: 'Kept');
    });

    // Each test's container owns the store and disposes it.

    ProviderContainer containerWith(
      _Plans plans, {
      String? accountId = 'acct-a',
    }) {
      final container = ProviderContainer(
        overrides: [
          cmpysStoreProvider.overrideWith((ref) => store),
          planRepositoryProvider.overrideWithValue(plans),
          cmpysBackendSyncProvider.overrideWith((ref) async {}),
          currentUserProvider.overrideWithValue(
            accountId == null
                ? null
                : Me(id: accountId, email: '$accountId@example.test'),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a signed-in account gets its server wins on the Record; notes are '
        'untouched', () async {
      final plans = _Plans(
        () async => [_ach('a1', source: 'plan_item'), _ach('a2', title: 'B')],
      );
      final container = containerWith(plans);
      await container.read(cmpysRecordRestoreProvider.future);

      expect(plans.calls, 1);
      final wins = store.state.achievements;
      expect(wins.map((w) => w.title), [
        'Device win',
        'Wrote the owner’s memo',
        'B',
      ]);
      expect(wins.where((w) => w.serverId == 'a1'), hasLength(1));
      expect(store.state.notes.single.title, 'Device note');
    });

    test('a failed fetch is silent and leaves the Record as it was', () async {
      final before = [...store.state.achievements];
      final plans = _Plans(() async => throw StateError('offline'));
      final container = containerWith(plans);
      await container.read(cmpysRecordRestoreProvider.future);

      expect(plans.calls, 1);
      expect(store.state.achievements, before);
      expect(store.state.notes.single.title, 'Device note');
    });

    test('signed out, nothing is fetched', () async {
      final plans = _Plans(() async => [_ach('a1')]);
      final container = containerWith(plans, accountId: null);
      await container.read(cmpysRecordRestoreProvider.future);
      expect(plans.calls, 0);
    });

    test(
      'wins fetched for another account never land on this Record',
      () async {
        final plans = _Plans(() async => [_ach('a1')]);
        // The session says account B while the store holds account A.
        final container = containerWith(plans, accountId: 'acct-b');
        await container.read(cmpysRecordRestoreProvider.future);
        expect(
          store.state.achievements.where((w) => w.serverId != null),
          isEmpty,
        );
      },
    );
  });
}
