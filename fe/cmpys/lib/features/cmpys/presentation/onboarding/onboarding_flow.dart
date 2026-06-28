import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/design_tokens.dart';
import '../../../../app/router.dart';
import '../../../auth/controllers/session_controller.dart';
import '../../data/cmpys_seed.dart';
import '../../state/cmpys_store.dart';
import 'analysis_step.dart';
import 'discovery_step.dart';
import 'idol_preview_step.dart';
import 'intake_step.dart';
import 'personalize_step.dart';
import 'plan_gen_step.dart';

/// CMPYS post-auth onboarding orchestrator.
///
/// Routes the user through: personalize → discovery → idol preview → idol-led
/// intake → AI analysis → plan generation → main app.
///
/// All sub-screens are local widgets that update a single [CmpysOnboardingDraft]
/// + selected [CmpysIdol] held in this orchestrator's state.
enum _OnboardingRoute {
  personalize,
  discovery,
  preview,
  intake,
  analysis,
  planGen,
}

class CmpysOnboardingFlow extends ConsumerStatefulWidget {
  const CmpysOnboardingFlow({super.key});

  @override
  ConsumerState<CmpysOnboardingFlow> createState() =>
      _CmpysOnboardingFlowState();
}

class _CmpysOnboardingFlowState extends ConsumerState<CmpysOnboardingFlow> {
  _OnboardingRoute _route = _OnboardingRoute.personalize;
  final CmpysOnboardingDraft _draft = CmpysOnboardingDraft();
  CmpysIdol? _previewIdol;
  CmpysIdol? _selectedIdol;

  Future<void> _finish() async {
    // Seed the CMPYS store with the user's onboarding answers, chosen idol,
    // backend session id, and the LLM-generated comparison + blueprint so the
    // main app renders real AI content everywhere.
    ref.read(cmpysStoreProvider.notifier).completeOnboarding(
          name: _draft.name,
          age: _draft.age,
          interests: _draft.interests.toList(),
          goalId: _draft.goalId,
          idol: _selectedIdol ?? defaultIdol(),
          sessionId: _draft.sessionId,
          comparisonMd: _draft.comparisonMd,
          blueprintMd: _draft.blueprintMd,
          planJobId: _draft.planJobId,
        );
    final idolId = (_selectedIdol ?? defaultIdol()).id;
    try {
      await ref.read(sessionControllerProvider.notifier).completeOnboarding();
      // Persist the chosen mentor so the next cold start resolves to
      // SessionReady → /home instead of bouncing back into onboarding. The
      // splash gates on SessionReady, which requires a persisted idol id.
      await ref
          .read(sessionControllerProvider.notifier)
          .setCurrentIdolId(idolId);
    } catch (_) {
      // Best-effort. The design demo can proceed even if backend wiring is
      // pending; we route into /home either way so the user sees the app.
    }
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) {
          final slide = Tween<Offset>(
            begin: const Offset(0.1, 0),
            end: Offset.zero,
          ).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: _buildRoute(),
      ),
    );
  }

  Widget _buildRoute() {
    switch (_route) {
      case _OnboardingRoute.personalize:
        return CmpysPersonalizeStep(
          key: const ValueKey('personalize'),
          draft: _draft,
          onUpdate: (d) => setState(() {}),
          onDone: () => setState(() => _route = _OnboardingRoute.discovery),
        );
      case _OnboardingRoute.discovery:
        return CmpysDiscoveryStep(
          key: ValueKey('discovery-${_draft.interests.join("|")}-${_draft.goalId}'),
          interests: _draft.interests,
          age: _draft.age,
          goalId: _draft.goalId,
          existingSessionId: _draft.sessionId,
          onSessionCreated: (id) => _draft.sessionId = id,
          onPick: (idol) => setState(() {
            _previewIdol = idol;
            _route = _OnboardingRoute.preview;
          }),
        );
      case _OnboardingRoute.preview:
        final idol = _previewIdol ?? defaultIdol();
        return CmpysIdolPreviewStep(
          key: ValueKey('preview-${idol.id}'),
          idol: idol,
          onBack: () => setState(() => _route = _OnboardingRoute.discovery),
          onChoose: (idol) => setState(() {
            _selectedIdol = idol;
            _route = _OnboardingRoute.intake;
          }),
        );
      case _OnboardingRoute.intake:
        final idol = _selectedIdol ?? defaultIdol();
        return CmpysIntakeChatStep(
          key: ValueKey('intake-${idol.id}'),
          idol: idol,
          draft: _draft,
          onDone: () => setState(() => _route = _OnboardingRoute.analysis),
        );
      case _OnboardingRoute.analysis:
        final idol = _selectedIdol ?? defaultIdol();
        return CmpysAnalysisStep(
          key: ValueKey('analysis-${idol.id}'),
          idol: idol,
          draft: _draft,
          onDone: () => setState(() => _route = _OnboardingRoute.planGen),
        );
      case _OnboardingRoute.planGen:
        final idol = _selectedIdol ?? defaultIdol();
        return CmpysPlanGenStep(
          key: ValueKey('plangen-${idol.id}'),
          idol: idol,
          draft: _draft,
          onDone: _finish,
        );
    }
  }
}
