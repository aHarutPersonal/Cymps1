import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/design_tokens.dart';
import 'cmpys_button.dart';

/// Empty state component for lists and screens.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.iconWidget,
    this.action,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String? message;
  final String? icon;
  final Widget? iconWidget;
  final Widget? action;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: compact ? AppSpacing.p16 : AppSpacing.p24,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconWidget != null)
              iconWidget!
            else if (icon != null)
              Container(
                width: compact ? 64 : 80,
                height: compact ? 64 : 80,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadii.br20,
                  border: Border.all(color: AppColors.border),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    icon!,
                    width: compact ? 28 : 36,
                    height: compact ? 28 : 36,
                    colorFilter: const ColorFilter.mode(
                      AppColors.textTertiary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            SizedBox(height: compact ? AppSpacing.s16 : AppSpacing.s24),
            Text(
              title,
              style: compact ? AppTypography.h4 : AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                message!,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null ||
                (actionLabel != null && onAction != null)) ...[
              SizedBox(height: compact ? AppSpacing.s16 : AppSpacing.s24),
              action ??
                  CmpysButton(
                    label: actionLabel!,
                    onPressed: onAction,
                    isExpanded: false,
                    size: compact
                        ? CmpysButtonSize.small
                        : CmpysButtonSize.medium,
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// No results state for search.
class NoResultsState extends StatelessWidget {
  const NoResultsState({super.key, this.query, this.onClear});

  final String? query;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: 'assets/icons/search.svg',
      title: 'No results found',
      message: query != null
          ? 'We couldn\'t find anything for "$query".\nTry a different search term.'
          : 'We couldn\'t find what you\'re looking for.',
      actionLabel: onClear != null ? 'Clear search' : null,
      onAction: onClear,
    );
  }
}

/// Error state with retry.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title = 'Something went wrong',
    this.message,
    this.onRetry,
    this.compact = false,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: 'assets/icons/alert_circle.svg',
      title: title,
      message: message ?? 'An error occurred. Please try again.',
      actionLabel: onRetry != null ? 'Try again' : null,
      onAction: onRetry,
      compact: compact,
    );
  }
}

/// Offline state.
class OfflineState extends StatelessWidget {
  const OfflineState({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: 'assets/icons/wifi_off.svg',
      title: 'You\'re offline',
      message: 'Check your internet connection and try again.',
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }
}
