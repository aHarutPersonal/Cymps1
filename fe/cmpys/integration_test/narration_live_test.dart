// Opt-in live API/native probe. Run only after signing into a synthetic
// cmpys-frontend-…@example.com account in this simulator. Never prints tokens,
// credentials, response bodies or audio URLs. Can request one short synthesis.
import 'dart:convert';

import 'package:cmpys/app/env.dart';
import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/auth/data/me_repository.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/presentation/book_narration.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'live transcription and native playback on synthetic account',
    (tester) async {
      expect(
        Env.enableLogging,
        isFalse,
        reason: 'Run with ENABLE_LOGGING=false to protect the saved session.',
      );
      final client = DioClient(tokenStore: TokenStore());
      expect(Uri.parse(client.baseUrl).scheme, 'https');
      addTearDown(() => client.dio.close());
      final me = await MeRepository(dioClient: client).getMe();
      expect(
        me.email.startsWith('cmpys-frontend-') &&
            me.email.endsWith('@example.com'),
        isTrue,
        reason: 'This opt-in probe requires the separate synthetic QA account.',
      );
      final repository = ContentResourcesRepository(dioClient: client);
      final plan = await PlanRepository(dioClient: client).getCurrentPlan();
      expect(plan, isNotNull);
      final weekHours = [
        for (var week = 1; week <= plan!.durationWeeks; week++)
          plan.items
              .where((item) => item.weekStart <= week && item.weekEnd >= week)
              .fold<int>(0, (total, item) => total + item.estimatedHours),
      ];
      var resource = await repository.getContinueReading();
      resource ??= (await repository.listLibraryResources(limit: 1)).first;
      resource = await repository.getResource(resource.id);
      final document = BookNarrationDocument.fromMarkdown(
        resource.contentMarkdown ?? '',
      );
      final words = document.segments
          .map((segment) => segment.text)
          .join(' ')
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .take(40)
          .toList();
      expect(words.length, greaterThanOrEqualTo(15));
      final excerpt = '${words.join(' ')}.';
      final request = Stopwatch()..start();
      final audio = await repository.prepareNarration(
        resource.id,
        text: excerpt,
        style: BookNarrationStyle.expressive.apiName,
      );
      final firstRequestMs = request.elapsedMilliseconds;
      request.reset();
      final repeated = await repository.prepareNarration(
        resource.id,
        text: excerpt,
        style: BookNarrationStyle.expressive.apiName,
      );
      final metrics = <String, Object?>{
        'plan_weeks': plan.durationWeeks,
        'weekly_hours': plan.weeklyHours,
        'week_allocated_hours': weekHours,
        'week_one_missions': plan.missionsForWeek(1).length,
        'resource_title': resource.title,
        'audio_scheme': audio.audioUri.scheme,
        'excerpt_words': words.length,
        'first_request_ms': firstRequestMs,
        'repeat_request_ms': request.elapsedMilliseconds,
        'repeat_same_audio': repeated.audioUri == audio.audioUri,
        'alignment_source': audio.alignmentSource,
        'alignment_granularity': audio.alignmentGranularity.name,
        'offset_encoding': audio.offsetEncoding,
        'source_text_hash_present': audio.sourceTextHash.isNotEmpty,
        'cue_count': audio.alignment.length,
        'duration_ms': audio.duration?.inMilliseconds,
      };
      debugPrint('NARRATION_LIVE_RESPONSE_METRICS ${jsonEncode(metrics)}');
      expect(audio.alignmentSource, 'transcription');
      expect(audio.audioUri.scheme, 'https');
      expect(audio.alignment, isNotEmpty);
      expect(
        audio.alignmentGranularity,
        BookNarrationAlignmentGranularity.word,
      );
      expect(repeated.audioUri, audio.audioUri);
      expect(repeated.alignment.length, audio.alignment.length);

      final player = AudioPlayer();
      addTearDown(player.dispose);
      final nativeLoad = Stopwatch()..start();
      await player.setUrl(audio.audioUri.toString());
      metrics['native_source_load_ms'] = nativeLoad.elapsedMilliseconds;
      metrics['native_duration_ms'] = player.duration?.inMilliseconds;
      final positions = player.createPositionStream(
        steps: 1000,
        minPeriod: const Duration(milliseconds: 30),
        maxPeriod: const Duration(milliseconds: 45),
      );
      for (final speed in [1.0, 1.5, 2.0]) {
        await player.pause();
        await player.setSpeed(speed);
        await player.seek(Duration.zero);
        // AVPlayer reports the seek result and its completed -> ready event
        // separately. Wait for that event before judging the next playback.
        final resetClock = Stopwatch()..start();
        while (player.processingState == ProcessingState.completed &&
            resetClock.elapsed < const Duration(seconds: 3)) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(player.processingState, isNot(ProcessingState.completed));
        final seen = <int>{};
        final lag = <double>[];
        var emptyCueEvents = 0;
        final subscription = positions.listen((position) {
          if (!player.playing) return;
          final cue = activeBookNarrationCueAt(audio.alignment, position);
          if (cue == null) {
            emptyCueEvents++;
          } else if (seen.add(cue.start)) {
            lag.add((position - cue.startTime).inMicroseconds / 1000 / speed);
          }
        });
        final clock = Stopwatch()..start();
        final playback = player.play();
        while (player.processingState != ProcessingState.completed &&
            clock.elapsed < const Duration(seconds: 90)) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await subscription.cancel();
        expect(player.processingState, ProcessingState.completed);
        await playback;
        expect(seen, isNotEmpty);
        lag.sort();
        metrics['speed_$speed'] = {
          'observed_cues': seen.length,
          'gap_events_without_cue': emptyCueEvents,
          'player_clock_lag_max_ms': lag.last,
          'playback_wall_ms': clock.elapsedMilliseconds,
        };
        debugPrint(
          'NARRATION_LIVE_SPEED $speed ${jsonEncode(metrics['speed_$speed'])}',
        );
      }
      await player.pause();
      final target = audio.alignment[audio.alignment.length ~/ 2];
      await player.seek(target.startTime);
      final pausedAt = player.position;
      await tester.pump(const Duration(milliseconds: 200));
      expect(player.playing, isFalse);
      expect((player.position - pausedAt).inMilliseconds.abs(), lessThan(50));
      metrics['paused_seek_error_ms'] = (pausedAt - target.startTime)
          .inMilliseconds
          .abs();
      debugPrint('NARRATION_LIVE_METRICS ${jsonEncode(metrics)}');
      expect(weekHours, everyElement(lessThanOrEqualTo(plan.weeklyHours)));
    },
    skip: !const bool.fromEnvironment('LIVE_NARRATION_PROBE'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
