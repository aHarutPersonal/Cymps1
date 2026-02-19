# CMPYS Frontend Rules

> **Stack:** Flutter | Dart | Riverpod | Dio | GoRouter | Freezed

---

## 🏗️ ARCHITECTURE

### Directory Structure
```
fe/cmpys/lib/
├── app/
│   ├── design_tokens.dart  # Colors, spacing, typography
│   ├── router.dart         # GoRouter configuration
│   └── theme.dart          # ThemeData
├── core/
│   ├── network/
│   │   ├── dio_client.dart # HTTP client with auth
│   │   └── api_error.dart  # Error handling
│   └── ui/                 # Shared UI components
├── features/
│   ├── auth/               # Login, register
│   ├── chat/               # Idol chat
│   ├── comparison/         # User vs idol comparison
│   ├── home/               # Dashboard
│   ├── idols/              # Idol discovery, import
│   ├── notes/              # Note management
│   ├── plans/              # Plan display, tracking
│   ├── profile/            # User settings
│   └── achievements/       # Achievement logging
└── main.dart               # App entry point
```

### Feature Module Structure
```
features/domain/
├── controllers/            # Riverpod StateNotifiers
│   └── domain_controller.dart
├── data/                   # Repositories, API calls
│   └── domain_repository.dart
├── models/                 # Freezed data models
│   └── domain_models.dart
└── presentation/           # UI Widgets
    └── domain_screen.dart
```

---

## 📝 CODING STANDARDS

### Dart Style
- **Effective Dart** guidelines
- **Null safety** enforced (no `dynamic` unless unavoidable)
- **Strict typing** - always specify types
- **Const constructors** when possible

### Naming Conventions
```dart
// Variables, functions, fields: camelCase
final userId = 'uuid';
void getUserById(String userId) {}

// Classes, enums: PascalCase
class UserResponse {}
enum LoadingState { idle, loading, success, error }

// Files: snake_case
// user_controller.dart, domain_models.dart

// Private: prefix with underscore
final _privateField = 'value';
void _privateMethod() {}
```

### Import Order
```dart
// 1. Dart SDK
import 'dart:async';

// 2. Flutter
import 'package:flutter/material.dart';

// 3. Third-party packages
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

// 4. Local imports (relative)
import '../../../core/network/dio_client.dart';
import 'domain_models.dart';
```

---

## 🔄 STATE MANAGEMENT (Riverpod)

### Controller Pattern
```dart
final domainControllerProvider = 
    StateNotifierProvider<DomainController, DomainState>((ref) {
  return DomainController(
    repository: ref.watch(domainRepositoryProvider),
  );
});

class DomainController extends StateNotifier<DomainState> {
  DomainController({required DomainRepository repository})
      : _repository = repository,
        super(const DomainState.initial());

  final DomainRepository _repository;

  Future<void> load() async {
    state = const DomainState.loading();
    try {
      final data = await _repository.fetchData();
      state = DomainState.loaded(data: data);
    } on ApiError catch (e) {
      state = DomainState.error(message: e.message);
    }
  }
}
```

### State Pattern (Freezed)
```dart
@freezed
class DomainState with _$DomainState {
  const factory DomainState.initial() = DomainInitial;
  const factory DomainState.loading() = DomainLoading;
  const factory DomainState.loaded({required DomainData data}) = DomainLoaded;
  const factory DomainState.error({required String message}) = DomainError;
}
```

### Watching State in UI
```dart
class DomainScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(domainControllerProvider);
    
    return state.when(
      initial: () => const SizedBox.shrink(),
      loading: () => const LoadingState(),
      loaded: (data) => DataDisplay(data: data),
      error: (message) => ErrorState(message: message),
    );
  }
}
```

---

## 📦 DATA MODELS (Freezed)

### Model Pattern
```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'domain_models.freezed.dart';
part 'domain_models.g.dart';

@freezed
class DomainItem with _$DomainItem {
  const factory DomainItem({
    required String id,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
    String? optionalField,
  }) = _DomainItem;

  factory DomainItem.fromJson(Map<String, dynamic> json) =>
      _$DomainItemFromJson(json);
}
```

### CRITICAL: JsonKey for API Fields
**EVERY field from API MUST have `@JsonKey(name: 'snake_case')`**

```dart
// ✅ CORRECT
@JsonKey(name: 'birth_date') required String birthDate,
@JsonKey(name: 'idol_id') required String idolId,

// ❌ WRONG - will fail to deserialize
required String birthDate,  // API sends "birth_date"
```

