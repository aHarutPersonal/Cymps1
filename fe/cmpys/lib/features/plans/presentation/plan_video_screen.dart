import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/resource_notes_panel.dart';
import '../../session/data/content_resources_repository.dart';
import '../../session/models/content_resource.dart';
import '../../session/providers/content_resources_provider.dart';

/// Full-screen in-app YouTube video player for plan materials.
class PlanVideoScreen extends ConsumerStatefulWidget {
  const PlanVideoScreen({
    super.key,
    required this.title,
    required this.url,
    this.source,
    this.reason,
    this.materialId,
    this.initialIsSaved = false,
  });

  final String title;
  final String url;
  final String? source;
  final String? reason;
  final String? materialId;
  final bool initialIsSaved;

  @override
  ConsumerState<PlanVideoScreen> createState() => _PlanVideoScreenState();
}

class _PlanVideoScreenState extends ConsumerState<PlanVideoScreen> {
  YoutubePlayerController? _controller;
  final TextEditingController _noteController = TextEditingController();
  String? _videoId;
  final bool _hasError = false;
  bool _isFullScreen = false;
  bool _isResourceSaved = false;
  bool _isSavingResource = false;
  bool _isLoadingHighlights = false;
  bool _isSavingHighlight = false;
  List<ContentHighlight> _highlights = const [];

