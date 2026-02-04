# 📅 Crunchyroll Simulcast Calendar

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

Ein leistungsstarker, inoffizieller Anime-Veröffentlichungskalender für Crunchyroll, entwickelt mit Flutter. Behalte alle deine Lieblings-Simulcasts im Blick und erhalte Benachrichtigungen, sobald eine neue Folge erscheint.

---

## ✨ Features

- **📍 Live-Kalender:** Übersicht über alle aktuellen Simulcast-Releases von Crunchyroll.
- **🔔 Benachrichtigungen:** Automatische Benachrichtigungen für deine Favoriten.
- **🧹 Intelligente Deduplizierung:** Verhindert doppelte Einträge (z.B. bei Batch-Releases von Folgen).
- **❤️ Watchlist & Favoriten:** Verwalte deine eigene Liste an Animes, die du verfolgst.
- **🖼️ Automatische Metadaten:** Bezieht Cover-Bilder und Beschreibungen automatisch von Kitsu und AniList.
- **🌓 Dark Mode:** Ein modernes Design, das deine Augen schont.

## 🚀 Installation & Setup

### Voraussetzungen
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Stable Channel)
- Android Studio / VS Code mit Flutter Extension

### Schritte
1. Repository klonen:
   ```bash
   git clone https://github.com/Sakashi92/crunchyroll_calendar.git
   ```
2. Abhängigkeiten installieren:
   ```bash
   flutter pub get
   ```
3. App starten:
   ```bash
   flutter run
   ```

## 🛠 Technologien

- **Framework:** Flutter (Dart)
- **Scraping:** [http](https://pub.dev/packages/http) & [html](https://pub.dev/packages/html)
- **Lokale DB:** [sqflite](https://pub.dev/packages/sqflite) & [shared_preferences](https://pub.dev/packages/shared_preferences)
- **Background Tasks:** [workmanager](https://pub.dev/packages/workmanager)
- **Benachrichtigungen:** [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)
- **Metadaten:** Kitsu API & AniList API integration

## 📂 Dokumentation

Weitere Details findest du im [docs/](./docs) Verzeichnis:
- [Quick Start Guide](./docs/QUICK_START.md)
- [Benachrichtigungs-System](./docs/README_NOTIFICATIONS.md)
- [Deduplizierungs-Logik](./docs/NOTIFICATION_DEDUPLICATION.md)

---

## ⚖️ Haftungsausschluss (Disclaimer)

**Dies ist ein inoffizielles Fan-Projekt.**
*   Diese App steht in keiner Verbindung zu Crunchyroll LLC.
*   "Crunchyroll" und die entsprechenden Logos sind eingetragene Markenzeichen von Crunchyroll LLC.
*   Die App nutzt Web-Scraping zur Datenbeschaffung. Die Verfügbarkeit der Daten hängt von der offiziellen Crunchyroll-Webseite ab.

## 📄 Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert - siehe die [LICENSE](LICENSE) Datei für Details.
