# CMPYS Optimization Task List

- [x] Backend Pre-computation
  - [x] Update `backend/app/tasks/plans.py` to enqueue all plan tasks instead of just Week 1

- [x] Backend Avatar Idempotency
  - [x] Add check to `POST /generate-image` in `backend/app/api/v1/idols.py` to return early if `image_url` exists

- [x] Frontend Request Deduplication
  - [x] Add load guard to `HomeController` (`lib/features/home/controllers/home_controller.dart`)
  - [x] Add load guard to `ChatController` (`lib/features/chat/controllers/chat_controller.dart`)

- [x] Frontend Navigation Fix
  - [x] Guard `context.pop()` with `context.canPop()` in `lib/features/chat/presentation/chat_threads_screen.dart`
