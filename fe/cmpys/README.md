# CMPYS — Flutter Client

Mobile client for the CMPYS mentorship platform.

## Run

```bash
flutter pub get
flutter run                 # iOS sim / web — backend at localhost:8000
```

Physical device (localhost unreachable):

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

Vibrant Deepstash/Wiser-style: off-white paper (`#F2F3F5`), white cards, green
accent, Bricolage Grotesque display + Plus Jakarta Sans body, big rounded corners,
floating pill tab bar.

## Tests

```bash
flutter analyze
flutter test
```
