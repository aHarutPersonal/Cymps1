import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/design_tokens.dart';
import '../motion/motion_config.dart';
import 'icons.dart';

/// `Field` from `v3/core.jsx`: an optional 12.5 pt label over a 52 pt input
/// box (radius 16, 1.5 pt border: hair, ink when focused with a 4 pt soft
/// ring, danger on [error]), with an optional [right] accessory and an
/// error line under it. [multiline] makes a [rows]-line text area.
///
/// Text is either owned by a [controller] or kept in sync with [value] (the
/// design's controlled `value` + `onChange`); with neither it starts empty.
class V3Field extends StatefulWidget {
  const V3Field({
    super.key,
    this.label,
    this.value,
    this.controller,
    this.onChanged,
    this.placeholder,
    this.keyboardType,
    this.obscureText = false,
    this.right,
    this.multiline = false,
    this.rows = 3,
    this.dark = false,
    this.error,
    this.autofocus = false,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.inputFormatters,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.enabled = true,
    this.autocorrect,
    this.enableSuggestions,
    this.onTapOutside,
    this.scrollPadding,
  });

  final String? label;

  /// Controlled text; when it differs from what is shown, the field updates.
  final String? value;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? placeholder;

  /// The design's `type` / `inputMode` (e.g. email, number with decimals).
  final TextInputType? keyboardType;

  /// The design's `type="password"`.
  final bool obscureText;

  /// Trailing accessory inside the box (e.g. a search icon).
  final Widget? right;
  final bool multiline;
  final int rows;
  final bool dark;
  final String? error;
  final bool autofocus;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final bool enabled;

  /// Platform autocorrect. Null decides from the field: off for a password
  /// ([obscureText]) and for an email or visible-password [keyboardType],
  /// where "correcting" an address or a secret corrupts it; on otherwise.
  final bool? autocorrect;

  /// Keyboard suggestions, decided like [autocorrect]: off for secrets and
  /// addresses, so a typed token is not offered back or learned.
  final bool? enableSuggestions;

  /// A tap outside the field (and its [right] accessory). Null dismisses the
  /// keyboard by unfocusing the field, as a form is expected to.
  final TapRegionCallback? onTapOutside;

  /// Space kept around the caret when the field scrolls itself into view
  /// (focus, or the keyboard opening). Null uses 20 pt on every side, and for
  /// a [multiline] field adds the rest of the box below the first line, so the
  /// whole box (not just its first line) ends above a footer or the keyboard.
  final EdgeInsets? scrollPadding;

  bool get _sensitive =>
      obscureText ||
      keyboardType == TextInputType.emailAddress ||
      keyboardType == TextInputType.visiblePassword;

  @override
  State<V3Field> createState() => _V3FieldState();
}

class _V3FieldState extends State<V3Field> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;

  TextEditingController get _controller =>
      widget.controller ??
      (_ownController ??= TextEditingController(text: widget.value ?? ''));
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    if (widget.controller != null && widget.value != null) {
      _syncValue();
    }
  }

  @override
  void didUpdateWidget(V3Field oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
    // Apply parent-driven changes only, so a parent that rebuilds with a
    // stale [value] never reverts what the user is typing.
    if (widget.value != null &&
        widget.value != oldWidget.value &&
        widget.value != _controller.text) {
      _syncValue();
    }
  }

  void _syncValue() {
    final text = widget.value!;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final focused = _focus.hasFocus;
    final hasError = widget.error != null;
    final motion = MotionConfig.enabled(context);
    final textColor = dark ? Colors.white : AppColors.ink;

    final Color borderColor;
    if (hasError) {
      borderColor = AppColors.danger;
    } else if (focused) {
      borderColor = dark ? const Color(0x80FFFFFF) : AppColors.ink;
    } else {
      borderColor = dark ? const Color(0x1FFFFFFF) : AppColors.hair;
    }

    final EdgeInsets scrollPadding;
    if (widget.scrollPadding != null) {
      scrollPadding = widget.scrollPadding!;
    } else if (widget.multiline) {
      // The caret sits on the first line: keep the other rows, the box's 14 pt
      // padding, its border and the focus ring on screen too.
      final line = MediaQuery.textScalerOf(context).scale(16 * 1.45);
      scrollPadding = EdgeInsets.fromLTRB(
        20,
        20,
        20,
        12 + (widget.rows - 1) * line + 14 + 6,
      );
    } else {
      scrollPadding = const EdgeInsets.all(20);
    }

    final input = TextField(
      scrollPadding: scrollPadding,
      controller: _controller,
      focusNode: _focus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      obscureText: widget.obscureText,
      keyboardType:
          widget.keyboardType ??
          (widget.multiline ? TextInputType.multiline : null),
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      textCapitalization: widget.textCapitalization,
      autocorrect: widget.autocorrect ?? !widget._sensitive,
      enableSuggestions: widget.enableSuggestions ?? !widget._sensitive,
      onTapOutside: widget.onTapOutside ?? (_) => _focus.unfocus(),
      minLines: widget.multiline ? widget.rows : 1,
      maxLines: widget.multiline ? widget.rows : 1,
      cursorColor: textColor,
      style: AppTypography.sans(16).copyWith(color: textColor, height: 1.45),
      // `InputDecoration.collapsed` leaves the per-state borders null, so an
      // app theme with an outlined `inputDecorationTheme` (this app's) would
      // draw a second border inside the box. Every state is switched off.
      decoration: InputDecoration(
        isCollapsed: true,
        filled: false,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        hintText: widget.placeholder,
        hintStyle: AppTypography.sans(16).copyWith(
          color: dark ? AppColors.nink3 : AppColors.ink3,
          height: 1.45,
        ),
      ),
    );

    final box = AnimatedContainer(
      duration: motion ? const Duration(milliseconds: 200) : Duration.zero,
      constraints: const BoxConstraints(minHeight: 52),
      padding: widget.multiline
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
          : const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: dark ? const Color(0x0FFFFFFF) : AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: focused
                ? (dark ? const Color(0x0FFFFFFF) : const Color(0x0D17151A))
                : const Color(0x00000000),
            spreadRadius: 4,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: widget.multiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Semantics(label: widget.label, child: input),
          ),
          if (widget.right != null) ...[
            const SizedBox(width: 10),
            // Part of the field: tapping it must not count as tapping outside
            // (the eye keeps the keyboard up).
            TextFieldTapRegion(child: widget.right!),
          ],
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null) ...[
          ExcludeSemantics(
            child: Text(
              widget.label!,
              style: AppTypography.sans(
                12.5,
                FontWeight.w600,
              ).copyWith(color: dark ? AppColors.nink2 : AppColors.ink2),
            ),
          ),
          const SizedBox(height: 7),
        ],
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.enabled ? _focus.requestFocus : null,
          child: box,
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const V3Icon(V3Icons.alert, size: 13, color: AppColors.danger),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  widget.error!,
                  style: AppTypography.sans(
                    12.5,
                  ).copyWith(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
