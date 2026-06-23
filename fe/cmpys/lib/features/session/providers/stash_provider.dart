import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/daily_insight.dart';

final stashProvider = StateNotifierProvider<StashNotifier, List<DailyInsight>>((
  ref,
) {
  return StashNotifier();
});

class StashNotifier extends StateNotifier<List<DailyInsight>> {
  StashNotifier() : super([]) {
    _loadStash();
  }

  static const _stashKey = 'cmpys_user_stash';

  Future<void> _loadStash() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_stashKey);
    if (jsonString != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(jsonString);
        state = decodedList.map((item) => DailyInsight.fromJson(item)).toList();
      } catch (e) {
        state = [];
      }
    }
  }

  Future<void> _saveStash() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = state.map((item) => item.toJson()).toList();
    await prefs.setString(_stashKey, jsonEncode(jsonList));
  }

  void toggleStash(DailyInsight insight) {
    if (isStashed(insight)) {
      state = state
          .where(
            (item) =>
                item.title != insight.title || item.content != insight.content,
          )
          .toList();
    } else {
      state = [...state, insight];
    }
    _saveStash();
  }

  bool isStashed(DailyInsight insight) {
    return state.any(
      (item) => item.title == insight.title && item.content == insight.content,
    );
  }
}
