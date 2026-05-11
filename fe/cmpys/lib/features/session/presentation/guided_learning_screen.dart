import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../controllers/session_controller.dart';
import '../models/session_models.dart';

abstract final class _LearningPalette {
  static const canvas = AppColors.bg;
  static const paper = Color(0xFFFFFFFF);
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
  static const mint = AppColors.mint;
  static const coral = AppColors.brandAccent;
  static const coralDark = AppColors.brandAccentDark;
}

class GuidedLearningScreen extends ConsumerStatefulWidget {
  const GuidedLearningScreen({super.key, this.topic = 'My Plan'});

  final String topic;

  @override
  ConsumerState<GuidedLearningScreen> createState() =>
      _GuidedLearningScreenState();
}

class _GuidedLearningScreenState extends ConsumerState<GuidedLearningScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  List<LearningMaterial> _materials = [];
  bool _isLoadingMaterials = true;

  @override
  void initState() {
    super.initState();
    _fetchMaterials();
  }

  Future<void> _fetchMaterials() async {
    final materials = await ref
        .read(sessionControllerProvider.notifier)
        .fetchLearningMaterials(widget.topic);

    if (!mounted) return;
    setState(() {
      _materials = materials;
      _isLoadingMaterials = false;
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: AppDurations.normal,
      curve: Curves.easeOutCubic,
    );
  }

  void _submitMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    ref
        .read(sessionControllerProvider.notifier)
        .sendGuidedLearningMessage(text);
    _textController.clear();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionControllerProvider);
    final isStreaming = state is SessionActive && state.isStreaming;

    return Scaffold(
      backgroundColor: _LearningPalette.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _LearningPalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _LearningPalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.52, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _LearningHeader(
                topic: widget.topic,
                onDone: () => context.go('/home'),
              ),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    _buildMaterialsSection(),
                    const SizedBox(height: 14),
                    _TutorPanel(topic: widget.topic, state: state),
                  ],
                ),
              ),
              _LearningComposer(
                controller: _textController,
                isStreaming: isStreaming,
                onSend: _submitMessage,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialsSection() {
    if (_isLoadingMaterials) {
      return const _MaterialsLoadingCard();
    }

    if (_materials.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          title: 'Recommended materials',
          subtitle: '${_materials.length} resources',
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 162,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _materials.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              return _LearningMaterialCard(material: _materials[index]);
            },
          ),
        ),
      ],
    );
  }
}

class _LearningHeader extends StatelessWidget {
  const _LearningHeader({required this.topic, required this.onDone});

  final String topic;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _LearningPalette.paper.withValues(alpha: 0.92),
          borderRadius: AppRadii.br20,
          border: Border.all(color: _LearningPalette.line),
          boxShadow: [
            BoxShadow(
              color: _LearningPalette.ink.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _LearningPalette.mint,
                borderRadius: AppRadii.br12,
              ),
              child: const Icon(
                Icons.school_outlined,
                color: _LearningPalette.ink,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Guided learning',
                    style: AppTypography.captionUpper.copyWith(
                      color: _LearningPalette.coralDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    topic,
                    style: AppTypography.h4.copyWith(
                      color: _LearningPalette.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Finish learning',
              onPressed: onDone,
              icon: const Icon(Icons.check),
              color: _LearningPalette.ink,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: AppTypography.h4.copyWith(color: _LearningPalette.ink),
        ),
        const Spacer(),
        Text(
          subtitle,
          style: AppTypography.caption.copyWith(color: _LearningPalette.muted),
        ),
      ],
    );
  }
}

class _MaterialsLoadingCard extends StatelessWidget {
  const _MaterialsLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _LearningPalette.paper,
        borderRadius: AppRadii.br16,
        border: Border.all(color: _LearningPalette.line),
      ),
      child: const Row(
        children: [
          CircularProgressIndicator(color: _LearningPalette.coral),
          SizedBox(width: 14),
          Text('Loading recommended resources...'),
        ],
      ),
    );
  }
}

class _LearningMaterialCard extends StatelessWidget {
  const _LearningMaterialCard({required this.material});

  final LearningMaterial material;

  Future<void> _open(BuildContext context) async {
    if (material.type == 'video' && material.url.trim().isNotEmpty) {
      context.goToPlanVideo(
        title: material.title,
        url: material.url,
        materialId: material.contentResourceId,
        reason: material.summary,
      );
      return;
    }

    final url = Uri.tryParse(material.url);
    if (url == null) return;
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = material.type == 'video';

    return SizedBox(
      width: 280,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: AppRadii.br16,
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _LearningPalette.paper,
              borderRadius: AppRadii.br16,
              border: Border.all(color: _LearningPalette.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isVideo
                          ? Icons.play_circle_outline
                          : Icons.article_outlined,
                      color: isVideo
                          ? _LearningPalette.coralDark
                          : _LearningPalette.ink,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        material.title,
                        style: AppTypography.bodyMedium.copyWith(
                          color: _LearningPalette.ink,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  material.summary,
                  style: AppTypography.caption.copyWith(
                    color: _LearningPalette.muted,
                    height: 1.35,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TutorPanel extends StatelessWidget {
  const _TutorPanel({required this.topic, required this.state});

  final String topic;
  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final content = state is SessionActive
        ? (state as SessionActive).streamedContent
        : 'Ask a question about $topic and I will tutor you through the next useful step.';
    final error = state is SessionActive
        ? (state as SessionActive).error
        : null;
    final isStreaming =
        state is SessionActive && (state as SessionActive).isStreaming;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _LearningPalette.paper,
        borderRadius: AppRadii.br16,
        border: Border.all(color: _LearningPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tutor thread',
            style: AppTypography.captionUpper.copyWith(
              color: _LearningPalette.coralDark,
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            content.isEmpty ? 'Ready when you are.' : content,
            style: AppTypography.body.copyWith(
              color: _LearningPalette.ink,
              height: 1.6,
            ),
          ),
          if (isStreaming) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(color: _LearningPalette.coral),
          ],
          if (error != null) ...[
            const SizedBox(height: 14),
            Text(
              error,
              style: AppTypography.caption.copyWith(
                color: _LearningPalette.coralDark,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LearningComposer extends StatelessWidget {
  const _LearningComposer({
    required this.controller,
    required this.isStreaming,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isStreaming;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: _LearningPalette.paper.withValues(alpha: 0.94),
        border: const Border(top: BorderSide(color: _LearningPalette.line)),
        boxShadow: [
          BoxShadow(
            color: _LearningPalette.ink.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _LearningPalette.canvas,
                  borderRadius: AppRadii.br16,
                  border: Border.all(color: _LearningPalette.line),
                ),
                child: TextField(
                  controller: controller,
                  enabled: !isStreaming,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: AppTypography.body.copyWith(
                    color: _LearningPalette.ink,
                  ),
                  cursorColor: _LearningPalette.coral,
                  decoration: InputDecoration(
                    hintText: isStreaming
                        ? 'Tutor is thinking...'
                        : 'Ask your tutor...',
                    hintStyle: AppTypography.body.copyWith(
                      color: _LearningPalette.muted,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: _LearningPalette.coral,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _LearningPalette.line,
              ),
              onPressed: isStreaming ? null : onSend,
              icon: const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    );
  }
}
