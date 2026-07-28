import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Durable, resource-scoped location for resuming book narration.
///
/// [characterOffset] is an offset inside the active narration segment. Keeping
/// it alongside the chapter and segment makes the checkpoint usable by both
/// generated audio (which can translate it to a media cue) and device TTS.
@immutable
class BookNarrationCheckpoint {
  const BookNarrationCheckpoint({
    required this.chapterIndex,
    required this.segmentIndex,
    required this.characterOffset,
    required this.updatedAtEpochMs,
  });

  static const int _maxSafeJsonInteger = 9007199254740991;

  final int chapterIndex;
  final int segmentIndex;
  final int characterOffset;
  final int updatedAtEpochMs;

  Map<String, Object> toJson() => {
    'chapterIndex': chapterIndex,
    'segmentIndex': segmentIndex,
    'characterOffset': characterOffset,
    'updatedAtEpochMs': updatedAtEpochMs,
  };

  /// Parses a checkpoint without throwing when persisted data is malformed.
  ///
  /// Optional inclusive bounds make stale checkpoints safe after book content
  /// changes. Out-of-range locations are clamped to the closest valid value;
  /// malformed, negative, or unusable bounds reject the checkpoint entirely.
  static BookNarrationCheckpoint? tryFromJson(
    Object? value, {
    int? maxChapterIndex,
    int? maxSegmentIndex,
    int? maxCharacterOffset,
  }) {
    if (value is! Map) return null;

    final chapterIndex = _nonNegativeInt(value['chapterIndex']);
    final segmentIndex = _nonNegativeInt(value['segmentIndex']);
    final characterOffset = _nonNegativeInt(value['characterOffset']);
    final updatedAtEpochMs = _nonNegativeInt(value['updatedAtEpochMs']);
    if (chapterIndex == null ||
        segmentIndex == null ||
        characterOffset == null ||
        updatedAtEpochMs == null ||
        updatedAtEpochMs == 0) {
      return null;
    }
    if ((maxChapterIndex != null && maxChapterIndex < 0) ||
        (maxSegmentIndex != null && maxSegmentIndex < 0) ||
        (maxCharacterOffset != null && maxCharacterOffset < 0)) {
      return null;
    }

    return BookNarrationCheckpoint(
      chapterIndex: maxChapterIndex == null
          ? chapterIndex
          : chapterIndex.clamp(0, maxChapterIndex).toInt(),
      segmentIndex: maxSegmentIndex == null
          ? segmentIndex
          : segmentIndex.clamp(0, maxSegmentIndex).toInt(),
      characterOffset: maxCharacterOffset == null
          ? characterOffset
          : characterOffset.clamp(0, maxCharacterOffset).toInt(),
      updatedAtEpochMs: updatedAtEpochMs,
    );
  }

  static int? _nonNegativeInt(Object? value) {
    if (value is! num || !value.isFinite || value != value.roundToDouble()) {
      return null;
    }
    final parsed = value.toInt();
    if (parsed < 0 || parsed > _maxSafeJsonInteger) return null;
    return parsed;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookNarrationCheckpoint &&
          chapterIndex == other.chapterIndex &&
          segmentIndex == other.segmentIndex &&
          characterOffset == other.characterOffset &&
          updatedAtEpochMs == other.updatedAtEpochMs;

  @override
  int get hashCode => Object.hash(
    chapterIndex,
    segmentIndex,
    characterOffset,
    updatedAtEpochMs,
  );
}

/// The single book narration session an authenticated account can resume.
///
/// The owner travels with the payload as a defense-in-depth check in addition
/// to being part of the storage key. A value accidentally written under a
/// different account's key is therefore ignored rather than exposed.
@immutable
class ActiveBookNarrationResume {
  const ActiveBookNarrationResume({
    required this.ownerId,
    required this.resourceId,
    required this.fallbackTitle,
    required this.branchIndex,
    required this.checkpoint,
    required this.wasPlaying,
    required this.updatedAtEpochMs,
  });

  static const int planBranchIndex = 1;
  static const int profileBranchIndex = 4;
  static const Set<int> supportedBranchIndexes = {
    planBranchIndex,
    profileBranchIndex,
  };

