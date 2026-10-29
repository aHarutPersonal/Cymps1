import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../app/env.dart';
import '../../../core/reading/lesson_fences.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/ui/v3/lesson_blocks/illustration_hero.dart';
import '../../../core/ui/v3/v3.dart';
import '../../cmpys/data/reported_win.dart' show recordDimForCategory;
import '../../cmpys/state/cmpys_store.dart';
import '../../cmpys/state/reader_settings.dart';
import '../../cmpys/state/today_data.dart' show accessTypeForMaterial;
import '../data/plan_repository.dart';
import '../models/plan_models.dart';
import '../state/current_plan_provider.dart';
import 'achievement_sheet.dart';
import 'book_narration_checkpoint.dart';
import 'book_reader_screen.dart';
import 'lesson_practice_screen.dart';
import 'material_reader_screen.dart';
import 'material_row.dart';
import 'material_video_screen.dart';
import 'material_web_screen.dart';
import 'reader_settings_sheet.dart';

String _normalizedTitle(String value) {
  final lowered = value.toLowerCase().trim();
  final asciiNormalized = lowered.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  return asciiNormalized.isEmpty ? lowered : asciiNormalized;
}

List<PlanMaterialDetail> matchLessonMaterials(
  List<String> resourceTitles,
  List<PlanMaterialDetail> materials,
) {
  final wanted = resourceTitles.map(_normalizedTitle).toSet();
  return materials
      .where((material) => wanted.contains(_normalizedTitle(material.title)))
      .toList();
}

final _referenceItem = RegExp(r'^\s{0,3}(?:[-*+•]|\d+[.)])\s+');

/// The References markdown left once [matched] materials show as material
/// rows: a list item (with its continuation lines) that names a matched
/// material is dropped, because its row stands for it. Every other item,
/// with its "what it adds" text, and all non-list prose is kept, so no
/// reference text is lost. In particular an item that also names one of
/// [otherTitles] (the step's unmatched resource titles) is kept.
///
/// A matched title of at least two words and eight characters matches as a
/// whole-word phrase inside the item; a shorter one ("Focus") only matches
/// an item that is exactly that title, never a word inside a sentence.
/// Unmatched titles are found as whole-word phrases, so keeping errs on the
/// side of more text.
String unmatchedReferenceMarkdown(
  String markdown,
  List<PlanMaterialDetail> matched, {
  List<String> otherTitles = const [],
}) {
  final titles = [
    for (final material in matched)
      if (_normalizedTitle(material.title) case final title
          when title.isNotEmpty)
        title,
  ];
  final others = [
    for (final title in otherTitles.map(_normalizedTitle))
      if (title.isNotEmpty && !titles.contains(title)) title,
  ];
  bool phrase(String text, String title) => ' $text '.contains(' $title ');
  bool distinctive(String title) =>
      title.split(' ').length >= 2 && title.length >= 8;
  bool namesMatched(List<String> lines) {
    final text = _normalizedTitle(
      lines.join(' ').replaceFirst(_referenceItem, ''),
    );
    if (others.any((title) => phrase(text, title))) return false;
    return titles.any(
      (title) => distinctive(title) ? phrase(text, title) : text == title,
    );
  }

  final kept = <String>[];
  List<String>? item;
  var blank = false;
  void flush() {
    final current = item;
    if (current != null) {
      // A dropped item leaves a blank line, so the text after it never
      // becomes a lazy continuation of the item before it.
      kept.addAll(namesMatched(current) ? const [''] : current);
    }
    item = null;
  }

  for (final line in markdown.split('\n')) {
    final current = item;
    if (_referenceItem.hasMatch(line)) {
      flush();
      item = [line];
    } else if (current != null &&
        (line.trim().isEmpty || line.startsWith(' ') || !blank)) {
      current.add(line);
    } else {
      flush();
      kept.add(line);
    }
    blank = line.trim().isEmpty;
  }
  flush();
  return kept.join('\n').trim();
}

/// The mission's week for the reader's kicker: "3", or "3–4" for a mission
/// spanning weeks.
String lessonWeekLabel(BackendPlanItem item) => item.weekEnd > item.weekStart
    ? '${item.weekStart}–${item.weekEnd}'
    : '${item.weekStart}';

