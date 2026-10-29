import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/v3/v3.dart';
import '../../cmpys/data/reported_win.dart' show recordDimForCategory;
import '../../cmpys/state/cmpys_store.dart';
import '../data/plan_repository.dart';
import '../models/plan_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pure presenter state — no Flutter dependency, fully unit-testable.
// ─────────────────────────────────────────────────────────────────────────────

/// Holds the achievement text the user will confirm (or skip).
///
/// Pre-filled with [initial] (the item's success metric). The AI suggestion
/// is applied only when the user has not yet typed anything themselves.
class AchievementSheetState {
  AchievementSheetState({required String initial}) : text = initial;

  String text;
  bool userEdited = false;

  /// Called whenever the user types in the text field.
  void onUserType(String value) {
    userEdited = true;
    text = value;
  }

  /// Apply an AI-generated suggestion. Ignored if the user has already typed.
  void applySuggestion(String suggestion) {
    if (!userEdited && suggestion.trim().isNotEmpty) text = suggestion;
  }
}

/// An AI-suggested achievement: its text and category.
typedef AchievementSuggestion = ({String title, String category});

/// "Confirm achievement" stays disabled until the text, trimmed, is at least
/// this long.
const int kAchievementMinLength = 6;

// ─────────────────────────────────────────────────────────────────────────────
// Backend-wired entry point
// ─────────────────────────────────────────────────────────────────────────────

