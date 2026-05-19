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

- [x] Content Depth & Quality (P0-A through P0-E)
  - [x] P0-A: Rewrite `book_module_generate.txt` with 2,500-4,000 word minimum
  - [x] P0-B: Rewrite `plan_item_details.txt` with 500-1,200 word lesson minimum
  - [x] P0-C: Update `plan_generate.txt` substance minimums + Pydantic schema
  - [x] P0-D: Add backend content quality validation with retry
  - [x] P0-E: Calculate `duration_minutes` from word count (words/200)

- [ ] Daily Engagement (P1)
  - [x] Streak API + badge
  - [x] Daily focus API
  - [x] Notification service
  - [ ] Notification settings UI

- [ ] Chat Context Awareness (P2)
  - [x] Enhanced chat system prompt
  - [x] Dynamic quick actions
  - [ ] Chat-to-content linking

- [ ] Onboarding Compression (P3)
  - [ ] Make agentic flow primary
  - [ ] Merge IdolSuggest + IdolConfirm

- [ ] Content Personalization (P4)
  - [ ] Feed relevance scoring
  - [ ] "Relevant to Week X" badge
  - [ ] Plan item -> Ideas link

- [ ] Reflection & Journaling (P5)
  - [ ] Reflections API
  - [ ] Reflection bottom sheet
  - [ ] Weekly summary card

- [ ] UI/UX Polish (P6)
  - [ ] Accessibility (semantics, contrast)
  - [ ] Dark theme
  - [ ] Error handling consistency

- [ ] Profile & Settings (P7)
  - [ ] Edit profile
  - [ ] Notification settings UI
  - [ ] Appearance settings
  - [ ] Help center / legal pages