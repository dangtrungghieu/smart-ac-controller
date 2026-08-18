# AC Control App 🌡️

A Flutter-based mobile application for controlling air conditioning systems with voice command support and remote database integration.

## Features ✨

- **Voice Control**: Hands-free AC control using offline speech recognition (Vietnamese language support)
- **Firebase Integration**: Real-time database synchronization and user authentication
- **Smart Temperature Management**: Monitor and adjust temperature settings remotely
- **User Authentication**: Secure login and sign-up with Firebase Authentication
- **State Management**: Efficient state management using Provider pattern
- **Cross-Platform**: Native support for Android and iOS
- **Offline Speech Recognition**: VOSK-powered offline voice commands (no internet required for voice)
- **Persistent Storage**: Local data persistence with shared preferences

## Tech Stack 🛠️

### Core
- **Framework**: Flutter 3.9.2+
- **Language**: Dart
- **Platform**: Android & iOS

### Backend & Services
- **Firebase Core** (^3.6.0)
- **Firebase Authentication** (^5.3.1)
- **Firebase Realtime Database** (^11.1.4)

### State Management
- **Provider** (^6.1.1) - State management solution

### UI/UX
- **Flutter SVG** (^2.0.9) - SVG asset support
- **Google Fonts** (^6.1.0) - Custom typography
- **Material Design** - Material Design components

### Voice Control
- **VOSK Flutter 2** (^1.0.2) - Offline speech recognition engine
- **Permission Handler** (^11.1.0) - Microphone permission management
- **Vietnamese Language Model** - Included VOSK model for Vietnamese speech

### Utilities
- **Intl** (^0.18.1) - Internationalization
- **Shared Preferences** (^2.2.2) - Local storage
- **UUID** (^4.2.2) - Unique identifier generation
- **HTTP** (^1.1.0) - HTTP client for API requests

## Project Structure 📁

```
ac_control_app/
├── lib/                      # Main Dart source code
├── android/                  # Android native code (Kotlin)
├── ios/                      # iOS native code (Swift)
├── web/                      # Web platform files
├── assets/                   # Static assets
│   └── vosk-model-small-vi.zip  # Vietnamese speech model
├── pubspec.yaml             # Flutter project configuration
└── analysis_options.yaml    # Lint rules configuration
```

## Getting Started 🚀

### Prerequisites
- Flutter SDK (3.9.2 or higher)
- Dart SDK (included with Flutter)
- Android SDK or Xcode (for mobile development)
- Firebase project setup

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/dangtrungghieu/ac_control_app.git
   cd ac_control_app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   - Set up a Firebase project at [Firebase Console](https://console.firebase.google.com)
   - Download and add configuration files:
     - `google-services.json` for Android
     - `GoogleService-Info.plist` for iOS

4. **Run the app**
   ```bash
   flutter run
   ```

### Build for Production

**Android**
```bash
flutter build apk
```

**iOS**
```bash
flutter build ios
```

## Usage 💡

### Voice Commands
The app supports voice control in Vietnamese:
- Speak commands to control AC settings
- Commands are processed offline using the VOSK speech recognition engine
- Microphone permission is required (requested on first use)

### Manual Control
- Adjust temperature and settings through the intuitive UI
- Changes sync in real-time with Firebase database
- Access your AC from multiple devices simultaneously

### User Account
- Create an account with email and password
- Secure authentication via Firebase
- Personalized preferences and settings

## Notable Dependencies Notes 📝

### Voice Control
The app uses **VOSK Flutter 2** with an offline Vietnamese language model bundled in the assets folder (`vosk-model-small-vi.zip`). This allows:
- 100% offline speech recognition
- No internet required for voice commands
- Low latency voice processing
- Privacy-focused (no cloud audio transmission)

### Background Tasks
The `android_alarm_manager_plus` dependency is currently disabled due to Kotlin compiler compatibility issues on Windows development. This will be re-enabled once the core app functionality is stable.

## Platform Support 📱

- **Android**: Tested on Android 5.0+ (API 21+)
- **iOS**: Tested on iOS 11.0+
- **Web**: Partially supported

## Permissions Required 🔐

- **Microphone**: Required for voice command functionality
- **Firebase Database Access**: For remote data synchronization
- **Local Storage**: For preferences and cache

## Development Status ⚙️

- **Version**: 1.0.0
- **Status**: Active Development
- **Last Updated**: December 2025

## License 📄

This project is currently unlicensed. See the repository for more information.

## Contributing 🤝

Contributions are welcome! Please feel free to submit issues and pull requests.

## Contact 📧

- **Author**: [dangtrungghieu](https://github.com/dangtrungghieu)
- **Repository**: https://github.com/dangtrungghieu/ac_control_app

---

**Note**: This is a private repository. Access is restricted to authorized users.
