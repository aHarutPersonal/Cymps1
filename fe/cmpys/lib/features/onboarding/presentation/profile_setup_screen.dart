import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/ui/ambient_background.dart';
import '../../../core/ui/cmpys_app_bar.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/cmpys_chip.dart';
import '../../../core/ui/cmpys_text_field.dart';
import '../../auth/controllers/session_controller.dart';
import '../../auth/data/me_repository.dart';
import '../../auth/models/me_models.dart';
import '../controllers/onboarding_controller.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  final _scrollController = ScrollController();
  final _nameFocusNode = FocusNode();

  DateTime? _birthDate;
  final Set<String> _selectedInterests = {};
  // Combined list of mock + custom interests
  late List<String> _allInterests;
  final _customInterestController = TextEditingController();
  int _currentStep = 0;
  bool _isLoading = false;
  bool _isLoadingProfile = true;
  String? _errorMessage;
  String? _nameError;
  String? _dateError;
  String? _interestsError;

  @override
  void initState() {
    super.initState();
    // Initialize interests
    _allInterests = List.from(mockInterests);

    // Delay loading to avoid modifying providers during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserProfile();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scrollController.dispose();
    _nameFocusNode.dispose();
    _customInterestController.dispose();
    super.dispose();
  }

  /// Load user profile from GET /me
  Future<void> _loadUserProfile() async {
    if (!mounted) return;
    setState(() => _isLoadingProfile = true);

    try {
      // First try to get from cached session
      Me? user = ref.read(currentUserProvider);

      // If not in cache, fetch from API
      if (user == null) {
        final meRepository = ref.read(meRepositoryProvider);
        user = await meRepository.getMe();
      }

      // Prefill form with existing data
      _prefillForm(user);

      // Initialize onboarding controller
      ref
          .read(onboardingControllerProvider.notifier)
          .startOnboarding(existingUser: user);
    } catch (e) {
      // If fetch fails, continue with empty form
      debugPrint('Failed to load profile: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  /// Prefill form fields with user data
  void _prefillForm(Me user) {
    _nameController.text = user.fullName ?? '';
    _birthDate = user.birthDate;

    // Pre-select existing interests
    _selectedInterests.clear();
    for (final interest in user.interests) {
      if (!_allInterests.contains(interest)) {
        _allInterests.add(interest);
      }
      _selectedInterests.add(interest);
    }
  }

  void _clearErrors() {
    setState(() {
      _errorMessage = null;
      _nameError = null;
      _dateError = null;
      _interestsError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen for onboarding state changes
    ref.listen(onboardingControllerProvider, (prev, next) {
      debugPrint(
        '📋 ProfileSetup: prev=${prev?.runtimeType}, next=${next.runtimeType}',
      );

      if (next is OnboardingIdolSuggestStep ||
          next is OnboardingIdolSearchStep) {
        // Profile saved successfully via PATCH /me, start canonical agentic activation.
        debugPrint('📋 ProfileSetup: Navigating to agentic intake');
        // Use addPostFrameCallback to avoid modifying during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.go(AppRoutes.agenticIntake);
          }
        });
      } else if (next is OnboardingError) {
        debugPrint('📋 ProfileSetup: Error - ${next.message}');
        setState(() {
          _isLoading = false;
          _errorMessage = next.message;
        });
        _scrollToTop();
      } else if (next is OnboardingSavingProfile) {
        debugPrint('📋 ProfileSetup: Saving profile...');
        setState(() => _isLoading = true);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: CmpysAppBar(
        showBackButton: _currentStep > 0,
        onBackPressed: _isLoading ? null : _onBack,
      ),
      body: AmbientBackground(
        useSafeArea: false,
        child: SafeArea(
          child: _isLoadingProfile
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.accent,
                    strokeWidth: 2,
                  ),
                )
              : Column(
                  children: [
                    // Error banner
                    _ErrorBanner(
                      message: _errorMessage,
                      onDismiss: () => setState(() => _errorMessage = null),
                    ),
                    // Progress indicator
                    Padding(
                      padding: AppSpacing.screenH,
                      child: Row(
                        children: List.generate(3, (index) {
                          final isActive = index <= _currentStep;
                          return Expanded(
                            child: Container(
                              height: 4,
                              margin: EdgeInsets.only(right: index < 2 ? 8 : 0),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.accent
                                    : AppColors.surface2,
                                borderRadius: AppRadii.brFull,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s24),
                    // Content
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: AppSpacing.screenH,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: _buildStep(),
                      ),
                    ),
                    // Bottom button
                    _BottomButton(
                      label: _currentStep < 2
                          ? 'Continue'
                          : 'Start Mentor Setup',
                      isEnabled: _canContinue() && !_isLoading,
                      isLoading: _isLoading,
                      onPressed: _onContinue,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: AppDurations.normal,
      curve: Curves.easeOut,
    );
  }

  void _onBack() {
    if (_currentStep > 0) {
      _clearErrors();
      setState(() => _currentStep--);
      _scrollToTop();
    }
  }

  Widget _buildStep() {
    switch (_currentStep) {
      case 0:
        return _buildNameStep();
      case 1:
        return _buildAgeStep();
      case 2:
        return _buildInterestsStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildNameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What\'s your name?', style: AppTypography.h1),
        const SizedBox(height: AppSpacing.s8),
        Text(
          'We\'ll use this to personalize your experience.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s32),
        CmpysTextField(
          controller: _nameController,
          focusNode: _nameFocusNode,
          label: 'Full Name',
          hint: 'Enter your name',
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          enabled: !_isLoading,
          errorText: _nameError,
          onChanged: (_) {
            if (_nameError != null) {
              setState(() => _nameError = null);
            }
            setState(() {});
          },
          onSubmitted: (_) {
            if (_canContinue()) _onContinue();
          },
        ),
        const SizedBox(height: AppSpacing.s16),
        // Validation hint
        Text(
          'At least 2 characters',
          style: AppTypography.caption.copyWith(
            color: _nameController.text.trim().length >= 2
                ? AppColors.success
                : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildAgeStep() {
    final now = DateTime.now();
    int? age;
    if (_birthDate != null) {
      age = now.year - _birthDate!.year;
      if (now.month < _birthDate!.month ||
          (now.month == _birthDate!.month && now.day < _birthDate!.day)) {
        age--;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('When were you born?', style: AppTypography.h1),
        const SizedBox(height: AppSpacing.s8),
        Text(
          'This helps us compare you at the same age as your idol.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s32),
        GestureDetector(
          onTap: _isLoading ? null : _selectDate,
          child: Container(
            padding: AppSpacing.p16,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.br16,
              border: Border.all(
                color: _dateError != null ? AppColors.error : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                SvgPicture.asset(
                  AppAssets.iconCalendar,
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    _dateError != null
                        ? AppColors.error
                        : AppColors.textSecondary,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Text(
                    _birthDate != null
                        ? _formatDate(_birthDate!)
                        : 'Select your birth date',
                    style: AppTypography.body.copyWith(
                      color: _birthDate != null
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                if (age != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s12,
                      vertical: AppSpacing.s4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: AppRadii.brFull,
                    ),
                    child: Text(
                      '$age years old',
                      style: AppTypography.captionMedium.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_dateError != null) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            _dateError!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: AppSpacing.s16),
        // Age requirement hint
        Text(
          'You must be at least 13 years old',
          style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildInterestsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What are you interested in?', style: AppTypography.h1),
        const SizedBox(height: AppSpacing.s8),
        Text(
          'Select at least 3 interests to help us find your perfect idol.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s32),
        Wrap(
          key: ValueKey('interests_wrap_${_allInterests.length}'),
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: _allInterests.map((interest) {
            final isSelected = _selectedInterests.contains(interest);
            return CmpysChip(
              label: interest,
              isSelected: isSelected,
              enabled: !_isLoading,
              onTap: () {
                if (_isLoading) return;
                if (_interestsError != null) {
                  setState(() => _interestsError = null);
                }
                setState(() {
                  if (isSelected) {
                    _selectedInterests.remove(interest);
                  } else {
                    _selectedInterests.add(interest);
                  }
                });
              },
            );
          }).toList(),
        ),

        const SizedBox(height: AppSpacing.s24),

        // Custom interest input
        Text(
          'Add your own',
          style: AppTypography.h4.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s12),
        Row(
          children: [
            Expanded(
              child: CmpysTextField(
                controller: _customInterestController,
                hint: 'e.g. Astrophysics',
                textCapitalization: TextCapitalization.sentences,
                enabled: !_isLoading,
                onSubmitted: (_) => _addCustomInterest(),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            CmpysButton(
              label: 'Add',
              variant: CmpysButtonVariant.secondary,
              onPressed: _isLoading ? null : _addCustomInterest,
              isExpanded: false,
              isLoading: false,
              // Making button smaller/compact if possible, or just standard size
            ),
          ],
        ),

        if (_interestsError != null) ...[
          const SizedBox(height: AppSpacing.s12),
          Text(
            _interestsError!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: AppSpacing.s16),
        // Selection counter
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: AppSpacing.s4,
              ),
              decoration: BoxDecoration(
                color: _selectedInterests.length >= 3
                    ? AppColors.success.withValues(alpha: 0.15)
                    : AppColors.surface,
                borderRadius: AppRadii.brFull,
              ),
              child: Text(
                '${_selectedInterests.length}/3',
                style: AppTypography.captionMedium.copyWith(
                  color: _selectedInterests.length >= 3
                      ? AppColors.success
                      : AppColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              _selectedInterests.length >= 3
                  ? 'Great choices!'
                  : 'Select ${3 - _selectedInterests.length} more',
              style: AppTypography.caption.copyWith(
                color: _selectedInterests.length >= 3
                    ? AppColors.success
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
        // Extra padding for scroll
        const SizedBox(height: AppSpacing.s32),
      ],
    );
  }

  bool _canContinue() {
    switch (_currentStep) {
      case 0:
        return _nameController.text.trim().length >= 2;
      case 1:
        return _birthDate != null;
      case 2:
        return _selectedInterests.length >= 3;
      default:
        return false;
    }
  }

  /// Validate current step and show errors if invalid
  bool _validateCurrentStep() {
    _clearErrors();

    switch (_currentStep) {
      case 0:
        final name = _nameController.text.trim();
        if (name.isEmpty) {
          setState(() => _nameError = 'Please enter your name');
          _nameFocusNode.requestFocus();
          return false;
        }
        if (name.length < 2) {
          setState(() => _nameError = 'Name must be at least 2 characters');
          _nameFocusNode.requestFocus();
          return false;
        }
        if (!RegExp(r'^[a-zA-Z\s\-\.]+$').hasMatch(name)) {
          setState(() => _nameError = 'Please enter a valid name');
          _nameFocusNode.requestFocus();
          return false;
        }
        return true;

      case 1:
        if (_birthDate == null) {
          setState(() => _dateError = 'Please select your birth date');
          return false;
        }
        final now = DateTime.now();
        final age = now.year - _birthDate!.year;
        if (age < 13) {
          setState(() => _dateError = 'You must be at least 13 years old');
          return false;
        }
        if (age > 120) {
          setState(() => _dateError = 'Please enter a valid birth date');
          return false;
        }
        return true;

      case 2:
        if (_selectedInterests.length < 3) {
          setState(
            () => _interestsError = 'Please select at least 3 interests',
          );
          return false;
        }
        return true;

      default:
        return false;
    }
  }

  void _onContinue() {
    // Validate current step
    if (!_validateCurrentStep()) {
      return;
    }

    if (_currentStep < 2) {
      // Move to next step
      setState(() => _currentStep++);
      _scrollToTop();
    } else {
      // Final step - save profile via PATCH /me
      _saveProfile();
    }
  }

  /// Save profile via PATCH /me through onboarding controller
  void _saveProfile() {
    final selectedInterestNames = _selectedInterests.toList();

    final controller = ref.read(onboardingControllerProvider.notifier);

    // Update profile data in controller
    controller.updateProfile(
      fullName: _nameController.text.trim(),
      birthDate: _birthDate,
      interests: selectedInterestNames,
    );

    // Save profile - this calls PATCH /me
    controller.saveProfile();
  }

  Future<void> _selectDate() async {
    // Dismiss keyboard if open
    FocusScope.of(context).unfocus();

    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year - 13),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.accent,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
              onPrimary: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() {
        _birthDate = date;
        _dateError = null;
      });
    }
  }

  void _addCustomInterest() {
    final text = _customInterestController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        if (!_allInterests.contains(text)) {
          _allInterests.add(text);
        }
        _selectedInterests.add(text);
        _interestsError = null;
        _customInterestController.clear();
      });
    }
  }
}

/// Inline error banner
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

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
                color: AppColors.error.withValues(alpha: 0.1),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.3),
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
                        AppColors.error.withValues(alpha: 0.7),
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

/// Bottom button with safe area
class _BottomButton extends StatelessWidget {
  const _BottomButton({
    required this.label,
    required this.isEnabled,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isEnabled;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.s24,
        right: AppSpacing.s24,
        bottom: AppSpacing.s24,
        top: AppSpacing.s16,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.88),
        border: const Border(top: BorderSide(color: AppColors.glassBorder)),
        boxShadow: AppShadows.sm,
      ),
      child: SafeArea(
        top: false,
        child: CmpysButton(
          label: label,
          onPressed: isEnabled && !isLoading ? onPressed : null,
          isLoading: isLoading,
        ),
      ),
    );
  }
}
