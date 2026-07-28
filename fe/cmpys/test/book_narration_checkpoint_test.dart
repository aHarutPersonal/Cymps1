import 'dart:convert';

import 'package:cmpys/features/plan/presentation/book_narration_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('checkpoint parsing rejects corrupt values and clamps stale bounds', () {
    expect(BookNarrationCheckpoint.tryFromJson(null), isNull);
    expect(
      BookNarrationCheckpoint.tryFromJson(const {
        'chapterIndex': -1,
        'segmentIndex': 2,
        'characterOffset': 10,
        'updatedAtEpochMs': 100,
      }),
      isNull,
    );
    expect(
      BookNarrationCheckpoint.tryFromJson(const {
        'chapterIndex': 1.5,
        'segmentIndex': 2,
        'characterOffset': 10,
        'updatedAtEpochMs': 100,
      }),
      isNull,
    );

    final checkpoint = BookNarrationCheckpoint.tryFromJson(
      const {
        'chapterIndex': 9,
        'segmentIndex': 18,
        'characterOffset': 400,
        'updatedAtEpochMs': 1722000000000,
      },
      maxChapterIndex: 2,
      maxSegmentIndex: 6,
      maxCharacterOffset: 80,
    );

    expect(
      checkpoint,
      const BookNarrationCheckpoint(
        chapterIndex: 2,
        segmentIndex: 6,
        characterOffset: 80,
        updatedAtEpochMs: 1722000000000,
      ),
    );
    expect(
      BookNarrationCheckpoint.tryFromJson(
        checkpoint!.toJson(),
        maxChapterIndex: -1,
      ),
      isNull,
    );
  });

  test(
    'shared preferences store keeps checkpoints isolated per resource',
    () async {
      const first = BookNarrationCheckpoint(
        chapterIndex: 1,
        segmentIndex: 4,
        characterOffset: 37,
        updatedAtEpochMs: 1722000000000,
      );
      const second = BookNarrationCheckpoint(
        chapterIndex: 3,
        segmentIndex: 8,
        characterOffset: 12,
        updatedAtEpochMs: 1722000001000,
      );
      final preferences = await SharedPreferences.getInstance();
      final BookNarrationCheckpointStore store =
          SharedPreferencesBookNarrationCheckpointStore(
            preferences: preferences,
          );

      await store.write('book/one', first);
      await store.write('book/two', second);

      expect(await store.read('book/one'), first);
      expect(await store.read('book/two'), second);

      await store.clear('book/one');
      expect(await store.read('book/one'), isNull);
      expect(await store.read('book/two'), second);
      await store.clear('book/one');
    },
  );

  test('shared preferences store ignores corrupt local data', () async {
    final preferences = await SharedPreferences.getInstance();
    const store = SharedPreferencesBookNarrationCheckpointStore();
    final key = SharedPreferencesBookNarrationCheckpointStore.storageKeyFor(
      'book-corrupt',
    );

    await preferences.setString(key, '{not-json');
    expect(await store.read('book-corrupt'), isNull);

    await preferences.setString(key, '{"chapterIndex": 1}');
    expect(await store.read('book-corrupt'), isNull);

    await preferences.setInt(key, 42);
    expect(await store.read('book-corrupt'), isNull);
  });

  group('active narration resume', () {
    const checkpoint = BookNarrationCheckpoint(
      chapterIndex: 2,
      segmentIndex: 7,
      characterOffset: 91,
      updatedAtEpochMs: 1722000000000,
    );

    ActiveBookNarrationResume resume({
      required String ownerId,
      String resourceId = 'book-1',
      int branchIndex = ActiveBookNarrationResume.planBranchIndex,
      bool wasPlaying = true,
    }) {
      return ActiveBookNarrationResume(
        ownerId: ownerId,
        resourceId: resourceId,
        fallbackTitle: 'The Friendly Book',
        branchIndex: branchIndex,
        checkpoint: checkpoint,
        wasPlaying: wasPlaying,
        updatedAtEpochMs: 1722000000100,
      );
    }

    test('parsing rejects malformed, unsupported, and wrong-owner data', () {
      final valid = resume(ownerId: 'account-a');

      expect(
        ActiveBookNarrationResume.tryFromJson(
          valid.toJson(),
          expectedOwnerId: 'account-a',
        ),
        valid,
      );
      expect(
        ActiveBookNarrationResume.tryFromJson(
          valid.toJson(),
          expectedOwnerId: 'account-b',
        ),
        isNull,
      );
      expect(
        ActiveBookNarrationResume.tryFromJson({
          ...valid.toJson(),
          'branchIndex': 2,
        }),
        isNull,
      );
      expect(
        ActiveBookNarrationResume.tryFromJson({
          ...valid.toJson(),
          'resourceId': '  ',
        }),
        isNull,
      );
      expect(
        ActiveBookNarrationResume.tryFromJson({
          ...valid.toJson(),
          'wasPlaying': 1,
        }),
        isNull,
      );
      expect(
        ActiveBookNarrationResume.tryFromJson({
          ...valid.toJson(),
          'checkpoint': {'chapterIndex': 1},
        }),
        isNull,
      );
    });

    test('copyWith consumes playing state without losing the checkpoint', () {
      final value = resume(ownerId: 'account-a');
      final consumed = value.copyWith(wasPlaying: false);

      expect(consumed.wasPlaying, isFalse);
      expect(consumed.checkpoint, checkpoint);
      expect(consumed.ownerId, value.ownerId);
      expect(consumed.resourceId, value.resourceId);
      expect(consumed.updatedAtEpochMs, value.updatedAtEpochMs);
    });

    test(
      'shared preferences records are isolated by authenticated owner',
      () async {
        final preferences = await SharedPreferences.getInstance();
        final ActiveBookNarrationResumeStore store =
            SharedPreferencesActiveBookNarrationResumeStore(
              preferences: preferences,
            );
        final first = resume(ownerId: 'account-a', resourceId: 'book-a');
        final second = resume(
          ownerId: 'account-b',
          resourceId: 'book-b',
          branchIndex: ActiveBookNarrationResume.profileBranchIndex,
          wasPlaying: false,
        );

        await store.write(first);
        await store.write(second);

        expect(await store.read('account-a'), first);
        expect(await store.read('account-b'), second);
        expect(await store.read('account-c'), isNull);

        await store.clear('account-a');
        expect(await store.read('account-a'), isNull);
        expect(await store.read('account-b'), second);
        await store.clear('account-a');
      },
    );

    test(
      'payload ownership is verified in addition to the scoped key',
      () async {
        final preferences = await SharedPreferences.getInstance();
        const store = SharedPreferencesActiveBookNarrationResumeStore();
        final wrongOwnerPayload = resume(ownerId: 'account-b').toJson();
        final accountAKey =
            SharedPreferencesActiveBookNarrationResumeStore.storageKeyFor(
              'account-a',
            );

        await preferences.setString(accountAKey, jsonEncode(wrongOwnerPayload));

        expect(await store.read('account-a'), isNull);
        expect(await store.read('account-b'), isNull);
      },
    );

    test('active resume store safely ignores corrupt local data', () async {
      final preferences = await SharedPreferences.getInstance();
      const store = SharedPreferencesActiveBookNarrationResumeStore();
      final key = SharedPreferencesActiveBookNarrationResumeStore.storageKeyFor(
        'account-a',
      );

      await preferences.setString(key, '{not-json');
      expect(await store.read('account-a'), isNull);

      await preferences.setString(key, jsonEncode({'ownerId': 'account-a'}));
      expect(await store.read('account-a'), isNull);

      await preferences.setInt(key, 42);
      expect(await store.read('account-a'), isNull);
    });
  });
}
