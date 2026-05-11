import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys_button.dart';

class PremiumPaywallScreen extends StatefulWidget {
  const PremiumPaywallScreen({super.key});

  @override
  State<PremiumPaywallScreen> createState() => _PremiumPaywallScreenState();
}

class _PremiumPaywallScreenState extends State<PremiumPaywallScreen> {
  bool _yearlySelected = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: _CloseButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    const _PremiumHero(),
                    const SizedBox(height: AppSpacing.s24),
                    Text(
                      'CMPYS Pro',
                      style: AppTypography.captionUpper.copyWith(
                        color: AppColors.brandAccentDark,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      'Master your trajectory.',
                      style: AppTypography.h1.copyWith(fontSize: 34),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    Text(
                      'Unlock the complete mirror, blueprint, mentor chat, and reusable learning vault in one focused workspace.',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s24),
                    const _FeatureRow(
                      icon: AppAssets.iconTarget,
                      title: '12-week success blueprint',
                      subtitle:
                          'Roadmaps tuned to your selected idol and current gap.',
                    ),
                    const _FeatureRow(
                      icon: AppAssets.iconMessageCircle,
                      title: 'Unlimited mentor chat',
                      subtitle:
                          'Ask for reflection, tactics, and next actions as you move.',
                    ),
                    const _FeatureRow(
                      icon: AppAssets.iconTrendingUp,
                      title: 'Live comparison mirror',
                      subtitle:
                          'Track progress against the milestones that matter.',
                    ),
                    const SizedBox(height: AppSpacing.s20),
                    _PlanOption(
                      title: 'Yearly Mastery',
                      subtitle: '\$7.49 / month, billed annually',
                      price: '\$89.99',
                      badge: 'BEST VALUE',
                      selected: _yearlySelected,
                      onTap: () => setState(() => _yearlySelected = true),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    _PlanOption(
                      title: 'Monthly Pursuit',
                      subtitle: 'Cancel anytime',
                      price: '\$14.99',
                      selected: !_yearlySelected,
                      onTap: () => setState(() => _yearlySelected = false),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surfaceGlass,
                border: Border(top: BorderSide(color: AppColors.borderLight)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CmpysButton(
                    label: 'Unlock The Blueprint',
                    iconRight: AppAssets.iconArrowRight,
                    onPressed: () => _showUiOnlyNotice(context),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  TextButton(
                    onPressed: () => _showUiOnlyNotice(context),
                    child: Text(
                      'Restore Purchase  -  Terms of Service',
                      style: AppTypography.captionUpper.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUiOnlyNotice(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Premium access is UI-only in this prototype.'),
      ),
    );
  }
}

class _PremiumHero extends StatelessWidget {
  const _PremiumHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 196,
      decoration: BoxDecoration(
        borderRadius: AppRadii.br32,
        border: Border.all(color: AppColors.borderLight),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F1B16), Color(0xFF393027), Color(0xFFFFF0D5)],
        ),
        boxShadow: AppShadows.md,
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _PremiumGridPainter())),
          Positioned(
            right: -38,
            top: -20,
            child: Container(
              width: 156,
              height: 156,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.peach.withValues(alpha: 0.24),
              ),
            ),
          ),
          Positioned(
            left: 22,
            bottom: 22,
            right: 22,
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: AppRadii.br16,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      AppAssets.iconSparkles,
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Text(
                    'Blueprint, Mirror, Studio, Vault',
                    style: AppTypography.h3.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
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

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.mint.withValues(alpha: 0.12),
              borderRadius: AppRadii.br12,
            ),
            child: Center(
              child: SvgPicture.asset(
                icon,
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  AppColors.mint,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyMedium),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
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

class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final String price;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.peach : AppColors.borderLight;
    final backgroundColor = selected
        ? AppColors.peach.withValues(alpha: 0.10)
        : AppColors.surface;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: AppCurves.easeOut,
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: AppRadii.br20,
          border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
          boxShadow: selected ? AppShadows.sm : null,
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.charcoal : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.charcoal : AppColors.borderFocus,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (badge != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.peach,
                        borderRadius: AppRadii.brFull,
                      ),
                      child: Text(
                        badge!,
                        style: AppTypography.captionUpper.copyWith(
                          color: AppColors.charcoal,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                  ],
                  Text(title, style: AppTypography.bodyMedium),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              price,
              style: AppTypography.h3.copyWith(
                color: selected ? AppColors.charcoal : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(side: BorderSide(color: AppColors.borderLight)),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 42,
          height: 42,
          child: Icon(Icons.close, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _PremiumGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;

    for (double x = 18; x < size.width; x += 34) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 18; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final accentPaint = Paint()
      ..color = AppColors.peach.withValues(alpha: 0.52)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 128, 38, 82, 82),
        const Radius.circular(22),
      ),
      accentPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