  bool get _hasSharedResource => widget.materialId?.isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    _isResourceSaved = widget.initialIsSaved;
    _videoId = YoutubePlayer.convertUrlToId(widget.url);
    if (_videoId != null) {
      _controller = YoutubePlayerController(
        initialVideoId: _videoId!,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          enableCaption: true,
          forceHD: false,
        ),
      );
    }
    if (_hasSharedResource) {
      _loadHighlights();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _noteController.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _toggleSharedResourceSave() async {
    if (!_hasSharedResource || _isSavingResource) return;
    setState(() => _isSavingResource = true);
    try {
      final repository = ref.read(contentResourcesRepositoryProvider);
      if (_isResourceSaved) {
        await repository.unsaveResource(widget.materialId!);
      } else {
        await repository.saveResource(widget.materialId!);
      }
      setState(() => _isResourceSaved = !_isResourceSaved);
      ref.invalidate(vaultResourcesProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not update Vault')));
    } finally {
      if (mounted) setState(() => _isSavingResource = false);
    }
  }

  Future<void> _markVideoComplete() async {
    if (!_hasSharedResource) return;
    try {
      await ref
          .read(contentResourcesRepositoryProvider)
          .updateProgress(
            widget.materialId!,
            progressPercent: 100,
            completed: true,
          );
      ref.invalidate(vaultResourcesProvider);
    } catch (_) {
      // Playback completion should not be interrupted by progress sync.
    }
  }

  Future<void> _loadHighlights() async {
    if (!_hasSharedResource) return;
    setState(() => _isLoadingHighlights = true);
    try {
      final highlights = await ref
          .read(contentResourcesRepositoryProvider)
          .listHighlights(widget.materialId!);
      if (!mounted) return;
      setState(() => _highlights = highlights);
    } catch (_) {
      if (!mounted) return;
      setState(() => _highlights = const []);
    } finally {
      if (mounted) setState(() => _isLoadingHighlights = false);
    }
  }

  Future<void> _saveVideoNote() async {
    final note = _noteController.text.trim();
    if (!_hasSharedResource || note.isEmpty || _isSavingHighlight) return;

    final seconds = _controller?.value.position.inSeconds ?? 0;
    setState(() => _isSavingHighlight = true);
    try {
      final highlight = await ref
          .read(contentResourcesRepositoryProvider)
          .createHighlight(
            widget.materialId!,
            locatorJson: {
              'screen': 'video',
              'seconds': seconds,
              'videoId': _videoId,
              'title': widget.title,
            },
            noteText: note,
          );
      if (!mounted) return;
      setState(() {
        _highlights = [highlight, ..._highlights];
        _noteController.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Video note saved')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not save note')));
    } finally {
      if (mounted) setState(() => _isSavingHighlight = false);
    }
  }

  Future<void> _deleteVideoNote(ContentHighlight highlight) async {
    if (!_hasSharedResource) return;
    final previous = _highlights;
    setState(() {
      _highlights = _highlights
          .where((item) => item.id != highlight.id)
          .toList();
    });

    try {
      await ref
          .read(contentResourcesRepositoryProvider)
          .deleteHighlight(widget.materialId!, highlight.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _highlights = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not delete note')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: _isFullScreen
          ? (_videoId == null || _hasError ? _buildFallback() : _buildPlayer())
          : SafeArea(
              bottom: false,
              child: _videoId == null || _hasError
                  ? _buildFallback()
                  : _buildPlayer(),
            ),
    );
  }

  Widget _buildPlayer() {
    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller!,
        showVideoProgressIndicator: true,
        progressIndicatorColor: AppColors.accent,
        onReady: () {},
        onEnded: (_) {
          _markVideoComplete();
        },
      ),
      onEnterFullScreen: () {
        setState(() => _isFullScreen = true);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      },
      onExitFullScreen: () {
        setState(() => _isFullScreen = false);
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      },
      builder: (context, player) {
        if (_isFullScreen) {
          return ColoredBox(color: Colors.black, child: player);
        }

        return Column(
          children: [
            _VideoPrototypeHeader(
              onBack: () => Navigator.of(context).pop(),
              trailingIcon: _hasSharedResource && _isResourceSaved
                  ? Icons.bookmark_rounded
                  : _hasSharedResource
                  ? Icons.bookmark_border_rounded
                  : Icons.cast_rounded,
              onTrailing: _hasSharedResource
                  ? (_isSavingResource ? null : _toggleSharedResourceSave)
                  : _openInBrowser,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ColoredBox(
                      color: Colors.black,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [Opacity(opacity: 0.82, child: player)],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.shield_outlined,
                                color: AppColors.mint,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Strategic_briefing',
                                style: AppTypography.captionUpper.copyWith(
                                  color: AppColors.mint,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.title,
                            style: AppTypography.h2.copyWith(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.16,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            widget.reason ??
                                'Watch the briefing and capture the logic you can apply this week.',
                            style: AppTypography.body.copyWith(
                              color: const Color(0xFF94A3B8),
                              fontSize: 14,
                              height: 1.55,
                            ),
                          ),
                          const SizedBox(height: 30),
                          Text(
                            'Key_Log_Takeaways',
                            style: AppTypography.captionUpper.copyWith(
                              color: const Color(0xFF64748B),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _DarkTakeaway(
                            icon: Icons.bolt_rounded,
                            title: 'Compounding Logic:',
                            body:
                                'Preserve the starting base before chasing upside.',
                          ),
                          _DarkTakeaway(
                            icon: Icons.track_changes_rounded,
                            title: 'The NO Protocol:',
                            body:
                                'Reject attractive distractions that weaken the week objective.',
                          ),
                          if (_hasSharedResource) ...[
                            const SizedBox(height: 12),
                            ResourceNotesPanel(
                              title: 'Video notes',
                              hintText: 'Capture what to replay or apply...',
                              controller: _noteController,
                              highlights: _highlights,
                              isLoading: _isLoadingHighlights,
                              isSaving: _isSavingHighlight,
                              dark: true,
                              padding: EdgeInsets.zero,
                              timestampBuilder: _timestampForHighlight,
                              onSave: _saveVideoNote,
                              onDelete: _deleteVideoNote,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(32, 12, 32, 40),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x000F172A), Color(0xFF0F172A)],
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: () {
                    _markVideoComplete();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: AppRadii.br12),
                  ),
                  child: Text(
                    'Mark as Processed',
                    style: AppTypography.h3.copyWith(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFallback() {
    return SafeArea(
      child: Column(
        children: [
          _VideoPrototypeHeader(
            onBack: () => Navigator.of(context).pop(),
            trailingIcon: Icons.cast_rounded,
            onTrailing: _openInBrowser,
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.brandAccent.withValues(alpha: 0.16),
                        borderRadius: AppRadii.br20,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: AppColors.brandAccent,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      widget.title,
                      style: AppTypography.h3.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This video cannot be played in-app. Open YouTube to continue.',
                      style: AppTypography.body.copyWith(
                        color: const Color(0xFF94A3B8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _openInBrowser,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Watch on YouTube'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.br12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _timestampForHighlight(ContentHighlight highlight) {
    final seconds = highlight.locatorJson?['seconds'];
    return seconds is num ? _formatTimestamp(seconds.toInt()) : null;
  }

  String _formatTimestamp(int seconds) {
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '$minutes:${remaining.toString().padLeft(2, '0')}';
  }
}

class _VideoPrototypeHeader extends StatelessWidget {
  const _VideoPrototypeHeader({
    required this.onBack,
    required this.trailingIcon,
    required this.onTrailing,
  });

  final VoidCallback onBack;
  final IconData trailingIcon;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      child: Row(
        children: [
          _DarkIconButton(icon: Icons.chevron_left_rounded, onTap: onBack),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Briefing.Source_Video',
                  style: AppTypography.captionUpper.copyWith(
                    color: const Color(0xFF64748B),
                    fontSize: 9,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SESSION_2.4.VIDEO',
                  style: AppTypography.captionUpper.copyWith(
                    color: AppColors.mint,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          _DarkIconButton(icon: trailingIcon, onTap: onTrailing),
        ],
      ),
    );
  }
}

class _DarkIconButton extends StatelessWidget {
  const _DarkIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF111827).withValues(alpha: 0.55),
      borderRadius: AppRadii.br12,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.br12,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF1E293B)),
            borderRadius: AppRadii.br12,
          ),
          child: Icon(icon, color: const Color(0xFF94A3B8), size: 22),
        ),
      ),
    );
  }
}

class _DarkTakeaway extends StatelessWidget {
  const _DarkTakeaway({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withValues(alpha: 0.42),
        borderRadius: AppRadii.br12,
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: AppRadii.br8,
              border: Border.all(color: AppColors.mint.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, color: AppColors.mint, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(text: body),
                ],
              ),
              style: AppTypography.caption.copyWith(
                color: const Color(0xFFCBD5E1),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
