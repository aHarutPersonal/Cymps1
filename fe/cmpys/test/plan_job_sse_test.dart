// The generate-results SSE stream now ends with a `plan_job` event carrying
// the 12-week-plan generation job id. These tests cover the streamer's
// callback wiring and the backend-plan model parsing/week-split helpers.

import 'package:cmpys/features/cmpys/presentation/onboarding/results_streamer.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streamGenerateResults surfaces the plan_job id', () async {
    final repo = _PlanJobRepository();
    String? jobId;
    String? blueprint;

    await streamGenerateResults(
      repo: repo,
      sessionId: 'session-1',
      onBlueprint: (acc) => blueprint = acc,
      onPlanJob: (id) => jobId = id,
    );

    expect(jobId, 'job-abc-123');
    expect(blueprint, 'Plan well.');
  });

  test('BackendPlan parses items and splits missions from daily rhythm', () {
    final plan = BackendPlan.fromJson({
      'id': 'plan-1',
      'durationWeeks': 12,
      'weeklyHours': 10,
      'idolName': 'Bill Gates',
      'roadmapThesis': 'Ship weekly.',
      'antiGoals': ['No passive consumption'],
      'totalItems': 3,
      'completedItems': 1,
      'overallProgress': 33.3,
      'createdAt': DateTime.now().toIso8601String(),
      'items': [
        {
          'id': 'i1',
          'title': 'Build a CLI tool',
          'type': 'project',
          'description': 'Ship it.',
          'weekStart': 1,
          'weekEnd': 1,
          'successMetric': 'Tool runs',
          'estimatedHours': 6,
          'status': 'completed',
          'progressPercent': 100,
        },
        {
          'id': 'i2',
          'title': '30 minutes of deliberate practice',
          'type': 'habit',
          'description': 'Every day.',
          'weekStart': 1,
          'weekEnd': 1,
          'successMetric': 'Done daily',
          'estimatedHours': 3,
          'status': 'not_started',
          'progressPercent': 0,
        },
        {
          'id': 'i3',
          'title': 'Read chapter 2',
          'type': 'reading',
          'description': 'Take notes.',
          'weekStart': 2,
          'weekEnd': 2,
          'successMetric': 'Notes written',
          'estimatedHours': 2,
          'status': 'not_started',
          'progressPercent': 0,
        },
      ],
    });

    expect(plan.items, hasLength(3));
    expect(plan.currentWeek(), 1);
    expect(plan.missionsForWeek(1).map((i) => i.id), ['i1']);
    expect(plan.dailyRhythmForWeek(1).map((i) => i.id), ['i2']);
    expect(plan.missionsForWeek(2).map((i) => i.id), ['i3']);
    expect(plan.dailyRhythmForWeek(2), isEmpty);
    expect(plan.items.first.isCompleted, isTrue);
    expect(plan.focusWeek, 2);
    expect(plan.isWeekUnlocked(1), isTrue);
    expect(plan.isWeekUnlocked(2), isTrue);
    expect(plan.isWeekUnlocked(3), isFalse);
    expect(plan.focusedItemForWeek(2)?.id, 'i3');
    expect(plan.allMissionWorkComplete, isFalse);
  });

  test('PlanMaterialDetail extracts YouTube ids and in-app content', () {
    PlanMaterialDetail mat(String? url) => PlanMaterialDetail.fromJson({
          'title': 'Video',
          'type': 'video',
          'url': url,
        });

    expect(mat('https://www.youtube.com/watch?v=CHsjWfBfHAw').youtubeVideoId,
        'CHsjWfBfHAw');
    expect(mat('https://youtu.be/abc123XYZ_-').youtubeVideoId, 'abc123XYZ_-');
    expect(mat('https://youtube.com/shorts/sh0rtID9x_Q').youtubeVideoId,
        'sh0rtID9x_Q');
    expect(mat('https://www.amazon.com/s?k=book').youtubeVideoId, isNull);
    expect(mat(null).youtubeVideoId, isNull);

    final lesson = PlanMaterialDetail.fromJson({
      'title': 'Journaling',
      'type': 'in_app_lesson',
      'content_markdown': '# Lesson',
      'ideas': [
        {'title': 'Cut losses', 'content': 'Fast.', 'category': 'Discipline'},
      ],
    });
    expect(lesson.hasInAppContent, isTrue);
    expect(lesson.ideas.single.category, 'Discipline');
    expect(mat('https://www.amazon.com/s?k=book').hasInAppContent, isFalse);
  });

  test('splitBookChapters splits on chapter headings with part fallback', () {
    final chaptered = splitBookChapters(
      '# Reminiscences\n\n## CHAPTER I\n\nFirst chapter text.\n\n'
      '## CHAPTER II\n\nSecond chapter text.',
    );
    expect(chaptered, hasLength(2));
    expect(chaptered.first.title, 'CHAPTER I');
    expect(chaptered.first.markdown, 'First chapter text.');
    expect(chaptered.last.title, 'CHAPTER II');

    // No headings, short text → a single section.
    final single = splitBookChapters('# Title\n\nJust one short lesson.');
    expect(single, hasLength(1));
    expect(single.first.markdown, contains('Just one short lesson.'));

    // No headings, long text → fixed-size parts.
    final longText = List.generate(40, (_) => List.filled(200, 'w').join(' '))
        .join('\n\n');
    final parts = splitBookChapters(longText);
    expect(parts.length, greaterThan(1));
    expect(parts.first.title, 'Part 1');
  });

  test('PlanJobStatus reads progress and the thinking line', () {
    final job = PlanJobStatus.fromJson({
      'id': 'job-abc-123',
      'status': 'running',
      'step': 'structuring_curriculum',
      'progressPercent': 45,
      'thinkingStream': {'currentLine': 'Balancing major missions...'},
    });

    expect(job.isCompleted, isFalse);
    expect(job.isFailed, isFalse);
    expect(job.progressPercent, 45);
    expect(job.thinkingLine, 'Balancing major missions...');
  });
}

class _PlanJobRepository implements AgenticSessionRepository {
  @override
  Stream<Map<String, dynamic>> generateResults(String sessionId) async* {
    yield {'type': 'status', 'message': 'Reading your interview…'};
    yield {'type': 'section', 'section': 'blueprint'};
    yield {'type': 'chunk', 'content': 'Plan well.'};
    yield {'type': 'plan_job', 'job_id': 'job-abc-123'};
    yield {'type': 'done'};
  }

  @override
  Future<Session> createSession(SessionCreateRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<Session> getSession(String sessionId) {
    throw UnimplementedError();
  }

  @override
  Future<Session?> getCurrentSession() {
    throw UnimplementedError();
  }

  @override
  Future<Session?> getLatestSession() async => null;

  @override
  Future<void> abandonCurrentSession() async {}

  @override
  Future<List<IdolSuggestion>> suggestIdols(String sessionId) {
    throw UnimplementedError();
  }

  @override
  Future<Session> selectIdol(String sessionId, SelectIdolRequest request) {
    throw UnimplementedError();
  }

  @override
  Stream<Map<String, dynamic>> sendInterviewMessage(
    String sessionId,
    String content, {
    bool isKickoff = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<LearningMaterial>> fetchLearningMaterials(
    String sessionId,
    String topic,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<DailyFeedResponse> fetchDailyFeed(String sessionId) {
    throw UnimplementedError();
  }

  @override
  Stream<Map<String, dynamic>> sendGuidedLearningMessage(
    String sessionId,
    String content,
  ) {
    throw UnimplementedError();
  }
}
