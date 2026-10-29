import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/network/api_error.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/v3/v3.dart';
import '../data/password_recovery_repository.dart';

/// Opens the password-recovery sheet (`v3/onboard.jsx` Recovery) and resolves
/// to whether the password was changed, however the sheet was closed.
///
/// The three steps map onto the real recovery API:
///   1. "Reset your password" checks `GET /auth/password-reset/availability`
///      and, for an available service, requests a code for [email]
///      (`POST /auth/password-reset/request`).
///   2. "Check your email" takes the emailed code and a new password
///      (`POST /auth/password-reset/confirm`). The server's code is a
///      43-character token that is pasted, not the design's six digits.
///   3. "Password updated" confirms and returns to sign-in.
///
/// [now] only exists so tests can move the cooldown clocks.
Future<bool> showRecoverySheet(
  BuildContext context, {
  String email = '',
  @visibleForTesting DateTime Function()? now,
}) async {
  final outcome = _RecoveryOutcome();
  await showV3Sheet<void>(
    context,
    // The sheet draws its own title (it changes with the step) and scrolls
    // only the body, so the title and its close button stay put.
    noPad: true,
    scrollable: false,
    builder: (_) => _RecoverySheet(email: email, now: now, outcome: outcome),
  );
  return outcome.updated;
}

class _RecoveryOutcome {
  bool updated = false;
}

enum _Step { email, code, done }

/// How long the server takes to expire a recovery code (minutes).
const _codeLifetimeMinutes = 20;

/// The wait before the same address can be asked for another code.
const _resendCooldown = Duration(seconds: 60);

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

class _RecoverySheet extends ConsumerStatefulWidget {
  const _RecoverySheet({
    required this.email,
    required this.now,
    required this.outcome,
  });

  final String email;
  final DateTime Function()? now;
  final _RecoveryOutcome outcome;

  @override
  ConsumerState<_RecoverySheet> createState() => _RecoverySheetState();
}

