import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/cmpys_text_field.dart';
import '../../auth/controllers/session_controller.dart';
import '../controllers/intake_controller.dart';
import '../models/intake_models.dart';

/// Intake wizard screen for collecting user information.
///
/// Shows one question at a time with progress indicator.
/// Supports various question types: text, multiline, single_choice, multi_choice, scale.
class IntakeWizardScreen extends ConsumerStatefulWidget {
  const IntakeWizardScreen({
    super.key,
    this.sessionId,
    this.questions,
    this.idolId,
    this.targetAge,
  });

  /// Existing session ID to resume.
  final String? sessionId;

  /// Pre-loaded questions (skips API call if provided with sessionId).
  final List<IntakeQuestion>? questions;

  /// Idol ID for new intake.
  final String? idolId;

  /// Target age for new intake.
  final int? targetAge;

  @override
  ConsumerState<IntakeWizardScreen> createState() => _IntakeWizardScreenState();
}

class _IntakeWizardScreenState extends ConsumerState<IntakeWizardScreen> {
  final _textController = TextEditingController();
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    // Schedule initialization after build to avoid modifying provider during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeIntake();
    });
  }

  void _initializeIntake() {
    if (!mounted) return;
    
    final controller = ref.read(intakeControllerProvider.notifier);

    if (widget.sessionId != null && widget.questions != null) {
      // Use provided data
      controller.initWithQuestions(
        sessionId: widget.sessionId!,
        questions: widget.questions!,
      );
    } else if (widget.sessionId != null) {
      // Load existing session
      controller.loadSession(widget.sessionId!);
    } else {
      // Start new intake
      controller.startIntake(
        idolId: widget.idolId,
        targetAge: widget.targetAge,
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(intakeControllerProvider);

    // Listen for state changes
    ref.listen<IntakeState>(intakeControllerProvider, (prev, next) {
      if (next is IntakeReady && prev is IntakeReady) {
        // Sync page controller with state
        if (next.currentIndex != prev.currentIndex) {
          _pageController.animateToPage(
            next.currentIndex,
            duration: AppDurations.normal,
            curve: Curves.easeInOut,
          );
          // Update text controller for text questions
          _updateTextController(next);
        }
      } else if (next is IntakeReady && prev is! IntakeReady) {
        // Initial load - update text controller
        _updateTextController(next);
      } else if (next is IntakeCompleted) {
        // Schedule navigation after current build to avoid provider modification during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Complete onboarding
          ref.read(sessionControllerProvider.notifier).completeOnboarding();
          // Navigate to plan generation screen
          context.goToGeneratingPlan(next.jobId);
        });
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: switch (state) {
          IntakeInitial() || IntakeLoading() => const _LoadingView(),
          IntakeError(message: final msg) => _ErrorView(
              message: msg,
              onRetry: _initializeIntake,
            ),
          IntakeReady() => _WizardView(
              state: state,
              textController: _textController,
              pageController: _pageController,
              onBack: _handleBack,
              onNext: _handleNext,
              onSkip: _handleSkip,
              onFinish: _handleFinish,
              onAnswerChanged: _handleAnswerChanged,
            ),
          IntakeCompleted() => const _LoadingView(), // Transitioning
        },
      ),
    );
  }

  void _updateTextController(IntakeReady state) {
    final question = state.currentQuestion;
    if (question.type == 'text' || question.type == 'multiline') {
      final answer = state.answers[question.id];
      _textController.text = answer?.toString() ?? '';
    }
  }

  void _handleBack() {
    final state = ref.read(intakeControllerProvider);
    if (state is IntakeReady && state.isFirstQuestion) {
      context.pop();
      return;
    }
    ref.read(intakeControllerProvider.notifier).goBack();
  }

  Future<void> _handleNext() async {
    await ref.read(intakeControllerProvider.notifier).submitAndNext();
  }

  Future<void> _handleSkip() async {
    await ref.read(intakeControllerProvider.notifier).skipQuestion();
  }

  Future<void> _handleFinish() async {
    await ref.read(intakeControllerProvider.notifier).finishIntake();
  }

  void _handleAnswerChanged(dynamic value) {
    ref.read(intakeControllerProvider.notifier).setAnswer(value);
  }
}

/// Loading view.
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.accent),
          const SizedBox(height: AppSpacing.s16),
          Text(
            'Loading questions...',
            style: AppTypography.body,
          ),
        ],
      ),
    );
  }
}