/// The tutorial reader (design v3/tutorial.jsx `LessonScreen`): one
/// continuous scroll with the design's sections, a progress bar, the title
/// fading into the top bar, Contents and Reading settings sheets, native
/// lesson blocks, references as material rows and the practice CTA.
class LessonReaderScreen extends ConsumerStatefulWidget {
  const LessonReaderScreen({
    super.key,
    required this.itemId,
    required this.missionTitle,
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
    required this.materials,
    required this.completed,
    this.week,
    this.artifactJobId,
    this.nextTitle = '',
    this.shellBranchIndex = ActiveBookNarrationResume.planBranchIndex,
  });

  final String itemId;
  final String missionTitle;
  final PlanStepDetail step;
  final int stepNumber;
  final int totalSteps;
  final List<PlanMaterialDetail> materials;
  final bool completed;

  /// The mission's week ("3" or "3–4"); the kicker omits it when null.
  final String? week;
  final String? artifactJobId;

  /// The next step's title, for the finish celebration ("Tutorial n+1,
  /// ‹title›, is now open."); blank when unknown or this is the last step.
  final String nextTitle;

  /// The shell branch this reader was opened from (Today or Plan), handed to
  /// the book reader so its player and a cold-start resume name and restore
  /// the right tab.
  final int shellBranchIndex;

  /// The reader's scroll view.
  static const scrollKey = ValueKey('lesson-reader-scroll');

  @override
  ConsumerState<LessonReaderScreen> createState() => _LessonReaderScreenState();
}

/// One reader section: its kicker label (null for an untitled lead) and body.
class _Section {
  const _Section(this.id, this.label, this.pieces);

  final String id;
  final String? label;
  final List<LessonPiece> pieces;
}

