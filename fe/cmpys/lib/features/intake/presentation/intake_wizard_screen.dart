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

abstract final class _IntakePalette {
  static const canvas = AppColors.bg;
  static const paper = Color(0xFFFFFFFF);
  static const paperWarm = AppColors.surfaceHighlight;
  static const ink = AppColors.textPrimary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;
  static const coral = AppColors.brandAccent;
  static const coralDark = AppColors.brandAccentDark;
  static const error = Color(0xFFC64036);
}

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
    this.mentorName,
  });

  /// Existing session ID to resume.
  final String? sessionId;

  /// Pre-loaded questions (skips API call if provided with sessionId).
  final List<IntakeQuestion>? questions;

  /// Idol ID for new intake.
  final String? idolId;

  /// Target age for new intake.
  final int? targetAge;

  /// Display name for the mentor-style conversation.
  final String? mentorName;

  @override
  ConsumerState<IntakeWizardScreen> createState() => _IntakeWizardScreenState();
}

class _IntakeWizardScreenState extends ConsumerState<IntakeWizardScreen> {
  final _textController = TextEditingController();
  final _chatScrollController = ScrollController();

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
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(intakeControllerProvider);

    // Listen for state changes
    ref.listen<IntakeState>(intakeControllerProvider, (prev, next) {
      if (next is IntakeReady && prev is IntakeReady) {
        if (next.currentIndex != prev.currentIndex) {
          _updateTextController(next);
          _scrollConversationToBottom();
        }
      } else if (next is IntakeReady && prev is! IntakeReady) {
        _updateTextController(next);
        _scrollConversationToBottom();
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
      backgroundColor: _IntakePalette.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _IntakePalette.canvas,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.surfaceHighlight,
              _IntakePalette.canvas,
              AppColors.bg,
            ],
            stops: [0, 0.48, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: switch (state) {
            IntakeInitial() || IntakeLoading() => const _LoadingView(),
            IntakeError(message: final msg) => _ErrorView(
              message: msg,
              onRetry: _initializeIntake,
            ),
            IntakeReady() => _WizardView(
              state: state,
              textController: _textController,
              scrollController: _chatScrollController,
              mentorName: widget.mentorName,
              onBack: _handleBack,
              onNext: _handleNext,
              onSkip: _handleSkip,
              onFinish: _handleFinish,
              onAnswerChanged: _handleAnswerChanged,
            ),
            IntakeCompleted() => const _LoadingView(), // Transitioning
          },
        ),
      ),
    );
  }

  void _updateTextController(IntakeReady state) {
    final question = state.currentQuestion;
    final answer = state.answers[question.id];
    _textController.text = answer?.toString() ?? '';
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

  void _scrollConversationToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: AppDurations.normal,
        curve: Curves.easeOutCubic,
      );
    });
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
            style: AppTypography.body.copyWith(color: _IntakePalette.ink),
          ),
        ],
      ),
    );
  }
}

/// Error view.
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

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
              style: AppTypography.h3.copyWith(color: _IntakePalette.ink),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              message,
              style: AppTypography.body.copyWith(color: _IntakePalette.muted),
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
    required this.scrollController,
    this.mentorName,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
    required this.onFinish,
    required this.onAnswerChanged,
  });

  final IntakeReady state;
  final TextEditingController textController;
  final ScrollController scrollController;
  final String? mentorName;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onFinish;
  final ValueChanged<dynamic> onAnswerChanged;

  @override
  Widget build(BuildContext context) {
    final currentQuestion = state.currentQuestion;
    final currentAnswer = state.answers[currentQuestion.id];

    return Column(
      children: [
        _WizardHeader(
          currentIndex: state.currentIndex,
          totalQuestions: state.questions.length,
          progress: state.progress,
          onBack: onBack,
        ),

        // Error banner
        if (state.error != null) _ErrorBanner(message: state.error!),

        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              _MentorIntroBubble(mentorName: mentorName),
              for (var i = 0; i < state.currentIndex; i++) ...[
                _MentorQuestionBubble(
                  question: state.questions[i],
                  stepLabel: '${i + 1}/${state.questions.length}',
                  mentorName: mentorName,
                ),
                _UserAnswerBubble(
                  text: _formatAnswer(
                    state.questions[i],
                    state.answers[state.questions[i].id],
                  ),
                ),
              ],
              _MentorQuestionBubble(
                question: currentQuestion,
                stepLabel:
                    '${state.currentIndex + 1}/${state.questions.length}',
                mentorName: mentorName,
                isActive: true,
              ),
            ],
          ),
        ),

        _AnswerDock(
          question: currentQuestion,
          answer: currentAnswer,
          textController: textController,
          onAnswerChanged: onAnswerChanged,
          isLastQuestion: state.isLastQuestion,
          isRequired: currentQuestion.isRequired,
          isSubmitting: state.isSubmitting,
          hasAnswer: _hasAnswer(currentAnswer),
          onNext: onNext,
          onSkip: onSkip,
          onFinish: onFinish,
        ),
      ],
    );
  }
}

