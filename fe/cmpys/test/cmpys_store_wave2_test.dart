// Fix wave 2 (final review 3): the device store.
//
// - R3-M8: a store that fails to load is backed up before anything is
//   written over it, and one malformed list item never loses the rest.
// - R3-I2: a synced win remembers its server achievement id (`serverId`).
// - R3-M5: a note remembers when it was saved (`at`).
// - R3-M1: a new onboarding session never shows the last one's milestones
//   or written comparison.
// - R3-M7: no canned mentor line under a win the mentor never wrote.
// - Every older stored payload (no `serverId`, no `at`) still loads.

import 'dart:convert';

import 'package:cmpys/features/cmpys/data/cmpys_record_data.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A store exactly as an older build wrote it: wins without `serverId`, a
/// note without `at`, v2 dimension ids, settings without reader fields.
final _legacyJson = {
  'user': {'name': 'Ana', 'age': 27, 'interests': ['Investing']},
  'idol': {'id': 'buffett', 'name': 'Warren Buffett'},
  'tasks': {'t1': true},
  'milestones': {'m1': true},
  'achievements': [
    {
      'id': 'w-old',
      'title': 'Opened a brokerage account',
      'dim': 'habits',
      'age': 22,
      'impact': 2,
      'source': 'manual',
      'assessed': true,
      'idolNote': 'Good.',
    },
    {
      'id': 'w-synced',
      'title': 'Wrote my own analysis',
      'dim': 'judgment',
      'age': 26,
      'source': 'manual',
      'synced': true,
    },
  ],
  'streak': 3,
  'dayNum': 9,
  'notes': [
    {
      'id': 'n-old',
      'kind': 'chat',
      'title': 'Buffett · Chat',
      'body': 'Margin of safety.',
      'from': 'Buffett',
      'when': 'Just now',
    },
  ],
  'saved': [
    {'id': 'q1', 'kind': 'idea', 'title': 'Be fearful', 'sub': 'Buffett'},
  ],
  'custom': [
    {'id': 'c1', 'title': 'Read one 10-K'},
  ],
  'ideaState': {
    'q1': {'liked': true, 'saved': true, 'comments': []},
  },
  'settings': {'reminder': false, 'mentorPing': true, 'digest': true},
  'sessionId': 'session-1',
  'comparisonMd': 'Old comparison',
  'blueprintMd': 'Old blueprint',
};

