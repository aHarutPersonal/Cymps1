// In-app YouTube playback for plan video materials, framed in the CMPYS
// editorial player layout (16:9 player card, title, why-this-material).

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/app_shell.dart';
import '../models/plan_models.dart';

class MaterialVideoScreen extends StatefulWidget {
  const MaterialVideoScreen({
    super.key,
    required this.material,
    required this.videoId,
  });

  final PlanMaterialDetail material;
  final String videoId;

  @override
  State<MaterialVideoScreen> createState() => _MaterialVideoScreenState();
}

class _MaterialVideoScreenState extends State<MaterialVideoScreen> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        strictRelatedVideos: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: ClipRRect(
                borderRadius: AppRadii.card,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: YoutubePlayer(controller: _controller),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(22, 18, 22, AppShell.bottomNavClearance(context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title,
                        style: AppTypography.h2.copyWith(
                            fontSize: 22, letterSpacing: -0.3, height: 1.16)),
                    if (m.authorOrCreator != null &&
                        m.authorOrCreator!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(m.authorOrCreator!,
                          style: AppTypography.captionMedium.copyWith(
                              color: AppColors.ink3,
                              fontWeight: FontWeight.w600)),
                    ],
                    if (m.reason != null && m.reason!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.greenSoft,
                          borderRadius: AppRadii.card,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('WHY THIS VIDEO',
                                style: AppTypography.kicker
                                    .copyWith(color: AppColors.green2)),
                            const SizedBox(height: 6),
                            Text(m.reason!,
                                style: AppTypography.body.copyWith(
                                    fontSize: 14, height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.hair),
                ),
                child: const Icon(Icons.chevron_left_rounded,
                    size: 22, color: AppColors.ink),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              (widget.material.authorOrCreator ?? 'Video lesson')
                  .toUpperCase(),
              style: AppTypography.kicker,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
