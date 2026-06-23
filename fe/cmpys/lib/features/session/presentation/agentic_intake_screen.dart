import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../controllers/session_controller.dart';

abstract final class _SessionPalette {
  static const canvas = AppColors.bg;
  static const paper = Color(0xFFFFFFFF);
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
  static const mint = AppColors.mint;
  static const coral = AppColors.brandAccent;
  static const coralDark = AppColors.brandAccentDark;
}

/// Screen for Phase 1: Collect age, financial status, and interests.
///
/// On submit, creates a session and navigates to idol selection.
class AgenticIntakeScreen extends ConsumerStatefulWidget {
  const AgenticIntakeScreen({super.key});

  @override
  ConsumerState<AgenticIntakeScreen> createState() =>
      _AgenticIntakeScreenState();
}

class _AgenticIntakeScreenState extends ConsumerState<AgenticIntakeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ageController = TextEditingController();
  final _financialController = TextEditingController();
  final List<String> _selectedInterests = [];

  static const _availableInterests = [
    'Technology',
    'Business',
    'Science',
    'Arts',
    'Finance',
    'Leadership',
    'Sports',
    'Writing',
    'Engineering',
    'Medicine',
    'Military',
    'Philanthropy',
    'Entertainment',
    'Investing',
    'Entrepreneurship',
  ];

  @override
  void dispose() {
    _ageController.dispose();
    _financialController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedInterests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one interest')),
      );
      return;
    }

    await ref
        .read(sessionControllerProvider.notifier)
        .createSession(
          age: int.parse(_ageController.text),
          financialStatus: _financialController.text,
          interests: _selectedInterests,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionControllerProvider, (prev, next) {
      if (next is SessionActive && next.session.phase.name == 'idolSelection') {
        context.go('/agentic/idol-pick', extra: next.session.id);
      }
      if (next is SessionError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.message)));
      }
    });

    final state = ref.watch(sessionControllerProvider);
    final isLoading = state is SessionLoading;

    return Scaffold(
      backgroundColor: _SessionPalette.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _SessionPalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _SessionPalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.5, 1],
          ),
        ),
        child: Form(
          key: _formKey,
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                const _AgenticHeader(),
                const SizedBox(height: 20),
                _PaperField(
                  controller: _ageController,
                  label: 'Your age',
                  hint: '24',
                  icon: Icons.cake_outlined,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final age = int.tryParse(v);
                    if (age == null || age < 1 || age > 150) {
                      return 'Enter a valid age';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _PaperField(
                  controller: _financialController,
                  label: 'Current life context',
                  hint: 'Student, early founder, career switcher...',
                  icon: Icons.account_balance_wallet_outlined,
                  minLines: 2,
                  maxLines: 3,
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                const _TrustNotice(
                  text:
                      'Used only to calibrate mentor suggestions, the diagnostic interview, and your first 12-week path. Avoid passwords, account numbers, or private documents.',
                ),
                const SizedBox(height: 22),
                _SectionLabel(
                  title: 'Interests',
                  subtitle: '${_selectedInterests.length} selected',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: _availableInterests.map((interest) {
                    final selected = _selectedInterests.contains(interest);
                    return FilterChip(
                      label: Text(interest),
                      selected: selected,
                      backgroundColor: _SessionPalette.paper,
                      selectedColor: _SessionPalette.mint,
                      checkmarkColor: _SessionPalette.ink,
                      side: BorderSide(
                        color: selected
                            ? _SessionPalette.ink.withValues(alpha: 0.18)
                            : _SessionPalette.line,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      labelStyle: AppTypography.captionMedium.copyWith(
                        color: _SessionPalette.ink,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      onSelected: (value) {
                        setState(() {
                          if (value) {
                            _selectedInterests.add(interest);
                          } else {
                            _selectedInterests.remove(interest);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _SessionPalette.ink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: isLoading ? null : _onSubmit,
                    icon: isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      isLoading ? 'Finding mentors' : 'Find my mentor',
                      style: AppTypography.button.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgenticHeader extends StatelessWidget {
  const _AgenticHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _SessionPalette.paper.withValues(alpha: 0.88),
        borderRadius: AppRadii.br20,
        border: Border.all(color: _SessionPalette.line),
        boxShadow: [
          BoxShadow(
            color: _SessionPalette.ink.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _SessionPalette.mint,
                  borderRadius: AppRadii.br12,
                ),
                child: const Icon(
                  Icons.route_outlined,
                  color: _SessionPalette.ink,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'CMPYS mirror setup',
                style: AppTypography.captionUpper.copyWith(
                  color: _SessionPalette.coralDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Start with the context your mentor should understand.',
            style: AppTypography.h1.copyWith(
              color: _SessionPalette.ink,
              fontSize: 30,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'These answers shape mentor suggestions, the diagnostic interview, and the first weekly path.',
            style: AppTypography.body.copyWith(color: _SessionPalette.muted),
          ),
          const SizedBox(height: 12),
          const _TrustNotice(
            text:
                'CMPYS simulates mentors from public information. Historical claims should be treated as AI-assisted guidance, not biography or financial advice.',
          ),
        ],
      ),
    );
  }
}

class _TrustNotice extends StatelessWidget {
  const _TrustNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _SessionPalette.paper.withValues(alpha: 0.72),
        borderRadius: AppRadii.br12,
        border: Border.all(color: _SessionPalette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            size: 18,
            color: _SessionPalette.coralDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                color: _SessionPalette.muted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: AppTypography.h4.copyWith(color: _SessionPalette.ink),
        ),
        const Spacer(),
        Text(
          subtitle,
          style: AppTypography.captionMedium.copyWith(
            color: _SessionPalette.muted,
          ),
        ),
      ],
    );
  }
}

class _PaperField extends StatelessWidget {
  const _PaperField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.minLines = 1,
    this.maxLines = 1,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _SessionPalette.paper,
        borderRadius: AppRadii.br16,
        border: Border.all(color: _SessionPalette.line),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        style: AppTypography.bodyMedium.copyWith(color: _SessionPalette.ink),
        cursorColor: _SessionPalette.coral,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: _SessionPalette.coralDark),
          labelStyle: AppTypography.caption.copyWith(
            color: _SessionPalette.muted,
          ),
          hintStyle: AppTypography.body.copyWith(color: _SessionPalette.muted),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
        ),
        validator: validator,
      ),
    );
  }
}
