import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/ambient_background.dart';
import '../controllers/auth_controller.dart';
import '../controllers/session_controller.dart';

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
    // Match the light paper shell used across the redesigned flows.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        statusBarColor: Colors.transparent,
      ),
    );

    final authState = ref.watch(authControllerProvider);
    final isLoading = authState is AuthLoading;

    // Listen for auth state changes
    ref.listen(authControllerProvider, (prev, next) async {
      if (next is AuthAuthenticated) {
        _clearError();
        await ref.read(sessionControllerProvider.notifier).onAuthenticated();
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final sessionState = ref.read(sessionControllerProvider);
          if (sessionState is SessionNeedsOnboarding) {
            context.go(AppRoutes.profileSetup);
          } else if (sessionState is SessionReady) {
            context.go(AppRoutes.home);
          } else {
            context.go(AppRoutes.profileSetup);
          }
        });
      } else if (next is AuthError) {
        setState(() => _errorMessage = next.message);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        useSafeArea: false,
        child: SafeArea(
          child: Column(
            children: [
              // Error banner
              _ErrorBanner(message: _errorMessage, onDismiss: _clearError),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          MediaQuery.of(context).size.height -
                          MediaQuery.of(context).padding.top -
                          MediaQuery.of(context).padding.bottom -
                          (_errorMessage != null ? 56 : 0),
                    ),
                    child: _showEmailForm
                        ? _buildEmailForm(isLoading)
                        : _buildSocialAuth(isLoading),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSocialAuth(bool isLoading) {
    return Column(
      children: [
        const SizedBox(height: 64),
        // Header
        Text(
          _isLoginMode ? 'Welcome Back' : 'Create Account',
          textAlign: TextAlign.center,
          style: AppTypography.h1.copyWith(fontSize: 34),
        ),
        const SizedBox(height: 8),
        Text(
          _isLoginMode
              ? 'Your comparison mirror is ready.'
              : 'Build your profile, then choose your North Star.',
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 32),

        // Social logins — 2-col grid
        Row(
          children: [
            Expanded(
              child: _SocialButton(
                label: 'Google',
                icon: AppAssets.iconGoogle,
                useColorIcon: true,
                onTap: isLoading ? null : () => _handleOAuth('google'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _SocialButton(
                label: 'Apple',
                icon: AppAssets.iconApple,
                onTap: isLoading ? null : () => _handleOAuth('apple'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),

        // Divider
        Row(
          children: [
            Expanded(child: Container(height: 1, color: AppColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OR CONTINUE WITH',
                style: AppTypography.captionUpper.copyWith(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            Expanded(child: Container(height: 1, color: AppColors.border)),
          ],
        ),
        const SizedBox(height: 32),

        // Name field (registration mode)
        if (!_isLoginMode) ...[
          _DarkInputField(
            label: 'FULL NAME',
            hintText: 'Enter your name',
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            enabled: !isLoading,
            onChanged: (_) => _clearError(),
          ),
          const SizedBox(height: 16),
        ],

        // Email form fields
        _DarkInputField(
          label: 'EMAIL ADDRESS',
          hintText: 'name@example.com',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          enabled: !isLoading,
          onChanged: (_) => _clearError(),
        ),
        const SizedBox(height: 16),
        _DarkInputField(
          label: 'PASSWORD',
          hintText: '••••••••',
          controller: _passwordController,
          obscureText: _obscurePassword,
          enabled: !isLoading,
          onChanged: (_) => _clearError(),
          suffixIcon: GestureDetector(
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
            child: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Forgot password
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => context.push(AppRoutes.forgotPassword),
            child: const Text(
              'Forgot Password?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Sign In button
        GestureDetector(
          onTap: isLoading ? null : _handleEmailAuth,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: AppRadii.brFull,
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isLoginMode ? 'Sign In' : 'Create Account',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Toggle login/register
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isLoginMode
                  ? "Don't have an account? "
                  : 'Already have an account? ',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            GestureDetector(
              onTap: isLoading
                  ? null
                  : () {
                      _clearError();
                      setState(() => _isLoginMode = !_isLoginMode);
                    },
              child: Text(
                _isLoginMode ? 'Create one' : 'Sign in',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
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
            const SizedBox(height: 16),
            // Back button
            GestureDetector(
              onTap: isLoading
                  ? null
                  : () {
                      _clearError();
                      setState(() => _showEmailForm = false);
                    },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isLoginMode ? 'Welcome back' : 'Create account',
              style: AppTypography.h1.copyWith(fontSize: 28),
            ),
            const SizedBox(height: 8),
            Text(
              _isLoginMode
                  ? 'Sign in to continue your journey'
                  : 'Start your journey to greatness',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            if (!_isLoginMode) ...[
              _DarkInputField(
                label: 'FULL NAME',
                hintText: 'Enter your name',
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                enabled: !isLoading,
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 16),
            ],
            _DarkInputField(
              label: 'EMAIL ADDRESS',
              hintText: 'name@example.com',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              enabled: !isLoading,
              onChanged: (_) => _clearError(),
            ),
            const SizedBox(height: 16),
            _DarkInputField(
              label: 'PASSWORD',
              hintText: _isLoginMode
                  ? 'Enter your password'
                  : 'Create a password',
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
            const SizedBox(height: 24),
            // Submit
            GestureDetector(
              onTap: isLoading ? null : _handleEmailAuth,
              child: Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: AppRadii.brFull,
                ),
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isLoginMode ? 'Sign In' : 'Create Account',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
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
                child: Text(
                  _isLoginMode
                      ? "Don't have an account? Sign up"
                      : 'Already have an account? Sign in',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
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

/// Paper input field for auth screens.
class _DarkInputField extends StatelessWidget {
  const _DarkInputField({
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
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimary,
                  ),
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

/// Social login button for auth screen.
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.useColorIcon = false,
  });

  final String label;
  final String icon;
  final VoidCallback? onTap;
  final bool useColorIcon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: AppRadii.br16,
          boxShadow: AppShadows.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              icon,
              width: 20,
              height: 20,
              colorFilter: useColorIcon
                  ? null
                  : const ColorFilter.mode(
                      AppColors.textPrimary,
                      BlendMode.srcIn,
                    ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.captionMedium.copyWith(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
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
