import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../idols/models/job_models.dart';
import '../models/intake_models.dart';

/// Intake repository provider.
final intakeRepositoryProvider = Provider<IntakeRepository>((ref) {
  return IntakeRepository(dioClient: ref.watch(dioClientProvider));
});

/// Repository for intake flow operations.
///
/// The intake flow collects user information to personalize
/// idol suggestions and plan generation.
class IntakeRepository {
  IntakeRepository({required DioClient dioClient}) : _dioClient = dioClient;

  final DioClient _dioClient;

  /// Start a new intake session.
  ///
  /// [idolId] - Optional idol ID to associate with this intake.
  /// [targetAge] - Optional target age for comparison.
  ///
  /// Returns [IntakeStartResponse] with session ID and questions.
  /// 
  /// NOTE: If backend doesn't support intake, returns mock questions for testing.
  Future<IntakeStartResponse> startIntake({
    String? idolId,
    int? targetAge,
  }) async {
    final data = <String, dynamic>{};
    if (idolId != null) data['idolId'] = idolId;
    if (targetAge != null) data['targetAge'] = targetAge;

    debugPrint('📋 Starting intake: idolId=$idolId, targetAge=$targetAge');

    try {
      final response = await _dioClient.post(
        '/intake/start',
        data: data.isNotEmpty ? data : null,
      );

      debugPrint('📋 Intake start response: ${response.data}');
      return IntakeStartResponse.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('📋 Backend intake not available, using mock questions: $e');
      // Return mock questions for testing when backend doesn't support intake
      return _getMockIntakeResponse(idolId, targetAge);
    }
  }
  
  /// Mock intake response for testing when backend doesn't have intake endpoints.
  IntakeStartResponse _getMockIntakeResponse(String? idolId, int? targetAge) {
    final sessionId = 'mock-session-${DateTime.now().millisecondsSinceEpoch}';
    
    return IntakeStartResponse(
      sessionId: sessionId,
      questions: [
        const IntakeQuestion(
          id: 'q1_career_stage',
          title: 'Career Stage',
          prompt: 'Where are you in your career journey right now?',
          type: 'single_choice',
          isRequired: true,
          category: 'career',
          options: [
            IntakeOption(value: 'student', label: 'Student', description: 'Still in school or recently graduated'),
            IntakeOption(value: 'early_career', label: 'Early Career', description: '0-3 years of professional experience'),
            IntakeOption(value: 'mid_career', label: 'Mid Career', description: '4-10 years of experience'),
            IntakeOption(value: 'senior', label: 'Senior/Leadership', description: '10+ years or in leadership role'),
            IntakeOption(value: 'entrepreneur', label: 'Entrepreneur', description: 'Running my own business'),
          ],
        ),
        const IntakeQuestion(
          id: 'q2_goals',
          title: 'Main Goals',
          prompt: 'What are your primary goals for the next 5 years?',
          type: 'multi_choice',
          isRequired: true,
          category: 'goals',
          options: [
            IntakeOption(value: 'career_growth', label: 'Career Advancement', description: 'Promotions, leadership roles'),
            IntakeOption(value: 'skill_development', label: 'Skill Development', description: 'Learn new technologies or skills'),
            IntakeOption(value: 'financial', label: 'Financial Success', description: 'Increase income, build wealth'),
            IntakeOption(value: 'startup', label: 'Start a Business', description: 'Launch my own company'),
            IntakeOption(value: 'work_life', label: 'Work-Life Balance', description: 'Better balance and well-being'),
            IntakeOption(value: 'impact', label: 'Make an Impact', description: 'Contribute to meaningful causes'),
          ],
        ),
        const IntakeQuestion(
          id: 'q3_challenges',
          title: 'Current Challenges',
          prompt: 'What\'s your biggest challenge right now?',
          type: 'single_choice',
          isRequired: true,
          category: 'challenges',
          options: [
            IntakeOption(value: 'direction', label: 'Finding Direction', description: 'Not sure what path to take'),
            IntakeOption(value: 'motivation', label: 'Staying Motivated', description: 'Maintaining focus and energy'),
            IntakeOption(value: 'skills', label: 'Skill Gaps', description: 'Need to learn new things'),
            IntakeOption(value: 'network', label: 'Building Network', description: 'Connecting with the right people'),
            IntakeOption(value: 'confidence', label: 'Confidence', description: 'Believing in myself'),
            IntakeOption(value: 'time', label: 'Time Management', description: 'Balancing everything'),
          ],
        ),
        const IntakeQuestion(
          id: 'q4_learning_style',
          title: 'Learning Style',
          prompt: 'How do you prefer to learn and grow?',
          type: 'single_choice',
          isRequired: false,
          category: 'preferences',
          options: [
            IntakeOption(value: 'reading', label: 'Reading & Research', description: 'Books, articles, deep dives'),
            IntakeOption(value: 'video', label: 'Videos & Courses', description: 'Visual and structured learning'),
            IntakeOption(value: 'doing', label: 'Learning by Doing', description: 'Hands-on projects'),
            IntakeOption(value: 'mentorship', label: 'Mentorship', description: 'Learning from others'),
            IntakeOption(value: 'mixed', label: 'Mix of Everything', description: 'Varies by topic'),
          ],
        ),
        const IntakeQuestion(
          id: 'q5_commitment',
          title: 'Weekly Commitment',
          prompt: 'How many hours per week can you dedicate to personal development?',
          type: 'scale',
          isRequired: true,
          category: 'commitment',
          validation: IntakeValidation(min: 1, max: 20),
        ),
        const IntakeQuestion(
          id: 'q6_inspiration',
          title: 'Inspiration',
          prompt: 'What inspires you most about your chosen idol?',
          type: 'multiline',
          isRequired: false,
          category: 'motivation',
          placeholder: 'Share what aspects of their journey resonate with you...',
          validation: IntakeValidation(maxLength: 500),
        ),
      ],
    );
  }

