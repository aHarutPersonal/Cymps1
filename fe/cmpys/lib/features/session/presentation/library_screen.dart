import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/learning_resource_card.dart';
import '../../ideas/models/idea_card_models.dart';
import '../../ideas/providers/idea_card_provider.dart';
import '../data/content_resources_repository.dart';
import '../models/content_resource.dart';
import '../providers/content_resources_provider.dart';
import '../providers/library_provider.dart';
import 'widgets/idea_card.dart';

abstract final class _VaultPalette {
  static const canvas = AppColors.bg;
  static const paper = Color(0xFFFFFFFF);
  static const paperWarm = AppColors.surfaceHighlight;
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
  static const coral = AppColors.brandAccent;
  static const coralDark = AppColors.brandAccentDark;
}

/// Unified library screen showing Reading content, Insights, and Saved items.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stashProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stashState = ref.watch(stashProvider);
    final libraryState = ref.watch(libraryResourcesProvider);
    final legacyLibrary = ref.watch(libraryProvider);
    final lessons = legacyLibrary.where((e) => e.isLesson).toList();

    return Scaffold(
      backgroundColor: _VaultPalette.canvas,
      appBar: AppBar(
        backgroundColor: _VaultPalette.canvas.withValues(alpha: 0.92),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Vault',
          style: AppTypography.h3.copyWith(color: _VaultPalette.ink),
        ),
        centerTitle: true,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _VaultPalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _VaultPalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.52, 1],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.s8),

            // Tabs
            Padding(
              padding: AppSpacing.screenH,
              child: Container(
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _VaultPalette.paper.withValues(alpha: 0.92),
                  borderRadius: AppRadii.brFull,
                  border: Border.all(color: _VaultPalette.line),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: _VaultPalette.ink,
                    borderRadius: AppRadii.brFull,
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: _VaultPalette.muted,
                  labelStyle: AppTypography.buttonSmall,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: [
                    Tab(
                      text: libraryState.when(
                        data: (resources) => 'Reading (${resources.length})',
                        loading: () => 'Reading',
                        error: (_, _) => lessons.isEmpty
                            ? 'Reading'
                            : 'Reading (${lessons.length})',
                      ),
                    ),
                    Tab(
                      text: stashState.when(
                        data: (cards) => 'Insights (${cards.length})',
                        loading: () => 'Insights',
                        error: (_, _) => 'Insights',
                      ),
                    ),
                    Tab(text: 'Saved'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildReadingList(libraryState, lessons),
                  _buildInsightsList(stashState),
                  _buildSavedList(libraryState),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: Reading — full-length content from library endpoint ──

  Widget _buildReadingList(
    AsyncValue<List<ContentResource>> libraryState,
    List<SavedItem> fallbackLessons,
  ) {
    return libraryState.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: _VaultPalette.coral),
      ),
      error: (_, _) {
        if (fallbackLessons.isNotEmpty) {
          return _buildLessonsList(fallbackLessons);
        }
        return _buildEmptyState(
          icon: PhosphorIconsRegular.bookOpen,
          title: 'No reading material yet',
          subtitle: 'Books and lessons from your Path\nwill appear here.',
        );
      },
      data: (resources) {
        if (resources.isEmpty) {
          if (fallbackLessons.isNotEmpty) {
            return _buildLessonsList(fallbackLessons);
          }
          return _buildEmptyState(
            icon: PhosphorIconsRegular.bookOpen,
            title: 'No reading material yet',
            subtitle: 'Books and lessons from your Path\nwill appear here.',
          );
        }

        return RefreshIndicator(
          color: _VaultPalette.coral,
          onRefresh: () async => ref.invalidate(libraryResourcesProvider),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.s8,
              AppSpacing.s20,
              AppSpacing.floatingNavBarHeight,
            ),
            itemCount: resources.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s12),
            itemBuilder: (context, index) =>
                _buildResourceItem(resources[index]),
          ),
        );
      },
    );
  }

  // ── Tab 2: Insights — stashed idea cards ──

  Widget _buildInsightsList(AsyncValue<List<IdeaCardModel>> stashState) {
    return stashState.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: _VaultPalette.coral),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.warningCircle,
              color: _VaultPalette.muted,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load insights',
              style: AppTypography.body.copyWith(color: _VaultPalette.ink),
            ),
            TextButton(
              onPressed: () => ref.read(stashProvider.notifier).load(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (cards) {
        if (cards.isEmpty) {
          return _buildEmptyState(
            icon: PhosphorIconsRegular.lightbulb,
            title: 'No insights yet',
            subtitle:
                'Swipe through the Ideas tab and tap\n"Stash" to save insights here.',
          );
        }

        return RefreshIndicator(
          color: _VaultPalette.coral,
          onRefresh: () => ref.read(stashProvider.notifier).load(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.s8,
              AppSpacing.s20,
              AppSpacing.floatingNavBarHeight,
            ),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s12),
            itemBuilder: (context, index) {
              final card = cards[index];
              return Dismissible(
                key: ValueKey(card.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: AppSpacing.s20),
                  decoration: BoxDecoration(
                    color: _VaultPalette.paperWarm,
                    borderRadius: AppRadii.br16,
                  ),
                  child: Icon(
                    PhosphorIconsRegular.trash,
                    size: 22,
                    color: _VaultPalette.coralDark,
                  ),
                ),
                onDismissed: (_) {
                  ref.read(stashProvider.notifier).toggleStash(card.id);
                },
                child: IdeaCard(
                  contentMarkdown: card.contentMarkdown,
                  category: card.categoryTag,
                  isStashed: true,
                  isCompact: true,
                  onStash: () {
                    HapticFeedback.lightImpact();
                    ref.read(stashProvider.notifier).toggleStash(card.id);
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ── Tab 3: Saved — vault resources (bookmarked items) ──

  Widget _buildSavedList(AsyncValue<List<ContentResource>> libraryState) {
    final vaultState = ref.watch(vaultResourcesProvider);
    return vaultState.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: _VaultPalette.coral),
      ),
      error: (_, _) => _buildEmptyState(
        icon: PhosphorIconsRegular.bookmarkSimple,
        title: 'No saved items yet',
        subtitle: 'Bookmark books, lessons, and insights\nto find them here.',
      ),
      data: (resources) {
        if (resources.isEmpty) {
          return _buildEmptyState(
            icon: PhosphorIconsRegular.bookmarkSimple,
            title: 'No saved items yet',
            subtitle:
                'Bookmark books, lessons, and insights\nto find them here.',
          );
        }

        return RefreshIndicator(
          color: _VaultPalette.coral,
          onRefresh: () async => ref.invalidate(vaultResourcesProvider),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.s8,
              AppSpacing.s20,
              AppSpacing.floatingNavBarHeight,
            ),
            itemCount: resources.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s12),
            itemBuilder: (context, index) =>
                _buildResourceItem(resources[index]),
          ),
        );
      },
    );
  }

  // ── Resource item builder (shared between Reading and Saved tabs) ──

  Future<void> _openResource(ContentResource resource) async {
    if (resource.canReadInApp) {
      context.goToInAppLesson(
        title: resource.title,
        markdown: resource.contentMarkdown!,
        materialId: resource.id,
        durationMinutes: resource.durationMinutes,
        initialIsSaved: resource.isSaved,
        initialProgressPercent: resource.progressPercent,
        initialIsCompleted: resource.isCompleted,
      );
      return;
    }

    if (resource.isVideo && resource.sourceUrl != null) {
      context.goToPlanVideo(
        title: resource.title,
        url: resource.sourceUrl!,
        materialId: resource.id,
        source: resource.authorOrCreator,
        initialIsSaved: resource.isSaved,
      );
      return;
    }

    final url = resource.sourceUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  Widget _buildResourceItem(ContentResource resource) {
    return Dismissible(
      key: ValueKey(resource.id),
      direction: DismissDirection.endToStart,
      background: _buildDismissBackground(),
      onDismissed: (_) async {
        await ref
            .read(contentResourcesRepositoryProvider)
            .unsaveResource(resource.id);
        ref.invalidate(vaultResourcesProvider);
        ref.invalidate(libraryResourcesProvider);
      },
      child: LearningResourceCard(
        title: resource.title,
        kindLabel: resource.kindLabel,
        metaLabel: resource.metaLabel,
        subtitle: _resourceSubtitle(resource),
        icon: _resourceIcon(resource),
        accentColor: _resourceAccent(resource),
        progressPercent: resource.progressPercent,
        isCompleted: resource.isCompleted,
        isUnavailable: resource.isUnavailable,
        onTap: () => _openResource(resource),
      ),
    );
  }

  Widget _buildDismissBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.s20),
      decoration: BoxDecoration(
        color: _VaultPalette.paperWarm,
        borderRadius: AppRadii.br20,
      ),
      child: Icon(
        PhosphorIconsRegular.trash,
        size: 22,
        color: _VaultPalette.coralDark,
      ),
    );
  }

  String? _resourceSubtitle(ContentResource resource) {
    final license = resource.licenseStatus.replaceAll('_', ' ');
    if (resource.isUnavailable) {
      return 'This resource could not be resolved yet.';
    }
    if (license.isNotEmpty && license != 'unknown') return license;
    return resource.sourceUrl;
  }

  IconData _resourceIcon(ContentResource resource) {
    if (resource.isVideo) return PhosphorIconsRegular.playCircle;
    if (resource.isBook) return PhosphorIconsRegular.bookOpen;
    return PhosphorIconsRegular.article;
  }

  Color _resourceAccent(ContentResource resource) {
    if (resource.isVideo) return _VaultPalette.coralDark;
    if (resource.isBook) return AppColors.mint;
    return _VaultPalette.ink;
  }

  Widget _buildLessonsList(List<SavedItem> lessons) {
    if (lessons.isEmpty) {
      return _buildEmptyState(
        icon: PhosphorIconsRegular.bookOpen,
        title: 'No saved lessons yet',
        subtitle: 'Save lessons from your plan steps\nto read them anytime.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s8,
        AppSpacing.s20,
        AppSpacing.floatingNavBarHeight,
      ),
      itemCount: lessons.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s12),
      itemBuilder: (context, index) => _buildLessonItem(lessons[index]),
    );
  }

  Widget _buildLessonItem(SavedItem item) {
    final wordCount = item.content.split(' ').length;
    final readMinutes = (wordCount / 200).ceil();

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: _buildDismissBackground(),
      onDismissed: (_) {
        ref.read(libraryProvider.notifier).removeItem(item.id);
      },
      child: LearningResourceCard(
        title: item.title,
        kindLabel: 'Lesson',
        metaLabel: [
          if (item.source?.trim().isNotEmpty ?? false) item.source!.trim(),
          '$readMinutes min',
        ].join(' • '),
        subtitle: 'Legacy saved lesson',
        icon: PhosphorIconsRegular.bookOpen,
        accentColor: AppColors.mint,
        onTap: () {
          context.goToInAppLesson(title: item.title, markdown: item.content);
        },
      ),
    );
  }

  // ── Shared Empty State ──

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _VaultPalette.paper,
                borderRadius: AppRadii.brFull,
                border: Border.all(color: _VaultPalette.line),
              ),
              child: Center(
                child: Icon(icon, size: 32, color: _VaultPalette.coralDark),
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            Text(
              title,
              style: AppTypography.h3.copyWith(color: _VaultPalette.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              subtitle,
              style: AppTypography.body.copyWith(color: _VaultPalette.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
