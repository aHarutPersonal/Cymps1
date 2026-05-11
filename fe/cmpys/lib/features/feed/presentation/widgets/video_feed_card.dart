import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../../../app/design_tokens.dart';

/// prototype-style full-screen video card.
/// Handles embed restrictions gracefully with thumbnail fallback.
class VideoFeedCard extends StatefulWidget {
  const VideoFeedCard({
    super.key,
    required this.title,
    this.reason,
    this.sourceTask,
    this.url,
    this.isActive = false,
  });

  final String title;
  final String? reason;
  final String? sourceTask;
  final String? url;
  final bool isActive;

  @override
  State<VideoFeedCard> createState() => _VideoFeedCardState();
}

class _VideoFeedCardState extends State<VideoFeedCard> {
  String? _videoId;
  YoutubePlayerController? _ytController;
  bool _embedError = false; // Error 150: embedding disabled

  @override
  void initState() {
    super.initState();
    _extractVideoId();
    if (widget.isActive && _videoId != null) {
      _ensureController();
    }
  }

  void _extractVideoId() {
    if (widget.url == null) return;
    _videoId = YoutubePlayer.convertUrlToId(widget.url!);
  }

  void _ensureController() {
    if (_videoId == null || _ytController != null) return;
    _ytController =
        YoutubePlayerController(
          initialVideoId: _videoId!,
          flags: const YoutubePlayerFlags(
            autoPlay: true,
            mute: false,
            showLiveFullscreenButton: false,
            hideControls: false,
            controlsVisibleAtStart: false,
            enableCaption: false,
          ),
        )..addListener(() {
          // Detect embed errors (Error 150, Error 100, etc.)
          if (_ytController != null &&
              _ytController!.value.hasError &&
              !_embedError) {
            if (mounted) setState(() => _embedError = true);
          }
        });
  }

  @override
  void didUpdateWidget(covariant VideoFeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_embedError) return; // don't try to play broken embeds

    if (widget.isActive && !oldWidget.isActive) {
      if (_ytController != null) {
        _ytController!.play();
      } else {
        _ensureController();
        if (mounted) setState(() {});
      }
    } else if (!widget.isActive && oldWidget.isActive) {
      _ytController?.pause();
    }
  }

  @override
  void dispose() {
    _ytController?.dispose();
    super.dispose();
  }

  Future<void> _openExternal() async {
    if (widget.url == null) return;
    final uri = Uri.tryParse(widget.url!);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  String? get _thumbnailUrl {
    if (_videoId == null) return null;
    return 'https://img.youtube.com/vi/$_videoId/hqdefault.jpg';
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video / Thumbnail / Error fallback ──
          if (_ytController != null && !_embedError)
            Positioned.fill(
              child: YoutubePlayer(
                controller: _ytController!,
                showVideoProgressIndicator: true,
                progressIndicatorColor: AppColors.accent,
                progressColors: const ProgressBarColors(
                  playedColor: AppColors.accent,
                  handleColor: AppColors.accent,
                ),
                aspectRatio:
                    MediaQuery.of(context).size.width / (screenHeight - 120),
              ),
            )
          else
            // Show thumbnail with play/open button
            _ThumbnailFallback(
              thumbnailUrl: _thumbnailUrl,
              onTap: _embedError || _videoId == null
                  ? _openExternal
                  : () {
                      _ensureController();
                      setState(() {});
                    },
              showExternalButton: _embedError || _videoId == null,
            ),

          // ── Bottom info overlay ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 72, // leave room for social actions
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                    Colors.black.withValues(alpha: 0.95),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: AppTypography.h3.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.reason != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.reason!,
                      style: AppTypography.body.copyWith(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (widget.sourceTask != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.play_circle_outline,
                          color: Colors.white38,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.sourceTask!,
                            style: AppTypography.caption.copyWith(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thumbnail with play button or "Watch on YouTube" button.
class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback({
    this.thumbnailUrl,
    required this.onTap,
    this.showExternalButton = false,
  });

  final String? thumbnailUrl;
  final VoidCallback onTap;
  final bool showExternalButton;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail
          if (thumbnailUrl != null)
            Image.network(
              thumbnailUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Container(color: const Color(0xFF0A0A0A)),
            )
          else
            Container(color: const Color(0xFF0A0A0A)),

          // Darken
          Container(color: Colors.black.withValues(alpha: 0.4)),

          // Button
          Center(
            child: showExternalButton
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.open_in_new_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Watch on YouTube',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                : Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