  final String ownerId;
  final String resourceId;
  final String fallbackTitle;
  final int branchIndex;
  final BookNarrationCheckpoint checkpoint;

  /// One-shot signal used only to restore a previously playing native session.
  final bool wasPlaying;
  final int updatedAtEpochMs;

  ActiveBookNarrationResume copyWith({
    String? ownerId,
    String? resourceId,
    String? fallbackTitle,
    int? branchIndex,
    BookNarrationCheckpoint? checkpoint,
    bool? wasPlaying,
    int? updatedAtEpochMs,
  }) {
    return ActiveBookNarrationResume(
      ownerId: ownerId ?? this.ownerId,
      resourceId: resourceId ?? this.resourceId,
      fallbackTitle: fallbackTitle ?? this.fallbackTitle,
      branchIndex: branchIndex ?? this.branchIndex,
      checkpoint: checkpoint ?? this.checkpoint,
      wasPlaying: wasPlaying ?? this.wasPlaying,
      updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
    );
  }

  Map<String, Object> toJson() => {
    'ownerId': ownerId,
    'resourceId': resourceId,
    'fallbackTitle': fallbackTitle,
    'branchIndex': branchIndex,
    'checkpoint': checkpoint.toJson(),
    'wasPlaying': wasPlaying,
    'updatedAtEpochMs': updatedAtEpochMs,
  };

  /// Parses persisted state without throwing and optionally verifies ownership.
  static ActiveBookNarrationResume? tryFromJson(
    Object? value, {
    String? expectedOwnerId,
  }) {
    if (value is! Map) return null;

    final ownerId = _requiredString(value['ownerId']);
    final resourceId = _requiredString(value['resourceId']);
    final fallbackTitle = _requiredString(value['fallbackTitle']);
    final branchIndex = BookNarrationCheckpoint._nonNegativeInt(
      value['branchIndex'],
    );
    final checkpoint = BookNarrationCheckpoint.tryFromJson(value['checkpoint']);
    final wasPlaying = value['wasPlaying'];
    final updatedAtEpochMs = BookNarrationCheckpoint._nonNegativeInt(
      value['updatedAtEpochMs'],
    );
    final normalizedExpectedOwnerId = expectedOwnerId?.trim();

    if (ownerId == null ||
        resourceId == null ||
        fallbackTitle == null ||
        branchIndex == null ||
        !supportedBranchIndexes.contains(branchIndex) ||
        checkpoint == null ||
        wasPlaying is! bool ||
        updatedAtEpochMs == null ||
        updatedAtEpochMs == 0 ||
        (normalizedExpectedOwnerId != null &&
            (normalizedExpectedOwnerId.isEmpty ||
                ownerId != normalizedExpectedOwnerId))) {
      return null;
    }

    return ActiveBookNarrationResume(
      ownerId: ownerId,
      resourceId: resourceId,
      fallbackTitle: fallbackTitle,
      branchIndex: branchIndex,
      checkpoint: checkpoint,
      wasPlaying: wasPlaying,
      updatedAtEpochMs: updatedAtEpochMs,
    );
  }

  static String? _requiredString(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveBookNarrationResume &&
          ownerId == other.ownerId &&
          resourceId == other.resourceId &&
          fallbackTitle == other.fallbackTitle &&
          branchIndex == other.branchIndex &&
          checkpoint == other.checkpoint &&
          wasPlaying == other.wasPlaying &&
          updatedAtEpochMs == other.updatedAtEpochMs;

  @override
  int get hashCode => Object.hash(
    ownerId,
    resourceId,
    fallbackTitle,
    branchIndex,
    checkpoint,
    wasPlaying,
    updatedAtEpochMs,
  );
}

/// Persistence boundary used by playback coordination code and test fakes.
abstract interface class BookNarrationCheckpointStore {
  Future<BookNarrationCheckpoint?> read(String resourceId);

  Future<void> write(String resourceId, BookNarrationCheckpoint checkpoint);

