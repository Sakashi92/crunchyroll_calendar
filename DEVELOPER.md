# 🛠 Developer Documentation

This file contains technical information for developers who want to contribute to the project or build it from source.

## 🚀 Installation & Setup

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Stable Channel)
- Android Studio / VS Code with Flutter Extension

### Steps
1. Clone the repository:
   ```bash
   git clone https://github.com/Sakashi92/crunchyroll_calendar.git
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```

## 📦 Automatic Releases (CI/CD)
This project uses GitHub Actions to automate APK builds. Whenever you push a version tag, the APK is automatically built and attached to a new release:
1. Update the version in `pubspec.yaml`.
2. Create and push a tag:
   ```bash
   git tag v0.9.0
   git push origin v0.9.0
   ```

## 🛠 Technologies
- **Framework:** Flutter (Dart)
- **Scraping:** [http](https://pub.dev/packages/http) & [html](https://pub.dev/packages/html)
- **Local DB:** [sqflite](https://pub.dev/packages/sqflite) & [shared_preferences](https://pub.dev/packages/shared_preferences)
- **Background Tasks:** [workmanager](https://pub.dev/packages/workmanager)
- **Notifications:** [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)
- **Metadata:** Kitsu API & AniList API integration

## 📂 Detailed Documentation
For more technical details, check the [docs/](./docs) directory:
- [Quick Start Guide](./docs/QUICK_START.md)
- [Notification System](./docs/README_NOTIFICATIONS.md)
- [Deduplication Logic](./docs/NOTIFICATION_DEDUPLICATION.md)
