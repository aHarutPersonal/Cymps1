import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../controllers/auth_controller.dart';
import '../controllers/session_controller.dart';

/// Welcome / auth entry.
///
/// The screen previews CMPYS's product loop before asking the user to sign in:
/// choose a mentor, see the same-age mirror, then work a 12-week plan. It uses
/// the same mentor imagery, ink surfaces, mono labels, paper background, and
/// green action language as the rest of the app.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _showEmailForm = false;
  bool _isLoginMode = true;
  String? _errorMessage;
  bool _obscurePassword = true;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        statusBarColor: Colors.transparent,
      ),
    );

    final authState = ref.watch(authControllerProvider);
    final isLoading = authState is AuthLoading;

    ref.listen(authControllerProvider, (prev, next) async {
      if (next is AuthAuthenticated) {
        _clearError();
        await ref
            .read(sessionControllerProvider.notifier)
            .onAuthenticated(isNewRegistration: next.isNewRegistration);
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final sessionState = ref.read(sessionControllerProvider);
          if (sessionState is SessionReady) {
            context.go(AppRoutes.home);
          } else {
            context.go(AppRoutes.cmpysOnboarding);
          }
        });
      } else if (next is AuthError) {
        setState(() => _errorMessage = next.message);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _ErrorBanner(message: _errorMessage, onDismiss: _clearError),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        MediaQuery.of(context).size.height -
                        MediaQuery.of(context).padding.top -
                        MediaQuery.of(context).padding.bottom -
                        (_errorMessage != null ? 56 : 0) -
                        28,
                  ),
                  child: IntrinsicHeight(
                    child: _showEmailForm
                        ? _buildEmailForm(isLoading)
                        : _buildSocialAuth(isLoading),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialAuth(bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'CMPYS',
              style: AppTypography.kicker.copyWith(
                fontSize: 16,
                color: AppColors.ink,
                letterSpacing: 4,
              ),
            ),
            const Spacer(),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              'MENTORSHIP',
              style: AppTypography.kicker.copyWith(
                fontSize: 9,
                letterSpacing: 1.1,
                color: AppColors.ink3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _MentorMirrorPanel(),
        const SizedBox(height: 26),
        Text(
          'Don’t admire their path. Build yours.',
          style: AppTypography.display.copyWith(
            fontSize: 39,
            height: 1.04,
            letterSpacing: -1.1,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 13),
        Text(
          'Choose a mentor. Face the truth at your age. Turn the gap '
          'into a plan you can work every day.',
          style: AppTypography.body.copyWith(
            fontSize: 15.5,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        _AuthPill(
          label: 'Continue with Apple',
          icon: AppAssets.iconApple,
          filled: true,
          onTap: isLoading ? null : () => _handleOAuth('apple'),
        ),
        const SizedBox(height: 12),
        // Google — outline pill
        _AuthPill(
          label: 'Continue with Google',
          icon: AppAssets.iconGoogle,
          filled: false,
          useColorIcon: true,
          onTap: isLoading ? null : () => _handleOAuth('google'),
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: isLoading
                ? null
                : () {
                    _clearError();
                    setState(() => _showEmailForm = true);
                  },
            child: Text(
              'Use email instead',
              style: AppTypography.bodyMedium.copyWith(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildEmailForm(bool isLoading) {
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            // Back to social
            GestureDetector(
              onTap: isLoading
                  ? null
                  : () {
                      _clearError();
                      setState(() => _showEmailForm = false);
                    },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: AppColors.ink,
                  size: 20,
                ),
              ),
            ),
            const Spacer(),
            Text(
              _isLoginMode ? 'Continue your climb.' : 'Start with a standard.',
              style: AppTypography.display.copyWith(
                fontSize: 34,
                height: 1.1,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isLoginMode
                  ? 'Your mentor, comparison, and plan are waiting.'
                  : 'We’ll match you with a mentor, show the gap, and build your 12-week plan.',
              style: AppTypography.body.copyWith(
                fontSize: 15.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            if (!_isLoginMode) ...[
              _PaperInputField(
                label: 'FULL NAME',
                hintText: 'Enter your name',
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                enabled: !isLoading,
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 12),
            ],
            _PaperInputField(
              label: 'EMAIL ADDRESS',
              hintText: 'name@example.com',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              enabled: !isLoading,
              onChanged: (_) => _clearError(),
            ),
            const SizedBox(height: 12),
            _PaperInputField(
              label: 'PASSWORD',
              hintText: '••••••••',
              controller: _passwordController,
              obscureText: _obscurePassword,
              enabled: !isLoading,
              onChanged: (_) => _clearError(),
              suffixIcon: GestureDetector(
                onTap: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                child: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
            ),
            if (_isLoginMode) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => context.push(AppRoutes.forgotPassword),
                  child: Text(
                    'Forgot Password?',
                    style: AppTypography.bodyMedium.copyWith(
                      fontSize: 14,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ],
            const Spacer(),
            _AuthPill(
              label: _isLoginMode ? 'Sign In' : 'Create Account',
              filled: true,
              accent: true,
              loading: isLoading,
              onTap: isLoading ? null : _handleEmailAuth,
            ),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: isLoading
                    ? null
                    : () {
                        _clearError();
                        setState(() => _isLoginMode = !_isLoginMode);
                      },
                child: Text.rich(
                  TextSpan(
                    text: _isLoginMode
                        ? "Don't have an account? "
                        : 'Already have an account? ',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                    children: [
                      TextSpan(
                        text: _isLoginMode ? 'Create one' : 'Sign in',
                        style: AppTypography.bodyMedium.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _handleEmailAuth() async {
    _clearError();

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _errorMessage = 'Please enter a valid email');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters');
      return;
    }
    if (!_isLoginMode && name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your name');
      return;
    }

    final authController = ref.read(authControllerProvider.notifier);

    if (_isLoginMode) {
      await authController.login(email: email, password: password);
    } else {
      await authController.register(
        email: email,
        password: password,
        fullName: name,
      );
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  void _handleOAuth(String provider) {
    setState(() => _errorMessage = '$provider login coming soon!');
  }
}

/// A compact product preview built from the app's real mentor portraits.
/// The composition makes the unique CMPYS loop understandable at a glance,
/// without relying on decorative stock imagery or invented user data.
class _MentorMirrorPanel extends StatelessWidget {
  const _MentorMirrorPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 194,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppColors.gradInk,
        borderRadius: AppRadii.card,
        boxShadow: AppShadows.md,
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 17, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'CHOOSE YOUR STANDARD',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          style: AppTypography.kicker.copyWith(
                            fontSize: 9,
                            color: Colors.white.withValues(alpha: 0.58),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'SAME-AGE MIRROR',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          textAlign: TextAlign.right,
                          style: AppTypography.kicker.copyWith(
                            fontSize: 8.5,
                            color: AppColors.greenSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      const SizedBox(
                        width: 120,
                        height: 62,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              child: _MentorPortrait(
                                slug: 'wb',
                                initials: 'WB',
                                color: AppColors.green,
                                tint: AppColors.greenSoft,
                                size: 60,
                              ),
                            ),
                            Positioned(
                              left: 34,
                              child: _MentorPortrait(
                                slug: 'mc',
                                initials: 'MC',
                                color: AppColors.blue,
                                tint: AppColors.blueSoft,
                                size: 60,
                              ),
                            ),
                            Positioned(
                              left: 68,
                              child: _MentorPortrait(
                                slug: 'sj',
                                initials: 'SJ',
                                color: AppColors.ink,
                                tint: AppColors.paper2,
                                size: 60,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 19,
                        color: Colors.white.withValues(alpha: 0.42),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 60,
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.78),
                            width: 2.5,
                          ),
                        ),
                        child: Text(
                          'YOU',
                          style: AppTypography.kicker.copyWith(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Text(
                        'MENTOR',
                        style: AppTypography.monoLabel.copyWith(
                          fontSize: 9.5,
                          color: Colors.white.withValues(alpha: 0.52),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'YOUR LIFE, MEASURED CLEARLY',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          textAlign: TextAlign.right,
                          style: AppTypography.monoLabel.copyWith(
                            fontSize: 8.5,
                            color: Colors.white.withValues(alpha: 0.52),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            color: AppColors.green,
            child: Row(
              children: [
                Text(
                  'THE GAP',
                  style: AppTypography.kicker.copyWith(
                    fontSize: 9.5,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
                Expanded(
                  child: Text(
                    'YOUR 12-WEEK PLAN',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    style: AppTypography.kicker.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MentorPortrait extends StatelessWidget {
  const _MentorPortrait({
    required this.slug,
    required this.initials,
    required this.color,
    required this.tint,
    this.size = 66,
  });

  final String slug;
  final String initials;
  final Color color;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CmpysMentorAvatar(
      slug: slug,
      initials: initials,
      color: color,
      tint: tint,
      size: size,
      border: Border.all(color: AppColors.card, width: 2.5),
    );
  }
}

/// Full-width pill button used across the auth screen.
/// - `filled` + `accent`: green primary (Sign In / Create Account).
/// - `filled` (no accent): ink-dark pill (Continue with Apple).
/// - outline: paper surface with a hairline border (Continue with Google).
class _AuthPill extends StatelessWidget {
  const _AuthPill({
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
    this.accent = false,
    this.useColorIcon = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final bool filled;
  final bool accent;
  final bool useColorIcon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final Color bg = accent
        ? AppColors.accent
        : filled
        ? AppColors.ink
        : AppColors.surface;
    final Color fg = filled || accent ? Colors.white : AppColors.ink;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadii.brFull,
          border: filled || accent
              ? null
              : Border.all(color: AppColors.borderFocus, width: 1.5),
          boxShadow: filled || accent ? AppShadows.sm : null,
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      SvgPicture.asset(
                        icon!,
                        width: 19,
                        height: 19,
                        colorFilter: useColorIcon
                            ? null
                            : ColorFilter.mode(fg, BlendMode.srcIn),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Paper input field (label above a borderless field, hairline card).
class _PaperInputField extends StatelessWidget {
  const _PaperInputField({
    required this.label,
    required this.hintText,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.onChanged,
    this.suffixIcon,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadii.br16,
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.captionUpper.copyWith(
              fontSize: 10,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  obscureText: obscureText,
                  enabled: enabled,
                  onChanged: onChanged,
                  textCapitalization: textCapitalization,
                  style: AppTypography.body.copyWith(color: AppColors.ink),
                  cursorColor: AppColors.accent,
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: AppTypography.body.copyWith(
                      fontSize: 15,
                      color: AppColors.textTertiary,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ),
              if (suffixIcon != null) suffixIcon!,
            ],
          ),
        ],
      ),
    );
  }
}

/// Inline error banner.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String? message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.fast,
      height: message != null ? null : 0,
      child: message != null
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s16,
                vertical: AppSpacing.s12,
              ),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 18,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Text(
                      message!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onDismiss,
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: AppColors.error.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
