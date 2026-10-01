import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';

/// Email recovery is not connected yet, so this screen must never claim
/// to have sent a password reset message.
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('Account access')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.key_outlined, size: 40, color: AppColors.green2),
              const SizedBox(height: 24),
              Text('Forgot your password?', style: AppTypography.h1),
              const SizedBox(height: 12),
              Text(
                'Password reset by email is not available yet.',
                style: AppTypography.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Check your password manager for a saved CMPYS password, then try signing in again.',
                style: AppTypography.bodyDim,
              ),
              const SizedBox(height: 32),
              CmpysButton(
                full: true,
                onTap: () => Navigator.of(context).maybePop(),
                child: const Text('Back to sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
