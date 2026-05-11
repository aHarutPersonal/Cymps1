# CMPYS Performance Optimization Plan

This document outlines the performance optimizations based on an architectural review of the CMPYS system focusing on SRE principles, frontend reliability, and backend asynchronous processing.

## 🚨 Identified Bottlenecks & Issues

1.  **Frontend Request Storms:** 
    - The debug logs show `GET /chat/threads` and `/idols/{id}/timeline` being called 3 to 4 times consecutively at the exact same millisecond.
    - Multiple Flutter controllers (`HomeController`, `ChatController`) are triggering widget rebuilds and executing their `.load()` / `.initialize()` functions concurrently without waiting for ongoing API calls to resolve.
2.  **Redundant Expensive LLM Generation:** 
    - The avatar generation pipeline `POST /idols/{id}/generate-image` is triggered by *both* the `HomeController` and `ChatController` simultaneously when an idol does not have an image URL. This results in duplicate slow DALL-E/Gemini generation calls occurring simultaneously.
3.  **Task Details Slow Loading:** 
    - Currently, only "Week 1" tasks are asynchronously pre-generated after a plan is created. If a user opens a Week 2 task, they must wait for the LLM to structure the curriculum live. 
4.  **Unsafe Navigation:**
    - `GoError: There is nothing to pop` crashes the app from `chat_threads_screen.dart` because `context.pop()` is called when the tab history stack is empty.

---

## 🛠️ Proposed Changes

### 1. Backend: Enqueue ALL Plan Tasks for Background Processing [Architect / SRE]

To fulfill the request to process tasks before opening them, we will expand the Celery background processing to queue *all* plan items immediately after plan generation, rather than just Week 1. This prevents the user from waiting for an LLM when drilling into later weeks.

#### [MODIFY] `backend/app/tasks/plans.py`
- Modify `_enqueue_week1_details_generation_async` to fetch and enqueue ALL `PlanItem`s belonging to the plan.
- Order the query by `week_start` ascending so Celery naturally prioritizes earlier weeks.
- Rename the function to `_enqueue_all_details_generation_async`.

### 2. Backend: Idempotency on Avatar Generation [Database Optimizer]

#### [MODIFY] `backend/app/api/v1/idols.py`
- Modify the `generate_idol_image` endpoint. 
- Fast path: Check if `idol.image_url` is already populated. If it is, immediately return it instead of invoking the Gemini client. This provides an immediate safety net if frontend deduplication fails.

### 3. Frontend: Request Deduplication & Rebuild Guards [Senior Developer]

#### [MODIFY] `lib/features/home/controllers/home_controller.dart`
- Add a guard to `load()`: `if (state is HomeLoading) return;` to ignore duplicate load signals during widget mount storms.

#### [MODIFY] `lib/features/chat/controllers/chat_controller.dart`
- Add a guard to `initialize()`: `if (state is ChatLoading) return;` to prevent redundant parallel thread / history fetches.
- **Critical Fix:** Prevent `generateAvatar()` from executing if `HomeController` is already generating it, or if it has already been generated. By fixing the `ChatLoading` guard, we severely drop the concurrent triggers.

### 4. Frontend: Navigation Hardening [SRE Safety]

#### [MODIFY] `lib/features/chat/presentation/chat_threads_screen.dart`
- Apply bounded navigation safety. In `_ChatThreadsScreenState`, wrap `context.pop()` calls with `if (context.canPop()) { context.pop(); } else { context.go(AppRoutes.home); }`.

---

## ❓ Open Questions
- **Celery Concurrency:** If a plan generates 36 tasks, we will enqueue 36 detail generation jobs into Celery simultaneously. Do you have a configured Celery concurrency limit on your worker? If it's a small VPS, I can chunk/delay them (e.g., prioritize the first 10, then stagger the rest), but if it's fine, I will just enqueue them all.

## ✅ Verification Plan

### Automated Tests
- Watch backend ASGI logs: Ensure `GET /chat/threads` appears strictly ONCE during app cold start.
- Ensure `POST /generate-image` appears strictly ONCE when switching idols or logging into an idol without an avatar.

### Manual Verification
- Generate a new plan for a new Idol. Wait 1 minute, then tap into a Week 4 task. It should open instantly rather than displaying a spinner, confirming the background Celery pre-computation logic covered it.
