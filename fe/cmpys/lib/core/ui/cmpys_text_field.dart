import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/design_tokens.dart';

/// Text field component with dark filled style.
class CmpysTextField extends StatefulWidget {
  const CmpysTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.autovalidateMode,
    this.autocorrect,
    this.enableSuggestions,
    this.autofillHints,
    this.onTapOutside,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final String? prefixIcon;
  final String? suffixIcon;
  final VoidCallback? onSuffixTap;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final AutovalidateMode? autovalidateMode;
  final bool? autocorrect;
  final bool? enableSuggestions;
  final Iterable<String>? autofillHints;
  final TapRegionCallback? onTapOutside;

  @override
  State<CmpysTextField> createState() => _CmpysTextFieldState();
}

class _CmpysTextFieldState extends State<CmpysTextField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    final isSingleLine =
        (widget.maxLines ?? 1) == 1 && (widget.minLines ?? 1) == 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: AppTypography.label.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: _obscureText,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          autofocus: widget.autofocus,
          maxLines: widget.obscureText ? 1 : widget.maxLines,
          minLines: widget.minLines,
          maxLength: widget.maxLength,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          inputFormatters: widget.inputFormatters,
          textCapitalization: widget.textCapitalization,
          autocorrect: widget.autocorrect ?? !widget.obscureText,
          enableSuggestions: widget.enableSuggestions ?? !widget.obscureText,
          autofillHints: widget.autofillHints,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          onTap: widget.onTap,
          validator: widget.validator,
          autovalidateMode: widget.autovalidateMode,
          style: AppTypography.body,
          cursorColor: AppColors.accent,
          textAlignVertical: isSingleLine
              ? TextAlignVertical.center
              : TextAlignVertical.top,
          onTapOutside:
              widget.onTapOutside ??
              (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: InputDecoration(
            hintText: widget.hint,
            counterText: '',
            prefixIcon: widget.prefixIcon != null
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: SvgPicture.asset(
                      widget.prefixIcon!,
                      width: 20,
                      height: 20,
                      colorFilter: const ColorFilter.mode(
                        AppColors.textSecondary,
                        BlendMode.srcIn,
                      ),
                    ),
                  )
                : null,
            suffixIcon: _buildSuffixIcon(),
            errorText: null, // We handle error text ourselves
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.br12,
              borderSide: BorderSide(
                color: hasError ? AppColors.error : AppColors.border,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadii.br12,
              borderSide: BorderSide(
                color: hasError ? AppColors.error : AppColors.borderFocus,
                width: 1.5,
              ),
            ),
          ),
        ),
        if (widget.errorText != null || widget.helperText != null) ...[
          const SizedBox(height: AppSpacing.s6),
          Text(
            widget.errorText ?? widget.helperText ?? '',
            style: AppTypography.caption.copyWith(
              color: hasError ? AppColors.error : AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  Widget? _buildSuffixIcon() {
    if (widget.obscureText) {
      return GestureDetector(
        onTap: () => setState(() => _obscureText = !_obscureText),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(
            _obscureText ? Icons.visibility_off : Icons.visibility,
            size: 20,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    if (widget.suffixIcon != null) {
      return GestureDetector(
        onTap: widget.onSuffixTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SvgPicture.asset(
            widget.suffixIcon!,
            width: 20,
            height: 20,
            colorFilter: const ColorFilter.mode(
              AppColors.textSecondary,
              BlendMode.srcIn,
            ),
          ),
        ),
      );
    }

    return null;
  }
}

/// Search field variant.
class CmpysSearchField extends StatelessWidget {
  const CmpysSearchField({
    super.key,
    this.controller,
    this.hint = 'Search...',
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return CmpysTextField(
      controller: controller,
      hint: hint,
      prefixIcon: 'assets/icons/search.svg',
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
    );
  }
}

/// Text area for longer content.
class CmpysTextArea extends StatelessWidget {
  const CmpysTextArea({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.minLines = 4,
    this.maxLines = 8,
    this.maxLength,
    this.onChanged,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return CmpysTextField(
      controller: controller,
      label: label,
      hint: hint,
      helperText: helperText,
      errorText: errorText,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: onChanged,
      enabled: enabled,
      keyboardType: TextInputType.multiline,
    );
  }
}