class _RecoverySheetState extends ConsumerState<_RecoverySheet> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();

  _Step _step = _Step.email;
  bool? _available;
  bool _checking = false;
  bool _busy = false;
  String? _availabilityError;
  String? _requestedEmail;
  DateTime? _requestRetryAt;
  DateTime? _confirmRetryAt;
  Timer? _timer;

  // One message at a time, on the field it is about.
  String? _emailError;
  String? _codeError;
  String? _passwordError;
  String? _confirmError;

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

  void _clearErrors() {
    _emailError = _codeError = _passwordError = _confirmError = null;
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

  Future<void> _requestCode({bool resend = false}) async {
    if (_busy || _available != true || _remaining(_requestRetryAt) > 0) return;
    final email = resend ? _requestedEmail : _email.text.trim();
    if (email == null || !_emailPattern.hasMatch(email)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _clearErrors();
    });
    try {
      await _repository.requestCode(email);
      if (!mounted) return;
      setState(() {
        _requestedEmail = email;
        _requestRetryAt = _now.add(_resendCooldown);
        _code.clear();
        if (!resend) _step = _Step.code;
      });
      _startClock();
    } catch (error) {
      if (mounted) _showRequestError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReset() async {
    if (_busy || _remaining(_confirmRetryAt) > 0) return;
    final code = _code.text.trim();
    final password = _password.text;
    final problem = _validateReset(code, password, _confirmation.text);
    if (problem != null) {
      setState(() {
        _clearErrors();
        switch (problem.field) {
          case _ResetField.code:
            _codeError = problem.message;
          case _ResetField.password:
            _passwordError = problem.message;
          case _ResetField.confirmation:
            _confirmError = problem.message;
        }
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _clearErrors();
    });
    try {
      await _repository.confirm(token: code, password: password);
      if (!mounted) return;
      _timer?.cancel();
      widget.outcome.updated = true;
      setState(() {
        _code.clear();
        _password.clear();
        _confirmation.clear();
        _step = _Step.done;
      });
    } catch (error) {
      if (mounted) _showConfirmError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The design's order: the code, then the new password, then the match.
  _ResetProblem? _validateReset(
    String code,
    String password,
    String confirmation,
  ) {
    if (!_tokenPattern.hasMatch(code)) {
      return const _ResetProblem(
        _ResetField.code,
        'Paste the complete recovery code from your email.',
      );
    }
    if (password.runes.length < 8) {
      return const _ResetProblem(
        _ResetField.password,
        'New password needs 8+ characters',
      );
    }
    if (utf8.encode(password).length > 72) {
      return const _ResetProblem(
        _ResetField.password,
        'This password is too long. Use a shorter password.',
      );
    }
    if (password != confirmation) {
      return const _ResetProblem(
        _ResetField.confirmation,
        'Passwords don’t match',
      );
    }
    return null;
  }

  void _showRequestError(Object error) {
    final status = error is ApiError ? error.statusCode : null;
    String message;
    if (status == 429) {
      final seconds = (error as ApiError).retryAfterSeconds ?? 900;
      _requestRetryAt = _now.add(Duration(seconds: seconds));
      message = 'Too many attempts. Please wait before trying again.';
      _startClock();
    } else if (status == 404 || status == 503) {
      _available = false;
      _availabilityError =
          'Password recovery is currently unavailable. Please try again later.';
      message = _availabilityError!;
    } else if (status == 422) {
      message = 'Check your email address and try again.';
    } else {
      message =
          'Couldn’t request a recovery code. Check your connection and try again.';
    }
    setState(() {
      // The first request reports under the address; a resend, under the form.
      if (_step == _Step.email) {
        _emailError = message;
      } else {
        _confirmError = message;
      }
    });
  }

  void _showConfirmError(Object error) {
    final status = error is ApiError ? error.statusCode : null;
    setState(() {
      if (status == 429) {
        final seconds = (error as ApiError).retryAfterSeconds ?? 900;
        _confirmRetryAt = _now.add(Duration(seconds: seconds));
        _confirmError = 'Too many attempts. Please wait before trying again.';
        _startClock();
      } else if (status == 400) {
        // The server answers "invalid or expired" for a code that is expired,
        // already used or unknown; asking for a new one fixes all three.
        _codeError = 'That code has expired. Request a new one.';
      } else if (status == 404 || status == 503) {
        _confirmError =
            'Password recovery is currently unavailable. Please try again later.';
      } else if (status == 422) {
        _confirmError =
            'Check the full recovery code and use a password of at least 8 characters (up to 72 UTF-8 bytes).';
      } else {
        _confirmError =
            'Couldn’t confirm the password change. Check your connection and try again. If the code has already been used, try signing in or request a new one.';
      }
    });
  }

  void _enterCode() {
    setState(() {
      _step = _Step.code;
      _clearErrors();
    });
  }

  void _requestNewCode() {
    setState(() {
      _step = _Step.email;
      _requestedEmail = null;
      _clearErrors();
      _code.clear();
      _password.clear();
      _confirmation.clear();
    });
    unawaited(_checkAvailability());
  }

  void _edited() => setState(_clearErrors);

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _Step.email => 'Reset your password',
      _Step.code => 'Check your email',
      _Step.done => 'Password updated',
    };
    return PopScope(
      canPop: !_busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The title row of `Sheet`: padding 6 22 4 around a 34 pt close.
          Padding(
            padding: const EdgeInsets.only(left: 22, right: 17, top: 1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.sans(
                      19,
                      FontWeight.w600,
                    ).copyWith(color: AppColors.ink, letterSpacing: -0.19),
                  ),
                ),
                const SizedBox(width: 5),
                V3IconButton(
                  icon: V3Icons.x,
                  size: 34,
                  label: 'Close',
                  onPressed: _busy ? null : _close,
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
              child: V3Rise(
                key: ValueKey(_step),
                child: switch (_step) {
                  _Step.email => _buildEmailStep(),
                  _Step.code => _buildCodeStep(),
                  _Step.done => _buildDoneStep(),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailStep() {
    final wait = _remaining(_requestRetryAt);
    final children = <Widget>[];
    if (_checking) {
      children.add(
        Row(
          children: [
            const V3Spinner(color: AppColors.ink3, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Checking email recovery…',
                style: AppTypography.sans(14).copyWith(color: AppColors.ink2),
              ),
            ),
          ],
        ),
      );
    } else if (_available == true) {
      children.addAll([
        Row(
          children: [
            const V3Icon(
              V3Icons.check,
              size: 15,
              strokeWidth: 2.4,
              color: AppColors.sage2,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Email recovery is available',
                style: AppTypography.sans(
                  13,
                  FontWeight.w600,
                ).copyWith(color: AppColors.sage2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        V3Field(
          key: const ValueKey('recovery-email'),
          label: 'Account email',
          controller: _email,
          placeholder: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          enableSuggestions: false,
          error: _emailError,
          enabled: !_busy,
          // The send button follows whether the address looks valid.
          onChanged: (_) => setState(() => _emailError = null),
          onSubmitted: (_) => _requestCode(),
        ),
        const SizedBox(height: 18),
        V3Button(
          full: true,
          loading: _busy,
          disabled: wait > 0 || !_emailPattern.hasMatch(_email.text.trim()),
          onPressed: _requestCode,
          child: Text(
            wait > 0
                ? 'Try again in ${_waitLabel(wait)}'
                : 'Send recovery code',
          ),
        ),
      ]);
    } else {
      children.addAll([
        Text(
          _availabilityError ?? 'Password reset by email is not available yet.',
          style: AppTypography.sans(
            15,
            FontWeight.w500,
          ).copyWith(color: AppColors.ink, height: 1.4),
        ),
        if (_availabilityError == null) ...[
          const SizedBox(height: 8),
          Text(
            'Check your password manager for a saved CMPYS password, or enter a recovery code you already received.',
            style: AppTypography.sans(
              14,
            ).copyWith(color: AppColors.ink2, height: 1.5),
          ),
        ],
        const SizedBox(height: 14),
        V3Button(
          kind: V3ButtonKind.soft,
          size: V3Size.md,
          full: true,
          onPressed: _checkAvailability,
          child: const Text('Check again'),
        ),
      ]);
    }
    children
      ..add(const SizedBox(height: 6))
      ..add(
        V3Button(
          kind: V3ButtonKind.ghost,
          size: V3Size.md,
          full: true,
          disabled: _busy,
          onPressed: _enterCode,
          child: const Text('Enter recovery code'),
        ),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildCodeStep() {
    final resendWait = _remaining(_requestRetryAt);
    final confirmWait = _remaining(_confirmRetryAt);
    final requested = _requestedEmail != null && _available == true;
    final lead = AppTypography.sans(
      14.5,
    ).copyWith(color: AppColors.ink2, height: 1.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_requestedEmail != null)
          Text.rich(
            TextSpan(
              style: lead,
              children: [
                const TextSpan(text: 'If an account uses '),
                TextSpan(
                  text: _requestedEmail,
                  style: lead.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(
                  text:
                      ', a recovery code is on its way. It expires in $_codeLifetimeMinutes minutes.',
                ),
              ],
            ),
          )
        else
          Text(
            'Paste the recovery code from your email. It expires in $_codeLifetimeMinutes minutes.',
            style: lead,
          ),
        const SizedBox(height: 16),
        V3Field(
          key: const ValueKey('recovery-code'),
          label: 'Recovery code',
          controller: _code,
          placeholder: 'Paste the code from your email',
          keyboardType: TextInputType.visiblePassword,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          // The token is a secret: never autocorrected or offered back.
          autocorrect: false,
          enableSuggestions: false,
          error: _codeError,
          enabled: !_busy,
          onChanged: (_) => _edited(),
        ),
        const SizedBox(height: 12),
        V3Field(
          key: const ValueKey('recovery-password'),
          label: 'New password',
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          error: _passwordError,
          enabled: !_busy,
          onChanged: (_) => _edited(),
        ),
        const SizedBox(height: 12),
        V3Field(
          key: const ValueKey('recovery-confirmation'),
          label: 'Confirm new password',
          controller: _confirmation,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          error: _confirmError,
          enabled: !_busy,
          onChanged: (_) => _edited(),
          onSubmitted: (_) => _confirmReset(),
        ),
        const SizedBox(height: 18),
        V3Button(
          full: true,
          loading: _busy,
          disabled: confirmWait > 0,
          onPressed: _confirmReset,
          child: Text(
            confirmWait > 0
                ? 'Try again in ${_waitLabel(confirmWait)}'
                : 'Update password',
          ),
        ),
        const SizedBox(height: 6),
        if (requested)
          V3Button(
            kind: V3ButtonKind.ghost,
            size: V3Size.md,
            full: true,
            disabled: _busy || resendWait > 0,
            onPressed: () => _requestCode(resend: true),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Resend code'),
                // While the cooldown runs, how long is left.
                if (resendWait > 0) ...[
                  const SizedBox(width: 8),
                  Text(_waitLabel(resendWait), style: AppTypography.tnum),
                ],
              ],
            ),
          )
        else
          // Entered by hand there is no address to resend to.
          V3Button(
            kind: V3ButtonKind.ghost,
            size: V3Size.md,
            full: true,
            disabled: _busy,
            onPressed: _requestNewCode,
            child: const Text('Request a new code'),
          ),
      ],
    );
  }

  Widget _buildDoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Center(
          child: V3Pop(
            duration: const Duration(milliseconds: 600),
            child: const SizedBox.square(
              dimension: 72,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.sageSoft,
                    ),
                    child: SizedBox.expand(),
                  ),
                  V3Icon(
                    V3Icons.check,
                    size: 32,
                    strokeWidth: 2.6,
                    color: AppColors.sage2,
                  ),
                  Positioned.fill(
                    child: V3Burst(color: AppColors.sage, radius: 46),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 20),
          child: Text(
            'Sign in with your new password.',
            textAlign: TextAlign.center,
            style: AppTypography.sans(15).copyWith(color: AppColors.ink2),
          ),
        ),
        V3Button(
          full: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}

enum _ResetField { code, password, confirmation }

class _ResetProblem {
  const _ResetProblem(this.field, this.message);

  final _ResetField field;
  final String message;
}

/// `CodeBoxes` from `v3/onboard.jsx`: [length] (six) digit boxes over one
/// hidden numeric input. Only digits are accepted, the box after the last
/// digit is outlined in ink with a blinking caret, and each new digit pops in.
/// Tapping anywhere focuses the input.
///
/// The live recovery sheet does not use it: the server's recovery code is a
/// 43-character token that is pasted, not typed. It is here for the design's
/// numeric-code flow should the server issue short codes.
class CodeBoxes extends StatefulWidget {
  const CodeBoxes({
    super.key,
    required this.value,
    required this.onChanged,
    this.length = 6,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final int length;

  @override
  State<CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<CodeBoxes> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(CodeBoxes oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A parent-driven change (a cleared code after a resend) reaches the input.
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus,
      child: Stack(
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < widget.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _box(i, value)),
                ],
              ],
            ),
          ),
          // `position: absolute; inset: 0; opacity: 0`.
          Positioned.fill(
            child: Semantics(
              label: 'Recovery code',
              textField: true,
              child: Opacity(
                opacity: 0,
                alwaysIncludeSemantics: true,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  showCursor: false,
                  enableInteractiveSelection: false,
                  decoration: const InputDecoration.collapsed(hintText: null),
                  onChanged: widget.onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(int i, String value) {
    final active = i == value.length;
    final digit = i < value.length ? value[i] : null;
    return AnimatedContainer(
      key: ValueKey('code-box-$i'),
      duration: MotionConfig.enabled(context)
          ? const Duration(milliseconds: 200)
          : Duration.zero,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? AppColors.ink : AppColors.hair,
          width: 1.5,
        ),
      ),
      child: digit != null
          ? V3Pop(
              key: ValueKey('$digit$i'),
              duration: const Duration(milliseconds: 300),
              child: Text(
                digit,
                style: AppTypography.sans(
                  22,
                  FontWeight.w600,
                ).copyWith(color: AppColors.ink),
              ),
            )
          : active
          ? const _Caret()
          : null,
    );
  }
}

/// `caret 1s steps(1) infinite`: a 2 × 22 ink bar, on for the first half of
/// every second. With reduced motion it stays on.
class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionConfig.enabled(context)) {
      if (!_blink.isAnimating) _blink.repeat();
    } else {
      _blink.stop();
      _blink.value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, child) =>
          Opacity(opacity: _blink.value < 0.5 ? 1 : 0, child: child),
      child: const SizedBox(
        width: 2,
        height: 22,
        child: ColoredBox(color: AppColors.ink),
      ),
    );
  }
}
