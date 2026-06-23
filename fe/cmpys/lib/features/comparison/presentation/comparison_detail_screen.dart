import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/ambient_background.dart';
import '../../../core/ui/cmpys_app_bar.dart';
import '../models/comparison_models.dart';

/// Detailed comparison report screen.
class ComparisonDetailScreen extends StatelessWidget {
  const ComparisonDetailScreen({super.key, required this.comparison});

  final ComparisonResponse comparison;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: CmpysAppBar(
        title: 'Detailed Report',
        centerTitle: true,
        backgroundColor: Colors.transparent,
        onBackPressed: () => context.pop(),
      ),
      body: AmbientBackground(
        useSafeArea: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s20,
            vertical: AppSpacing.s16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Overall score header ---
              _buildOverallHeader(),
              const SizedBox(height: AppSpacing.s24),

              // --- AI Analysis ---
              if ((comparison.overallAnalysis ?? '').isNotEmpty)
                _buildSection(
                  icon: Icons.auto_awesome,
                  iconColor: AppColors.accent,
                  title: 'AI Analysis',
                  child: Text(
                    comparison.overallAnalysis!,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.6,
                    ),
                  ),
                ),

              // --- Realistic Perspective ---
              if ((comparison.realisticPerspective ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s16),
                _buildSection(
                  icon: Icons.visibility,
                  iconColor: AppColors.accent,
                  title: 'Reality Check',
                  child: Text(
                    comparison.realisticPerspective!,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.6,
                    ),
                  ),
                ),
              ],

              // --- Encouragement ---
              if ((comparison.encouragement ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s16),
                _buildSection(
                  icon: Icons.emoji_events,
                  iconColor: AppColors.accent,
                  title: 'Encouragement',
                  child: Text(
                    comparison.encouragement!,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.6,
                    ),
                  ),
                ),
              ],

              // --- Category Breakdown ---
              if (comparison.categoryBreakdown.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s24),
                _buildSectionHeader('Category Breakdown'),
                const SizedBox(height: AppSpacing.s12),
                ...comparison.categoryBreakdown.map(_buildCategoryRow),
              ],

              // --- Strengths ---
              if (comparison.strengths.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s24),
                _buildSectionHeader('Your Strengths'),
                const SizedBox(height: AppSpacing.s12),
                ...comparison.strengths.map(_buildStrengthCard),
              ],

              // --- Gaps ---
              if (comparison.gaps.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s24),
                _buildSectionHeader('Growth Opportunities'),
                const SizedBox(height: AppSpacing.s12),
                ...comparison.gaps.map(_buildGapCard),
              ],

              // --- Missing vs Idol ---
              if (comparison.missingVsIdol.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s24),
                _buildSectionHeader('Missing Milestones'),
                const SizedBox(height: AppSpacing.s12),
                ...comparison.missingVsIdol.map(_buildMilestoneCard),
              ],

              // --- Next Milestone ---
              if (comparison.nextMilestone != null) ...[
                const SizedBox(height: AppSpacing.s24),
                _buildNextMilestone(comparison.nextMilestone!),
              ],

              // --- Stats Footer ---
              const SizedBox(height: AppSpacing.s24),
              _buildStatsFooter(),
              const SizedBox(height: AppSpacing.s48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverallHeader() {
    final score = comparison.overallScore.clamp(0, 100).toInt();
    final idolName = comparison.idolName ?? 'Idol';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.surface, AppColors.surfaceHighlight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadii.br20,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        children: [
          Text(
            '$score%',
            style: AppTypography.h1.copyWith(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            'Overall Sync with $idolName',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statChip(
                '${comparison.totalUserAchievements}',
                'Your\nAchievements',
              ),
              const SizedBox(width: AppSpacing.s20),
              _statChip(
                '${comparison.idolMilestonesAtAge}',
                'Idol\nMilestones',
              ),
              const SizedBox(width: AppSpacing.s20),
              _statChip('${comparison.matchedCount}', 'Matched'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.h3.copyWith(
            color: AppColors.accent,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textTertiary,
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.br16,
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: AppSpacing.s8),
              Text(
                title.toUpperCase(),
                style: AppTypography.captionUpper.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          child,
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTypography.h3.copyWith(fontWeight: FontWeight.w800),
    );
  }

  Widget _buildCategoryRow(CategoryBreakdown cat) {
    final userPct = cat.userScore.clamp(0, 100);
    final idolPct = cat.idolScore.clamp(0, 100);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.br12,
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cat.category,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.s10),
            // User bar
            _progressRow('You', userPct / 100, const Color(0xFF16A34A)),
            const SizedBox(height: AppSpacing.s6),
            // Idol bar
            _progressRow('Idol', idolPct / 100, AppColors.accent),
          ],
        ),
      ),
    );
  }

  Widget _progressRow(String label, double progress, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: ClipRRect(
            borderRadius: AppRadii.brFull,
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFE5E7EB),
              color: color,
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        SizedBox(
          width: 36,
          child: Text(
            '${(progress * 100).round()}%',
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildStrengthCard(ComparisonStrength s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: const Color(0xFF16A34A).withValues(alpha: 0.06),
          borderRadius: AppRadii.br12,
          border: Border.all(
            color: const Color(0xFF16A34A).withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF16A34A),
                  size: 16,
                ),
                const SizedBox(width: AppSpacing.s6),
                Text(
                  s.category,
                  style: AppTypography.bodyMedium.copyWith(
                    color: const Color(0xFF16A34A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              s.description,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGapCard(ComparisonGap g) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: AppColors.coral.withValues(alpha: 0.06),
          borderRadius: AppRadii.br12,
          border: Border.all(color: AppColors.coral.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: AppColors.coral, size: 16),
                const SizedBox(width: AppSpacing.s6),
                Text(
                  g.category,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.coral,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              g.description,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
            if (g.suggestion != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Container(
                padding: const EdgeInsets.all(AppSpacing.s10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadii.br8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: AppColors.accent,
                      size: 14,
                    ),
                    const SizedBox(width: AppSpacing.s6),
                    Expanded(
                      child: Text(
                        g.suggestion!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMilestoneCard(MissingMilestone m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.br12,
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Age badge
            if (m.ageAtEvent != null)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: AppRadii.br8,
                ),
                child: Center(
                  child: Text(
                    '${m.ageAtEvent}',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            if (m.ageAtEvent != null) const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.title ?? 'Milestone',
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (m.description != null) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      m.description!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextMilestone(NextMilestone nm) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.08),
            AppColors.accentLight.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadii.br16,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag, color: AppColors.accent, size: 18),
              const SizedBox(width: AppSpacing.s8),
              Text(
                'NEXT MILESTONE',
                style: AppTypography.captionUpper.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            nm.title,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            nm.description,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          if (nm.estimatedTimeframe != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Estimated: ${nm.estimatedTimeframe}',
              style: AppTypography.caption.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsFooter() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.br12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _footerStat('${comparison.totalUserAchievements}', 'Achievements'),
          Container(width: 1, height: 24, color: AppColors.border),
          _footerStat('${comparison.idolMilestonesAtAge}', 'Idol Milestones'),
          Container(width: 1, height: 24, color: AppColors.border),
          _footerStat(
            '${(comparison.completeness * 100).round()}%',
            'Complete',
          ),
        ],
      ),
    );
  }

  Widget _footerStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textTertiary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
