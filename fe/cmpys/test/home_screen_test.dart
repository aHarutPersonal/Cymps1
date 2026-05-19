import 'package:cmpys/core/network/dio_client.dart';
import 'package:cmpys/core/storage/token_store.dart';
import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/feed/data/feed_repository.dart';
import 'package:cmpys/features/feed/models/feed_models.dart';
import 'package:cmpys/features/home/presentation/home_screen.dart';
import 'package:cmpys/features/plans/data/plans_repository.dart';
import 'package:cmpys/features/plans/models/plan_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopPlansRepository extends PlansRepository {
  _NoopPlansRepository()
    : super(dioClient: DioClient(tokenStore: TokenStore()));

  @override
  Future<Plan?> getCurrentPlan() async => null;
}

class _NoopFeedRepository extends FeedRepository {
  _NoopFeedRepository() : super(dioClient: DioClient(tokenStore: TokenStore()));

  @override
  Future<FeedResponse> getFeed({
    int page = 1,
    int pageSize = 10,
    int? seed,
  }) async {
    return FeedResponse(
      items: const [],
      total: 0,
      page: page,
      pageSize: pageSize,
      hasMore: false,
    );
  }
}

void main() {
  testWidgets(
    'home screen does not register Riverpod listeners from initState',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentIdolIdProvider.overrideWithValue(null),
            plansRepositoryProvider.overrideWithValue(_NoopPlansRepository()),
            feedRepositoryProvider.overrideWithValue(_NoopFeedRepository()),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();

      final exception = tester.takeException();

      expect(exception, isNot(isA<AssertionError>()));
    },
  );
}
