// Owner decision 2: the device store is kept per account.
//
// - The store (`cmpys_store_v1`) and its `.bak` are keyed by the signed-in
//   account id.
// - An unkeyed store from an older build migrates once, to its owner (the
//   first account that signs in, or the account that was signed in).
// - Switching accounts loads the other account's data; nothing leaks.
// - Closing (an involuntary sign-out) keeps the account's data on the
//   device; reset (a deliberate logout) clears only that account's data.

import 'dart:convert';

import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _stored({String name = 'Ana', String note = 'Mine'}) => {
  'user': {'name': name, 'age': 27},
  'notes': [
    {'id': 'n1', 'kind': 'read', 'title': note, 'body': 'Body'},
  ],
};

Future<Map<String, dynamic>?> _read(String key) async {
  final raw = (await SharedPreferences.getInstance()).getString(key);
  return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 400));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the store keys are per account', () {
    expect(cmpysStoreKeyFor('acct-1'), 'cmpys_store_v1:acct-1');
    expect(cmpysStoreBackupKeyFor('acct-1'), 'cmpys_store_v1:acct-1.bak');
  });

  group('migration of the unkeyed store', () {
    test(
      'moves once to the first account that signs in, with its backup',
      () async {
        SharedPreferences.setMockInitialValues({
          'cmpys_store_v1': jsonEncode(_stored()),
          'cmpys_store_v1.bak': 'older backup',
        });
        final store = CmpysStore();
        await store.openAccount('a', unkeyedOwner: 'a');
        expect(store.state.user.name, 'Ana');
        expect(store.state.notes.single.title, 'Mine');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('cmpys_store_v1'), isNull);
        expect(prefs.getString('cmpys_store_v1.bak'), isNull);
        expect((await _read('cmpys_store_v1:a'))?['user']['name'], 'Ana');
        expect(prefs.getString('cmpys_store_v1:a.bak'), 'older backup');

        // Once: a second account finds nothing to adopt.
        await store.openAccount('b', unkeyedOwner: 'b');
        expect(store.state.user.name, isEmpty);
        expect(store.state.notes, isEmpty);
        expect(prefs.getString('cmpys_store_v1:b'), isNull);
        store.dispose();
      },
    );

    test('goes to the account that owned it, not the one signing in', () async {
      SharedPreferences.setMockInitialValues({
        'cmpys_store_v1': jsonEncode(_stored()),
      });
      final store = CmpysStore();
      await store.openAccount('b', unkeyedOwner: 'a');
      expect(store.state.notes, isEmpty);
      expect(store.state.user.name, isEmpty);
      expect((await _read('cmpys_store_v1:a'))?['user']['name'], 'Ana');

      await store.openAccount('a', unkeyedOwner: 'a');
      expect(store.state.notes.single.title, 'Mine');
      store.dispose();
    });

    test('with no owner (a new registration) it is not adopted', () async {
      SharedPreferences.setMockInitialValues({
        'cmpys_store_v1': jsonEncode(_stored()),
      });
      final store = CmpysStore();
      await store.openAccount('new', unkeyedOwner: null);
      expect(store.state.notes, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cmpys_store_v1'), isNull);
      expect(prefs.getString('cmpys_store_v1:new'), isNull);
      store.dispose();
    });

    test('never overwrites an account that already has keyed data', () async {
      SharedPreferences.setMockInitialValues({
        'cmpys_store_v1': jsonEncode(_stored(note: 'Stale')),
        'cmpys_store_v1:a': jsonEncode(_stored(note: 'Current')),
      });
      final store = CmpysStore();
      await store.openAccount('a', unkeyedOwner: 'a');
      expect(store.state.notes.single.title, 'Current');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cmpys_store_v1'), isNull);
      store.dispose();
    });
  });

  group('account isolation', () {
    test(
      'switching accounts loads the other account and nothing leaks',
      () async {
        final store = CmpysStore();
        await store.openAccount('a', unkeyedOwner: 'a');
        store.saveNote(kind: 'read', title: 'A’s note', body: 'Private');
        store.updateUser(name: 'Ana');
        await _settle();

        await store.openAccount('b', unkeyedOwner: 'a');
        expect(store.state.notes, isEmpty);
        expect(store.state.user.name, isEmpty);
        store.addWin(title: 'B’s win', dim: 'practice', age: 30);
        await _settle();

        await store.openAccount('a', unkeyedOwner: 'a');
        expect(store.state.notes.single.title, 'A’s note');
        expect(store.state.user.name, 'Ana');
        expect(store.state.achievements, isEmpty);

        final a = jsonEncode(await _read('cmpys_store_v1:a'));
        final b = jsonEncode(await _read('cmpys_store_v1:b'));
        expect(a, isNot(contains('B’s win')));
        expect(b, isNot(contains('A’s note')));
        expect(b, contains('B’s win'));
        store.dispose();
      },
    );

    test('a pending write lands in the account it was made in', () async {
      final store = CmpysStore();
      await store.openAccount('a', unkeyedOwner: 'a');
      store.saveNote(kind: 'read', title: 'Last A edit', body: 'x');
      // Switch before the debounced write fires.
      await store.openAccount('b', unkeyedOwner: 'a');
      await _settle();
      expect(
        jsonEncode(await _read('cmpys_store_v1:a')),
        contains('Last A edit'),
      );
      final b = await _read('cmpys_store_v1:b');
      expect(jsonEncode(b), isNot(contains('Last A edit')));
      store.dispose();
    });

    test('a store with no account open writes nothing', () async {
      final store = CmpysStore();
      store.saveNote(kind: 'read', title: 'Nobody’s', body: 'x');
      await _settle();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => k.startsWith('cmpys_store_v1')),
        isEmpty,
      );
      store.dispose();
    });

    test(
      'closing (an involuntary sign-out) keeps the account on the device',
      () async {
        final store = CmpysStore();
        await store.openAccount('a', unkeyedOwner: 'a');
        store.saveNote(kind: 'read', title: 'Kept', body: 'x');
        await store.closeAccount();
        expect(store.accountId, isNull);
        expect(store.state.notes, isEmpty);
        expect(jsonEncode(await _read('cmpys_store_v1:a')), contains('Kept'));

        await store.openAccount('a', unkeyedOwner: 'a');
        expect(store.state.notes.single.title, 'Kept');
        store.dispose();
      },
    );

    test('reset (a deliberate logout) clears only that account', () async {
      SharedPreferences.setMockInitialValues({
        'cmpys_store_v1:a': '{"notes": [',
        'cmpys_store_v1:b': jsonEncode(_stored(name: 'Ben')),
      });
      final store = CmpysStore();
      await store.openAccount('a', unkeyedOwner: 'a');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cmpys_store_v1:a.bak'), '{"notes": [');
      await store.reset();
      expect(store.accountId, isNull);
      expect(prefs.getString('cmpys_store_v1:a'), isNull);
      expect(prefs.getString('cmpys_store_v1:a.bak'), isNull);
      expect((await _read('cmpys_store_v1:b'))?['user']['name'], 'Ben');

      // A later edit (no account open) never resurrects the cleared data.
      store.saveNote(kind: 'read', title: 'After', body: 'x');
      await _settle();
      expect(prefs.getString('cmpys_store_v1:a'), isNull);
      store.dispose();
    });
  });
}
