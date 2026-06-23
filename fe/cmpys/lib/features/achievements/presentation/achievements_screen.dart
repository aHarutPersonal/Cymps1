import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/cmpys_card.dart';
import '../../../core/ui/cmpys_chip.dart';
import '../../../core/ui/loading_state.dart';
import '../controllers/achievements_controller.dart';
import '../models/achievement_models.dart';

abstract final class _AchievementPalette {
  static const canvas = AppColors.bg;
  static const paper = Color(0xFFFFFFFF);
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
  static const mint = AppColors.mint;
  static const coral = AppColors.brandAccent;
  static const coralDark = AppColors.brandAccentDark;
}

/// Screen showing list of user achievements.
class AchievementsScreen extends ConsumerStatefulWidget {
  const AchievementsScreen({super.key});

  @override
  ConsumerState<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends ConsumerState<AchievementsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(achievementsControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(achievementsControllerProvider);

    return Scaffold(
      backgroundColor: _AchievementPalette.canvas,
      appBar: AppBar(
        backgroundColor: _AchievementPalette.canvas.withValues(alpha: 0.92),
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: SvgPicture.asset(
            AppAssets.iconArrowLeft,
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(
              _AchievementPalette.ink,
              BlendMode.srcIn,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Achievements',
          style: AppTypography.h3.copyWith(color: _AchievementPalette.ink),
        ),
        actions: [
          IconButton(
            icon: SvgPicture.asset(
              AppAssets.iconPlus,
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                _AchievementPalette.coralDark,
                BlendMode.srcIn,
              ),
            ),
            onPressed: () => _showAddAchievement(context),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _AchievementPalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _AchievementPalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.52, 1],
          ),
        ),
        child: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(AchievementsState state) {
    if (state is AchievementsLoading) {
      return const LoadingState(message: 'Loading achievements...');
    }

    if (state is AchievementsError) {
      return _buildErrorState(state.message);
    }

    if (state is AchievementsLoaded) {
      if (state.achievements.isEmpty) {
        return _buildEmptyState();
      }
      return _buildAchievementsList(state.achievements);
    }

    return const LoadingState(message: 'Loading...');
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              AppAssets.iconTrophy,
              width: 64,
              height: 64,
              colorFilter: ColorFilter.mode(
                _AchievementPalette.coralDark.withValues(alpha: 0.7),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: AppSpacing.s24),
            Text(
              'No achievements yet',
              style: AppTypography.h3.copyWith(color: _AchievementPalette.ink),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Start tracking your accomplishments by adding your first achievement!',
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: _AchievementPalette.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.s32),
            CmpysButton(
              label: 'Add Achievement',
              icon: AppAssets.iconPlus,
              onPressed: () => _showAddAchievement(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              AppAssets.iconAlertCircle,
              width: 48,
              height: 48,
              colorFilter: const ColorFilter.mode(
                AppColors.error,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Text('Unable to load achievements', style: AppTypography.h4),
            const SizedBox(height: AppSpacing.s8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: _AchievementPalette.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.s24),
            CmpysButton(
              label: 'Try Again',
              variant: CmpysButtonVariant.secondary,
              onPressed: () =>
                  ref.read(achievementsControllerProvider.notifier).load(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementsList(List<Achievement> achievements) {
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(achievementsControllerProvider.notifier).refresh(),
      color: _AchievementPalette.coral,
      backgroundColor: _AchievementPalette.paper,
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s24,
          vertical: AppSpacing.s16,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppSpacing.s16,
          mainAxisSpacing: AppSpacing.s16,
          childAspectRatio: 0.85,
        ),
        itemCount: achievements.length,
        itemBuilder: (context, index) {
          final achievement = achievements[index];
          return _AchievementCard(
            achievement: achievement,
            onTap: () => _showAchievementDetail(context, achievement),
            onDelete: () => _deleteAchievement(achievement),
          );
        },
      ),
    );
  }

  void _showAddAchievement(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const AddAchievementScreen()),
    );
  }

  void _showAchievementDetail(BuildContext context, Achievement achievement) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AchievementDetailScreen(achievement: achievement),
      ),
    );
  }

  Future<void> _deleteAchievement(Achievement achievement) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _AchievementPalette.paper,
        title: Text(
          'Delete Achievement',
          style: AppTypography.h4.copyWith(color: _AchievementPalette.ink),
        ),
        content: Text(
          'Are you sure you want to delete "${achievement.title}"?',
          style: AppTypography.body.copyWith(color: _AchievementPalette.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppTypography.button.copyWith(
                color: _AchievementPalette.muted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: AppTypography.button.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final success = await ref
          .read(achievementsControllerProvider.notifier)
          .deleteAchievement(achievement.id);
      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Achievement deleted')));
      }
    }
  }
}

/// Achievement card widget.
class _AchievementCard extends StatelessWidget {
  const _AchievementCard({
    required this.achievement,
    this.onTap,
    this.onDelete,
  });