/// Error view.
class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              AppAssets.iconAlertCircle,
              width: 48,
              height: 48,
              colorFilter: const ColorFilter.mode(
                AppColors.error,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              'Something went wrong',
              style: AppTypography.h3,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              message,
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s24),
            CmpysButton(
              label: 'Try Again',
              onPressed: onRetry,
              isExpanded: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// Main wizard view.
class _WizardView extends StatelessWidget {
  const _WizardView({
    required this.state,
    required this.textController,
    required this.pageController,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
    required this.onFinish,
    required this.onAnswerChanged,
  });

  final IntakeReady state;
  final TextEditingController textController;
  final PageController pageController;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onFinish;
  final ValueChanged<dynamic> onAnswerChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with back button and progress
        _WizardHeader(
          currentIndex: state.currentIndex,
          totalQuestions: state.questions.length,
          progress: state.progress,
          onBack: onBack,
        ),

        // Error banner
        if (state.error != null)
          _ErrorBanner(message: state.error!),

        // Question pages
        Expanded(
          child: PageView.builder(
            controller: pageController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.questions.length,
            itemBuilder: (context, index) {
              final question = state.questions[index];
              final answer = state.answers[question.id];

              return _QuestionPage(
                question: question,
                answer: answer,
                textController: index == state.currentIndex ? textController : null,
                onAnswerChanged: onAnswerChanged,
              );
            },
          ),
        ),

        // Bottom actions
        _WizardActions(
          isLastQuestion: state.isLastQuestion,
          isRequired: state.currentQuestion.isRequired,
          isSubmitting: state.isSubmitting,
          hasAnswer: state.answers[state.currentQuestion.id] != null &&
              state.answers[state.currentQuestion.id] != '' &&
              (state.answers[state.currentQuestion.id] is! List ||
                  (state.answers[state.currentQuestion.id] as List).isNotEmpty),
          onNext: onNext,
          onSkip: onSkip,
          onFinish: onFinish,
        ),
      ],
    );
  }
}

/// Header with progress indicator.
class _WizardHeader extends StatelessWidget {
  const _WizardHeader({
    required this.currentIndex,
    required this.totalQuestions,
    required this.progress,
    required this.onBack,
  });

  final int currentIndex;
  final int totalQuestions;
  final double progress;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s8,
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
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
              const Spacer(),
              Text(
                '${currentIndex + 1} of $totalQuestions',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.s16),
            ],
          ),
        ),

        // Progress bar
        Padding(
          padding: AppSpacing.ph24,
          child: ClipRRect(
            borderRadius: AppRadii.brFull,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.surface2,
              color: AppColors.accent,
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
      ],
    );
  }
}

/// Error banner.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s24,
        vertical: AppSpacing.s12,
      ),
      color: AppColors.error.withValues(alpha: 0.1),
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
              message,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single question page.
class _QuestionPage extends StatelessWidget {
  const _QuestionPage({
    required this.question,
    required this.answer,
    this.textController,
    required this.onAnswerChanged,
  });

  final IntakeQuestion question;
  final dynamic answer;
  final TextEditingController? textController;
  final ValueChanged<dynamic> onAnswerChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: AppSpacing.screenH,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.s16),

          // Category badge
          if (question.category != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s12,
                vertical: AppSpacing.s6,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentMuted,
                borderRadius: AppRadii.brFull,
              ),
              child: Text(
                question.category!.toUpperCase(),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 1,
                ),
              ),
            ),

          const SizedBox(height: AppSpacing.s16),

          // Question title
          Text(
            question.title,
            style: AppTypography.h2,
          ),

          const SizedBox(height: AppSpacing.s8),

          // Question prompt
          Text(
            question.prompt,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),

          // Required indicator
          if (question.isRequired) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              '* Required',
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.s32),

          // Answer input based on type
          _buildAnswerInput(),
        ],
      ),
    );
  }

  Widget _buildAnswerInput() {
    switch (question.type.toLowerCase()) {
      case 'text':
        return _TextInput(
          controller: textController,
          placeholder: question.placeholder,
          validation: question.validation,
          onChanged: onAnswerChanged,
        );

      case 'multiline':
        return _MultilineInput(
          controller: textController,
          placeholder: question.placeholder,
          validation: question.validation,
          onChanged: onAnswerChanged,
        );

      case 'single_choice':
      case 'select':
        return _SingleChoiceInput(
          options: question.options,
          selectedValue: answer?.toString(),
          onChanged: onAnswerChanged,
        );

      case 'multi_choice':
      case 'multiselect':
        return _MultiChoiceInput(
          options: question.options,
          selectedValues: answer is List
              ? (answer as List).map((e) => e.toString()).toList()
              : <String>[],
          onChanged: onAnswerChanged,
        );

      case 'scale':
        return _ScaleInput(
          min: question.validation?.min ?? 1,
          max: question.validation?.max ?? 5,
          currentValue: answer is num ? answer.toInt() : null,
          onChanged: onAnswerChanged,
        );

      case 'number':
        return _NumberInput(
          controller: textController,
          placeholder: question.placeholder,
          validation: question.validation,
          onChanged: onAnswerChanged,
        );

      case 'boolean':
        return _BooleanInput(
          currentValue: answer is bool ? answer : null,
          onChanged: onAnswerChanged,
        );

      case 'date':
        return _DateInput(
          currentValue: answer?.toString(),
          onChanged: onAnswerChanged,
        );

      default:
        return _TextInput(
          controller: textController,
          placeholder: question.placeholder,
          validation: question.validation,
          onChanged: onAnswerChanged,
        );
    }
  }
}

