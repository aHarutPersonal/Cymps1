import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../data/notes_repository.dart';
import '../models/note_models.dart';

/// Notes list state.
sealed class NotesState {
  const NotesState();
}

class NotesInitial extends NotesState {
  const NotesInitial();
}

class NotesLoading extends NotesState {
  const NotesLoading();
}

class NotesLoaded extends NotesState {
  const NotesLoaded({required this.notes, this.query = '', this.totalCount});
  final List<Note> notes;
  final String query;
  final int? totalCount;
}

class NotesError extends NotesState {
  const NotesError({required this.message});
  final String message;
}

/// Notes controller provider.
final notesControllerProvider =
    StateNotifierProvider<NotesController, NotesState>((ref) {
      return NotesController(
        notesRepository: ref.watch(notesRepositoryProvider),
      );
    });

/// Controller for notes list.
class NotesController extends StateNotifier<NotesState> {
  NotesController({required NotesRepository notesRepository})
    : _notesRepository = notesRepository,
      super(const NotesInitial());

  final NotesRepository _notesRepository;
  Timer? _searchDebounce;

  /// Load all notes.
  Future<void> load() async {
    state = const NotesLoading();

    try {
      final response = await _notesRepository.listNotes();
      state = NotesLoaded(
        notes: response.notes,
        totalCount: response.totalCount ?? response.notes.length,
      );
    } on ApiError catch (e) {
      state = NotesError(message: e.message);
    } catch (e) {
      state = NotesError(message: e.toString());
    }
  }

  /// Search notes with debounce.
  void search(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    // Preserve previous notes while loading
    final previousNotes = state is NotesLoaded
        ? (state as NotesLoaded).notes
        : <Note>[];

    try {
      final response = await _notesRepository.listNotes(query: query);
      state = NotesLoaded(
        notes: response.notes,
        query: query,
        totalCount: response.totalCount ?? response.notes.length,
      );
    } on ApiError catch (e) {
      state = NotesError(message: e.message);
    } catch (e) {
      // On error, restore previous state with query
      state = NotesLoaded(notes: previousNotes, query: query);
    }
  }

  /// Refresh notes.
  Future<void> refresh() async {
    final currentQuery = state is NotesLoaded
        ? (state as NotesLoaded).query
        : '';

    if (currentQuery.isNotEmpty) {
      await _performSearch(currentQuery);
    } else {
      await load();
    }
  }

  /// Create a new note.
  Future<Note?> createNote({
    String? title,
    required String content,
    List<NoteAttachment>? attachments,
  }) async {
    try {
      final note = await _notesRepository.createNote(
        title: title,
        content: content,
        attachments: attachments,
      );

      // Refresh the list
      await refresh();

      return note;
    } on ApiError {
      rethrow;
    }
  }

  /// Update a note.
  Future<Note?> updateNote(
    String noteId, {
    String? title,
    String? content,
    List<NoteAttachment>? attachments,
  }) async {
    try {
      final note = await _notesRepository.updateNote(
        noteId,
        title: title,
        content: content,
        attachments: attachments,
      );

      // Refresh the list
      await refresh();

      return note;
    } on ApiError {
      rethrow;
    }
  }

  /// Delete a note.
  Future<bool> deleteNote(String noteId) async {
    try {
      await _notesRepository.deleteNote(noteId);

      // Refresh the list
      await refresh();

      return true;
    } on ApiError {
      rethrow;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}

/// Provider for a single note (for detail screen).
final noteDetailProvider = FutureProvider.family<Note, String>((
  ref,
  noteId,
) async {
  final repository = ref.watch(notesRepositoryProvider);
  return repository.getNote(noteId);
});
