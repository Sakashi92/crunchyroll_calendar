# 🚀 Nächste Implementierungsschritte

## ✅ Bereits erstellt

### Datenmodelle
- ✅ `lib/models/favorite_anime.dart` - Favoriten-Modell mit Serialisierung
- ✅ `lib/models/notification_log.dart` - Benachrichtigungs-Log-Modell

### Repositories (Datenzugriffschicht)
- ✅ `lib/repositories/favorites_repository.dart` - SQLite-basierte Favoriten-Verwaltung
- ✅ `lib/repositories/notification_repository.dart` - Benachrichtigungs-Historie mit Duplikat-Vermeidung

### Services
- ✅ `lib/services/notification_service.dart` - Lokale Benachrichtigungen (iOS/Android)
- ✅ `lib/services/background_service.dart` - Background-Scraping mit Workmanager

### Utilities
- ✅ `lib/utils/release_comparator.dart` - Release-Vergleich und Filterung

### Dokumentation
- ✅ `FAVORITEN_NOTIFICATION_PLAN.md` - Detaillierter Implementierungsleitfaden

---

## 📦 Abhängigkeiten hinzufügen (pubspec.yaml)

```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Bestehend ...
  
  # NEU für Background-Scraping
  workmanager: ^0.4.6
  
  # NEU für Benachrichtigungen
  flutter_local_notifications: ^17.1.0
  
  # NEU für Datenbankmanagement
  sqflite: ^2.3.0
  path: ^1.8.3
  
  # NEU für Zeitzone-Handling
  timezone: ^0.9.3

dev_dependencies:
  flutter_test:
    sdk: flutter
```

**Danach ausführen:**
```bash
flutter pub get
```

---

## 🔧 Android-Konfiguration (AndroidManifest.xml)

Füge diese Permissions hinzu:

```xml
<!-- android/app/src/main/AndroidManifest.xml -->

<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Bereits vorhanden -->
    <uses-permission android:name="android.permission.INTERNET"/>
    
    <!-- NEU für Background Tasks -->
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    
    <application ...>
        <!-- NEU: Receiver für Boot Complete -->
        <receiver 
            android:name="com.android.systemui.BootReceiver"
            android:enabled="true"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
            </intent-filter>
        </receiver>
    </application>
</manifest>
```

---

## 🍎 iOS-Konfiguration (Info.plist)

Füge diese Keys hinzu:

```xml
<!-- ios/Runner/Info.plist -->

<dict>
    <!-- Bestehend ... -->
    
    <!-- NEU für Background Tasks -->
    <key>BGTaskSchedulerPermittedIdentifiers</key>
    <array>
        <string>de.example.crunchyroll-calendar.scraper</string>
    </array>
    
    <!-- NEU für Benachrichtigungen -->
    <key>UIUserInterfaceStyle</key>
    <string>Automatic</string>
    
    <!-- NEU für Timezone -->
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Used to determine your timezone for notifications</string>
</dict>
```

---

## 🎯 Integration in main.dart

Füge folgende Initialisierungen hinzu:

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // NEU: Initialisiere Services
  await NotificationService().initialize();
  await BackgroundService.initialize();
  
  // Bestehende Initialisierungen ...
  
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // ... Konfiguration
      home: const MyHomePage(),
    );
  }
}

class MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    _initializeBackgroundScraper();
  }
  
  Future<void> _initializeBackgroundScraper() async {
    // Starte Background Scraper wenn App startet
    await BackgroundService().startPeriodicScraperTask(intervalMinutes: 30);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crunchyroll Kalender'),
        actions: [
          // NEU: Button für Favoriten
          IconButton(
            icon: const Icon(Icons.favorite),
            onPressed: _openFavorites,
          ),
          // NEU: Button für Einstellungen
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      // ... Rest des UI
    );
  }
}
```

---

## 📱 UI-Features (noch zu implementieren)

### 1. **Favoriten-Button in AnimeDetailsDialog**
```dart
// In AnimeDetailsDialog - neuer Button in AppBar
actions: [
  IconButton(
    icon: Icon(
      _isFavorite ? Icons.favorite : Icons.favorite_border,
      color: _isFavorite ? Colors.red : null,
    ),
    onPressed: _toggleFavorite,
  ),
],
```

### 2. **Neue Favoriten-Management-Seite**
```dart
class FavoritesPage extends StatefulWidget {
  @override
  _FavoritesPageState createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final _favoritesRepo = FavoritesRepository();
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Favoriten')),
      body: FutureBuilder(
        future: _favoritesRepo.getAllFavorites(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const CircularProgressIndicator();
          
          final favorites = snapshot.data!;
          
          return ListView.builder(
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final favorite = favorites[index];
              return ListTile(
                title: Text(favorite.title),
                subtitle: Text('Hinzugefügt: ${favorite.addedDate}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _removeFavorite(favorite.title),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

### 3. **Benachrichtigungs-Einstellungen**
```dart
// In settings.dart hinzufügen
Future<void> _buildNotificationSettings() {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Benachrichtigungen'),
      content: Column(
        children: [
          SwitchListTile(
            title: const Text('Benachrichtigungen aktivieren'),
            value: _notificationsEnabled,
            onChanged: (value) {
              setState(() => _notificationsEnabled = value);
              _saveSettings();
            },
          ),
          SwitchListTile(
            title: const Text('Nur neue Episoden'),
            value: _onlyNewEpisodes,
            onChanged: (value) {
              setState(() => _onlyNewEpisodes = value);
              _saveSettings();
            },
          ),
        ],
      ),
    ),
  );
}
```

---

## 🧪 Testing-Checkliste

- [ ] **Favoriten-Feature**
  - [ ] Anime zu Favoriten hinzufügen
  - [ ] Anime aus Favoriten entfernen
  - [ ] Favoriten-Liste anzeigen
  - [ ] Favoriten persist nach App-Neustart

- [ ] **Benachrichtigungen (Debug)**
  - [ ] Manuelle Benachrichtigung zeigen: `NotificationService().showNotification(...)`
  - [ ] Geplante Benachrichtigung: `NotificationService().scheduleNotification(...)`
  - [ ] Auf Benachrichtigung klicken → Navigation

- [ ] **Background Scraping**
  - [ ] App schließen → Background Service läuft
  - [ ] 30+ Minuten warten → Benachrichtigung sollte ankommen
  - [ ] Favorit ist in Liste → Benachrichtigung für diesen Anime
  - [ ] Favorit ist NICHT in Liste → Keine Benachrichtigung

- [ ] **Duplikat-Vermeidung**
  - [ ] Zwei Favoriten mit gleichem Release
  - [ ] Sollte nur eine Benachrichtigung sein

---

## 🐛 Debugging-Tipps

### Lokale Notification testen (im Debug-Modus)
```dart
// In main.dart oder irgendwo im UI
ElevatedButton(
  onPressed: () async {
    final notificationService = NotificationService();
    await notificationService.showNotification(
      title: 'Test Notification',
      body: 'Dies ist eine Test-Benachrichtigung',
    );
  },
  child: const Text('Test Notification'),
)
```

### Background Task manuell triggern (Debug)
```dart
// Nur für Tests - nicht für Production
await Workmanager().registerOneOffTask(
  'test-scraper',
  'crunchyrollScraperTask',
);
```

### Datenbank-Inhalt anzeigen
```dart
final favoritesRepo = FavoritesRepository();
final favorites = await favoritesRepo.getAllFavorites();
print('Favorites: ${favorites.map((f) => f.title).toList()}');

final notificationRepo = NotificationRepository();
final history = await notificationRepo.getHistory(limit: 20);
print('Recent notifications: $history');
```

---

## ✨ Kompletter Workflow nach Implementation

1. **App startet** → Background Service initialisiert
2. **User navigiert zu Anime-Details** → Kann Herz-Icon klicken um zu Favoriten zu fügen
3. **App geschlossen** → Background Service prüft Favoriten alle 30 Minuten
4. **Neuer Release für Favorit** → Benachrichtigung wird angezeigt
5. **User klickt Benachrichtigung** → App öffnet und zeigt den neuen Release
6. **User öffnet Favoriten-Seite** → Sieht alle Favoriten und letzten Check-Zeit

---

## 📝 Wichtige Dateien-Übersicht

```
lib/
├── models/
│   ├── anime_release.dart (existiert)
│   ├── favorite_anime.dart (NEU) ✅
│   └── notification_log.dart (NEU) ✅
├── services/
│   ├── crunchyroll_service.dart (existiert)
│   ├── notification_service.dart (NEU) ✅
│   └── background_service.dart (NEU) ✅
├── repositories/
│   ├── favorites_repository.dart (NEU) ✅
│   └── notification_repository.dart (NEU) ✅
└── utils/
    └── release_comparator.dart (NEU) ✅

android/
└── app/src/main/
    └── AndroidManifest.xml (EDIT)

ios/
└── Runner/
    └── Info.plist (EDIT)

main.dart (EDIT)
pubspec.yaml (EDIT)
```

---

## 🎓 Code-Quality Standards

- ✅ Alle Services verwenden Singleton-Pattern
- ✅ Error Handling in allen async Operationen
- ✅ KDebugMode statt _debugPrint
- ✅ Dokumentation mit /// Dart Docs
- ✅ Konsistente Naming Convention
- ✅ Separation of Concerns (Models/Services/Repositories)

---

## ⏭️ Nächste Phase

1. Abhängigkeiten hinzufügen und `flutter pub get` ausführen
2. Android + iOS Konfiguration durchführen
3. main.dart mit BackgroundService initialisieren
4. Favoriten-UI-Komponenten erstellen
5. Testing und Optimierung

**Geschätzter Aufwand:** 2-3 Tage für komplette Implementation