bool _hasAnswer(dynamic answer) {
  return answer != null &&
      answer != '' &&
      (answer is! List || answer.isNotEmpty);
}

String _formatAnswer(IntakeQuestion question, dynamic answer) {
  if (!_hasAnswer(answer)) return 'Skipped';

  final type = question.type.toLowerCase();
  if (type == 'boolean') {
    return answer == true ? 'Yes' : 'No';
  }
  if (type == 'date') {
    final date = DateTime.tryParse(answer.toString());
    if (date != null) return _formatShortDate(date);
  }
  if (answer is List) {
    final labels = answer
        .map((value) => _optionLabel(question, value))
        .toList();
    return labels.join(', ');
  }
  return _optionLabel(question, answer);
}

String _optionLabel(IntakeQuestion question, dynamic value) {
  final raw = value.toString();
  for (final option in question.options) {
    if (option.value == raw) return option.label;
  }
  return raw;
}

String _formatShortDate(DateTime date) {
  final months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
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
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s10,
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
                    _IntakePalette.ink,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _IntakePalette.paper.withValues(alpha: 0.86),
                  borderRadius: AppRadii.brFull,
                  border: Border.all(color: _IntakePalette.line),
                ),
                child: Text(
                  '${currentIndex + 1} / $totalQuestions',
                  style: AppTypography.captionMedium.copyWith(
                    color: _IntakePalette.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: AppRadii.brFull,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: _IntakePalette.line,
              color: _IntakePalette.coral,
              minHeight: 4,
            ),
          ),
        ),
      ],
    );
  }
}

class _MentorIntroBubble extends StatelessWidget {
  const _MentorIntroBubble({this.mentorName});

  final String? mentorName;

  @override
  Widget build(BuildContext context) {
    return _MentorBubbleShell(
      mentorName: mentorName,
      child: Text(
        'I will ask a few focused questions, then turn your answers into a practical path.',
      ),
    );
  }
}

class _MentorQuestionBubble extends StatelessWidget {
  const _MentorQuestionBubble({
    required this.question,
    required this.stepLabel,
    this.mentorName,
    this.isActive = false,
  });

