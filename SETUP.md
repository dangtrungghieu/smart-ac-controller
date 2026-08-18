# Firebase Setup Guide

## 🔐 Security First!

This project uses Firebase for authentication and real-time database. Due to security reasons, Firebase configuration files are **NOT committed** to the repository.

## 📋 Prerequisites

- Flutter SDK (3.9.2+)
- Firebase Account
- Android SDK / Xcode (for mobile development)

## 🚀 Setup Instructions

### Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Click "Create a new project"
3. Name it (e.g., `ac-control-db`)
4. Enable Google Analytics (optional)
5. Create the project

### Step 2: Enable Firebase Services

In your Firebase project:

1. **Authentication**
   - Go to Build → Authentication
   - Sign-in methods → Enable "Email/Password"

2. **Realtime Database**
   - Go to Build → Realtime Database
   - Create Database
   - Start in test mode (or configure security rules)
   - Region: Asia Southeast 1 (recommended for Vietnam)

### Step 3: Download Firebase Config Files

#### Android Setup

1. In Firebase Console → Project Settings → Your apps → Android
2. Register your app with package name: `com.example.ac_control_app`
3. Download `google-services.json`
4. Place it at: `android/app/google-services.json`

#### iOS Setup

1. In Firebase Console → Project Settings → Your apps → iOS
2. Register your app
3. Download `GoogleService-Info.plist`
4. Place it at: `ios/Runner/GoogleService-Info.plist`

### Step 4: Install Dependencies

```bash
flutter pub get
```

### Step 5: Run the App

**Android:**
```bash
flutter run -d android
```

**iOS:**
```bash
flutter run -d ios
```

## 📝 Project Structure

```
lib/
├── services/
│   ├── auth_service.dart      # Firebase Authentication
│   ├── device_service.dart    # Device/AC data management
│   └── ...
├── screens/                   # UI screens
├── utils/
│   └── theme.dart            # App theme
└── main.dart                 # App entry point
```

## 🔧 Configuration Details

### Firebase Services Used

- **Firebase Core**: ^3.6.0
- **Firebase Authentication**: ^5.3.1 (Email/Password login)
- **Firebase Realtime Database**: ^11.1.4 (Store AC device data)

### Database Structure Example

```
/users/{uid}
  /devices
    /{deviceId}
      - name: "Living Room AC"
      - temperature: 25
      - status: "on"
      - lastUpdated: timestamp
```

## 🛡️ Security Rules

Set your Realtime Database rules to:

```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": "$uid === auth.uid",
        ".write": "$uid === auth.uid"
      }
    }
  }
}
```

## ❌ Troubleshooting

### "Plugin not found" Error
```bash
flutter clean
flutter pub get
flutter pub get --upgrade
```

### Firebase Initialization Error
- Ensure `google-services.json` and `GoogleService-Info.plist` are in correct locations
- Check Firebase credentials in Firebase Console

### Voice Recognition Not Working
- Ensure microphone permission is granted
- Check Vietnamese language model is in `assets/vosk-model-small-vi.zip`

## 📞 Support

For Firebase issues, visit [Firebase Documentation](https://firebase.flutter.dev/)

For app-specific issues, check the GitHub repository issues.

---

**Note:** Never commit Firebase config files to version control. They contain sensitive API keys!
