# CMPYS Frontend Agent Rules

> **Note:** This directory contains frontend-specific rules. For complete documentation, see the main rules in the backend repository.

## Quick Links

- Full rules are in the backend repository: `cmpys/.agent/rules/`
- This file provides a quick reference for frontend development.

---

## 🎯 APPLICATION MISSION

**CMPYS ("CoMPare Your Success")** helps users achieve their goals by comparing their life progress against historical role models and providing actionable 12-week plans.

**Quality Standards:**
- Every feature must be production-ready
- No bugs, no regressions, no half-implemented features
- Small but 100% sure steps toward user success

---

## 📋 MANDATORY WORKFLOW

### Before ANY Change
1. **ANALYZE** - Understand the request fully
2. **PLAN** - List files to modify, potential issues
3. **ASK** - If ANY ambiguity, ask before coding

### After EVERY Change
- [ ] No Dart analysis errors
- [ ] All types specified (no dynamic)
- [ ] `@JsonKey` for all API fields
- [ ] Ran `build_runner` for freezed models
- [ ] State transitions work smoothly
- [ ] Backend API still matches

---

## 🔑 CRITICAL RULES

### 1. Naming Convention Sync
| Layer | Convention |
|-------|------------|
| API (Python) | `snake_case` |
| Dart | `camelCase` |
| Dart Models | `@JsonKey(name: 'snake_case')` |

```dart
// ✅ CORRECT
@JsonKey(name: 'birth_date') required String birthDate,

// ❌ WRONG
required String birthDate,  // Will be null!
```

### 2. State Management (Riverpod)
- Controllers extend `StateNotifier`
- States use Freezed unions
- Always handle all state cases

### 3. UI Consistency
- Use `design_tokens.dart` for colors, spacing
- Use shared widgets from `core/ui/`
- Never hardcode values

---

## 📁 PROJECT STRUCTURE

```
lib/
├── app/              # Config, routing, theme
├── core/             # Shared utilities, network
└── features/         # Feature modules
    └── domain/
        ├── controllers/    # Riverpod controllers
        ├── data/           # Repositories
        ├── models/         # Freezed models
        └── presentation/   # UI widgets
```

---

## 🔄 Build Commands

```bash
# Generate freezed code
dart run build_runner build --delete-conflicting-outputs

# Run app
flutter run

# Build for production
flutter build ios
flutter build apk
```

---

*For complete documentation, see `/Users/harutantonyan/work/cmpys/.agent/rules/`*