Session _session(
  String id, {
  String? comparison = 'Generated verdict',
  String? blueprint = 'Generated blueprint',
}) => Session(
  id: id,
  phase: SessionPhase.completed,
  userAge: 24,
  userFinancialStatus: '',
  userInterests: const [],
  selectedIdol: const SelectedIdolInfo(id: 'idol-1', name: 'Great'),
  comparisonOutput: comparison,
  blueprintOutput: blueprint,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('R3-M8 store load hardening', () {
    test('an older store without the new fields loads in full', () async {
      // Unkeyed, as an older build wrote it: it migrates to the account.
      SharedPreferences.setMockInitialValues({
        'cmpys_store_v1': jsonEncode(_legacyJson),
      });
      final store = CmpysStore();
      await store.openAccount('acct', unkeyedOwner: 'acct');
      await store.ready;
      final st = store.state;
      expect(st.user.name, 'Ana');
      expect(st.achievements.map((w) => w.id), ['w-old', 'w-synced']);
      expect(st.achievements.first.serverId, isNull);
      expect(st.achievements.first.dim, 'habits');
      expect(st.achievements.last.synced, isTrue);
      expect(st.achievements.last.serverId, isNull);
      expect(st.notes.single.at, isNull);
      expect(st.notes.single.when, 'Just now');
      expect(st.saved.single.id, 'q1');
      expect(st.custom.single.title, 'Read one 10-K');
      expect(st.ideaState['q1']?.liked, isTrue);
      expect(st.settings.reminder, isFalse);
      expect(st.sessionId, 'session-1');
      // A clean load keeps no backup.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cmpys_store_v1:acct.bak'), isNull);
      store.dispose();
    });

    test('one malformed item is skipped and the rest of the list loads', () {
      final json = Map<String, dynamic>.from(_legacyJson)
        ..['achievements'] = [
          {'title': 'No id'},
          {'id': 'w-bad', 'title': 42, 'dim': 7, 'source': false},
          'not a map',
          (_legacyJson['achievements'] as List).first,
        ]
        ..['notes'] = [
          {'kind': 'chat', 'body': 'No id'},
          {'id': 'n-bad', 'title': 3, 'body': null, 'when': 12},
          (_legacyJson['notes'] as List).single,
        ]
        ..['saved'] = [
          {'kind': 'idea'},
          (_legacyJson['saved'] as List).single,
        ]
        ..['custom'] = [
          {'title': 'no id'},
          (_legacyJson['custom'] as List).single,
        ]
        ..['ideaState'] = {
          'q0': 'broken',
          'q1': {'liked': 'yes', 'comments': 'none'},
        };
      final st = CmpysState.fromJson(json);
      // A wrong-typed field reads as its default; a win without an id is
      // dropped.
      expect(st.achievements.map((w) => w.id), ['w-bad', 'w-old']);
      expect(st.achievements.first.title, '');
      expect(st.achievements.first.dim, 'knowledge');
      expect(st.achievements.first.source, 'manual');
      expect(st.notes.map((n) => n.id), ['n-bad', 'n-old']);
      expect(st.notes.first.title, '');
      expect(st.notes.first.body, '');
      expect(st.saved.map((s) => s.id), ['q1']);
      expect(st.custom.map((c) => c.id), ['c1']);
      expect(st.ideaState.keys, ['q1']);
      expect(st.ideaState['q1']!.liked, isFalse);
      expect(st.ideaState['q1']!.comments, isEmpty);
      expect(st.user.name, 'Ana');
    });

    test('a store that cannot be read is backed up before any write', () async {
      const raw = '{"user": {"name": "Ana"}, "notes": [';
      SharedPreferences.setMockInitialValues({'cmpys_store_v1:acct': raw});
      final store = CmpysStore();
      final opening = store.openAccount('acct', unkeyedOwner: 'acct');
      // A mutation right away schedules a write over the unreadable store.
      store.saveNote(kind: 'chat', title: 'T', body: 'B');
      await opening;
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cmpys_store_v1:acct.bak'), raw);
      // The persist that follows never overwrites the backup.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(prefs.getString('cmpys_store_v1:acct.bak'), raw);
      expect(prefs.getString('cmpys_store_v1:acct'), isNot(raw));
      store.dispose();
    });

    test('a store whose items had to be dropped is backed up too', () async {
      final json = Map<String, dynamic>.from(_legacyJson)
        ..['notes'] = [
          {'kind': 'chat', 'body': 'No id'},
        ];
      final raw = jsonEncode(json);
      SharedPreferences.setMockInitialValues({'cmpys_store_v1:acct': raw});
      final store = CmpysStore();
      await store.openAccount('acct', unkeyedOwner: 'acct');
      expect(store.state.user.name, 'Ana');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cmpys_store_v1:acct.bak'), raw);
      store.dispose();
    });
  });

  test('logging out clears the backup with the store (account isolation)',
      () async {
    SharedPreferences.setMockInitialValues({
      'cmpys_store_v1:acct': '{"notes": [',
    });
    final store = CmpysStore();
    await store.openAccount('acct', unkeyedOwner: 'acct');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cmpys_store_v1:acct.bak'), isNotNull);
    await store.reset();
    expect(prefs.getString('cmpys_store_v1:acct.bak'), isNull);
    expect(prefs.getString('cmpys_store_v1:acct'), isNull);
    store.dispose();
  });

  group('R3-I2 server achievement id', () {
    test('a synced win keeps its server id through a save and reload', () {
      final store = CmpysStore();
      final id = store.addWin(
        title: 'Wrote the owner’s memo',
        dim: 'capital',
        age: 24,
        source: 'auto',
        assessed: true,
        synced: true,
        serverId: 'ach-1',
      );
      final win = store.state.achievements.singleWhere((w) => w.id == id);
      expect(win.serverId, 'ach-1');
      final reloaded = CmpysState.fromJson(
        jsonDecode(jsonEncode(store.state.toJson())) as Map<String, dynamic>,
      );
      expect(reloaded.achievements.single.serverId, 'ach-1');
      expect(reloaded.achievements.single.copyWith(note: 'x').serverId, 'ach-1');
      store.dispose();
    });

    test('the same server achievement saved again replaces its win', () {
      // A mission achievement is upserted on the server (same id), so the
      // Record keeps one entry for it.
      final store = CmpysStore();
      final first = store.addWin(
        title: 'First wording',
        dim: 'practice',
        age: 24,
        source: 'auto',
        assessed: true,
        synced: true,
        serverId: 'ach-1',
      );
      final second = store.addWin(
        title: 'Second wording',
        dim: 'capital',
        age: 24,
        source: 'auto',
        assessed: true,
        synced: true,
        serverId: 'ach-1',
      );
      expect(second, first);
      expect(store.state.achievements.single.title, 'Second wording');
      expect(store.state.achievements.single.dim, 'capital');
      store.dispose();
    });
  });

  group('R3-M5 note timestamps', () {
    test('a saved note records when it was saved', () {
      final store = CmpysStore();
      final before = DateTime.now().millisecondsSinceEpoch;
      store.saveNote(kind: 'chat', title: 'Buffett · Chat', body: 'Body');
      final at = store.state.notes.single.at;
      expect(at, isNotNull);
      expect(at!, greaterThanOrEqualTo(before));
      final reloaded = CmpysState.fromJson(
        jsonDecode(jsonEncode(store.state.toJson())) as Map<String, dynamic>,
      );
      expect(reloaded.notes.single.at, at);
      store.dispose();
    });
  });

  group('R3-M1 session switch', () {
    test('a new session drops the old milestones and written comparison', () {
      final store = CmpysStore();
      store.syncFromSession(_session('first'));
      store.claimMilestone('m1', 'Read 100 annual reports', age: 24);
      expect(store.state.milestones, {'m1': true});
      expect(store.state.comparisonMd, 'Generated verdict');

      // The new session's results aren't written yet: nothing from the old
      // one may stand in for them.
      store.syncFromSession(_session('second', comparison: '', blueprint: null));
      expect(store.state.sessionId, 'second');
      expect(store.state.milestones, isEmpty);
      expect(store.state.comparisonMd, isNull);
      expect(store.state.blueprintMd, isNull);

      // Once they are written, they show.
      store.syncFromSession(_session('second', comparison: 'New verdict'));
      expect(store.state.comparisonMd, 'New verdict');
      expect(store.state.blueprintMd, 'Generated blueprint');
      store.dispose();
    });

    test('the first sync and a re-sync of the same session keep local data', () {
      final store = CmpysStore();
      store.syncFromSession(_session('first'));
      store.claimMilestone('m1', 'Read 100 annual reports', age: 24);
      // The same session with its texts momentarily missing keeps them.
      store.syncFromSession(_session('first', comparison: null, blueprint: ''));
      expect(store.state.milestones, {'m1': true});
      expect(store.state.comparisonMd, 'Generated verdict');
      expect(store.state.blueprintMd, 'Generated blueprint');
      store.dispose();
    });
  });

  group('R3-M7 no canned mentor notes', () {
    test('only a chat win starts with a mentor line', () {
      final store = CmpysStore();
      for (final source in ['manual', 'auto', 'intake']) {
        final id = store.addWin(
          title: 'Wrote my own analysis',
          dim: 'judgment',
          age: 24,
          source: source,
        );
        expect(
          store.state.achievements.singleWhere((w) => w.id == id).idolNote,
          isNull,
          reason: source,
        );
      }
      final chat = store.addWin(
        title: 'Asked an expert a question',
        dim: 'network',
        age: 24,
        source: 'chat',
      );
      expect(
        store.state.achievements.singleWhere((w) => w.id == chat).idolNote,
        idolReaction('network', 'Asked an expert a question'),
      );
      store.claimMilestone('m2', 'Started a partnership', age: 24);
      expect(
        store.state.achievements.singleWhere((w) => w.source == 'milestone')
            .idolNote,
        isNull,
      );
      store.dispose();
    });
  });
}
