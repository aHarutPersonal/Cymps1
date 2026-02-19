# CMPYS

**Compare Your Success** - A Flutter app to compare your achievements with successful people.

## Getting Started

### Prerequisites

- Flutter SDK ^3.10.4
- Dart SDK ^3.10.4
- Xcode (for iOS development)
- Android Studio (for Android development)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd cmpys

# Install dependencies
flutter pub get

# Run the app
flutter run
```

## Project Structure

```
lib/
├── app/                    # App configuration
│   ├── app.dart           # MaterialApp setup
│   ├── assets.dart        # Asset path constants
│   ├── design_tokens.dart # Colors, spacing, typography
│   ├── env.dart           # Environment configuration
│   ├── router.dart        # go_router configuration
│   └── theme.dart         # ThemeData
├── core/
│   ├── data/              # Mock data providers
│   ├── network/           # Dio HTTP client
│   ├── storage/           # Secure storage
│   └── ui/                # Reusable UI components
└── features/
    ├── auth/              # Authentication screens
    ├── chat/              # AI Coach chat
    ├── comparison/        # Progress comparison
    ├── home/              # Dashboard
    ├── idols/             # Idol selection
    ├── notes/             # Notes feature
    ├── onboarding/        # Profile setup
    ├── plans/             # Plan tracker
    └── profile/           # User profile & settings
```

## Environment Configuration

The app supports different backend URLs for development, staging, and production.

### Platform-Specific Development URLs

| Platform | URL | Notes |
|----------|-----|-------|
| **iOS Simulator** | `http://localhost:8000` | Localhost connects directly to host machine |
| **Android Emulator** | `http://10.0.2.2:8000` | Special alias that maps to host's localhost |
| **Physical Device** | Your machine's IP | e.g., `http://192.168.1.100:8000` |

### Default Behavior

The app automatically selects the appropriate URL based on the platform:

```dart
import 'package:cmpys/app/env.dart';

// Automatically uses correct URL for platform
final apiUrl = Env.apiBaseUrl;
```

### Override via dart-define

You can override the API base URL at build/run time:

```bash
# Development with custom backend
flutter run --dart-define=API_BASE_URL=http://localhost:8000

# Staging build
flutter run --dart-define=API_BASE_URL=https://staging-api.cmpys.app --dart-define=FLAVOR=staging

# Production build
flutter build apk --dart-define=API_BASE_URL=https://api.cmpys.app --dart-define=FLAVOR=prod
```

### Available Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `API_BASE_URL` | Platform-specific | Backend API URL |
| `FLAVOR` | `dev` | App flavor: `dev`, `staging`, `prod` |
| `DEBUG` | `true` | Enable debug mode |
| `ENABLE_LOGGING` | `true` | Enable verbose logging |

### Running with Local Backend

#### iOS Simulator

```bash
# Start your backend on localhost:8000
# Then run the app - it will connect automatically
flutter run
```

#### Android Emulator

```bash
# Start your backend on localhost:8000
# The app automatically uses 10.0.2.2:8000
flutter run
```

#### Physical Device

For physical devices, you need to use your machine's local IP:

```bash
# Find your IP (macOS)
ipconfig getifaddr en0

# Run with your IP
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8000
```

## Design System

The app uses a premium minimalist dark UI with consistent design tokens:

- **Colors**: `AppColors` (bg, surface, accent #7B61FF)
- **Spacing**: `AppSpacing` (s4-s48)
- **Radii**: `AppRadii` (r8-r24)
- **Typography**: `AppTypography` (Inter font family)

## Dependencies

- `flutter_riverpod` - State management
- `go_router` - Navigation
- `dio` - HTTP client
- `flutter_svg` - SVG rendering
- `flutter_secure_storage` - Secure token storage
- `google_fonts` - Typography

## License

Proprietary - All rights reserved.
