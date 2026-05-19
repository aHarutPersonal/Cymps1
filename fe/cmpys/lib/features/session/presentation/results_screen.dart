import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../controllers/session_controller.dart';

abstract final class _ResultsPalette {
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

/// Phase 4-5: streams comparison and blueprint results.
class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  bool _generationStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_generationStarted) {
        _generationStarted = true;
        ref.read(sessionControllerProvider.notifier).generateResults();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionControllerProvider);

    return Scaffold(
      backgroundColor: _ResultsPalette.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _ResultsPalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _ResultsPalette.canvas,
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
    if (state is SessionLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _ResultsPalette.coral),
      );
    }

    if (state is SessionActive) {
      return _buildStreamingContent(state);
    }

    if (state is SessionCompleted) {
      return _buildCompletedView(state);
    }

    if (state is SessionError) {
      return _ErrorState(message: state.message);
    }

    return const Center(
      child: CircularProgressIndicator(color: _ResultsPalette.coral),
    );
  }

  Widget _buildStreamingContent(SessionActive state) {
    final section = state.streamedSection;
    final content = state.streamedContent;
    final isComparison = section == 'comparison';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        _ResultsHeader(
          title: isComparison ? 'Mirror analysis' : 'Plan blueprint',
          subtitle: isComparison
              ? 'Comparing your current trajectory with the mentor pattern. Choose the intensity that keeps you honest and moving.'
              : 'Turning the diagnosis into the strategic verdict that powers your 12-week execution path.',
          icon: isComparison ? Icons.compare_arrows : Icons.map_outlined,
        ),
        const SizedBox(height: 14),
        _TrustStrip(
          label: isComparison
              ? 'AI mentor simulation. Verify historical claims before major decisions.'
              : 'Strategic blueprint. Your actionable work continues in the 12-week Plan tab.',
        ),
        const SizedBox(height: 12),
        _ResultPaper(
          title: isComparison ? 'Comparison' : 'Blueprint',
          body: content.isEmpty ? 'Preparing your analysis...' : content,
        ),
        if (state.isStreaming) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(color: _ResultsPalette.coral),
          const SizedBox(height: 8),
          Text(
            isComparison
                ? 'Generating your mirror...'
                : 'Building your path...',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: _ResultsPalette.muted),
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 16),
          _InlineError(message: state.error!),
        ],
      ],
    );
  }

  Widget _buildCompletedView(SessionCompleted state) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const _ResultsHeader(
          title: 'Your mirror is ready',
          subtitle:
              'The diagnosis and blueprint are saved to the session. Start the guided path when you are ready.',
          icon: Icons.auto_awesome,
        ),
        const SizedBox(height: 14),
        _ResultPaper(
          title: 'Mirror analysis',
          body: state.session.comparisonOutput ?? 'No comparison available.',
        ),
        const SizedBox(height: 12),
        const _TrustStrip(
          label:
              'This is AI-assisted coaching from public context. Treat it as directional, then use the Plan tab for concrete work.',
        ),
        const SizedBox(height: 12),
        _ResultPaper(
          title: 'Strategic blueprint',
          body: state.session.blueprintOutput ?? 'No blueprint available.',
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _ResultsPalette.ink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () => context.goToPlan(),
            icon: const Icon(Icons.school_outlined),
            label: Text(
              'Open my 12-week plan',
              style: AppTypography.button.copyWith(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _ResultsPalette.ink,
              side: const BorderSide(color: _ResultsPalette.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () => context.goToHome(),
            icon: const Icon(Icons.home_outlined),
            label: const Text('Go to Today'),
          ),
        ),
      ],
    );
  }
}

class _TrustStrip extends StatelessWidget {
  const _TrustStrip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _ResultsPalette.paperWarm,
        borderRadius: AppRadii.br12,
        border: Border.all(color: _ResultsPalette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.fact_check_outlined,
            size: 18,
            color: _ResultsPalette.coralDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: _ResultsPalette.muted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ResultsPalette.paper.withValues(alpha: 0.92),
        borderRadius: AppRadii.br20,
        border: Border.all(color: _ResultsPalette.line),
        boxShadow: [
          BoxShadow(
            color: _ResultsPalette.ink.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _ResultsPalette.mint,
              borderRadius: AppRadii.br12,
            ),
            child: Icon(icon, color: _ResultsPalette.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.h2.copyWith(color: _ResultsPalette.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: AppTypography.body.copyWith(
                    color: _ResultsPalette.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultPaper extends StatelessWidget {
  const _ResultPaper({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ResultsPalette.paper,
        borderRadius: AppRadii.br16,
        border: Border.all(color: _ResultsPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.captionUpper.copyWith(
              color: _ResultsPalette.coralDark,
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            body,
            style: AppTypography.body.copyWith(
              color: _ResultsPalette.ink,
              height: 1.62,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _ResultsPalette.paperWarm,
        borderRadius: AppRadii.br12,
        border: Border.all(color: _ResultsPalette.coral),
      ),
      child: Text(
        message,
        style: AppTypography.body.copyWith(color: _ResultsPalette.coralDark),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: _ResultsPalette.coralDark,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: _ResultsPalette.ink),
            ),
          ],
        ),
      ),
    );
  }
}
