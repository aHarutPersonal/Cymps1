import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
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

// ─────────────────────────────────────────────────────────────────────────────
// Modal bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

/// Show the achievement confirmation sheet for a completed mission task.
///
/// Pre-fills the text field with [item.successMetric], then fires
/// [PlanRepository.fetchAchievementSuggestion] in the background and swaps
/// the text in via [AchievementSheetState.applySuggestion] if the user has
/// not yet started typing. A failed suggestion call is silently swallowed.
///
/// Confirm → [PlanRepository.saveAchievement] then close.
/// Skip → close immediately.
Future<void> showAchievementSheet(
  BuildContext context, {
  required WidgetRef ref,
  required BackendPlanItem item,
  required String planId,
  required int cycleNumber,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    barrierColor: const Color(0x6B16161C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) => _AchievementSheetBody(
      ref: ref,
      item: item,
      planId: planId,
      cycleNumber: cycleNumber,
    ),
  );
}

class _AchievementSheetBody extends StatefulWidget {
  const _AchievementSheetBody({
    required this.ref,
    required this.item,
    required this.planId,
    required this.cycleNumber,
  });

  final WidgetRef ref;
  final BackendPlanItem item;
  final String planId;
  final int cycleNumber;

  @override
  State<_AchievementSheetBody> createState() => _AchievementSheetBodyState();
}

class _AchievementSheetBodyState extends State<_AchievementSheetBody> {
  late final AchievementSheetState _state;
  late final TextEditingController _ctrl;
  String _aiCategory = 'other';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _state = AchievementSheetState(initial: widget.item.successMetric);
    _ctrl = TextEditingController(text: _state.text);
    _fetchSuggestion();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _fetchSuggestion() async {
    try {
      final suggestion = await widget.ref
          .read(planRepositoryProvider)
          .fetchAchievementSuggestion(widget.item.id);
      if (!mounted) return;
      _state.applySuggestion(suggestion.title);
      setState(() {
        _aiCategory = suggestion.category;
        if (!_state.userEdited) {
          _ctrl.text = _state.text;
          // Move cursor to end.
          _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
        }
      });
    } catch (_) {
      // Suggestion failure is non-fatal; the pre-filled success metric remains.
    }
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.ref.read(planRepositoryProvider).saveAchievement(
            title: _state.text.trim(),
            category: _aiCategory,
            source: 'plan_item',
            planItemId: widget.item.id,
            planId: widget.planId,
            cycleNumber: widget.cycleNumber,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        showCmpysToast(
          context,
          "Couldn't save - try again.",
          icon: Icons.error_outline_rounded,
          tone: AppColors.ink2,
        );
        setState(() => _saving = false);
      }
    }
  }

  void _skip() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16, top: 4),
                  decoration: BoxDecoration(
                    color: AppColors.hair2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              // Icon badge
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.greenSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  PhosphorIconsFill.trophy,
                  size: 24,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(height: 14),
              // Heading
              Text(
                'Log your achievement',
                style: AppTypography.h3,
              ),
              const SizedBox(height: 6),
              Text(
                'Confirm or refine what you accomplished for "${widget.item.title}".',
                style: AppTypography.bodyDim.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 18),
              // Text field
              CmpysCardSurface(
                pad: EdgeInsets.zero,
                border: true,
                child: TextField(
                  controller: _ctrl,
                  maxLines: 4,
                  minLines: 3,
                  style: AppTypography.body.copyWith(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Describe what you completed…',
                    hintStyle: AppTypography.body.copyWith(
                      color: AppColors.ink3,
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(14),
                  ),
                  onChanged: (v) {
                    _state.onUserType(v);
                  },
                ),
              ),
              const SizedBox(height: 20),
              // Confirm button
              CmpysButton(
                variant: CmpysBtnVariant.primary,
                size: CmpysBtnSize.lg,
                full: true,
                disabled: _saving,
                leadingIcon: Icons.check_rounded,
                onTap: _confirm,
                child: Text(_saving ? 'Saving…' : 'Confirm achievement'),
              ),
              const SizedBox(height: 10),
              // Skip button
              CmpysButton(
                variant: CmpysBtnVariant.ghost,
                size: CmpysBtnSize.md,
                full: true,
                onTap: _skip,
                child: const Text('Skip for now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