  /// Submit an answer to an intake question.
  ///
  /// [sessionId] - The intake session ID.
  /// [questionId] - The question being answered.
  /// [answer] - The answer value (type depends on question type).
  ///
  /// Returns [SubmitAnswerResponse] with status and next question.
  Future<SubmitAnswerResponse> submitAnswer({
    required String sessionId,
    required String questionId,
    required dynamic answer,
  }) async {
    // Handle mock sessions locally
    if (sessionId.startsWith('mock-session-')) {
      debugPrint('📝 Mock session - storing answer locally: $questionId = $answer');
      return SubmitAnswerResponse(
        success: true,
        answer: IntakeAnswer(questionId: questionId, answer: answer),
      );
    }
    
    final data = {
      'questionId': questionId,
      'answer': answer,
    };

    debugPrint('📝 Submitting answer: sessionId=$sessionId, questionId=$questionId');

    // API: POST /intake/{session_id}/answer
    final response = await _dioClient.post(
      '/intake/$sessionId/answer',
      data: data,
    );

    debugPrint('📝 Submit answer response: ${response.data}');
    return SubmitAnswerResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Finish an intake session and start processing.
  ///
  /// [sessionId] - The intake session ID to finish.
  ///
  /// Returns [FinishIntakeResponse] with job ID for tracking.
  Future<FinishIntakeResponse> finishIntake(String sessionId) async {
    // Handle mock sessions - return a mock job ID
    if (sessionId.startsWith('mock-session-')) {
      debugPrint('✅ Mock session - returning mock job');
      return FinishIntakeResponse(
        jobId: 'mock-job-${DateTime.now().millisecondsSinceEpoch}',
        message: 'Intake completed (mock mode)',
      );
    }
    
    debugPrint('✅ Finishing intake: sessionId=$sessionId');

    // API: POST /intake/{session_id}/finish
    final response = await _dioClient.post(
      '/intake/$sessionId/finish',
    );

    debugPrint('✅ Finish intake response: ${response.data}');
    return FinishIntakeResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get the current state of an intake session.
  ///
  /// [sessionId] - The intake session ID.
  ///
  /// Returns [IntakeSessionResponse] with all questions and answers.
  Future<IntakeSessionResponse> getIntakeSession(String sessionId) async {
    debugPrint('📖 Getting intake session: sessionId=$sessionId');

    // API: GET /intake/{session_id}
    final response = await _dioClient.get(
      '/intake/$sessionId',
    );

    debugPrint('📖 Intake session response: ${response.data}');
    return IntakeSessionResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get job status by ID.
  ///
  /// [jobId] - The job's unique identifier.
  ///
  /// Returns the current [JobStatus].
  /// Note: This is a convenience method that wraps the jobs endpoint.
  Future<JobStatus> getJob(String jobId) async {
    debugPrint('🔄 Getting job status: jobId=$jobId');

    final response = await _dioClient.get('/jobs/$jobId');

    debugPrint('🔄 Job status response: ${response.data}');
    return JobStatus.fromJson(response.data as Map<String, dynamic>);
  }

  /// Poll job status until completion.
  ///
  /// [jobId] - The job's unique identifier.
  /// [pollInterval] - How often to check status (default: 2 seconds).
  /// [timeout] - Maximum time to wait (default: 5 minutes).
  /// [onProgress] - Callback for progress updates.
  ///
  /// Returns the final [JobStatus] when job completes or fails.
  Future<JobStatus> pollJobUntilComplete(
    String jobId, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
    void Function(JobStatus status)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      final status = await getJob(jobId);

      onProgress?.call(status);

      if (status.isTerminal) {
        return status;
      }

      await Future.delayed(pollInterval);
    }

    throw Exception('Job $jobId did not complete within timeout');
  }

  /// Stream job status updates.
  ///
  /// [jobId] - The job's unique identifier.
  /// [pollInterval] - How often to check status (default: 2 seconds).
  ///
  /// Yields [JobStatus] updates until job is terminal.
  Stream<JobStatus> watchJob(
    String jobId, {
    Duration pollInterval = const Duration(seconds: 2),
  }) async* {
    while (true) {
      final status = await getJob(jobId);
      yield status;

      if (status.isTerminal) {
        break;
      }

      await Future.delayed(pollInterval);
    }
  }

  /// Skip an optional question.
  ///
  /// [sessionId] - The intake session ID.
  /// [questionId] - The question to skip.
  ///
  /// Returns [SubmitAnswerResponse] with next question.
  Future<SubmitAnswerResponse> skipQuestion({
    required String sessionId,
    required String questionId,
  }) async {
    // Handle mock sessions locally
    if (sessionId.startsWith('mock-session-')) {
      debugPrint('⏭️ Mock session - skipping question locally: $questionId');
      return const SubmitAnswerResponse(success: true);
    }
    
    debugPrint('⏭️ Skipping question: sessionId=$sessionId, questionId=$questionId');

    // API: POST /intake/{session_id}/skip (if supported)
    final response = await _dioClient.post(
      '/intake/$sessionId/skip',
      data: {'questionId': questionId},
    );

    debugPrint('⏭️ Skip question response: ${response.data}');
    return SubmitAnswerResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Abandon an intake session.
  ///
  /// [sessionId] - The intake session ID to abandon.
  Future<void> abandonIntake(String sessionId) async {
    debugPrint('❌ Abandoning intake: sessionId=$sessionId');

    // API: DELETE /intake/{session_id} (if supported)
    await _dioClient.delete('/intake/$sessionId');

    debugPrint('❌ Intake abandoned');
  }

  /// Get user's active intake session if any.
  ///
  /// Returns [IntakeSessionResponse] if there's an active session, null otherwise.
  Future<IntakeSessionResponse?> getActiveIntakeSession() async {
    debugPrint('🔍 Checking for active intake session');

    try {
      final response = await _dioClient.get('/intake/active');

      if (response.data == null) {
        debugPrint('🔍 No active intake session');
        return null;
      }

      debugPrint('🔍 Active intake session found: ${response.data}');
      return IntakeSessionResponse.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      // No active session
      debugPrint('🔍 No active intake session (error: $e)');
      return null;
    }
  }
}
