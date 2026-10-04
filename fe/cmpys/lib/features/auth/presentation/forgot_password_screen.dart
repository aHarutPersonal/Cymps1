import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/network/api_error.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../data/password_recovery_repository.dart';

enum _RecoveryStage { email, code, success }

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.now});

  @visibleForTesting
  final DateTime Function()? now;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _emailForm = GlobalKey<FormState>();
  final _codeForm = GlobalKey<FormState>();
  _RecoveryStage _stage = _RecoveryStage.email;
  bool? _available;
  bool _checking = false;
  bool _busy = false;
  bool _hideCode = true;
  bool _hidePassword = true;
  bool _hideConfirmation = true;
  String? _availabilityError;
  String? _error;
  String? _notice;
  String? _requestedEmail;
  DateTime? _requestRetryAt;
  DateTime? _confirmRetryAt;
  Timer? _timer;

  PasswordRecoveryRepository get _repository =>
      ref.read(passwordRecoveryRepositoryProvider);
  DateTime get _now => widget.now?.call() ?? DateTime.now();

  int _remaining(DateTime? until) {
    if (until == null) return 0;
    final ms = until.difference(_now).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  String _waitLabel(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  void _startClock() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_remaining(_requestRetryAt) == 0 &&
          _remaining(_confirmRetryAt) == 0) {
        _timer?.cancel();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_checkAvailability());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _availabilityError = null;
    });
    try {
      final available = await _repository.isAvailable();
      if (mounted) setState(() => _available = available);
    } catch (_) {
      if (mounted) {
        setState(() {
          _available = null;
          _availabilityError =
              'Couldn’t check email recovery. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  Future<void> _requestCode({bool resend = false}) async {
    if (_busy || _available != true || _remaining(_requestRetryAt) > 0) return;
    if (!resend && !(_emailForm.currentState?.validate() ?? false)) return;
    final email = resend ? _requestedEmail : _email.text.trim();
    if (email == null || _validateEmail(email) != null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await _repository.requestCode(email);
      if (!mounted) return;
      setState(() {
        _stage = _RecoveryStage.code;
        _requestedEmail = email;
        _notice =
            'If an account uses this email, a recovery code will arrive shortly.';
        _requestRetryAt = _now.add(const Duration(seconds: 60));
        _code.clear();
      });
      _startClock();
    } catch (error) {
      if (mounted) _showError(error, requesting: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReset() async {
    if (_busy || _remaining(_confirmRetryAt) > 0) return;
    if (!(_codeForm.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repository.confirm(
        token: _code.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _code.clear();
        _password.clear();
        _confirmation.clear();
        _notice = null;
        _stage = _RecoveryStage.success;
      });
    } catch (error) {
      if (mounted) _showError(error, requesting: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error, {required bool requesting}) {
    final status = error is ApiError ? error.statusCode : null;
    setState(() {
      if (status == 429) {
        final seconds = (error as ApiError).retryAfterSeconds ?? 900;
        final until = _now.add(Duration(seconds: seconds));
        if (requesting) {
          _requestRetryAt = until;
        } else {
          _confirmRetryAt = until;
        }
        _error = 'Too many attempts. Please wait before trying again.';
        _startClock();
      } else if (status == 400 && !requesting) {
        _error =
            'This recovery code is invalid or expired. Request a new code.';
      } else if (status == 404 || status == 503) {
        if (requesting) _available = false;
        _error =
            'Password recovery is currently unavailable. Please try again later.';
      } else if (status == 422) {
        _error = requesting
            ? 'Check your email address and try again.'
            : 'Check the full recovery code and use a password of at least 8 characters (up to 72 UTF-8 bytes).';
      } else {
        _error = requesting
            ? 'Couldn’t request a recovery code. Check your connection and try again.'
            : 'Couldn’t confirm the password change. Check your connection and try again. If the code has already been used, try signing in or request a new one.';
      }
    });
  }

  void _enterCode() {
    setState(() {
      _stage = _RecoveryStage.code;
      _error = null;
      _notice = null;
    });
  }

  void _requestNewCode() {
    setState(() {
      _stage = _RecoveryStage.email;
      _requestedEmail = null;
      _error = null;
      _notice = null;
      _code.clear();
      _password.clear();
      _confirmation.clear();
    });
    unawaited(_checkAvailability());
  }

  void _backToSignIn() {
    final success = _stage == _RecoveryStage.success;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(success);
    } else {
      context.go(AppRoutes.auth);
    }
  }

  Widget _field({
    required String keyName,
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    List<String>? autofillHints,
    bool obscure = false,
    Widget? suffix,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(keyName),
      controller: controller,
      enabled: !_busy,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      validator: validator,
      style: AppTypography.body,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.card,
        errorMaxLines: 3,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
  );

  Widget _visibility(bool hidden, String name, VoidCallback toggle) =>
      IconButton(
        tooltip: '${hidden ? 'Show' : 'Hide'} $name',
        onPressed: _busy ? null : toggle,
        icon: Icon(
          hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      );

  Widget _button(String label, VoidCallback? action) => CmpysButton(
    full: true,
    onTap: action,
    disabled: action == null,
    child: Text(label, textAlign: TextAlign.center),
  );

  @override
  Widget build(BuildContext context) {
    final requestWait = _remaining(_requestRetryAt);
    final confirmWait = _remaining(_confirmRetryAt);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          title: const Text('Account access'),
          leading: IconButton(
            tooltip: 'Back to sign in',
            onPressed: _busy ? null : _backToSignIn,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    Icon(
                      _stage == _RecoveryStage.success
                          ? Icons.check_circle_outline
                          : Icons.key_outlined,
                      size: 40,
                      color: AppColors.green2,
                    ),
                    const SizedBox(height: 24),
                    Text(switch (_stage) {
                      _RecoveryStage.email => 'Forgot your password?',
                      _RecoveryStage.code => 'Enter recovery code',
                      _RecoveryStage.success => 'Password updated',
                    }, style: AppTypography.h1),
                    const SizedBox(height: 12),
                    if (_error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: AppTypography.body.copyWith(
                            color: AppColors.red,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_stage == _RecoveryStage.email) ...[
                      if (_checking) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        const Text('Checking email recovery…'),
                      ] else if (_available == true) ...[
                        Text(
                          'Enter your account email to request a recovery code.',
                          style: AppTypography.bodyDim,
                        ),
                        const SizedBox(height: 24),
                        Form(
                          key: _emailForm,
                          child: _field(
                            keyName: 'recovery-email',
                            label: 'Email address',
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            validator: _validateEmail,
                          ),
                        ),
                        _button(
                          _busy
                              ? 'Requesting code…'
                              : requestWait > 0
                              ? 'Try again in ${_waitLabel(requestWait)}'
                              : 'Request recovery code',
                          _busy || requestWait > 0 ? null : _requestCode,
                        ),
                      ] else ...[
                        Text(
                          _availabilityError ??
                              'Password reset by email is not available yet.',
                          style: AppTypography.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Check your password manager for a saved CMPYS password, or enter a recovery code you already received.',
                          style: AppTypography.bodyDim,
                        ),
                        TextButton(
                          onPressed: _checkAvailability,
                          child: const Text('Check again'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _busy ? null : _enterCode,
                        child: const Text('Enter recovery code'),
                      ),
                    ],
                    if (_stage == _RecoveryStage.code) ...[
                      if (_notice != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _notice!,
                            style: AppTypography.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        'Paste the complete code from your email. It can be used once and expires in 20 minutes.',
                        style: AppTypography.bodyDim,
                      ),
                      const SizedBox(height: 24),
                      Form(
                        key: _codeForm,
                        child: Column(
                          children: [
                            _field(
                              keyName: 'recovery-code',
                              label: 'Recovery code',
                              controller: _code,
                              obscure: _hideCode,
                              keyboardType: TextInputType.visiblePassword,
                              validator: (value) =>
                                  RegExp(
                                    r'^[A-Za-z0-9_-]{43}$',
                                  ).hasMatch(value?.trim() ?? '')
                                  ? null
                                  : 'Paste the complete recovery code from your email.',
                              suffix: _visibility(
                                _hideCode,
                                'recovery code',
                                () => setState(() => _hideCode = !_hideCode),
                              ),
                            ),
                            _field(
                              keyName: 'recovery-password',
                              label: 'New password',
                              controller: _password,
                              obscure: _hidePassword,
                              keyboardType: TextInputType.visiblePassword,
                              validator: (value) {
                                if ((value ?? '').runes.length < 8) {
                                  return 'Use at least 8 characters.';
                                }
                                if (utf8.encode(value!).length > 72) {
                                  return 'This password is too long. Use a shorter password.';
                                }
                                return null;
                              },
                              suffix: _visibility(
                                _hidePassword,
                                'new password',
                                () => setState(
                                  () => _hidePassword = !_hidePassword,
                                ),
                              ),
                            ),
                            _field(
                              keyName: 'recovery-confirmation',
                              label: 'Confirm new password',
                              controller: _confirmation,
                              obscure: _hideConfirmation,
                              keyboardType: TextInputType.visiblePassword,
                              validator: (value) =>
                                  value == _password.text &&
                                      (value ?? '').isNotEmpty
                                  ? null
                                  : 'Passwords do not match.',
                              suffix: _visibility(
                                _hideConfirmation,
                                'password confirmation',
                                () => setState(
                                  () => _hideConfirmation = !_hideConfirmation,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Use at least 8 characters.',
                        style: AppTypography.caption,
                      ),
                      const SizedBox(height: 16),
                      _button(
                        _busy
                            ? 'Updating password…'
                            : confirmWait > 0
                            ? 'Try again in ${_waitLabel(confirmWait)}'
                            : 'Update password',
                        _busy || confirmWait > 0 ? null : _confirmReset,
                      ),
                      if (_requestedEmail != null && _available == true)
                        TextButton(
                          onPressed: _busy || requestWait > 0
                              ? null
                              : () => _requestCode(resend: true),
                          child: Text(
                            requestWait > 0
                                ? 'Request another code in ${_waitLabel(requestWait)}'
                                : 'Request another code',
                          ),
                        ),
                      TextButton(
                        onPressed: _busy ? null : _requestNewCode,
                        child: const Text('Request a new code or change email'),
                      ),
                    ],
                    if (_stage == _RecoveryStage.success)
                      Text(
                        'Sign in with your new password to continue. Your other sessions have been signed out.',
                        style: AppTypography.bodyMedium,
                      ),
                    const SizedBox(height: 24),
                    _button('Back to sign in', _busy ? null : _backToSignIn),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
