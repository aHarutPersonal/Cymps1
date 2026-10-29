import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/network/api_error.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/v3/v3.dart';
import '../controllers/auth_controller.dart';
import '../controllers/session_controller.dart';
import 'forgot_password_screen.dart';

/// Which side of the Create account / Sign in segment is selected.
enum AuthMode { signUp, signIn }

/// Auth (`v3/onboard.jsx` Auth): create an account or sign in with email and
/// password, with inline validation and "Forgot password?" opening the
/// three-step recovery sheet.
///
/// [initialMode] picks the segment the splash's two buttons ask for.
/// [startRecovery] opens the recovery sheet as soon as the screen is up (the
/// `/forgot-password` link).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({
    super.key,
    this.initialMode = AuthMode.signIn,
    this.startRecovery = false,
  });

  final AuthMode initialMode;
  final bool startRecovery;

  /// The collapsing name row (its height animates 0 ↔ full over .45 s).
  @visibleForTesting
  static const nameCollapseKey = ValueKey<String>('auth-name-collapse');

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  late AuthMode _mode = widget.initialMode;
  bool _showPassword = false;
  bool _openingRecovery = false;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Inline messages: one per field, plus a general one under the button.
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _generalError;

  bool get _isSignUp => _mode == AuthMode.signUp;

  @override
  void initState() {
    super.initState();
    if (widget.startRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openRecovery();
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearErrors() {
    _nameError = _emailError = _passwordError = _generalError = null;
  }

  void _setMode(AuthMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _clearErrors();
    });
  }

  /// Editing a field drops its own message and any message from the server.
  void _edited({bool name = false, bool email = false, bool password = false}) {
    setState(() {
      if (name) _nameError = null;
      if (email) _emailError = null;
      if (password) _passwordError = null;
      _generalError = null;
    });
  }

  Future<void> _submit() async {
    if (ref.read(authControllerProvider) is AuthLoading) return;
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    String? nameError;
    String? emailError;
    String? passwordError;
    if (_isSignUp && name.isEmpty) nameError = 'Tell us your name';
    if (!_emailPattern.hasMatch(email)) emailError = 'Enter a valid email';
    // The server takes any non-empty password on login, so only a new account
    // is held to the eight-character minimum.
    if (password.isEmpty || (_isSignUp && password.runes.length < 8)) {
      passwordError = 'At least 8 characters';
    } else if (utf8.encode(password).length > 72) {
      passwordError = 'This password is too long. Use a shorter password.';
    }
    setState(() {
      _nameError = nameError;
      _emailError = emailError;
      _passwordError = passwordError;
      _generalError = null;
    });
    if (nameError != null || emailError != null || passwordError != null) {
      return;
    }

    FocusScope.of(context).unfocus();
    final auth = ref.read(authControllerProvider.notifier);
    if (_isSignUp) {
      await auth.register(email: email, password: password, fullName: name);
    } else {
      await auth.login(email: email, password: password);
    }
  }

  /// Shows a failed sign-in or sign-up. A 422 is a validation failure whose
  /// message is the validator's raw text: its fields get friendly copy
  /// instead ([_validationCopy]), and anything the form can't name gets
  /// [_validationFallback]. Other errors go through [_showAuthMessage].
  void _showAuthError(AuthError error) {
    if (error.statusCode != 422) {
      _showAuthMessage(error.message);
      return;
    }
    String? name;
    String? email;
    String? password;
    var unknown = error.fieldErrors.isEmpty;
    for (final field in error.fieldErrors) {
      final copy = _validationCopy(field);
      switch (copy?.$1) {
        case 'name':
          name ??= copy!.$2;
        case 'email':
          email ??= copy!.$2;
        case 'password':
          password ??= copy!.$2;
        default:
          unknown = true;
      }
    }
    setState(() {
      _nameError = name ?? _nameError;
      _emailError = email ?? _emailError;
      _passwordError = password ?? _passwordError;
      _generalError = unknown ? _validationFallback : null;
    });
  }

  static const _validationFallback =
      'Something in this form isn’t right. Check it and try again.';

  /// The form field ('name', 'email' or 'password') a server validation
  /// error belongs to and the copy it shows, or null when the form has no
  /// words for it.
  static (String, String)? _validationCopy(ApiFieldError error) {
    final type = error.type;
    switch (error.field) {
      case 'email':
        return ('email', 'Enter a valid email address.');
      case 'password':
        if (type == 'string_too_short') {
          return ('password', 'Use at least 8 characters.');
        }
        if (type == 'string_too_long' || type == 'value_error') {
          return (
            'password',
            'This password is too long. Use a shorter password.',
          );
        }
        return null;
      case 'full_name' || 'fullName':
        if (type == 'string_too_long') return ('name', 'Use a shorter name.');
        return null;
      default:
        return null;
    }
  }

  /// Puts a server message on the email field when it is about the email
  /// (an address that is already registered), otherwise under the button.
  void _showAuthMessage(String message) {
    final lower = message.toLowerCase();
    final aboutEmail =
        lower.contains('email') &&
        (lower.contains('already') ||
            lower.contains('registered') ||
            lower.contains('exists') ||
            lower.contains('in use'));
    setState(() {
      if (aboutEmail) {
        _emailError = message;
      } else {
        _generalError = message;
      }
    });
  }

  Future<void> _openRecovery() async {
    if (_openingRecovery) return;
    _openingRecovery = true;
    final reset = await showRecoverySheet(
      context,
      email: _emailController.text.trim(),
    );
    _openingRecovery = false;
    if (!mounted || reset != true) return;
    // The password was just replaced: ask for the new one, keep the email.
    ref.read(authControllerProvider.notifier).clearError();
    setState(() {
      _passwordController.clear();
      _clearErrors();
      _mode = AuthMode.signIn;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider) is AuthLoading;

    ref.listen(authControllerProvider, (prev, next) async {
      if (next is AuthAuthenticated) {
        setState(() => _generalError = null);
        await ref
            .read(sessionControllerProvider.notifier)
            .onAuthenticated(isNewRegistration: next.isNewRegistration);
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final sessionState = ref.read(sessionControllerProvider);
          if (sessionState is SessionReady) {
            context.go(AppRoutes.home);
          } else if (sessionState is SessionNeedsOnboarding) {
            context.go(AppRoutes.cmpysOnboarding);
          } else if (sessionState is SessionError) {
            context.go(AppRoutes.splash);
          } else {
            setState(
              () => _generalError =
                  'Your session could not be verified. Please sign in again.',
            );
          }
        });
      } else if (next is AuthError) {
        _showAuthError(next);
      }
    });

    final canGoBack = Navigator.of(context).canPop();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: DefaultTextStyle(
          style: AppTypography.sans(16).copyWith(color: AppColors.ink),
          child: Column(
            children: [
              V3TopBar(
                onBack: canGoBack && !isLoading
                    ? () => Navigator.of(context).maybePop()
                    : null,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final gutter = math.max(
                      24.0,
                      (constraints.maxWidth - 520) / 2,
                    );
                    return SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 40),
                      child: _buildForm(isLoading),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool isLoading) {
    final signUp = _isSignUp;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          V3Rise(
            key: ValueKey(_mode),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (signUp ? 'Create account' : 'Welcome back').toUpperCase(),
                  style: AppTypography.kick,
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    style: AppTypography.display(
                      44,
                    ).copyWith(color: AppColors.ink),
                    children: [
                      TextSpan(
                        text: signUp
                            ? 'Start with who you\n'
                            : 'Pick up where\n',
                      ),
                      TextSpan(
                        text: signUp ? 'want to become.' : 'you left off.',
                        style: AppTypography.displayItalic(
                          44,
                        ).copyWith(color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          V3Seg<AuthMode>(
            items: const [
              V3SegItem(AuthMode.signUp, 'Create account'),
              V3SegItem(AuthMode.signIn, 'Sign in'),
            ],
            value: _mode,
            onChanged: isLoading ? (_) {} : _setMode,
          ),
          const SizedBox(height: 22),
          _Collapse(
            key: AuthScreen.nameCollapseKey,
            open: signUp,
            child: V3Field(
              label: 'Name',
              controller: _nameController,
              placeholder: 'Your first name',
              error: _nameError,
              enabled: !isLoading,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.givenName],
              // A name is not a word the keyboard should "fix".
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => _edited(name: true),
            ),
          ),
          const SizedBox(height: 14),
          V3Field(
            label: 'Email',
            controller: _emailController,
            placeholder: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            error: _emailError,
            enabled: !isLoading,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => _edited(email: true),
          ),
          const SizedBox(height: 14),
          V3Field(
            label: 'Password',
            controller: _passwordController,
            placeholder: '8+ characters',
            obscureText: !_showPassword,
            // Also off while the password is shown.
            autocorrect: false,
            enableSuggestions: false,
            error: _passwordError,
            enabled: !isLoading,
            textInputAction: TextInputAction.done,
            autofillHints: [
              signUp ? AutofillHints.newPassword : AutofillHints.password,
            ],
            onChanged: (_) => _edited(password: true),
            onSubmitted: (_) => _submit(),
            right: V3Pressable(
              semanticLabel: _showPassword ? 'Hide password' : 'Show password',
              onTap: () => setState(() => _showPassword = !_showPassword),
              child: V3Icon(
                _showPassword ? V3Icons.eyeOff : V3Icons.eye,
                size: 19,
                color: AppColors.ink3,
              ),
            ),
          ),
          if (!signUp) ...[
            // The 44 pt hit box supplies 12 pt above and below the 20 pt link,
            // so the gaps are the design's 14 and 26 less that.
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: V3Rise(
                child: V3Pressable(
                  onTap: isLoading ? null : _openRecovery,
                  focusRadius: const BorderRadius.all(Radius.circular(8)),
                  child: Text(
                    'Forgot password?',
                    style: AppTypography.sans(
                      13.5,
                      FontWeight.w600,
                    ).copyWith(color: AppColors.ember2),
                  ),
                ),
              ),
            ),
          ],
          SizedBox(height: signUp ? 26 : 14),
          V3Button(
            full: true,
            loading: isLoading,
            onPressed: _submit,
            child: Text(signUp ? 'Create account' : 'Sign in'),
          ),
          if (_generalError != null) ...[
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: V3Icon(
                      V3Icons.alert,
                      size: 13,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      _generalError!,
                      textAlign: TextAlign.center,
                      style: AppTypography.sans(
                        12.5,
                      ).copyWith(color: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Mentors in CMPYS are AI interpretations of real people’s '
            'documented methods. They are not the people themselves.',
            textAlign: TextAlign.center,
            style: AppTypography.sans(
              12,
            ).copyWith(color: AppColors.ink3, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// `display: grid; grid-template-rows: 1fr → 0fr` over .45 s on `--out`: the
/// child keeps its full size while its row collapses to nothing. A collapsed
/// child is out of paint, hit testing, semantics and the focus order, but
/// keeps its state (so a typed name survives a trip to Sign in).
class _Collapse extends StatelessWidget {
  const _Collapse({super.key, required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: open ? 1 : 0),
      duration: MotionConfig.enabled(context)
          ? const Duration(milliseconds: 450)
          : Duration.zero,
      curve: AppMotion.out,
      child: child,
      builder: (context, factor, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: factor,
          child: ExcludeFocus(
            excluding: factor == 0,
            child: Offstage(offstage: factor == 0, child: child),
          ),
        ),
      ),
    );
  }
}
