# CMPYS — Flutter Client

Mobile client for the CMPYS mentorship platform.

## Run

```bash
flutter pub get
flutter run                 # iOS — deployed backend; web — localhost:8000
```

Explicit local-backend override:

```bash
flutter run --dart-define=API_BASE_URL=http://<your-ip>:8000/api/v1
```

## Architecture

```
lib/
  app/               entry, router, theme, design tokens, env
  core/
    network/         Dio HTTP client + typed errors + token refresh
    storage/         secure token store
    ui/              app shell + design-system primitives
  features/
    auth/            splash, login, forgot-password
    session/         backend session client (SSE streaming, models)
    cmpys/           the product:
      data/          seed catalog (mentor portraits/colours), idea provider
      state/         CmpysStore (Riverpod, persisted) + backend sync
      presentation/  all screens
```

## Screens

**Onboarding:** splash > auth > personalize > discover mentor (LLM) > preview >
interview (LLM, SSE) > analysis (streams verdict) > plan generation > app.

**Five tabs:**
- **Today** — progress ring, next action, daily habits, AI idea of the day
- **Plan** — LLM blueprint + colour-block pillars
- **Chat** — streaming AI conversation with the mentor (SSE)
- **Compare** — head-to-head gauge, verdict, radar, milestones, achievement record
- **You** — profile, library, settings

## Design

Cool off-white paper (`#F2F3F5`), white cards, Bricolage Grotesque display and
Plus Jakarta Sans body. Deep green actions provide readable contrast, while
brighter green marks progress. The floating navigation keeps every tab labeled
and adapts to larger text. Buttons and sheets grow with their content, and wide
screens use a comfortable reading width.

## Tests

```bash
flutter analyze
flutter test
```