  final IntakeQuestion question;
  final String stepLabel;
  final String? mentorName;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return _MentorBubbleShell(
      mentorName: mentorName,
      isActive: isActive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                stepLabel,
                style: AppTypography.captionUpper.copyWith(
                  color: _IntakePalette.coralDark,
                  fontSize: 10,
                  letterSpacing: 1.2,
                ),
              ),
              if (question.category != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    question.category!.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.captionUpper.copyWith(
                      color: _IntakePalette.muted,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            question.title,
            style: AppTypography.h4.copyWith(
              color: _IntakePalette.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            question.prompt,
            style: AppTypography.body.copyWith(
              color: _IntakePalette.ink,
              height: 1.55,
            ),
          ),
          if (question.isRequired) ...[
            const SizedBox(height: 10),
            Text(
              'Required',
              style: AppTypography.caption.copyWith(
                color: _IntakePalette.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MentorBubbleShell extends StatelessWidget {
  const _MentorBubbleShell({
    required this.child,
    this.mentorName,
    this.isActive = false,
  });

  final Widget child;
  final String? mentorName;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _IntakePalette.paper,
              border: Border.all(color: _IntakePalette.line),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: _IntakePalette.coral.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 17,
              color: _IntakePalette.coralDark,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isActive
                    ? _IntakePalette.paper
                    : _IntakePalette.paperWarm,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(22),
                  bottomLeft: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                ),
                border: Border.all(
                  color: isActive ? _IntakePalette.coral : _IntakePalette.line,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _IntakePalette.ink.withValues(
                      alpha: isActive ? 0.10 : 0.05,
                    ),
                    blurRadius: isActive ? 20 : 12,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: DefaultTextStyle(
                style: AppTypography.body.copyWith(
                  color: _IntakePalette.ink,
                  height: 1.45,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mentorName?.isNotEmpty == true
                          ? mentorName!
                          : 'Your mentor',
                      style: AppTypography.captionMedium.copyWith(
                        color: _IntakePalette.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserAnswerBubble extends StatelessWidget {
  const _UserAnswerBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.74,
        ),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _IntakePalette.ink,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(6),
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(22),
          ),
          boxShadow: [
            BoxShadow(
              color: _IntakePalette.ink.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          text,
          style: AppTypography.body.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
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
      color: _IntakePalette.error.withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: _IntakePalette.error,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                color: _IntakePalette.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Structured answer controls shown in the conversation dock.
class _AnswerInput extends StatelessWidget {
  const _AnswerInput({
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
    return _buildAnswerInput();
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
        // Fallback to text input if no options provided
        if (question.options.isEmpty) {
          return _TextInput(
            controller: textController,
            placeholder: question.placeholder,
            validation: question.validation,
            onChanged: onAnswerChanged,
          );
        }
        return _SingleChoiceInput(
          options: question.options,
          selectedValue: answer?.toString(),
          onChanged: onAnswerChanged,
        );

      case 'multi_choice':
      case 'multiselect':
        if (question.options.isEmpty) {
          return _TextInput(
            controller: textController,
            placeholder: question.placeholder,
            validation: question.validation,
            onChanged: onAnswerChanged,
          );
        }
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
        // If unknown type but has options, render as single choice
        if (question.options.isNotEmpty) {
          return _SingleChoiceInput(
            options: question.options,
            selectedValue: answer?.toString(),
            onChanged: onAnswerChanged,
          );
        }
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
                  color: isSelected
                      ? _IntakePalette.coral
                      : _IntakePalette.line,
                  width: 2,
                ),
                color: isSelected ? _IntakePalette.coral : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
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
                  color: isSelected
                      ? _IntakePalette.coral
                      : _IntakePalette.line,
                  width: 2,
                ),
                color: isSelected ? _IntakePalette.coral : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
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
      color: isSelected ? _IntakePalette.paperWarm : _IntakePalette.paper,
      borderRadius: AppRadii.br12,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.br12,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s16),
          decoration: BoxDecoration(
            borderRadius: AppRadii.br12,
            border: Border.all(
              color: isSelected ? _IntakePalette.coral : _IntakePalette.line,
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
                        color: _IntakePalette.ink,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        description!,
                        style: AppTypography.caption.copyWith(
                          color: _IntakePalette.muted,
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
            color: _IntakePalette.paper,
            borderRadius: AppRadii.br20,
            border: Border.all(color: _IntakePalette.line),
          ),
          child: Column(
            children: [
              Text(
                value.toString(),
                style: AppTypography.h1.copyWith(
                  color: _IntakePalette.coralDark,
                  fontSize: 48,
                ),
              ),
              const SizedBox(height: AppSpacing.s16),

              // Slider
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: _IntakePalette.coral,
                  inactiveTrackColor: _IntakePalette.line,
                  thumbColor: _IntakePalette.ink,
                  overlayColor: _IntakePalette.coral.withValues(alpha: 0.16),
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 12,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 24,
                  ),
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
                    style: AppTypography.caption.copyWith(
                      color: _IntakePalette.muted,
                    ),
                  ),
                  Text(
                    max.toString(),
                    style: AppTypography.caption.copyWith(
                      color: _IntakePalette.muted,
                    ),
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
                  color: isSelected ? _IntakePalette.ink : _IntakePalette.paper,
                  borderRadius: AppRadii.br12,
                  child: InkWell(
                    onTap: () => onChanged(buttonValue),
                    borderRadius: AppRadii.br12,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.br12,
                        border: Border.all(
                          color: isSelected
                              ? _IntakePalette.ink
                              : _IntakePalette.line,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          buttonValue.toString(),
                          style: AppTypography.buttonSmall.copyWith(
                            color: isSelected
                                ? Colors.white
                                : _IntakePalette.ink,
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
  const _BooleanInput({this.currentValue, required this.onChanged});

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
                  color: currentValue == true
                      ? _IntakePalette.coral
                      : _IntakePalette.line,
                  width: 2,
                ),
                color: currentValue == true
                    ? _IntakePalette.coral
                    : Colors.transparent,
              ),
              child: currentValue == true
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
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
                  color: currentValue == false
                      ? _IntakePalette.coral
                      : _IntakePalette.line,
                  width: 2,
                ),
                color: currentValue == false
                    ? _IntakePalette.coral
                    : Colors.transparent,
              ),
              child: currentValue == false
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
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
  const _DateInput({this.currentValue, required this.onChanged});

  final String? currentValue;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    DateTime? selectedDate;
    if (currentValue != null) {
      selectedDate = DateTime.tryParse(currentValue!);
    }

    return Material(
      color: _IntakePalette.paper,
      borderRadius: AppRadii.br12,
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
                    primary: _IntakePalette.coral,
                    onPrimary: Colors.white,
                    surface: _IntakePalette.paper,
                    onSurface: _IntakePalette.ink,
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
            borderRadius: AppRadii.br12,
            border: Border.all(color: _IntakePalette.line),
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                AppAssets.iconCalendar,
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  _IntakePalette.muted,
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
                        ? _IntakePalette.ink
                        : _IntakePalette.muted,
                  ),
                ),
              ),
              SvgPicture.asset(
                AppAssets.iconChevronRight,
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  _IntakePalette.muted,
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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// Bottom answer dock with structured controls and submit actions.
class _AnswerDock extends StatelessWidget {
  const _AnswerDock({
    required this.question,
    required this.answer,
    required this.textController,
    required this.onAnswerChanged,
    required this.isLastQuestion,
    required this.isRequired,
    required this.isSubmitting,
    required this.hasAnswer,
    required this.onNext,
    required this.onSkip,
    required this.onFinish,
  });

  final IntakeQuestion question;
  final dynamic answer;
  final TextEditingController textController;
  final ValueChanged<dynamic> onAnswerChanged;
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
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: _IntakePalette.paper.withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(color: _IntakePalette.line.withValues(alpha: 0.9)),
        ),
        boxShadow: [
          BoxShadow(
            color: _IntakePalette.ink.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.34,
              ),
              child: SingleChildScrollView(
                child: _AnswerInput(
                  question: question,
                  answer: answer,
                  textController: textController,
                  onAnswerChanged: onAnswerChanged,
                ),
              ),
            ),
            const SizedBox(height: 14),
            CmpysButton(
              label: isLastQuestion ? 'Generate My Path' : 'Send Answer',
              onPressed: isSubmitting
                  ? null
                  : (isRequired && !hasAnswer)
                  ? null
                  : (isLastQuestion ? onFinish : onNext),
              isLoading: isSubmitting,
              icon: isLastQuestion ? AppAssets.iconSparkles : null,
              iconRight: isLastQuestion ? null : AppAssets.iconArrowRight,
            ),
            if (!isRequired && !isLastQuestion) ...[
              const SizedBox(height: AppSpacing.s12),
              TextButton(
                onPressed: isSubmitting ? null : onSkip,
                child: Text(
                  'Skip this question',
                  style: AppTypography.buttonSmall.copyWith(
                    color: _IntakePalette.muted,
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