class _LessonReaderScreenState extends ConsumerState<LessonReaderScreen> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _progress = ValueNotifier(0);
  final Map<String, GlobalKey> _headingKeys = {};
  late final List<_Section> _sections;
  late final List<PlanMaterialDetail> _references;
  bool _completing = false;
  bool _practicePassed = false;
  late String? _artifactJobId = widget.artifactJobId;
  final Map<String, String> _resolvedBookGuideIds = {};
  final Set<String> _preparingBookGuideKeys = {};

  String get _unit => widget.step.isTutorial ? 'Tutorial' : 'Lesson';

  @override
  void initState() {
    super.initState();
    _references = matchLessonMaterials(widget.step.resources, widget.materials);
    final outline = outlineLesson(widget.step.lessonContent ?? '');
    _sections = [
      for (final section in outline.sections)
        _Section(section.id, section.label, section.pieces),
      // Matched references still get their section when the lesson has no
      // References heading of its own.
      if (_references.isNotEmpty &&
          !outline.sections.any((section) => section.id == 'refs'))
        const _Section('refs', 'References', []),
    ];
    for (final section in _sections) {
      if (section.label != null) _headingKeys[section.id] = GlobalKey();
    }
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final max = position.maxScrollExtent;
    _progress.value = max <= 0
        ? 0
        : (position.pixels / max).clamp(0.0, 1.0).toDouble();
  }

  Future<void> _finish() async {
    if (_completing) return;
    if (widget.completed) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _completing = true);
    final bool completed;
    try {
      completed =
          (await ref
                  .read(planRepositoryProvider)
                  .toggleStepComplete(
                    widget.itemId,
                    widget.step.id,
                    artifactJobId: _artifactJobId,
                    // The desired state, never a toggle: a retry after a
                    // committed-but-lost response is a no-op, so it can't
                    // un-complete the step.
                    complete: true,
                  ))
              .completed;
    } catch (_) {
      // A failed completion: the retry CTA, and no celebration.
      if (!mounted) return;
      setState(() => _completing = false);
      showV3Toast(
        context,
        'Couldn’t complete this ${_unit.toLowerCase()}. Try again.',
        icon: V3Icons.alert,
        tone: V3ToastTone.warn,
      );
      return;
    }
    if (!mounted) return;
    // Celebrate only a completion the server confirmed, outside the
    // completion's error handling: the step is done, so a celebration or
    // record error must never offer a retry (the toggle would un-complete).
    if (completed && widget.step.isTutorial) {
      try {
        await _celebrate();
      } catch (_) {
        /* The step stays complete; the celebration is a courtesy. */
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(completed);
  }

  /// The tutorial celebration (`v3/app.jsx`), after the step is complete.
  /// "Add to your record" opens the achievement sheet; a confirmed
  /// achievement is saved as the learner's own (`manual`, with this plan and
  /// cycle; a `plan_item` source would overwrite the mission's achievement)
  /// and added to the record on this device as an assessed win, under its
  /// category's dimension (Practice when it has none), with the server id.
  Future<void> _celebrate() async {
    final achievement = LessonPracticeScreen.achievementFor(widget.step.title);
    final choice = await showCelebration(
      context,
      Celebration.tutorial(
        completed: widget.stepNumber,
        total: widget.totalSteps,
        nextTitle: widget.nextTitle,
        achievement: achievement,
      ),
    );
    if (!mounted || choice != CelebrationResult.addToRecord) return;
    final plan = ref.read(currentPlanProvider).plan;
    final plans = ref.read(planRepositoryProvider);
    final store = ref.read(cmpysStoreProvider.notifier);
    final age = ref.read(cmpysStoreProvider).user.age;
    await AchievementSheet.show(
      context,
      initial: achievement,
      age: age > 0 ? age : null,
      onSave: (title, category) async {
        final serverId = await plans.saveAchievement(
          title: title,
          category: category,
          source: 'manual',
          planId: plan?.id,
          cycleNumber: plan?.cycleNumber ?? 1,
        );
        // With no age (0) the Record shows the win under "Undated" (the
        // sheet drops its "Age" tag). It has a server copy: `synced`, with
        // its id so the Record can delete both.
        store.addWin(
          title: title,
          dim: recordDimForCategory(category) ?? 'practice',
          age: age,
          source: 'auto',
          assessed: true,
          synced: true,
          serverId: serverId,
        );
      },
    );
  }

  Future<void> _openPractice() async {
    final passed = await Navigator.of(context, rootNavigator: true).push<bool>(
      CmpysPageRoute<bool>(
        builder: (_) => LessonPracticeScreen(
          itemId: widget.itemId,
          stepId: widget.step.id,
          artifactJobId: _artifactJobId,
          onArtifactRefreshed: (artifact) {
            if (mounted) setState(() => _artifactJobId = artifact);
          },
          lessonTitle: widget.step.title,
          lessonContent: widget.step.lessonContent ?? '',
          dark: ref.read(readerSettingsProvider).theme == ReaderTheme.dark,
          isTutorial: widget.step.isTutorial,
          tutorialNumber: widget.stepNumber,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _practicePassed = passed == true);
    // A true result only comes from practice's explicit "Finish lesson".
    if (_practicePassed) await _finish();
  }

  // ── navigation within the scroll ──────────────────────────────────────────

  /// Scrolls [id]'s heading to just under the top bar (the design's
  /// `offsetTop - 110`).
  Future<void> _jump(String id) async {
    final heading = _headingKeys[id]?.currentContext?.findRenderObject();
    if (heading == null || !_scroll.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(heading);
    if (viewport == null) return;
    final position = _scroll.position;
    final target =
        (viewport.getOffsetToReveal(heading, 0).offset -
                _topChrome(context) -
                8)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    if (MotionConfig.enabled(context)) {
      await _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 520),
        curve: AppMotion.io,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  double _topChrome(BuildContext context) =>
      MediaQuery.paddingOf(context).top + 52 + 3;

  Future<void> _showContents() async {
    final labelled = [
      for (final section in _sections)
        if (section.label != null) section,
    ];
    final id = await showV3Sheet<String>(
      context,
      title: 'Contents',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < labelled.length; i++)
            V3Pressable(
              onTap: () => Navigator.of(sheetContext).pop(labelled[i].id),
              pressedScale: 1,
              semanticLabel: labelled[i].label,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : const Border(top: BorderSide(color: AppColors.hair)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text(
                        '${i + 1}',
                        style: AppTypography.sans(12, FontWeight.w700)
                            .merge(AppTypography.tnum)
                            .copyWith(color: AppColors.ink3),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        labelled[i].label!,
                        style: AppTypography.sans(
                          15.5,
                          FontWeight.w500,
                        ).copyWith(color: AppColors.ink),
                      ),
                    ),
                    const V3Icon(
                      V3Icons.right,
                      size: 16,
                      color: AppColors.ink3,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (id != null && mounted) await _jump(id);
  }

  Future<void> _showSettings() => showReaderSettingsSheet(context);

  // ── materials ─────────────────────────────────────────────────────────────

  Future<void> _showMaterial(PlanMaterialDetail material) async {
    final open = await showV3Sheet<bool>(
      context,
      builder: (sheetContext) => MaterialSheetBody(
        material: material,
        type: _accessType(material),
        onOpen: () => Navigator.of(sheetContext).pop(true),
      ),
    );
    if (open == true && mounted) await _openMaterial(material);
  }

  AccessType _accessType(PlanMaterialDetail material) => accessTypeForMaterial(
    material,
    resolvedGuideId: _bookResourceId(material),
  );

  Future<void> _openMaterial(PlanMaterialDetail material) async {
    final videoId = material.youtubeVideoId;
    final canonicalKey = (material.canonicalKey ?? '').trim();
    var bookResourceId = _bookResourceId(material);
    BookReadingSource? readingSource;
    if (material.type == 'book' &&
        bookResourceId == null &&
        material.directUrl == null &&
        canonicalKey.isNotEmpty) {
      if (_preparingBookGuideKeys.contains(canonicalKey)) return;
      setState(() => _preparingBookGuideKeys.add(canonicalKey));
      try {
        final repository = ref.read(planRepositoryProvider);
        final access = await repository.resolveBookReadingAccess(
          canonicalKey,
          material.title,
          material.authorOrCreator,
        );
        bookResourceId = access.resourceId;
        readingSource = access.source;
        if (bookResourceId == null && readingSource == null) {
          if (access.unavailable != null) throw access.unavailable!;
          bookResourceId = await repository.waitForContentResourceId(
            canonicalKey,
          );
        }
      } on BookGuideUnavailableException catch (error) {
        if (!mounted) return;
        setState(() => _preparingBookGuideKeys.remove(canonicalKey));
        showV3Toast(
          context,
          error.message,
          icon: V3Icons.alert,
          tone: V3ToastTone.warn,
        );
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() => _preparingBookGuideKeys.remove(canonicalKey));
        showV3Toast(
          context,
          'Could not check the book guide. Try again.',
          icon: V3Icons.alert,
          tone: V3ToastTone.warn,
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _preparingBookGuideKeys.remove(canonicalKey);
        if (bookResourceId != null) {
          _resolvedBookGuideIds[canonicalKey] = bookResourceId;
        }
      });
      if (bookResourceId == null && readingSource == null) {
        showV3Toast(
          context,
          'The guide is taking longer than expected. Try again in a moment.',
          icon: V3Icons.clock,
          tone: V3ToastTone.warn,
        );
        return;
      }
    }
    Widget? screen;
    final tutorialTitle = widget.step.title.trim();
    final openedFrom = tutorialTitle.isEmpty
        ? null
        : 'Tutorial · $tutorialTitle';
    if (material.type == 'book' && bookResourceId != null) {
      screen = BookReaderScreen(
        resourceId: bookResourceId,
        fallbackTitle: material.title,
        fallbackSourceUrl: material.directUrl,
        shellBranchIndex: widget.shellBranchIndex,
      );
    } else if (readingSource != null) {
      screen = MaterialWebScreen(
        title: material.title,
        url: readingSource.url,
        sourceDescription: readingSource.description,
        initialSectionTitle: readingSource.sectionTitle,
        access: readingSource.scope == 'excerpt'
            ? AccessType.excerpt
            : AccessType.original,
        openedFrom: openedFrom,
      );
    } else if (videoId != null) {
      screen = MaterialVideoScreen(material: material, videoId: videoId);
    } else if (material.prefersExternalLink) {
      screen = MaterialWebScreen(
        title: material.title,
        url: material.directUrl!,
        access: AccessType.web,
        openedFrom: openedFrom,
      );
    } else if (material.hasInAppContent) {
      screen = MaterialReaderScreen(material: material);
    } else if (material.directUrl != null) {
      screen = MaterialWebScreen(
        title: material.title,
        url: material.directUrl!,
        access: AccessType.web,
        openedFrom: openedFrom,
      );
    }
    if (screen == null) return;
    final navigator = screen is BookReaderScreen
        ? Navigator.of(context)
        : Navigator.of(context, rootNavigator: true);
    navigator.push(CmpysPageRoute<void>(builder: (_) => screen!));
  }

  String? _bookResourceId(PlanMaterialDetail material) {
    final directId = material.contentResourceId?.trim();
    if (directId != null && directId.isNotEmpty) return directId;
    final canonicalKey = material.canonicalKey?.trim();
    if (canonicalKey == null || canonicalKey.isEmpty) return null;
    return _resolvedBookGuideIds[canonicalKey];
  }

  bool _isPreparingBookGuide(PlanMaterialDetail material) {
    final canonicalKey = material.canonicalKey?.trim();
    return canonicalKey != null &&
        canonicalKey.isNotEmpty &&
        _preparingBookGuideKeys.contains(canonicalKey);
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final theme = settings.theme;
    final dark = theme == ReaderTheme.dark;
    final practice = widget.step.effectivePracticeMinutes;
    final done = widget.completed;
    // Practice passed but marking the step done failed: retry it directly.
    final retry = !done && _practicePassed;
    final footer = V3Button(
      full: true,
      icon: retry ? V3Icons.check : V3Icons.edit,
      kind: done ? V3ButtonKind.dark : V3ButtonKind.primary,
      loading: _completing,
      onPressed: _completing
          ? null
          : retry
          ? _finish
          : _openPractice,
      child: Text(
        done
            ? 'Review practice & attempts'
            : retry
            ? 'Complete ${_unit.toLowerCase()}'
            : practice == null
            ? 'Open practice'
            : 'Open practice · $practice min',
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: theme.bg,
        body: Padding(
          padding: EdgeInsets.only(
            bottom: AppShell.isWithinShell(context)
                ? AppShell.bottomNavClearance(context)
                : 0,
          ),
          child: V3FooterScaffold(
            background: theme.bg,
            footer: footer,
            body: (context, bottom) => Stack(
              children: [
                Positioned.fill(child: _body(context, settings, bottom)),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _topBar(context, theme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, ReaderTheme theme) {
    final dark = theme == ReaderTheme.dark;
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        // linear-gradient(bg 70%, transparent) behind the bar.
        Positioned.fill(
          bottom: -16,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [theme.bg, theme.bg, theme.bg.withValues(alpha: 0)],
                  stops: const [0, .7, 1],
                ),
              ),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(top: top),
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 16),
                  child: Row(
                    children: [
                      V3IconButton(
                        icon: V3Icons.left,
                        dark: dark,
                        label: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _progress,
                          builder: (context, p, child) => AnimatedOpacity(
                            opacity: p > .04 ? 1 : 0,
                            duration: MotionConfig.enabled(context)
                                ? const Duration(milliseconds: 300)
                                : Duration.zero,
                            child: child,
                          ),
                          child: ExcludeSemantics(
                            child: Text(
                              widget.step.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.sans(
                                15.5,
                                FontWeight.w600,
                              ).copyWith(color: theme.fg),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      V3IconButton(
                        icon: V3Icons.list,
                        dark: dark,
                        label: 'Contents',
                        onPressed: _showContents,
                      ),
                      const SizedBox(width: 8),
                      V3IconButton(
                        icon: V3Icons.type,
                        dark: dark,
                        label: 'Reading settings',
                        onPressed: _showSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ValueListenableBuilder<double>(
                valueListenable: _progress,
                builder: (context, p, _) => Semantics(
                  label: 'Reading progress',
                  value: '${(p * 100).round()}%',
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: theme.hair,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: p,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.ember,
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _body(BuildContext context, ReaderSettings settings, double bottom) {
    final theme = settings.theme;
    final fs = settings.fontSize;
    final step = widget.step;
    final read = step.effectiveReadingMinutes;
    final practice = step.effectivePracticeMinutes;
    final illustration = step.illustration;
    final kicker = [
      '$_unit ${widget.stepNumber} of ${widget.totalSteps}',
      if (widget.week != null) 'Week ${widget.week}',
    ].join(' · ');
    return SingleChildScrollView(
      key: LessonReaderScreen.scrollKey,
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
        22,
        _topChrome(context) + 14,
        22,
        bottom + 24,
      ),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.completed)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: V3Rise(
                    child: V3Tag(
                      background: AppColors.sageSoft,
                      color: AppColors.sage2,
                      icon: V3Icons.check,
                      // No per-tutorial score exists in the data, so the
                      // design's "Completed · score" shows as "Completed".
                      child: const Text('Completed'),
                    ),
                  ),
                ),
              ),
            V3Rise(
              delay: const Duration(milliseconds: 30),
              child: Text(
                kicker.toUpperCase(),
                style: AppTypography.kick.copyWith(color: theme.fg2),
              ),
            ),
            const SizedBox(height: 10),
            V3Rise(
              delay: const Duration(milliseconds: 80),
              child: Text(
                step.title,
                style: AppTypography.display(44).copyWith(color: theme.fg),
              ),
            ),
            if (read != null || practice != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: V3Rise(
                  delay: const Duration(milliseconds: 130),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (read != null)
                        V3Tag(
                          icon: V3Icons.book,
                          background: AppColors.irisSoft,
                          color: AppColors.iris2,
                          child: Text('$read min read'),
                        ),
                      if (practice != null)
                        V3Tag(
                          icon: V3Icons.edit,
                          background: AppColors.emberSoft,
                          color: AppColors.ember2,
                          child: Text('$practice min practice'),
                        ),
                    ],
                  ),
                ),
              ),
            if (illustration != null) ...[
              const SizedBox(height: 22),
              IllustrationHero(
                url: _mediaUrl(illustration.url),
                alt: illustration.alt.isEmpty ? step.title : illustration.alt,
                aspectRatio: illustration.aspectRatio,
                theme: theme,
              ),
            ],
            for (final section in _sections) ..._section(section, theme, fs),
          ],
        ),
      ),
    );
  }

  /// The API serves illustrations from a relative `/media/tutorials/` path.
  String _mediaUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.hasScheme) return url;
    return Uri.parse(Env.apiBaseUrl).resolveUri(parsed).toString();
  }

  /// The design's `H`: an ember rule and the kicker label.
  Widget _heading(_Section section, ReaderTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 40, bottom: 12),
      child: Semantics(
        header: true,
        // Keyed on the kicker row itself (not the 40 pt margin above it), so
        // a Contents jump lands the label just under the top bar.
        child: Row(
          key: _headingKeys[section.id],
          children: [
            Container(width: 16, height: 1.5, color: AppColors.ember),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                section.label!.toUpperCase(),
                style: AppTypography.kick.copyWith(color: theme.fg2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(_Section section, ReaderTheme theme, double fs) {
    final children = <Widget>[];
    void add(Widget child) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 14));
      children.add(child);
    }

    Widget prose(String markdown) => CmpysMarkdown(
      markdown,
      readerTheme: theme,
      fontSize: section.id == 'why' ? fs + 2 : fs,
      lineHeight: section.id == 'why' ? 1.55 : 1.65,
    );

    if (section.id == 'refs') {
      for (var i = 0; i < _references.length; i++) {
        if (i > 0) children.add(const SizedBox(height: 8));
        final material = _references[i];
        final preparing = _isPreparingBookGuide(material);
        children.add(
          MaterialRow(
            material: material,
            type: _accessType(material),
            preparing: preparing,
            theme: theme,
            onTap: preparing ? null : () => _showMaterial(material),
          ),
        );
      }
    }
    for (final piece in section.pieces) {
      switch (piece) {
        case LessonFence(:final kind, :final body):
          add(
            SelectionContainer.disabled(
              child: LessonFenceBlock(
                kind: kind,
                body: body,
                theme: theme,
                fontSize: fs,
              ),
            ),
          );
        case LessonProse(:final markdown) when section.id == 'refs':
          // Matched references are the rows above; the rest stays prose.
          final rest = unmatchedReferenceMarkdown(
            markdown,
            _references,
            otherTitles: widget.step.resources,
          );
          if (rest.isNotEmpty) add(prose(rest));
        case LessonProse(:final markdown) when section.id == 'errors':
          final split = splitErrorItems(markdown);
          if (split.lead.isNotEmpty) add(prose(split.lead));
          for (var i = 0; i < split.items.length; i++) {
            if (i > 0) children.add(const SizedBox(height: 8));
            final card = _errorCard(
              split.items[i],
              theme,
              ValueKey('lesson-error-$i'),
            );
            i == 0 ? add(card) : children.add(card);
          }
          if (split.tail.isNotEmpty) add(prose(split.tail));
        case LessonProse(:final markdown):
          add(prose(markdown));
      }
    }
    if (children.isEmpty && section.label == null) return const [];
    return [if (section.label != null) _heading(section, theme), ...children];
  }

  /// A Common errors item: the design's ✕ card.
  Widget _errorCard(String markdown, ReaderTheme theme, Key key) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.hair),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.dangerSoft,
              shape: BoxShape.circle,
            ),
            child: const V3Icon(
              V3Icons.x,
              size: 12,
              strokeWidth: 3,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _inlineMarkdown(
              markdown,
              AppTypography.sans(14.5).copyWith(color: theme.fg, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// One error item's inline markdown (bold, italics, code) in [style].
Widget _inlineMarkdown(String markdown, TextStyle style) => MarkdownBody(
  data: markdown,
  styleSheet: MarkdownStyleSheet(
    p: style,
    strong: style.copyWith(fontWeight: FontWeight.w600),
    em: style.copyWith(fontStyle: FontStyle.italic),
    code: style,
  ),
);
