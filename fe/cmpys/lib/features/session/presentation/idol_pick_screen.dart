import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../controllers/session_controller.dart';
import '../models/session_models.dart';

abstract final class _SessionPalette {
  static const canvas = AppColors.bg;
  static const paper = Color(0xFFFFFFFF);
  static const paperWarm = AppColors.surfaceHighlight;
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
  static const mint = AppColors.mint;
  static const coral = AppColors.brandAccent;
  static const coralDark = AppColors.brandAccentDark;
}

/// Screen for Phase 2: Display idol suggestions and let the user pick one.
class IdolPickScreen extends ConsumerStatefulWidget {
  const IdolPickScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<IdolPickScreen> createState() => _IdolPickScreenState();
}

class _IdolPickScreenState extends ConsumerState<IdolPickScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionControllerProvider.notifier).suggestIdols();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionControllerProvider, (prev, next) {
      if (next is SessionActive &&
          next.session.phase == SessionPhase.interview) {
        context.go('/agentic/interview', extra: next.session.id);
      }
      if (next is SessionActive && next.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final state = ref.watch(sessionControllerProvider);

    return Scaffold(
      backgroundColor: _SessionPalette.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _SessionPalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _SessionPalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.5, 1],
          ),
        ),
        child: SafeArea(child: _buildBody(state)),
      ),
    );
  }

  Widget _buildBody(SessionState state) {
    if (state is SessionLoading ||
        (state is SessionActive &&
            state.isStreaming &&
            state.suggestions == null)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: _SessionPalette.coral),
            const SizedBox(height: 24),
            Text(
              'Finding mentor matches...',
              style: AppTypography.h4.copyWith(color: _SessionPalette.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Scanning achievement patterns and relevance.',
              style: AppTypography.caption.copyWith(
                color: _SessionPalette.muted,
              ),
            ),
          ],
        ),
      );
    }

    if (state is SessionActive && state.suggestions != null) {
      return _buildSuggestionsList(state.suggestions!);
    }

    return Center(
      child: Text(
        'Something went wrong',
        style: AppTypography.body.copyWith(color: _SessionPalette.ink),
      ),
    );
  }

  Widget _buildSuggestionsList(List<IdolSuggestion> suggestions) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_ios_new, size: 19),
              color: _SessionPalette.ink,
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _SessionPalette.paper,
                borderRadius: AppRadii.brFull,
                border: Border.all(color: _SessionPalette.line),
              ),
              child: Text(
                '${suggestions.length} matches',
                style: AppTypography.captionMedium.copyWith(
                  color: _SessionPalette.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _PickHeader(),
        const SizedBox(height: 18),
        ...suggestions.map((suggestion) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _IdolSuggestionCard(
              suggestion: suggestion,
              onTap: () {
                ref
                    .read(sessionControllerProvider.notifier)
                    .selectIdol(
                      suggestion.name,
                      wikidataId: suggestion.wikidataId,
                    );
              },
            ),
          );
        }),
      ],
    );
  }
}

class _PickHeader extends StatelessWidget {
  const _PickHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _SessionPalette.paper.withValues(alpha: 0.9),
        borderRadius: AppRadii.br20,
        border: Border.all(color: _SessionPalette.line),
        boxShadow: [
          BoxShadow(
            color: _SessionPalette.ink.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose the mentor voice for your mirror.',
            style: AppTypography.h1.copyWith(
              color: _SessionPalette.ink,
              fontSize: 30,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Each suggestion is selected for age relevance, domain fit, and the kind of questions they can ask about your achievements.',
            style: AppTypography.body.copyWith(color: _SessionPalette.muted),
          ),
        ],
      ),
    );
  }
}

class _IdolSuggestionCard extends StatelessWidget {
  const _IdolSuggestionCard({required this.suggestion, required this.onTap});

  final IdolSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initials = suggestion.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.br20,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _SessionPalette.paper,
            borderRadius: AppRadii.br20,
            border: Border.all(color: _SessionPalette.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 74,
                height: 92,
                decoration: BoxDecoration(
                  color: _SessionPalette.paperWarm,
                  borderRadius: AppRadii.br16,
                  border: Border.all(color: _SessionPalette.line),
                ),
                child: Center(
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: AppTypography.h3.copyWith(
                      color: _SessionPalette.coralDark,
                      fontSize: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            suggestion.name,
                            style: AppTypography.h3.copyWith(
                              color: _SessionPalette.ink,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward,
                          color: _SessionPalette.ink,
                          size: 19,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      suggestion.era,
                      style: AppTypography.captionUpper.copyWith(
                        color: _SessionPalette.coralDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      suggestion.relevanceSummary,
                      style: AppTypography.body.copyWith(
                        color: _SessionPalette.muted,
                        height: 1.45,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (suggestion.domains.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: suggestion.domains.take(3).map((domain) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _SessionPalette.mint,
                              borderRadius: AppRadii.brFull,
                            ),
                            child: Text(
                              domain,
                              style: AppTypography.captionMedium.copyWith(
                                color: _SessionPalette.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