### Running Code Generation
```bash
# Generate freezed/json_serializable code
dart run build_runner build --delete-conflicting-outputs

# Watch mode during development
dart run build_runner watch --delete-conflicting-outputs
```

---

## 🌐 NETWORK LAYER

### Repository Pattern
```dart
final domainRepositoryProvider = Provider<DomainRepository>((ref) {
  return DomainRepository(dioClient: ref.watch(dioClientProvider));
});

class DomainRepository {
  DomainRepository({required DioClient dioClient}) : _dioClient = dioClient;
  final DioClient _dioClient;

  Future<DomainItem> getItem(String id) async {
    final response = await _dioClient.get('/domain/$id');
    return DomainItem.fromJson(response.data);
  }

  Future<void> createItem(CreateItemRequest request) async {
    await _dioClient.post('/domain', data: request.toJson());
  }
}
```

### Error Handling
```dart
try {
  final item = await repository.getItem(id);
} on ApiError catch (e) {
  // Network or server error
  showSnackBar(e.message);
} catch (e) {
  // Unexpected error
  debugPrint('Unexpected error: $e');
}
```

### DioClient Features
- Automatic JWT token attachment
- Token refresh on 401
- Request/response logging
- Timeout handling

---

## 🎨 UI PATTERNS

### Design Tokens
Always use values from `design_tokens.dart`:

```dart
// ✅ CORRECT
padding: EdgeInsets.all(AppSpacing.s16),
color: AppColors.primary,
style: AppTypography.heading1,

// ❌ WRONG - hardcoded values
padding: EdgeInsets.all(16.0),
color: Color(0xFF6366F1),
```

### Common Widgets
Use shared components from `core/ui/`:
- `CmpysAppBar` - Standard app bar
- `CmpysButton` - Primary/secondary buttons
- `CmpysTextField` - Form inputs
- `LoadingState` - Loading indicator
- `ErrorState` - Error display
- `EmptyState` - No data display

### Screen Structure
```dart
class DomainScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const CmpysAppBar(title: 'Domain'),
      body: SafeArea(
        child: _buildContent(context, ref),
      ),
    );
  }
  
  Widget _buildContent(BuildContext context, WidgetRef ref) {
    // State handling
  }
}
```

---

## 🧭 NAVIGATION (GoRouter)

### Route Definition
```dart
// In app/router.dart
GoRoute(
  path: '/domain/:id',
  name: 'domain-detail',
  builder: (context, state) {
    final id = state.pathParameters['id']!;
    return DomainDetailScreen(id: id);
  },
),
```

### Navigation Extensions
```dart
// Define in router.dart
extension RouterExtensions on BuildContext {
  void goToDomainDetail(String id) {
    go('/domain/$id');
  }
}

// Use in widgets
context.goToDomainDetail(item.id);
```

---

## ✅ VERIFICATION CHECKLIST

After frontend changes:

```
□ No Dart analysis errors
□ All types specified (no dynamic)
□ @JsonKey for all API fields
□ Ran build_runner for freezed models
□ State transitions are smooth
□ Loading states shown
□ Error states handled
□ Navigation works correctly
□ Design tokens used (not hardcoded)
□ Hot reload works
```

---

## 🔄 SYNC WITH BACKEND

When backend API changes:

1. **New/changed fields?**
   - Add to freezed model with `@JsonKey(name: 'field_name')`
   - Run `build_runner`

2. **New endpoint?**
   - Add method to repository
   - Update controller to use it

3. **Changed response structure?**
   - Update model completely
   - Test deserialization

**ALWAYS verify backend endpoint exists before adding frontend call.**

---

## ⚠️ COMMON PITFALLS

### 1. Missing JsonKey
```dart
// API returns: {"user_id": "..."}
@JsonKey(name: 'user_id') required String userId,  // ✅
required String userId,  // ❌ Will be null!
```

### 2. Race Conditions in Search
```dart
// Always check if result is still relevant
if (currentState.query == searchedQuery) {
  state = SearchLoaded(results);
} else {
  // Ignore stale results
}
```

### 3. Async Loading in initState
```dart
@override
void initState() {
  super.initState();
  // Use addPostFrameCallback for async operations
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref.read(controllerProvider.notifier).load();
  });
}
```

### 4. Not Handling All States
```dart
// Always handle ALL freezed union cases
state.when(
  initial: () => ...,
  loading: () => ...,
  loaded: (data) => ...,
  error: (msg) => ...,
);
```
