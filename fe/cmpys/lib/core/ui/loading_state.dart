import 'dart:async';
import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// Loading state with spinner and optional rotating messages.
class LoadingState extends StatefulWidget {
  const LoadingState({
    super.key,
    this.message,
    this.messages,
    this.compact = false,
  });

  final String? message;
  final List<String>? messages;
  final bool compact;

  @override
  State<LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<LoadingState> {
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.messages != null && widget.messages!.isNotEmpty) {
      _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (mounted) {
          setState(() {
            _currentIndex = (_currentIndex + 1) % widget.messages!.length;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayMessage =
        widget.messages != null && widget.messages!.isNotEmpty
        ? widget.messages![_currentIndex]
        : widget.message;

    return Center(
      child: Padding(
        padding: widget.compact ? AppSpacing.p16 : AppSpacing.p24,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.compact ? 32 : 48,
              height: widget.compact ? 32 : 48,
              child: CircularProgressIndicator(
                strokeWidth: widget.compact ? 2 : 3,
                color: AppColors.accent,
              ),
            ),
            if (displayMessage != null) ...[
              SizedBox(
                height: widget.compact ? AppSpacing.s12 : AppSpacing.s16,
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  displayMessage,
                  key: ValueKey<String>(displayMessage),
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline loading indicator.
class InlineLoader extends StatelessWidget {
  const InlineLoader({
    super.key,
    this.size = 20,
    this.strokeWidth = 2,
    this.color,
  });

  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: color ?? AppColors.accent,
      ),
    );
  }
}

/// Skeleton loading placeholder.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height, this.borderRadius});

  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(
      begin: 0.3,
      end: 0.6,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.surface2.withValues(alpha: _animation.value),
            borderRadius: widget.borderRadius ?? AppRadii.br8,
          ),
        );
      },
    );
  }
}

/// Skeleton text line.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.width, this.height = 14});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(height / 2),
    );
  }
}

/// Skeleton card placeholder.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 100});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: AppSpacing.p16,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.br20,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SkeletonBox(
                width: 44,
                height: 44,
                borderRadius: AppRadii.br12,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(
                      width: MediaQuery.of(context).size.width * 0.4,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    SkeletonLine(
                      width: MediaQuery.of(context).size.width * 0.25,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          const SkeletonLine(),
        ],
      ),
    );
  }
}

/// List skeleton placeholder.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 80,
    this.spacing = AppSpacing.s12,
  });

  final int itemCount;
  final double itemHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, _) => SizedBox(height: spacing),
      itemBuilder: (_, _) => SkeletonCard(height: itemHeight),
    );
  }
}