  Future<void> clear(String resourceId);
}

/// Local checkpoint storage. Each book has an independent versioned key so a
/// damaged or stale entry cannot affect another resource.
final class SharedPreferencesBookNarrationCheckpointStore
    implements BookNarrationCheckpointStore {
  const SharedPreferencesBookNarrationCheckpointStore({
    SharedPreferences? preferences,
  }) : _preferences = preferences;

  static const _keyPrefix = 'cmpys.book_narration_checkpoint.v1.';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> _instance() async =>
      _preferences ?? SharedPreferences.getInstance();

  @visibleForTesting
  static String storageKeyFor(String resourceId) {
    final normalized = resourceId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(resourceId, 'resourceId', 'must not be empty');
    }
    return '$_keyPrefix${Uri.encodeComponent(normalized)}';
  }

  @override
  Future<BookNarrationCheckpoint?> read(String resourceId) async {
    final preferences = await _instance();
    try {
      final encoded = preferences.getString(storageKeyFor(resourceId));
      if (encoded == null) return null;
      return BookNarrationCheckpoint.tryFromJson(jsonDecode(encoded));
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on StateError {
      return null;
    }
  }

  @override
  Future<void> write(
    String resourceId,
    BookNarrationCheckpoint checkpoint,
  ) async {
    final preferences = await _instance();
    final saved = await preferences.setString(
      storageKeyFor(resourceId),
      jsonEncode(checkpoint.toJson()),
    );
    if (!saved) {
      throw StateError('Could not persist the book narration checkpoint');
    }
  }

  @override
  Future<void> clear(String resourceId) async {
    final preferences = await _instance();
    final key = storageKeyFor(resourceId);
    if (!preferences.containsKey(key)) return;
    final removed = await preferences.remove(key);
    if (!removed) {
      throw StateError('Could not clear the book narration checkpoint');
    }
  }
}

/// Account-scoped persistence boundary for the active narration session.
abstract interface class ActiveBookNarrationResumeStore {
  Future<ActiveBookNarrationResume?> read(String ownerId);

  Future<void> write(ActiveBookNarrationResume value);

  Future<void> clear(String ownerId);
}

/// Shared-preferences implementation with one independent active record per
/// account. The owner is checked in both the key and decoded payload.
final class SharedPreferencesActiveBookNarrationResumeStore
    implements ActiveBookNarrationResumeStore {
  const SharedPreferencesActiveBookNarrationResumeStore({
    SharedPreferences? preferences,
  }) : _preferences = preferences;

  static const _keyPrefix = 'cmpys.active_book_narration_resume.v1.';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> _instance() async =>
      _preferences ?? SharedPreferences.getInstance();

  @visibleForTesting
  static String storageKeyFor(String ownerId) {
    final normalized = ownerId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'must not be empty');
    }
    return '$_keyPrefix${Uri.encodeComponent(normalized)}';
  }

  @override
  Future<ActiveBookNarrationResume?> read(String ownerId) async {
    final normalizedOwnerId = ownerId.trim();
    final preferences = await _instance();
    try {
      final encoded = preferences.getString(storageKeyFor(normalizedOwnerId));
      if (encoded == null) return null;
      return ActiveBookNarrationResume.tryFromJson(
        jsonDecode(encoded),
        expectedOwnerId: normalizedOwnerId,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on StateError {
      return null;
    }
  }

  @override
  Future<void> write(ActiveBookNarrationResume value) async {
    final validated = ActiveBookNarrationResume.tryFromJson(
      value.toJson(),
      expectedOwnerId: value.ownerId,
    );
    if (validated == null) {
      throw ArgumentError.value(value, 'value', 'must be a valid resume');
    }

    final preferences = await _instance();
    final saved = await preferences.setString(
      storageKeyFor(validated.ownerId),
      jsonEncode(validated.toJson()),
    );
    if (!saved) {
      throw StateError('Could not persist the active book narration resume');
    }
  }

  @override
  Future<void> clear(String ownerId) async {
    final preferences = await _instance();
    final key = storageKeyFor(ownerId);
    if (!preferences.containsKey(key)) return;
    final removed = await preferences.remove(key);
    if (!removed) {
      throw StateError('Could not clear the active book narration resume');
    }
  }
}