/// Show the "Suggested achievement" sheet for a completed mission task.
///
/// Pre-fills the text field with [initial] (default: the item's
/// `successMetric`), then asks [PlanRepository.fetchAchievementSuggestion]
/// in the background and swaps the text in if the user has not started
/// typing. A failed suggestion call is silently swallowed.
///
/// Confirm → [PlanRepository.saveAchievement], then the win on the Record on
/// this device (`auto`, assessed, synced with the server id, filed under the
/// category's dimension or Practice, and under "Undated" with no known age),
/// an "Achievement saved" toast, then close. A failed save keeps the sheet
/// open with an inline error. Skip → close immediately. Resolves to whether
/// the achievement was saved.
Future<bool> showAchievementSheet(
  BuildContext context, {
  required WidgetRef ref,
  required BackendPlanItem item,
  required String? planId,
  required int cycleNumber,
  String? initial,
}) {
  // Read everything up front: the sheet outlives the caller's `ref`.
  final repository = ref.read(planRepositoryProvider);
  final store = ref.read(cmpysStoreProvider.notifier);
  final age = ref.read(cmpysStoreProvider).user.age;
  return AchievementSheet.show(
    context,
    initial: initial ?? item.successMetric,
    age: age > 0 ? age : null,
    loadSuggestion: () => repository.fetchAchievementSuggestion(item.id),
    onSave: (title, category) async {
      final serverId = await repository.saveAchievement(
        title: title,
        category: category,
        source: 'plan_item',
        planItemId: item.id,
        planId: planId,
        cycleNumber: cycleNumber,
      );
      store.addWin(
        title: title,
        dim: recordDimForCategory(category) ?? 'practice',
        // 0 (unknown) is kept: the Record files the win under "Undated".
        age: math.max(0, age),
        source: 'auto',
        assessed: true,
        synced: true,
        serverId: serverId,
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet
// ─────────────────────────────────────────────────────────────────────────────

/// `AchievementSheet` from `v3/app.jsx`: the body of the "Suggested
/// achievement" sheet. A two-row field holds the suggestion, tags say where
/// it comes from, "Confirm achievement" saves it (disabled under
/// [kAchievementMinLength] trimmed characters, spinning while it saves) and
/// "Skip" closes.
///
/// The widget does not know the backend: [onSave] stores the achievement and
/// throws on failure. A failed save keeps the sheet open with an inline
/// error; a successful one shows the "Achievement saved" toast and pops the
/// route with `true`. Skip pops with `false`. Open it with [show].
class AchievementSheet extends StatefulWidget {
  const AchievementSheet({
    super.key,
    required this.initial,
    required this.onSave,
    this.age,
    this.loadSuggestion,
  });

  /// The sheet's route title.
  static const title = 'Suggested achievement';

  /// Opens the sheet as a [V3Sheet] and resolves to whether it was saved.
  static Future<bool> show(
    BuildContext context, {
    required String initial,
    required Future<void> Function(String title, String category) onSave,
    int? age,
    Future<AchievementSuggestion> Function()? loadSuggestion,
  }) async {
    final saved = await showV3Sheet<bool>(
      context,
      title: title,
      builder: (_) => AchievementSheet(
        initial: initial,
        age: age,
        onSave: onSave,
        loadSuggestion: loadSuggestion,
      ),
    );
    return saved == true;
  }

  /// The text the field starts with.
  final String initial;

  /// The user's age for the "Age N" tag; null leaves the tag out.
  final int? age;

  /// Stores the achievement. [title] is trimmed; [category] is the AI
  /// suggestion's category, or `other`. Throw to report a failure.
  final Future<void> Function(String title, String category) onSave;

  /// Fetches an AI suggestion to swap in while the user has not typed. Its
  /// failure is ignored.
  final Future<AchievementSuggestion> Function()? loadSuggestion;

  @override
  State<AchievementSheet> createState() => _AchievementSheetState();
}

class _AchievementSheetState extends State<AchievementSheet> {
  // Existing copy for a failed save.
  static const _saveError = "Couldn't save - try again.";

  late final AchievementSheetState _state;
  late final TextEditingController _ctrl;
  String _category = 'other';
  bool _saving = false;
  String? _error;

  bool get _canConfirm => _ctrl.text.trim().length >= kAchievementMinLength;

  @override
  void initState() {
    super.initState();
    _state = AchievementSheetState(initial: widget.initial);
    _ctrl = TextEditingController(text: _state.text);
    _fetchSuggestion();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _fetchSuggestion() async {
    final load = widget.loadSuggestion;
    if (load == null) return;
    try {
      final suggestion = await load();
      if (!mounted) return;
      _state.applySuggestion(suggestion.title);
      setState(() {
        _category = suggestion.category;
        if (!_state.userEdited) {
          _ctrl.value = TextEditingValue(
            text: _state.text,
            selection: TextSelection.collapsed(offset: _state.text.length),
          );
        }
      });
    } catch (_) {
      // Suggestion failure is non-fatal; the pre-filled text remains.
    }
  }

  void _onChanged(String value) {
    setState(() {
      _state.onUserType(value);
      _error = null;
    });
  }

  Future<void> _confirm() async {
    if (_saving || !_canConfirm) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_ctrl.text.trim(), _category);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _saveError;
      });
      return;
    }
    if (!mounted) return;
    // The toast lives in the root overlay, so it outlasts the sheet.
    showV3Toast(context, 'Achievement saved', icon: V3Icons.trophy);
    Navigator.of(context).pop(true);
  }

  void _skip() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    final age = widget.age;
    // No way out mid-save: Skip is disabled, and back / swipe / scrim are
    // vetoed, so the "saved" toast is never missed.
    return PopScope(
      canPop: !_saving,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Based on the work you just completed. Edit it so it’s true in '
            'your words.',
            style: AppTypography.sans(
              14,
            ).copyWith(color: AppColors.ink2, height: 1.5),
          ),
          const SizedBox(height: 14),
          V3Field(
            controller: _ctrl,
            multiline: true,
            rows: 2,
            enabled: !_saving,
            onChanged: _onChanged,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              const V3Tag(child: Text('Practice')),
              if (age != null && age > 0) V3Tag(child: Text('Age $age')),
              const V3Tag(
                color: AppColors.sage2,
                background: AppColors.sageSoft,
                icon: V3Icons.check,
                child: Text('From plan completion'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  const V3Icon(
                    V3Icons.alert,
                    size: 13,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _error!,
                      style: AppTypography.sans(
                        12.5,
                      ).copyWith(color: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          V3Button(
            full: true,
            loading: _saving,
            disabled: !_canConfirm,
            onPressed: _confirm,
            child: const Text('Confirm achievement'),
          ),
          const SizedBox(height: 8),
          V3Button(
            full: true,
            kind: V3ButtonKind.ghost,
            disabled: _saving,
            onPressed: _skip,
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }
}
