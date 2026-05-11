import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A unified saved item that can be a card (from discover/daily feed) or a lesson.
class SavedItem {
  final String id;
  final String title;
  final String content;
  final String category; // e.g., "Mindset", "Strategy", "quote", "video"
  final String type; // "card" | "lesson"
  final String? source; // e.g., idol name, feed source
  final DateTime savedAt;

  SavedItem({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.type,
    this.source,
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'category': category,
    'type': type,
    'source': source,
    'savedAt': savedAt.toIso8601String(),
  };

  factory SavedItem.fromJson(Map<String, dynamic> json) => SavedItem(
    id: json['id'] as String,
    title: json['title'] as String,
    content: json['content'] as String,
    category: json['category'] as String? ?? '',
    type: json['type'] as String? ?? 'card',
    source: json['source'] as String?,
    savedAt: json['savedAt'] != null
        ? DateTime.tryParse(json['savedAt'] as String) ?? DateTime.now()
        : DateTime.now(),
  );

  bool get isCard => type == 'card';
  bool get isLesson => type == 'lesson';
}

final libraryProvider = StateNotifierProvider<LibraryNotifier, List<SavedItem>>(
  (ref) {
    return LibraryNotifier();
  },
);

class LibraryNotifier extends StateNotifier<List<SavedItem>> {
  LibraryNotifier() : super([]) {
    _load();
  }

  static const _key = 'cmpys_library_v2';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final List<dynamic> decoded = jsonDecode(raw);
        state = decoded.map((e) => SavedItem.fromJson(e)).toList();
      } catch (_) {
        state = [];
      }
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(state.map((e) => e.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  void toggleItem(SavedItem item) {
    if (isSaved(item.id)) {
      state = state.where((e) => e.id != item.id).toList();
    } else {
      state = [item, ...state]; // newest first
    }
    _save();
  }

  void saveItem(SavedItem item) {
    if (!isSaved(item.id)) {
      state = [item, ...state];
      _save();
    }
  }

  void removeItem(String id) {
    state = state.where((e) => e.id != id).toList();
    _save();
  }

  bool isSaved(String id) => state.any((e) => e.id == id);

  List<SavedItem> get cards => state.where((e) => e.isCard).toList();
  List<SavedItem> get lessons => state.where((e) => e.isLesson).toList();
}
