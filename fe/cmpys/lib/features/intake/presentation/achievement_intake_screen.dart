import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/cmpys_text_field.dart';
import '../../../core/ui/prototype_grid_background.dart';
import '../../auth/controllers/session_controller.dart';
import '../../idols/presentation/idol_visuals.dart';
import '../data/intake_repository.dart';
import '../models/intake_models.dart';

/// Achievement intake screen — asks idol-specific achievement questions
/// before the general intake wizard. Answers are stored as UserAchievement records.
class AchievementIntakeScreen extends ConsumerStatefulWidget {
  const AchievementIntakeScreen({
    super.key,
    required this.idolId,
    this.targetAge,
    this.mentorName,
    this.mentorImageUrl,
  });

  final String idolId;
  final int? targetAge;
  final String? mentorName;
  final String? mentorImageUrl;

  @override
  ConsumerState<AchievementIntakeScreen> createState() =>
      _AchievementIntakeScreenState();
}

class _AchievementIntakeScreenState
    extends ConsumerState<AchievementIntakeScreen> {
  final _textController = TextEditingController();
  final _pageController = PageController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  String? _sessionId;
  List<IntakeQuestion> _questions = [];
  final Map<String, dynamic> _answers = {};
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQuestions());
  }

  @override
  void dispose() {
    _textController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ref.read(intakeRepositoryProvider);
      final response = await repo.startAchievementIntake(
        idolId: widget.idolId,
        targetAge: widget.targetAge,
      );

      if (!mounted) return;
      setState(() {
        _sessionId = response.sessionId;
        _questions = response.questions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load questions. You can skip this step.';
      });
    }
  }

  void _setAnswer(dynamic value) {
    setState(() {
      _answers[_questions[_currentIndex].id] = value;
    });
  }

  Future<void> _submitAndNext() async {
    final question = _questions[_currentIndex];
    final answer = _answers[question.id];

    if (question.isRequired && (answer == null || answer == '')) {
      setState(() => _error = 'This question is required');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // Submit answer to backend
      if (answer != null && _sessionId != null) {
        final repo = ref.read(intakeRepositoryProvider);
        await repo.submitAnswer(
          sessionId: _sessionId!,
          questionId: question.id,
          answer: answer,
        );
      }

      if (_currentIndex < _questions.length - 1) {
        setState(() {
          _currentIndex++;
          _isSubmitting = false;
        });
        _pageController.animateToPage(
          _currentIndex,
          duration: AppDurations.normal,
          curve: Curves.easeInOut,
        );
        _updateTextController();
      } else {
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _error = 'Failed to save. Please try again.';
      });
    }
  }

  void _goBack() {
    if (_currentIndex == 0) {
      context.pop();
      return;
    }
    setState(() {
      _currentIndex--;
      _error = null;
    });
    _pageController.animateToPage(
      _currentIndex,
      duration: AppDurations.normal,
      curve: Curves.easeInOut,
    );
    _updateTextController();
  }

  void _updateTextController() {
    final q = _questions[_currentIndex];
    if (q.type == 'text' || q.type == 'multiline') {
      _textController.text = _answers[q.id]?.toString() ?? '';
    }
  }

  Future<void> _finish() async {
    // Submit last answer first
    final question = _questions[_currentIndex];
    final answer = _answers[question.id];

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final repo = ref.read(intakeRepositoryProvider);

      // Submit last answer if present
      if (answer != null && _sessionId != null) {
        await repo.submitAnswer(
          sessionId: _sessionId!,
          questionId: question.id,
          answer: answer,
        );
      }

      // Finish achievement intake
      if (_sessionId != null) {
        await repo.finishAchievementIntake(_sessionId!);
      }

      if (!mounted) return;

      // Proceed to the general intake wizard
      _navigateToIntake();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Failed to save achievements. Please try again.';
      });
    }
  }

  /// Skip achievement intake entirely and go to general intake.
  void _skip() {
    _navigateToIntake();
  }

  /// Navigate to the general intake wizard.
  Future<void> _navigateToIntake() async {
    try {
      final userAge = ref.read(sessionControllerProvider.notifier).userAge;
      final repo = ref.read(intakeRepositoryProvider);

      final intakeResponse = await repo.startIntake(
        idolId: widget.idolId,
        targetAge: userAge,
      );

      if (!mounted) return;

      context.goToIntake(
        sessionId: intakeResponse.sessionId,
        questions: intakeResponse.questions,
        idolId: widget.idolId,
        targetAge: userAge,
      );
    } catch (e) {
      // If intake fails, complete onboarding and go home
      await ref.read(sessionControllerProvider.notifier).completeOnboarding();
      if (!mounted) return;
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: PrototypeGridBackground(
        gridSize: 20,
        child: SafeArea(
          child: _isLoading
              ? _buildLoading()
              : _error != null && _questions.isEmpty
              ? _buildError()
              : _buildWizard(),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.accent),
          const SizedBox(height: AppSpacing.s16),
          Text(
            'Preparing achievement questions...',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.warning,
              size: 48,
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              _error ?? 'Something went wrong',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s24),
            CmpysButton(
              label: 'Try Again',
              onPressed: _loadQuestions,
              isExpanded: false,
            ),
            const SizedBox(height: AppSpacing.s12),
            CmpysButton(
              label: 'Skip for Now',
              variant: CmpysButtonVariant.ghost,
              onPressed: _skip,
              isExpanded: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWizard() {
    final isLast = _currentIndex == _questions.length - 1;
    final question = _questions[_currentIndex];
    return Column(
      children: [
        _buildHeader(),

        if (_error != null) _buildErrorBanner(),

        Expanded(
          child: PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _questions.length,
            itemBuilder: (context, index) {
              return _buildQuestionPage(_questions[index]);
            },
          ),
        ),

        Container(
          padding: EdgeInsets.only(
            left: AppSpacing.s16,
            right: AppSpacing.s16,
            top: AppSpacing.s16,
            bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.s16,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.borderLight)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAnswerComposer(question),
              const SizedBox(height: AppSpacing.s16),
              CmpysButton(
                label: isLast ? 'Finalize Diagnostic' : 'Submit Value',
                onPressed: _isSubmitting
                    ? null
                    : (isLast ? _finish : _submitAndNext),
                isLoading: _isSubmitting,
                isExpanded: true,
              ),
              if (!question.isRequired || !isLast) ...[
                const SizedBox(height: AppSpacing.s8),
                CmpysButton(
                  label: isLast ? 'Skip & Continue' : 'Skip',
                  variant: CmpysButtonVariant.ghost,
                  onPressed: _isSubmitting
                      ? null
                      : (isLast
                            ? _skip
                            : () {
                                setState(() {
                                  _currentIndex++;
                                  _error = null;
                                });
                                _pageController.animateToPage(
                                  _currentIndex,
                                  duration: AppDurations.normal,
                                  curve: Curves.easeInOut,
                                );
                                _updateTextController();
                              }),
                  isExpanded: true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final progress = _questions.isEmpty
        ? 0.0
        : (_currentIndex + 1) / _questions.length;
    final mentorName = widget.mentorName ?? 'Warren Buffett';
    final mentorImage =
        resolveIdolImageUrl(widget.mentorImageUrl) ??
        idolImageUrlForName(mentorName);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        border: const Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _goBack,
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppColors.textPrimary,
          ),
          const SizedBox(width: AppSpacing.s8),
          ClipOval(
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix(<double>[
                0.2126,
                0.7152,
                0.0722,
                0,
                0,
                0.2126,
                0.7152,
                0.0722,
                0,
                0,
                0.2126,
                0.7152,
                0.0722,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
              ]),
              child: Image.network(
                mentorImage,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mentorName,
                  style: AppTypography.h4.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.mint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'DIAGNOSTIC_ACTIVE',
                      style: AppTypography.captionUpper.copyWith(
                        color: AppColors.mint,
                        fontSize: 9,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(progress * 100).round()}% Complete',
                  style: AppTypography.captionUpper.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 8,
                  ),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: AppRadii.brFull,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.borderLight,
                    color: AppColors.mint,
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s24,
        vertical: AppSpacing.s12,
      ),
      color: AppColors.error.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              _error!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionPage(IntakeQuestion question) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s24,
        AppSpacing.s24,
        AppSpacing.s24,
        AppSpacing.s40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._buildPreviousAnswerBubbles(),
          _buildIdolPromptBubble(question),
        ],
      ),
    );
  }

  List<Widget> _buildPreviousAnswerBubbles() {
    final widgets = <Widget>[];
    for (var i = 0; i < _currentIndex; i++) {
      final question = _questions[i];
      final answer = _answers[question.id];
      if (answer == null || answer.toString().trim().isEmpty) continue;
      widgets.add(
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.s8),
              padding: AppSpacing.p16,
              decoration: const BoxDecoration(
                color: AppColors.charcoal,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Text(
                answer.toString(),
                style: AppTypography.caption.copyWith(
                  color: Colors.white,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ),
      );
      widgets.add(
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s20),
            child: Text(
              '14:05:32 // LOGGED',
              style: AppTypography.captionUpper.copyWith(
                color: AppColors.textTertiary,
                fontSize: 8,
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildIdolPromptBubble(IntakeQuestion question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 310),
          child: Container(
            padding: AppSpacing.p16,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.charcoal.withValues(alpha: 0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Text(
              'Let us calibrate this like a comparison ledger. I need one precise data point before we continue.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.55,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        Container(
          width: double.infinity,
          padding: AppSpacing.p20,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(
              left: BorderSide(color: AppColors.mint, width: 4),
              top: const BorderSide(color: AppColors.border),
              right: const BorderSide(color: AppColors.border),
              bottom: const BorderSide(color: AppColors.border),
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question.chatEyebrow,
                style: AppTypography.captionUpper.copyWith(
                  color: AppColors.mint,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: AppSpacing.s10),
              Text(
                question.title,
                style: AppTypography.h3.copyWith(height: 1.25),
              ),
              const SizedBox(height: AppSpacing.s10),
              Text(
                question.chatPrompt,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
              ),
              if (question.isRequired) ...[
                const SizedBox(height: AppSpacing.s12),
                Text(
                  'Required for a sharper comparison',
                  style: AppTypography.captionUpper.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnswerComposer(IntakeQuestion question) {
    return Container(
      width: double.infinity,
      padding: AppSpacing.p16,
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: AppRadii.br16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.type == 'scale'
                ? 'Discipline_Intensity'
                : 'Achievement_Response',
            style: AppTypography.captionUpper.copyWith(
              color: AppColors.mint,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          _buildInput(question),
        ],
      ),
    );
  }

  Widget _buildInput(IntakeQuestion question) {
    final answer = _answers[question.id];

    switch (question.type.toLowerCase()) {
      case 'multiline':
        return CmpysTextArea(
          controller: question == _questions[_currentIndex]
              ? _textController
              : null,
          hint: question.placeholder ?? 'Describe your achievement...',
          maxLength: question.validation?.maxLength,
          minLines: 4,
          maxLines: 8,
          onChanged: _setAnswer,
        );
      case 'text':
        return CmpysTextField(
          controller: question == _questions[_currentIndex]
              ? _textController
              : null,
          hint: question.placeholder ?? 'Enter your answer',
          maxLength: question.validation?.maxLength,
          onChanged: _setAnswer,
          textInputAction: TextInputAction.done,
        );
      case 'number':
        return CmpysTextField(
          controller: question == _questions[_currentIndex]
              ? _textController
              : null,
          hint: question.placeholder ?? 'Enter a number',
          keyboardType: TextInputType.number,
          onChanged: (v) => _setAnswer(int.tryParse(v) ?? v),
          textInputAction: TextInputAction.done,
        );
      case 'scale':
        final min = question.validation?.min ?? 1;
        final max = question.validation?.max ?? 5;
        final current = answer is num ? answer.toDouble() : min.toDouble();
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$min', style: AppTypography.caption),
                Text(
                  '${current.toInt()}',
                  style: AppTypography.h2.copyWith(color: AppColors.accent),
                ),
                Text('$max', style: AppTypography.caption),
              ],
            ),
            Slider(
              value: current,
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              activeColor: AppColors.accent,
              onChanged: (v) => _setAnswer(v.toInt()),
            ),
          ],
        );
      case 'single_choice':
      case 'select':
        return _buildSelectOptions(question, answer, multiSelect: false);
      case 'multiselect':
      case 'multi_choice':
        return _buildSelectOptions(question, answer, multiSelect: true);
      case 'boolean':
        return _buildSelectOptions(
          question.copyWith(
            options: const [
              IntakeOption(value: 'yes', label: 'Yes'),
              IntakeOption(value: 'no', label: 'No'),
            ],
          ),
          answer,
          multiSelect: false,
        );
      default:
        // Fallback: if the question has options, render them as choices
        if (question.options.isNotEmpty) {
          return _buildSelectOptions(question, answer, multiSelect: false);
        }
        return CmpysTextField(
          controller: question == _questions[_currentIndex]
              ? _textController
              : null,
          hint: question.placeholder ?? 'Enter your answer',
          onChanged: _setAnswer,
          textInputAction: TextInputAction.done,
        );
    }
  }

  Widget _buildSelectOptions(
    IntakeQuestion question,
    dynamic currentAnswer, {
    required bool multiSelect,
  }) {
    final selectedValues = multiSelect
        ? (currentAnswer is List ? currentAnswer.cast<String>() : <String>[])
        : null;
    final selectedValue = !multiSelect ? currentAnswer?.toString() : null;

    return Column(
      children: question.options.map((option) {
        final isSelected = multiSelect
            ? selectedValues!.contains(option.value)
            : selectedValue == option.value;

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s8),
          child: GestureDetector(
            onTap: () {
              if (multiSelect) {
                final list = List<String>.from(selectedValues!);
                if (isSelected) {
                  list.remove(option.value);
                } else {
                  list.add(option.value);
                }
                _setAnswer(list);
              } else {
                _setAnswer(option.value);
              }
            },
            child: AnimatedContainer(
              duration: AppDurations.fast,
              padding: const EdgeInsets.all(AppSpacing.s16),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.1)
                    : AppColors.surface2,
                borderRadius: AppRadii.br16,
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.label,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? AppColors.accent
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (option.description != null) ...[
                          const SizedBox(height: AppSpacing.s4),
                          Text(
                            option.description!,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      multiSelect
                          ? Icons.check_box_rounded
                          : Icons.radio_button_checked_rounded,
                      color: AppColors.accent,
                      size: 22,
                    )
                  else
                    Icon(
                      multiSelect
                          ? Icons.check_box_outline_blank_rounded
                          : Icons.radio_button_off_rounded,
                      color: AppColors.textTertiary,
                      size: 22,
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
