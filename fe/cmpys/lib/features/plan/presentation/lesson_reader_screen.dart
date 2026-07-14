import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../data/plan_repository.dart';
import '../models/plan_models.dart';
import 'book_reader_screen.dart';
import 'material_reader_screen.dart';
import 'material_video_screen.dart';
import 'material_web_screen.dart';

class LessonSection {
  const LessonSection({required this.title, required this.markdown});

  final String title;
  final String markdown;
}

List<LessonSection> splitLessonSections(String markdown) {
  final sections = <LessonSection>[];
  final buffer = StringBuffer();
  var title = 'Lesson overview';

  void flush() {
    final body = buffer.toString().trim();
    if (body.isNotEmpty) {
      sections.add(LessonSection(title: title, markdown: body));
    }
    buffer.clear();
  }

  for (final line in markdown.split('\n')) {
    if (line.startsWith('## ')) {
      flush();
      title = line.substring(3).trim();
    } else if (!line.startsWith('# ')) {
      buffer.writeln(line);
    }
  }
  flush();

  return sections.isEmpty
      ? [LessonSection(title: 'Lesson', markdown: markdown)]
      : sections;
}

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
  });

  final String itemId;
  final String missionTitle;
  final PlanStepDetail step;
  final int stepNumber;
  final int totalSteps;
  final List<PlanMaterialDetail> materials;
  final bool completed;

  @override
  ConsumerState<LessonReaderScreen> createState() => _LessonReaderScreenState();
}

class _LessonReaderScreenState extends ConsumerState<LessonReaderScreen> {
  late final PageController _pageController;
  late final List<LessonSection> _sections;
  late final List<PlanMaterialDetail> _references;
  int _page = 0;
  int _theme = 0;
  double _fontSize = 18;
  bool _completing = false;
  final Map<String, String> _resolvedBookGuideIds = {};
  final Set<String> _preparingBookGuideKeys = {};

  Color get _background => switch (_theme) {
    1 => const Color(0xFFF7F0E3),
    2 => const Color(0xFF1B1C21),
    _ => const Color(0xFFFAFAF8),
  };

  Color get _ink => _theme == 2 ? const Color(0xFFF2F0EA) : AppColors.ink;

  Color get _muted => _theme == 2 ? const Color(0xFFA8A8B2) : AppColors.ink3;

  Color get _chrome => _theme == 2 ? const Color(0xFF25262D) : Colors.white;

