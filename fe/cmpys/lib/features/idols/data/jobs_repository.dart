import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../models/job_models.dart';

/// Jobs repository provider.
final jobsRepositoryProvider = Provider<JobsRepository>((ref) {
  return JobsRepository(dioClient: ref.watch(dioClientProvider));
});

/// Repository for job status operations.
class JobsRepository {
  JobsRepository({required DioClient dioClient}) : _dioClient = dioClient;

  final DioClient _dioClient;

  /// Get job status by ID.
  ///
  /// [jobId] - The job's unique identifier.
  /// Returns the current [JobStatus].
  Future<JobStatus> getJob(String jobId) async {
    final response = await _dioClient.get('/jobs/$jobId');
    // ignore: avoid_print
    print('📊 Job status response: ${response.data}');
    return JobStatus.fromJson(response.data);
  }

  /// Poll job status until completion.
  ///
  /// [jobId] - The job's unique identifier.
  /// [pollInterval] - How often to check status (default: 2 seconds).
  /// [timeout] - Maximum time to wait (default: 5 minutes).
  /// [onProgress] - Callback for progress updates.
  ///
  /// Returns the final [JobStatus] when job completes or fails.
  /// Throws [TimeoutException] if job doesn't complete within timeout.
  Future<JobStatus> pollUntilComplete(
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

    throw TimeoutException('Job $jobId did not complete within timeout');
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
}
