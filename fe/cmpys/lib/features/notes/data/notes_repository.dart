import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../models/note_models.dart';

/// Notes repository provider.
final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  return NotesRepository(dioClient: ref.watch(dioClientProvider));
});

/// Repository for notes operations.
class NotesRepository {
  NotesRepository({required DioClient dioClient}) : _dioClient = dioClient;

  final DioClient _dioClient;

  /// List all notes with optional search.
  ///
  /// [query] - Optional search query.
  /// [limit] - Maximum number of notes to return.
  /// [offset] - Pagination offset.
  /// Returns a [NotesListResponse] with notes.
  Future<NotesListResponse> listNotes({
    String? query,
    int? limit,
    int? offset,
  }) async {
    final queryParams = <String, dynamic>{};
    if (query != null && query.isNotEmpty) queryParams['q'] = query;
    if (limit != null) queryParams['limit'] = limit;
    if (offset != null) queryParams['offset'] = offset;

    final response = await _dioClient.get(
      '/notes',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    // Handle both list and object responses
    if (response.data is List) {
      return NotesListResponse(
        notes: (response.data as List)
            .map((json) => Note.fromJson(json as Map<String, dynamic>))
            .toList(),
      );
    }

    return NotesListResponse.fromJson(response.data);
  }

  /// Get a single note by ID.
  ///
  /// [noteId] - The note's unique identifier.
  /// Returns the [Note].
  Future<Note> getNote(String noteId) async {
    final response = await _dioClient.get('/notes/$noteId');
    return Note.fromJson(response.data);
  }

  /// Create a new note.
  ///
  /// [title] - Optional note title.
  /// [content] - Note content (required).
  /// [attachments] - Optional attachments linking to other entities.
  /// Returns the created [Note].
  /// 
  /// API: POST /notes
  Future<Note> createNote({
    String? title,
    required String content,
    List<NoteAttachment>? attachments,
  }) async {
    final request = CreateNoteRequest(
      title: title,
      content: content,
      attachments: attachments,
    );

    final response = await _dioClient.post(
      '/notes',
      data: request.toJson(),
    );

    return Note.fromJson(response.data);
  }

  /// Update an existing note.
  ///
  /// [noteId] - The note's unique identifier.
  /// [title] - Optional new title.
  /// [content] - Optional new content.
  /// [attachments] - Optional new attachments.
  /// Returns the updated [Note].
  /// 
  /// API: PATCH /notes/{note_id}
  Future<Note> updateNote(
    String noteId, {
    String? title,
    String? content,
    List<NoteAttachment>? attachments,
  }) async {
    final request = UpdateNoteRequest(
      title: title,
      content: content,
      attachments: attachments,
    );

    final response = await _dioClient.patch(
      '/notes/$noteId',
      data: request.toJson(),
    );

    return Note.fromJson(response.data);
  }

  /// Delete a note.
  ///
  /// [noteId] - The note's unique identifier.
  Future<void> deleteNote(String noteId) async {
    await _dioClient.delete('/notes/$noteId');
  }

  /// Quick create a note with just content.
  Future<Note> quickNote(String content) async {
    return createNote(content: content);
  }

  /// Create a note attached to an idol.
  Future<Note> createIdolNote({
    required String idolId,
    String? title,
    required String content,
  }) async {
    return createNote(
      title: title,
      content: content,
      attachments: [NoteAttachment(idolId: idolId)],
    );
  }

  /// Create a note attached to a plan item.
  Future<Note> createPlanItemNote({
    required String planItemId,
    String? title,
    required String content,
  }) async {
    return createNote(
      title: title,
      content: content,
      attachments: [NoteAttachment(planItemId: planItemId)],
    );
  }
}
