import 'package:flutter/material.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/cmpys_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  String? _errorText;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _RecoveryGridPainter()),
            ),
            SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.vertical -
                      44,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _BackButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const Spacer(),
                        Text(
                          'PROTOCOL_RECOVERY',
                          style: AppTypography.monoLabel.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s48),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadii.br20,
                        border: Border.all(color: AppColors.borderLight),
                        boxShadow: AppShadows.sm,
                      ),
                      child: const Icon(
                        Icons.key_outlined,
                        color: AppColors.accent,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s24),
                    Text(
                      _sent ? 'Check your inbox' : 'Recover access',
                      style: AppTypography.h1.copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    Text(
                      _sent
                          ? 'If this email exists, a recovery link will arrive shortly. Keep this screen open if you want to retry with another address.'
                          : 'Enter the email associated with your account to receive a recovery link.',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s40),
                    CmpysTextField(
                      controller: _emailController,
                      label: 'REGISTERED EMAIL',
                      hint: 'name@domain.com',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      prefixIcon: AppAssets.iconMessageCircle,
                      errorText: _errorText,
                      onChanged: (_) {
                        if (_errorText != null || _sent) {
                          setState(() {
                            _errorText = null;
                            _sent = false;
                          });
                        }
                      },
                      onSubmitted: (_) => _sendRecovery(),
                    ),
                    const SizedBox(height: AppSpacing.s20),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.s16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadii.br16,
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(
                              color: _sent ? AppColors.mint : AppColors.peach,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (_sent ? AppColors.mint : AppColors.peach)
                                          .withValues(alpha: 0.4),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s12),
                          Expanded(
                            child: Text(
                              _sent
                                  ? 'Recovery protocol queued for this account.'
                                  : 'Verification is required before password reset is initialized.',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s48),
                    CmpysButton(
                      label: _sent ? 'Send Again' : 'Send Recovery Link',
                      iconRight: AppAssets.iconArrowRight,
                      onPressed: _sendRecovery,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    CmpysButton(
                      label: 'Retry System Auth',
                      variant: CmpysButtonVariant.ghost,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendRecovery() {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorText = 'Enter your account email');
      return;
    }
    if (!RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      setState(() => _errorText = 'Enter a valid email address');
      return;
    }
    setState(() {
      _errorText = null;
      _sent = true;
    });
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadii.br16,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadii.br16,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: AppRadii.br16,
            border: Border.all(color: AppColors.borderLight),
          ),
          child: const Icon(
            Icons.arrow_back,
            color: AppColors.textPrimary,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _RecoveryGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.mint.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 22) {
      canvas.drawLine(
        Offset(x, size.height * 0.42),
        Offset(x, size.height),
        paint,
      );
    }
    for (double y = size.height * 0.42; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
