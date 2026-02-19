import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/cmpys_text_field.dart';
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
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState is AuthLoading;

    // Listen for auth state changes
    ref.listen(authControllerProvider, (prev, next) async {
      if (next is AuthAuthenticated) {
        // Clear any error
        _clearError();
        // Trigger session initialization
        await ref.read(sessionControllerProvider.notifier).onAuthenticated();
        
        if (!mounted) return;
        
        // Navigate based on session state after frame completes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          
          final sessionState = ref.read(sessionControllerProvider);
          debugPrint('🔐 Auth success, session: ${sessionState.runtimeType}');
          
          if (sessionState is SessionNeedsOnboarding) {
            context.go(AppRoutes.profileSetup);
          } else if (sessionState is SessionReady) {
            context.go(AppRoutes.home);
          } else {
            // Default to profile setup for new users
            context.go(AppRoutes.profileSetup);
          }
        });
      } else if (next is AuthError) {
        // Show error in banner
        setState(() => _errorMessage = next.message);
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Error banner
            _ErrorBanner(
              message: _errorMessage,
              onDismiss: _clearError,
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: AppSpacing.screenH,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height -
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
    );
  }

  Widget _buildSocialAuth(bool isLoading) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.s48),
        // Logo
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.accentLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: AppRadii.br24,
            boxShadow: AppShadows.accent,
          ),
          child: Center(
            child: Text(
              'C',
              style: AppTypography.h1.copyWith(fontSize: 44),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s24),
        Text('CMPYS', style: AppTypography.h1),
        const SizedBox(height: AppSpacing.s8),
        Text(
          'Compare your success with the\nworld\'s greatest achievers',
          style: AppTypography.body.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s32),
        // Feature pills
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          alignment: WrapAlignment.center,
          children: ['Track Progress', 'Compare Timelines', 'Get Inspired']
              .map((feature) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s16,
                      vertical: AppSpacing.s8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadii.brFull,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      feature,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: AppSpacing.s48),
        // Auth buttons
        _AuthButton(
          label: 'Continue with Apple',
          icon: AppAssets.iconApple,
          onTap: isLoading ? null : () => _handleOAuth('apple'),
          isPrimary: true,
        ),
        const SizedBox(height: AppSpacing.s12),
        _AuthButton(
          label: 'Continue with Google',
          icon: AppAssets.iconGoogle,
          onTap: isLoading ? null : () => _handleOAuth('google'),
          useColorIcon: true,
        ),
        const SizedBox(height: AppSpacing.s20),
        // Divider
        Row(
          children: [
            Expanded(child: Divider(color: AppColors.border)),
            Padding(
              padding: AppSpacing.ph16,
              child: Text(
                'or',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            Expanded(child: Divider(color: AppColors.border)),
          ],
        ),
        const SizedBox(height: AppSpacing.s20),
        TextButton(
          onPressed: isLoading
              ? null
              : () {
                  _clearError();
                  setState(() {
                    _showEmailForm = true;
                    _isLoginMode = true;
                  });
                },
          child: Text(
            'Continue with Email',
            style: AppTypography.buttonSmall.copyWith(
              color: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s32),
        Text(
          'By continuing, you agree to our Terms of Service\nand Privacy Policy',
          style: AppTypography.caption.copyWith(
            color: AppColors.textTertiary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s24),
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
            const SizedBox(height: AppSpacing.s16),
            // Back button
            IconButton(
              onPressed: isLoading
                  ? null
                  : () {
                      _clearError();
                      setState(() => _showEmailForm = false);
                    },
              icon: SvgPicture.asset(
                AppAssets.iconArrowLeft,
                width: 24,
                height: 24,
              colorFilter: const ColorFilter.mode(
                AppColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s24),
          Text(
            _isLoginMode ? 'Welcome back' : 'Create account',
            style: AppTypography.h1,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            _isLoginMode
                ? 'Sign in to continue your journey'
                : 'Start your journey to greatness',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.s32),
          // Name field (only for register)
          if (!_isLoginMode) ...[
            CmpysTextField(
              key: const ValueKey('name_field'),
              controller: _nameController,
              label: 'Full Name',
              hint: 'Enter your name',
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              enabled: !isLoading,
              onChanged: (_) => _clearError(),
            ),
            const SizedBox(height: AppSpacing.s16),
          ],
          // Email field - using plain TextField to avoid obscureText issues
          Column(
            key: const ValueKey('email_field'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Email',
                style: AppTypography.label.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.none,
                obscureText: false,
                autocorrect: false,
                enableSuggestions: true,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                enabled: !isLoading,
                onChanged: (_) => _clearError(),
                style: AppTypography.body,
                cursorColor: AppColors.accent,
                decoration: const InputDecoration(
                  hintText: 'Enter your email',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          // Password field
          CmpysTextField(
            key: const ValueKey('password_field'),
            controller: _passwordController,
            label: 'Password',
            hint: _isLoginMode ? 'Enter your password' : 'Create a password',
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: _isLoginMode
                ? const [AutofillHints.password]
                : const [AutofillHints.newPassword],
            enabled: !isLoading,
            onChanged: (_) => _clearError(),
            onSubmitted: (_) => _handleEmailAuth(),
          ),
          const SizedBox(height: AppSpacing.s24),
          // Submit button
          CmpysButton(
            label: _isLoginMode ? 'Sign In' : 'Create Account',
            onPressed: isLoading ? null : _handleEmailAuth,
            isLoading: isLoading,
          ),
          const SizedBox(height: AppSpacing.s16),
          // Toggle mode
          Center(
            child: TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      _clearError();
                      setState(() => _isLoginMode = !_isLoginMode);
                    },
              child: Text(
                _isLoginMode
                    ? 'Don\'t have an account? Sign up'
                    : 'Already have an account? Sign in',
                style: AppTypography.buttonSmall.copyWith(
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s24),
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

    // Validate email
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email');
      return;
    }
    
    if (!_isValidEmail(email)) {
      setState(() => _errorMessage = 'Please enter a valid email');
      return;
    }

    // Validate password
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password');
      return;
    }
    
    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters');
      return;
    }

    // Validate name for registration
    if (!_isLoginMode && name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your name');
      return;
    }

    final authController = ref.read(authControllerProvider.notifier);

    if (_isLoginMode) {
      // POST /auth/login
      await authController.login(email: email, password: password);
    } else {
      // POST /auth/register
      await authController.register(
        email: email,
        password: password,
        fullName: name,
      );
    }
    // Navigation handled by router redirect based on session state
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  void _handleOAuth(String provider) {
    // TODO: Implement OAuth flow with platform-specific plugins
    setState(() => _errorMessage = '$provider login coming soon!');
  }
}

/// Inline error banner consistent with Figma style.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
  });

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
                color: AppColors.error.withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.error.withOpacity(0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  SvgPicture.asset(
                    AppAssets.iconAlertCircle,
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(
                      AppColors.error,
                      BlendMode.srcIn,
                    ),
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
                    child: SvgPicture.asset(
                      AppAssets.iconX,
                      width: 16,
                      height: 16,
                      colorFilter: ColorFilter.mode(
                        AppColors.error.withOpacity(0.7),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
    this.useColorIcon = false,
  });

  final String label;
  final String icon;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool useColorIcon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isPrimary ? AppColors.textPrimary : AppColors.surface,
      borderRadius: AppRadii.br16,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.br16,
        child: Container(
          height: 56,
          padding: AppSpacing.ph16,
          decoration: BoxDecoration(
            borderRadius: AppRadii.br16,
            border: isPrimary ? null : Border.all(color: AppColors.border),
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
                    : ColorFilter.mode(
                        isPrimary ? AppColors.bg : AppColors.textPrimary,
                        BlendMode.srcIn,
                      ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Text(
                label,
                style: AppTypography.button.copyWith(
                  color: isPrimary ? AppColors.bg : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