/// Text input.
class _TextInput extends StatelessWidget {
  const _TextInput({
    this.controller,
    this.placeholder,
    this.validation,
    required this.onChanged,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final IntakeValidation? validation;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    return CmpysTextField(
      controller: controller,
      hint: placeholder ?? 'Enter your answer',
      maxLength: validation?.maxLength,
      onChanged: onChanged,
      textInputAction: TextInputAction.done,
    );
  }
}

/// Multiline text input.
class _MultilineInput extends StatelessWidget {
  const _MultilineInput({
    this.controller,
    this.placeholder,
    this.validation,
    required this.onChanged,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final IntakeValidation? validation;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    return CmpysTextArea(
      controller: controller,
      hint: placeholder ?? 'Enter your answer',
      maxLength: validation?.maxLength,
      minLines: 4,
      maxLines: 8,
      onChanged: onChanged,
    );
  }
}

/// Number input.
class _NumberInput extends StatelessWidget {
  const _NumberInput({
    this.controller,
    this.placeholder,
    this.validation,
    required this.onChanged,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final IntakeValidation? validation;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    return CmpysTextField(
      controller: controller,
      hint: placeholder ?? 'Enter a number',
      keyboardType: TextInputType.number,
      onChanged: (value) {
        final parsed = int.tryParse(value);
        onChanged(parsed ?? value);
      },
      textInputAction: TextInputAction.done,
    );
  }
}

/// Single choice (radio) input.
class _SingleChoiceInput extends StatelessWidget {
  const _SingleChoiceInput({
    required this.options,
    this.selectedValue,
    required this.onChanged,
  });

  final List<IntakeOption> options;
  final String? selectedValue;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: options.map((option) {
        final isSelected = selectedValue == option.value;

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s12),
          child: _OptionTile(
            label: option.label,
            description: option.description,
            isSelected: isSelected,
            onTap: () => onChanged(option.value),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.border,
                  width: 2,
                ),
                color: isSelected ? AppColors.accent : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: AppColors.textPrimary,
                    )
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Multi choice (checkbox) input.
class _MultiChoiceInput extends StatelessWidget {
  const _MultiChoiceInput({
    required this.options,
    required this.selectedValues,
    required this.onChanged,
  });

  final List<IntakeOption> options;
  final List<String> selectedValues;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: options.map((option) {
        final isSelected = selectedValues.contains(option.value);

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s12),
          child: _OptionTile(
            label: option.label,
            description: option.description,
            isSelected: isSelected,
            onTap: () {
              final newValues = List<String>.from(selectedValues);
              if (isSelected) {
                newValues.remove(option.value);
              } else {
                newValues.add(option.value);
              }
              onChanged(newValues);
            },
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: AppRadii.br8,
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.border,
                  width: 2,
                ),
                color: isSelected ? AppColors.accent : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: AppColors.textPrimary,
                    )
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Option tile for choice inputs.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    this.description,
    required this.isSelected,
    required this.onTap,
    required this.trailing,
  });

