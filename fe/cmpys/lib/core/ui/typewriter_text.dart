import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../app/design_tokens.dart';

/// Characters appear one by one, creating an engaging "AI thinking" experience.
class TypewriterText extends StatefulWidget {
  const TypewriterText({
    super.key,
    required this.text,
    this.charDuration = const Duration(milliseconds: 30),
    this.style,
    this.onComplete,
    this.cursor = true,
    this.cursorColor,
  });

  /// The text to display with typewriter effect
  final String text;

  /// Duration between each character appearing
  final Duration charDuration;

  /// Text style
  final TextStyle? style;

  /// Called when the animation completes
  final VoidCallback? onComplete;

  /// Whether to show a blinking cursor at the end
  final bool cursor;

  /// Cursor color (defaults to text color)
  final Color? cursorColor;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText>
    with SingleTickerProviderStateMixin {
  String _displayedText = '';
  int _charIndex = 0;
  Timer? _typingTimer;
  late AnimationController _cursorController;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _startTyping();
  }

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      // Text changed - check if we should reset or continue
      if (!widget.text.startsWith(_displayedText)) {
        // New text doesn't start with current text - reset
        _charIndex = 0;
        _displayedText = '';
        _isComplete = false;
        _startTyping();
      } else {
        // Appended text.
        // If we were done or timer wasn't running, resume/restart
        if (_isComplete) {
          _isComplete = false;
          _startTyping();
        }
        // If timer is already running, we don't need to do anything.
        // It will pick up the new widget.text length automatically.
      }
    }
  }

  void _startTyping() {
    _typingTimer?.cancel();

    if (_charIndex >= widget.text.length) {
      // Already at the end
      if (!_isComplete) {
        _isComplete = true;
        widget.onComplete?.call();
      }
      return;
    }

    _typingTimer = Timer.periodic(widget.charDuration, (timer) {
      if (_charIndex < widget.text.length) {
        setState(() {
          _charIndex++;
          _displayedText = widget.text.substring(0, _charIndex);
        });
      } else {
        timer.cancel();
        if (!_isComplete) {
          _isComplete = true;
          widget.onComplete?.call();
        }
      }
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showCursor = widget.cursor && !_isComplete;
    final textColor = widget.style?.color ?? Theme.of(context).textTheme.bodyMedium?.color;
    final cursorColor = widget.cursorColor ?? textColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: MarkdownBody(
            data: _displayedText,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: widget.style,
              strong: widget.style?.copyWith(fontWeight: FontWeight.bold, color: AppColors.accent),
              // Ensure markdown uses the passed style for normal text
            ),
          ),
        ),
        if (showCursor)
          AnimatedBuilder(
            animation: _cursorController,
            builder: (context, child) {
              return Opacity(
                opacity: _cursorController.value,
                child: Text(
                  '▊',
                  style: widget.style?.copyWith(color: cursorColor) ??
                      TextStyle(color: cursorColor),
                ),
              );
            },
          ),
      ],
    );
  }
}
