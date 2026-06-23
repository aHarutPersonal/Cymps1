import 'package:cmpys/core/network/api_error.dart';
import 'package:cmpys/features/home/controllers/home_controller.dart';
import 'package:cmpys/features/idols/models/idol_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loads home with empty timeline when timeline fetch has server error',
    () async {
      final controller = HomeController(
        currentIdolId: 'idol-1',
        readUserAge: () => 30,
        clearCurrentIdolId: () async {},
        loadIdolProfile: (_) async => const IdolProfile(
          id: 'idol-1',
          name: 'Ada Lovelace',
          avatarUrl: 'https://example.com/ada.jpg',
        ),
        loadIdolTimeline: (_, {age, mode}) async => throw const ApiError(
          message: 'Server error. Please try again',
          statusCode: 500,
        ),
        generateMissingAvatar: (_, {age}) async => 'ignored',
      );

      await controller.load();

      final state = controller.state;
      expect(state, isA<HomeLoaded>());
      final loaded = state as HomeLoaded;
      expect(loaded.idol.name, 'Ada Lovelace');
      expect(loaded.userAge, 30);
      expect(loaded.timeline.items, isEmpty);
      expect(loaded.timeline.idolId, 'idol-1');
      expect(loaded.timeline.idolName, 'Ada Lovelace');
    },
  );
}