  final String label;
  final String? description;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.accentMuted : AppColors.surface,
      borderRadius: AppRadii.br16,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.br16,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s16),
          decoration: BoxDecoration(
            borderRadius: AppRadii.br16,
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.bodyMedium.copyWith(
                        color: isSelected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        description!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Scale (slider) input.
class _ScaleInput extends StatelessWidget {
  const _ScaleInput({
    required this.min,
    required this.max,
    this.currentValue,
    required this.onChanged,
  });

  final int min;
  final int max;
  final int? currentValue;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = currentValue ?? min;

    return Column(
      children: [
        // Scale value display
        Container(
          padding: const EdgeInsets.all(AppSpacing.s24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.br20,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Text(
                value.toString(),
                style: AppTypography.h1.copyWith(
                  color: AppColors.accent,
                  fontSize: 48,
                ),
              ),
              const SizedBox(height: AppSpacing.s16),

              // Slider
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AppColors.accent,
                  inactiveTrackColor: AppColors.surface2,
                  thumbColor: AppColors.accent,
                  overlayColor: AppColors.accentMuted,
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                ),
                child: Slider(
                  value: value.toDouble(),
                  min: min.toDouble(),
                  max: max.toDouble(),
                  divisions: max - min,
                  onChanged: (v) => onChanged(v.round()),
                ),
              ),

              // Labels
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    min.toString(),
                    style: AppTypography.caption,
                  ),
                  Text(
                    max.toString(),
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.s16),

        // Quick select buttons
        Row(
          children: List.generate(max - min + 1, (index) {
            final buttonValue = min + index;
            final isSelected = buttonValue == value;

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index < max - min ? AppSpacing.s8 : 0,
                ),
                child: Material(
                  color: isSelected ? AppColors.accent : AppColors.surface,
                  borderRadius: AppRadii.br12,
                  child: InkWell(
                    onTap: () => onChanged(buttonValue),
                    borderRadius: AppRadii.br12,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.br12,
                        border: Border.all(
                          color: isSelected ? AppColors.accent : AppColors.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          buttonValue.toString(),
                          style: AppTypography.buttonSmall.copyWith(
                            color: isSelected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Boolean (yes/no) input.
class _BooleanInput extends StatelessWidget {
  const _BooleanInput({
    this.currentValue,
    required this.onChanged,
  });

  final bool? currentValue;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _OptionTile(
            label: 'Yes',
            isSelected: currentValue == true,
            onTap: () => onChanged(true),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: currentValue == true ? AppColors.accent : AppColors.border,
                  width: 2,
                ),
                color: currentValue == true ? AppColors.accent : Colors.transparent,
              ),
              child: currentValue == true
                  ? const Icon(Icons.check, size: 16, color: AppColors.textPrimary)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: _OptionTile(
            label: 'No',
            isSelected: currentValue == false,
            onTap: () => onChanged(false),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: currentValue == false ? AppColors.accent : AppColors.border,
                  width: 2,
                ),
                color: currentValue == false ? AppColors.accent : Colors.transparent,
              ),
              child: currentValue == false
                  ? const Icon(Icons.check, size: 16, color: AppColors.textPrimary)
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// Date input.
class _DateInput extends StatelessWidget {
  const _DateInput({
    this.currentValue,
    required this.onChanged,
  });

  final String? currentValue;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    DateTime? selectedDate;
    if (currentValue != null) {
      selectedDate = DateTime.tryParse(currentValue!);
    }

    return Material(
      color: AppColors.surface,
      borderRadius: AppRadii.br16,
      child: InkWell(
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: selectedDate ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime.now(),
            builder: (context, child) {
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppColors.accent,
                    onPrimary: AppColors.textPrimary,
                    surface: AppColors.surface,
                    onSurface: AppColors.textPrimary,
                  ),
                ),
                child: child!,
              );
            },
          );
          if (date != null) {
            onChanged(date.toIso8601String().split('T').first);
          }
        },
        borderRadius: AppRadii.br16,
        child: Container(
          height: 56,
          padding: AppSpacing.ph16,
          decoration: BoxDecoration(
            borderRadius: AppRadii.br16,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                AppAssets.iconCalendar,
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  AppColors.textSecondary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  selectedDate != null
                      ? _formatDate(selectedDate)
                      : 'Select a date',
                  style: AppTypography.body.copyWith(
                    color: selectedDate != null
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                  ),
                ),
              ),
              SvgPicture.asset(
                AppAssets.iconChevronRight,
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  AppColors.textTertiary,
                  BlendMode.srcIn,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// Bottom action buttons.
class _WizardActions extends StatelessWidget {
  const _WizardActions({
    required this.isLastQuestion,
    required this.isRequired,
    required this.isSubmitting,
    required this.hasAnswer,
    required this.onNext,
    required this.onSkip,
    required this.onFinish,
  });

  final bool isLastQuestion;
  final bool isRequired;
  final bool isSubmitting;
  final bool hasAnswer;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s24),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(
          top: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main action button
            CmpysButton(
              label: isLastQuestion ? 'Submit & Generate Plan' : 'Continue',
              onPressed: isSubmitting
                  ? null
                  : (isLastQuestion ? onFinish : onNext),
              isLoading: isSubmitting,
              icon: isLastQuestion ? AppAssets.iconSparkles : null,
              iconRight: isLastQuestion ? null : AppAssets.iconArrowRight,
            ),

            // Skip button (for optional questions)
            if (!isRequired && !isLastQuestion) ...[
              const SizedBox(height: AppSpacing.s12),
              TextButton(
                onPressed: isSubmitting ? null : onSkip,
                child: Text(
                  'Skip this question',
                  style: AppTypography.buttonSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