  final Achievement achievement;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        decoration: BoxDecoration(
          color: _AchievementPalette.paper,
          borderRadius: AppRadii.br16,
          border: Border.all(color: _AchievementPalette.line),
          boxShadow: [
            BoxShadow(
              color: _getCategoryColor(
                achievement.category,
              ).withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: AppSpacing.p16,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getCategoryColor(
                  achievement.category,
                ).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SvgPicture.asset(
                  _getCategoryIcon(achievement.category),
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    _getCategoryColor(achievement.category),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            const Spacer(),
            Text(
              achievement.title,
              style: AppTypography.label.copyWith(
                color: _AchievementPalette.ink,
                fontSize: 13,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.s8),
            if (achievement.achievementDate != null)
              Text(
                DateFormat('MMM d, yyyy').format(achievement.achievementDate!),
                style: AppTypography.tiny.copyWith(
                  color: _AchievementPalette.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(AchievementCategory category) {
    switch (category) {
      case AchievementCategory.career:
        return AppColors.info;
      case AchievementCategory.learning:
        return AppColors.success;
      case AchievementCategory.finance:
        return AppColors.warning;
      case AchievementCategory.impact:
        return AppColors.accent;
      case AchievementCategory.mindset:
        return const Color(0xFF9C27B0);
      case AchievementCategory.other:
        return _AchievementPalette.muted;
    }
  }

  String _getCategoryIcon(AchievementCategory category) {
    switch (category) {
      case AchievementCategory.career:
        return AppAssets.iconBriefcase;
      case AchievementCategory.learning:
        return AppAssets.iconGraduationCap;
      case AchievementCategory.finance:
        return AppAssets.iconDollarSign;
      case AchievementCategory.impact:
        return AppAssets.iconHeart;
      case AchievementCategory.mindset:
        return AppAssets.iconBrain;
      case AchievementCategory.other:
        return AppAssets.iconTrophy;
    }
  }
}

/// Screen to add a new achievement.
class AddAchievementScreen extends ConsumerStatefulWidget {
  const AddAchievementScreen({super.key});

  @override
  ConsumerState<AddAchievementScreen> createState() =>
      _AddAchievementScreenState();
}

class _AddAchievementScreenState extends ConsumerState<AddAchievementScreen> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  AchievementCategory _selectedCategory = AchievementCategory.career;
  DateTime? _selectedDate;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _canSave => _titleController.text.trim().isNotEmpty && !_isSaving;

  Future<void> _save() async {
    if (!_canSave) return;

    setState(() => _isSaving = true);

    try {
      final achievement = await ref
          .read(achievementsControllerProvider.notifier)
          .createAchievement(
            title: _titleController.text.trim(),
            category: _selectedCategory,
            achievementDate: _selectedDate,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      if (achievement != null && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Achievement added!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AchievementPalette.canvas,
      appBar: AppBar(
        backgroundColor: _AchievementPalette.canvas,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          icon: SvgPicture.asset(
            AppAssets.iconX,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(
              _isSaving ? _AchievementPalette.muted : _AchievementPalette.ink,
              BlendMode.srcIn,
            ),
          ),
        ),
        title: Text(
          'Add Achievement',
          style: AppTypography.h3.copyWith(color: _AchievementPalette.ink),
        ),
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.accent,
                      ),
                    ),
                  )
                : Text(
                    'Save',
                    style: AppTypography.button.copyWith(
                      color: _canSave
                          ? _AchievementPalette.coralDark
                          : _AchievementPalette.muted,
                    ),
                  ),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _AchievementPalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _AchievementPalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.52, 1],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                'Title *',
                style: AppTypography.label.copyWith(
                  color: _AchievementPalette.ink,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              TextField(
                controller: _titleController,
                enabled: !_isSaving,
                decoration: InputDecoration(
                  hintText: 'What did you achieve?',
                  hintStyle: AppTypography.body.copyWith(
                    color: _AchievementPalette.muted,
                  ),
                  filled: true,
                  fillColor: _AchievementPalette.paper,
                  border: OutlineInputBorder(
                    borderRadius: AppRadii.br12,
                    borderSide: const BorderSide(
                      color: _AchievementPalette.line,
                    ),
                  ),
                  contentPadding: AppSpacing.p16,
                ),
                style: AppTypography.body.copyWith(
                  color: _AchievementPalette.ink,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.s24),

              // Category
              Text(
                'Category',
                style: AppTypography.label.copyWith(
                  color: _AchievementPalette.ink,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: AchievementCategory.values.map((category) {
                  final isSelected = _selectedCategory == category;
                  return GestureDetector(
                    onTap: _isSaving
                        ? null
                        : () => setState(() => _selectedCategory = category),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s12,
                        vertical: AppSpacing.s8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _AchievementPalette.ink
                            : _AchievementPalette.paper,
                        borderRadius: AppRadii.brFull,
                        border: Border.all(
                          color: isSelected
                              ? _AchievementPalette.ink
                              : _AchievementPalette.line,
                        ),
                      ),
                      child: Text(
                        category.name[0].toUpperCase() +
                            category.name.substring(1),
                        style: AppTypography.buttonSmall.copyWith(
                          color: isSelected
                              ? Colors.white
                              : _AchievementPalette.ink,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.s24),

              // Date
              Text(
                'Date',
                style: AppTypography.label.copyWith(
                  color: _AchievementPalette.ink,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              GestureDetector(
                onTap: _isSaving ? null : _selectDate,
                child: Container(
                  padding: AppSpacing.p16,
                  decoration: BoxDecoration(
                    color: _AchievementPalette.paper,
                    borderRadius: AppRadii.br12,
                    border: Border.all(color: _AchievementPalette.line),
                  ),
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        AppAssets.iconCalendar,
                        width: 20,
                        height: 20,
                        colorFilter: const ColorFilter.mode(
                          _AchievementPalette.muted,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                      Text(
                        _selectedDate != null
                            ? DateFormat('MMMM d, yyyy').format(_selectedDate!)
                            : 'Select date (optional)',
                        style: AppTypography.body.copyWith(
                          color: _selectedDate != null
                              ? _AchievementPalette.ink
                              : _AchievementPalette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s24),

              // Notes
              Text(
                'Notes',
                style: AppTypography.label.copyWith(
                  color: _AchievementPalette.ink,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              TextField(
                controller: _notesController,
                enabled: !_isSaving,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Add any details about this achievement...',
                  hintStyle: AppTypography.body.copyWith(
                    color: _AchievementPalette.muted,
                  ),
                  filled: true,
                  fillColor: _AchievementPalette.paper,
                  border: OutlineInputBorder(
                    borderRadius: AppRadii.br12,
                    borderSide: const BorderSide(
                      color: _AchievementPalette.line,
                    ),
                  ),
                  contentPadding: AppSpacing.p16,
                ),
                style: AppTypography.body.copyWith(
                  color: _AchievementPalette.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _AchievementPalette.coral,
              surface: _AchievementPalette.paper,
              onSurface: _AchievementPalette.ink,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }
}

/// Screen showing achievement details.
class AchievementDetailScreen extends ConsumerWidget {
  const AchievementDetailScreen({super.key, required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: _AchievementPalette.canvas,
      appBar: AppBar(
        backgroundColor: _AchievementPalette.canvas,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: SvgPicture.asset(
            AppAssets.iconArrowLeft,
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(
              _AchievementPalette.ink,
              BlendMode.srcIn,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Achievement',
          style: AppTypography.h3.copyWith(color: _AchievementPalette.ink),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _AchievementPalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _AchievementPalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.52, 1],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon and title
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _AchievementPalette.mint,
                      borderRadius: AppRadii.br16,
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        AppAssets.iconTrophy,
                        width: 28,
                        height: 28,
                        colorFilter: const ColorFilter.mode(
                          _AchievementPalette.ink,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          achievement.title,
                          style: AppTypography.h3.copyWith(
                            color: _AchievementPalette.ink,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        CmpysTag(label: achievement.category.name),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s32),

              // Date
              if (achievement.achievementDate != null) ...[
                _DetailRow(
                  icon: AppAssets.iconCalendar,
                  label: 'Date',
                  value: DateFormat(
                    'MMMM d, yyyy',
                  ).format(achievement.achievementDate!),
                ),
                const SizedBox(height: AppSpacing.s16),
              ],

              // Notes
              if (achievement.notes != null &&
                  achievement.notes!.isNotEmpty) ...[
                Text(
                  'Notes',
                  style: AppTypography.label.copyWith(
                    color: _AchievementPalette.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                CmpysCard(
                  padding: AppSpacing.p16,
                  child: Text(
                    achievement.notes!,
                    style: AppTypography.body.copyWith(
                      color: _AchievementPalette.muted,
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s16),
              ],

              // Evidence link
              if (achievement.evidenceLink != null) ...[
                _DetailRow(
                  icon: AppAssets.iconLink,
                  label: 'Evidence',
                  value: achievement.evidenceLink!,
                ),
              ],

              // Timestamps
              const SizedBox(height: AppSpacing.s32),
              if (achievement.createdAt != null)
                Text(
                  'Added ${DateFormat('MMM d, yyyy').format(achievement.createdAt!)}',
                  style: AppTypography.caption.copyWith(
                    color: _AchievementPalette.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SvgPicture.asset(
          icon,
          width: 18,
          height: 18,
          colorFilter: const ColorFilter.mode(
            _AchievementPalette.muted,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: _AchievementPalette.muted,
              ),
            ),
            Text(
              value,
              style: AppTypography.body.copyWith(
                color: _AchievementPalette.ink,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
