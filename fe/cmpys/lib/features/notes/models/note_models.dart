import 'package:freezed_annotation/freezed_annotation.dart';

part 'note_models.freezed.dart';

/// A note attachment linking to other entities.
/// API reference shows: idolId, planItemId, achievementId
@freezed
class NoteAttachment with _$NoteAttachment {
  const factory NoteAttachment({
    String? id,
    String? idolId,
    String? planItemId,
    String? achievementId,
  }) = _NoteAttachment;

  factory NoteAttachment.fromJson(Map<String, dynamic> json) {
    return NoteAttachment(
      id: json['id']?.toString(),
      idolId: (json['idolId'] ?? json['idol_id'])?.toString(),
      planItemId: (json['planItemId'] ?? json['plan_item_id'])?.toString(),
      achievementId: (json['achievementId'] ?? json['achievement_id'])
          ?.toString(),
    );
  }
}

/// A user note.
/// API: GET /notes/{note_id}, POST /notes, etc.
@freezed
class Note with _$Note {
  const factory Note({
    required String id,
    String? userId,
    String? title,
    required String content,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default([]) List<NoteAttachment> attachments,
  }) = _Note;

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? json['user_id'])?.toString(),
      title: json['title']?.toString(),
      content: (json['content'] ?? '').toString(),
      createdAt:
          _parseDate(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      updatedAt:
          _parseDate(json['updatedAt'] ?? json['updated_at']) ?? DateTime.now(),
      attachments: _parseAttachments(json['attachments']) ?? [],
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static List<NoteAttachment>? _parseAttachments(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => NoteAttachment.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Request to create a note.
/// API: POST /notes
@freezed
class CreateNoteRequest with _$CreateNoteRequest {
  const CreateNoteRequest._();

  const factory CreateNoteRequest({
    String? title,
    required String content,
    List<NoteAttachment>? attachments,
  }) = _CreateNoteRequest;

  factory CreateNoteRequest.fromJson(Map<String, dynamic> json) {
    return CreateNoteRequest(
      title: json['title']?.toString(),
      content: (json['content'] ?? '').toString(),
      attachments: _parseAttachments(json['attachments']),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {'content': content};
    if (title != null) {
      data['title'] = title;
    }
    if (attachments != null) {
      data['attachments'] = attachments!.map((a) {
        final Map<String, dynamic> attData = {};
        if (a.idolId != null) attData['idolId'] = a.idolId;
        if (a.planItemId != null) attData['planItemId'] = a.planItemId;
        if (a.achievementId != null) attData['achievementId'] = a.achievementId;
        return attData;
      }).toList();
    }
    return data;
  }

  static List<NoteAttachment>? _parseAttachments(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => NoteAttachment.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Request to update a note.
/// API: PATCH /notes/{note_id}
@freezed
class UpdateNoteRequest with _$UpdateNoteRequest {
  const UpdateNoteRequest._();

  const factory UpdateNoteRequest({
    String? title,
    String? content,
    List<NoteAttachment>? attachments,
  }) = _UpdateNoteRequest;

  factory UpdateNoteRequest.fromJson(Map<String, dynamic> json) {
    return UpdateNoteRequest(
      title: json['title']?.toString(),
      content: json['content']?.toString(),
      attachments: _parseAttachments(json['attachments']),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (title != null) {
      data['title'] = title;
    }
    if (content != null) {
      data['content'] = content;
    }
    if (attachments != null) {
      data['attachments'] = attachments!.map((a) {
        final Map<String, dynamic> attData = {};
        if (a.idolId != null) attData['idolId'] = a.idolId;
        if (a.planItemId != null) attData['planItemId'] = a.planItemId;
        if (a.achievementId != null) attData['achievementId'] = a.achievementId;
        return attData;
      }).toList();
    }
    return data;
  }

  static List<NoteAttachment>? _parseAttachments(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => NoteAttachment.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Response for listing notes.
@freezed
class NotesListResponse with _$NotesListResponse {
  const factory NotesListResponse({
    @Default([]) List<Note> notes,
    int? totalCount,
    int? total,
    @Default(false) bool hasMore,
  }) = _NotesListResponse;

  factory NotesListResponse.fromJson(Map<String, dynamic> json) {
    return NotesListResponse(
      notes: _parseNotes(json['notes']) ?? [],
      totalCount: (json['totalCount'] ?? json['total_count'] as num?)?.toInt(),
      total: (json['total'] as num?)?.toInt(),
      hasMore: json['hasMore'] == true || json['has_more'] == true,
    );
  }

  static List<Note>? _parseNotes(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
  }
}
