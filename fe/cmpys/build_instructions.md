# CMPYS Frontend UI & Code Update Instructions

I have integrated the new `DailyInsight` and `DailyFeedResponse` Freezed models into `lib/features/session/models/session_models.dart`, and I added the `fetchDailyFeed` API call into `data/session_repository.dart`.

To compile these new backend schema models effectively and view the new Deepstash-inspired UIs, please open a terminal in your frontend root folder (`/Users/harutantonyan/work/fe/cmpys`) and run the following execution plan.

## Step 1: Generate Freezed Models
Run the build runner to automatically generate the `.freezed.dart` and `.g.dart` schema files for the new JSON structures:

```bash
cd /Users/harutantonyan/work/fe/cmpys
dart run build_runner build --delete-conflicting-outputs
```

## Step 2: Wire up Controller (I can do this after!)
Once the models generate successfully without errors, let me know! 

I will immediately update `/Users/harutantonyan/work/fe/cmpys/lib/features/session/controllers/session_controller.dart` to expose this state to the Riverpod UI, and wire `_insights` in your `daily_feed_screen.dart` to use the real AI data instead of the hardcoded mock data.

## Step 3: Run Flutter 
You can then run the app on your emulator or physical device to test the vertical swipe Daily Feed and the new Idea Card layouts:
```bash
flutter run
```