  int get _totalPages => _sections.length + (_references.isEmpty ? 0 : 1);
  bool get _onReferences => _page >= _sections.length;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _sections = splitLessonSections(widget.step.lessonContent ?? '');
    final wanted = widget.step.resources.map((e) => e.toLowerCase()).toSet();
    final matched = widget.materials
        .where((material) => wanted.contains(material.title.toLowerCase()))
        .toList();
    _references = matched.isNotEmpty ? matched : widget.materials;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_completing) return;
    if (widget.completed) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _completing = true);
    try {
      final result = await ref
          .read(planRepositoryProvider)
          .toggleStepComplete(widget.itemId, widget.step.id);
      if (!mounted) return;
      Navigator.of(context).pop(result.completed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _completing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn’t complete this lesson. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _next() async {
    if (_page < _totalPages - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      await _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            LinearProgressIndicator(
              value: _totalPages == 0 ? 0 : (_page + 1) / _totalPages,
              minHeight: 3,
              backgroundColor: _muted.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.green),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _totalPages,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (_, index) => index < _sections.length
                    ? _sectionPage(_sections[index], index)
                    : _referencesPage(),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: IconButton.styleFrom(
              backgroundColor: _chrome,
              side: BorderSide(color: _muted.withValues(alpha: 0.15)),
            ),
            icon: Icon(Icons.chevron_left_rounded, color: _muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.missionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: _ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Lesson ${widget.stepNumber} of ${widget.totalSteps} · ${_onReferences ? 'References' : _sections[_page].title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: _muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Contents',
            onPressed: _showContents,
            icon: Icon(Icons.format_list_bulleted_rounded, color: _muted),
          ),
          IconButton(
            tooltip: 'Reading settings',
            onPressed: _showSettings,
            icon: Icon(Icons.format_size_rounded, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _sectionPage(LessonSection section, int index) {
    return SingleChildScrollView(
      key: PageStorageKey<String>('${widget.step.id}-$index'),
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 52),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LESSON ${widget.stepNumber} · PART ${index + 1} OF ${_sections.length}',
                  style: AppTypography.kicker.copyWith(
                    color: AppColors.green,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  section.title,
                  style: AppTypography.h1.copyWith(
                    color: _ink,
                    fontSize: 29,
                    height: 1.16,
                    letterSpacing: -0.5,
                  ),
                ),
                if (index == 0) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _timeChip(
                        PhosphorIconsRegular.bookOpenText,
                        '${widget.step.readingMinutes ?? _estimatedReadingMinutes} min read',
                      ),
                      _timeChip(
                        PhosphorIconsRegular.timer,
                        '${widget.step.practiceMinutes ?? _estimatedPracticeMinutes} min practice',
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                CmpysMarkdown(
                  section.markdown,
                  onDark: _theme == 2,
                  fontSize: _fontSize,
                  lineHeight: 1.72,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int get _estimatedReadingMinutes {
    final words = (widget.step.lessonContent ?? '')
        .split(RegExp(r'\s+'))
        .length;
    return (words / 200).ceil().clamp(1, 60);
  }

  int get _estimatedPracticeMinutes =>
      ((widget.step.estimateMinutes ?? 45) - _estimatedReadingMinutes).clamp(
        20,
        55,
      );

  Widget _timeChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _chrome,
        borderRadius: AppRadii.brFull,
        border: Border.all(color: _muted.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _muted),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTypography.captionMedium.copyWith(
              color: _muted,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _referencesPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 52),
      children: [
        Text(
          'REFERENCES · USE WHEN NEEDED',
          style: AppTypography.kicker.copyWith(
            color: AppColors.ochre2,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 13),
        Text(
          'Go deeper without losing focus',
          style: AppTypography.h1.copyWith(
            color: _ink,
            fontSize: 29,
            height: 1.16,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          'These resources support this lesson. Use them when the lesson calls for more context—not as a detour from the practice.',
          style: AppTypography.body.copyWith(
            color: _muted,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        for (final material in _references) ...[
          _referenceCard(material),
          const SizedBox(height: 11),
        ],
      ],
    );
  }

  Widget _referenceCard(PlanMaterialDetail material) {
    final action = _materialAction(material);
    final preparingBookGuide = _isPreparingBookGuide(material);
    return CmpysCardSurface(
      color: _chrome,
      onTap: action == null || preparingBookGuide
          ? null
          : () => _openMaterial(material),
      pad: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 52,
            decoration: BoxDecoration(
              color: material.type == 'book'
                  ? AppColors.ochreSoft
                  : AppColors.greenSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              material.type == 'book'
                  ? PhosphorIconsRegular.bookOpen
                  : PhosphorIconsRegular.playCircle,
              color: material.type == 'book'
                  ? AppColors.ochre2
                  : AppColors.green2,
              size: 20,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: _ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  material.reason ??
                      material.authorOrCreator ??
                      'Lesson reference',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: _muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            Text(
              action,
              style: AppTypography.captionMedium.copyWith(
                color: AppColors.green2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.green2,
              size: 18,
            ),
          ],
        ],
      ),
    );
  }

  String? _materialAction(PlanMaterialDetail material) {
    if (material.type == 'book' && _bookResourceId(material) != null) {
      return 'Read book';
    }
    if (material.type == 'book' && (material.canonicalKey ?? '').isNotEmpty) {
      return _isPreparingBookGuide(material) ? 'Preparing…' : 'Open guide';
    }
    if (material.youtubeVideoId != null) return 'Watch';
    if (material.prefersExternalLink) return 'Open';
    if (material.hasInAppContent) return 'Read';
    if ((material.url ?? '').isNotEmpty) return 'Open';
    return null;
  }

  Future<void> _openMaterial(PlanMaterialDetail material) async {
    final videoId = material.youtubeVideoId;
    final canonicalKey = (material.canonicalKey ?? '').trim();
    var bookResourceId = _bookResourceId(material);
    if (material.type == 'book' &&
        bookResourceId == null &&
        canonicalKey.isNotEmpty) {
      if (_preparingBookGuideKeys.contains(canonicalKey)) return;
      setState(() => _preparingBookGuideKeys.add(canonicalKey));
      try {
        bookResourceId = await ref
            .read(planRepositoryProvider)
            .waitForContentResourceId(canonicalKey);
      } catch (_) {
        if (!mounted) return;
        setState(() => _preparingBookGuideKeys.remove(canonicalKey));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not check the book guide. Try again.'),
            behavior: SnackBarBehavior.floating,
          ),
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
      if (bookResourceId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The guide is taking longer than expected. Try again in a moment.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    Widget? screen;
    if (material.type == 'book' && bookResourceId != null) {
      screen = BookReaderScreen(
        resourceId: bookResourceId,
        fallbackTitle: material.title,
      );
    } else if (videoId != null) {
      screen = MaterialVideoScreen(material: material, videoId: videoId);
    } else if (material.prefersExternalLink) {
      screen = MaterialWebScreen(title: material.title, url: material.url!);
    } else if (material.hasInAppContent) {
      screen = MaterialReaderScreen(material: material);
    } else if ((material.url ?? '').isNotEmpty) {
      screen = MaterialWebScreen(title: material.title, url: material.url!);
    }
    if (screen == null) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(CmpysPageRoute<void>(builder: (_) => screen!));
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

  Widget _bottomBar() {
    final last = _page == _totalPages - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: _chrome,
        border: Border(top: BorderSide(color: _muted.withValues(alpha: 0.13))),
      ),
      child: Row(
        children: [
          if (_page > 0)
            IconButton(
              onPressed: () => _pageController.previousPage(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              ),
              icon: Icon(Icons.arrow_back_rounded, color: _muted),
            ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _completing ? null : _next,
            icon: _completing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                    size: 18,
                  ),
            label: Text(
              last
                  ? widget.completed
                        ? 'Close lesson'
                        : 'Complete lesson'
                  : 'Next',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.brFull),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showContents() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _chrome,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          children: [
            Text(
              'Lesson contents',
              style: AppTypography.h2.copyWith(color: _ink, fontSize: 23),
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < _sections.length; index++)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: index == _page
                      ? AppColors.green
                      : _muted.withValues(alpha: 0.12),
                  child: Text(
                    '${index + 1}',
                    style: AppTypography.captionMedium.copyWith(
                      color: index == _page ? Colors.white : _muted,
                    ),
                  ),
                ),
                title: Text(
                  _sections[index].title,
                  style: AppTypography.bodyMedium.copyWith(color: _ink),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
            if (_references.isNotEmpty)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.ochreSoft,
                  child: const Icon(
                    PhosphorIconsRegular.books,
                    color: AppColors.ochre2,
                    size: 18,
                  ),
                ),
                title: Text(
                  'References',
                  style: AppTypography.bodyMedium.copyWith(color: _ink),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pageController.animateToPage(
                    _sections.length,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _chrome,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reading settings',
                  style: AppTypography.h2.copyWith(color: _ink, fontSize: 23),
                ),
                Row(
                  children: [
                    Text('A', style: TextStyle(color: _ink, fontSize: 15)),
                    Expanded(
                      child: Slider(
                        value: _fontSize,
                        min: 15,
                        max: 23,
                        divisions: 8,
                        activeColor: AppColors.green,
                        onChanged: (value) {
                          setState(() => _fontSize = value);
                          setSheetState(() {});
                        },
                      ),
                    ),
                    Text('A', style: TextStyle(color: _ink, fontSize: 24)),
                  ],
                ),
                Row(
                  children: [
                    _themeButton(
                      0,
                      'Light',
                      const Color(0xFFFAFAF8),
                      setSheetState,
                    ),
                    const SizedBox(width: 8),
                    _themeButton(
                      1,
                      'Warm',
                      const Color(0xFFF7F0E3),
                      setSheetState,
                    ),
                    const SizedBox(width: 8),
                    _themeButton(
                      2,
                      'Dark',
                      const Color(0xFF1B1C21),
                      setSheetState,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _themeButton(
    int value,
    String label,
    Color color,
    StateSetter setSheetState,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _theme = value);
          setSheetState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: color,
            borderRadius: AppRadii.br12,
            border: Border.all(
              color: _theme == value ? AppColors.green : AppColors.hair2,
              width: _theme == value ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.captionMedium.copyWith(
              color: value == 2 ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
