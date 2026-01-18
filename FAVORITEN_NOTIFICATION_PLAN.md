# Favoriten & Benachrichtigungen - Implementierungsleitfaden

## 🎯 Projektstruktur (neu erforderlich)

```
lib/
├── models/
│   ├── anime_release.dart (existiert bereits)
│   ├── favorite_anime.dart (NEU)
│   └── notification_log.dart (NEU)
├── services/
│   ├── crunchyroll_service.dart (existiert bereits)
│   ├── background_service.dart (NEU)
│   ├── notification_service.dart (NEU)
│   └── favorite_repository.dart (NEU)
├── repositories/
│   ├── favorites_repository.dart (NEU)
│   └── notification_repository.dart (NEU)
└── utils/
    └── release_comparator.dart (NEU)
```

## 📋 Abhängigkeiten (pubspec.yaml)

```yaml
dependencies:
  # Bestehend
  flutter: ...
  # NEU für Background-Scraping
  workmanager: ^0.4.6  # iOS & Android Background Tasks
  # NEU für Benachrichtigungen
  flutter_local_notifications: ^17.1.0
  # NEU für Datenbankverwaltung
  sqflite: ^2.3.0  # SQLite Local DB
  # NEU für zeitbasierte Trigger
  timezone: ^0.9.3
```

## 🔄 Architektur-Übersicht

```
┌─────────────────────────────────────────┐
│         User Interface (UI)             │
│  - Favoriten-Anzeige                   │
│  - Einstellungen (Update-Intervall)    │
└────────────┬────────────────────────────┘
             │
┌────────────▼────────────────────────────┐
│      NotificationService                │
│  - Lokale Benachrichtigungen anzeigen  │
│  - Notification-History speichern      │
└────────────┬────────────────────────────┘
             │
┌────────────▼────────────────────────────┐
│      BackgroundService                  │
│  - Periodic Background Task             │
│  - Neue Releases erkennen               │
│  - Nur Favoriten filtern                │
└────────────┬────────────────────────────┘
             │
┌────────────▼────────────────────────────┐
│   CrunchyrollService (Scraper)         │
│  - Scraped aktuelle Releases           │
│  - Nur neue Daten abrufen              │
└────────────┬────────────────────────────┘
             │
┌────────────▼────────────────────────────┐
│     Repository Layer                    │
│  ├─ FavoritesRepository                │
│  │  ├─ Add/Remove Favorit              │
│  │  ├─ Get Alle Favoriten              │
│  │  └─ Check if Favorit                │
│  ├─ NotificationRepository             │
│  │  ├─ Log Benachrichtigung            │
│  │  ├─ Get History                     │
│  │  └─ Mark as shown                   │
│  └─ ReleaseComparator                  │
│     ├─ Find new releases               │
│     ├─ Filter by favorites             │
│     └─ Avoid duplicates                │
└────────────┬────────────────────────────┘
             │
┌────────────▼────────────────────────────┐
│     SQLite Database                     │
│  ├─ favorites_table                    │
│  ├─ notification_log_table             │
│  └─ release_history_table              │
└─────────────────────────────────────────┘
```

## ✅ Detaillierte TODO-Liste

### Phase 1: Datenmodelle & Repositories (Basis)
- [ ] **1.1** `favorite_anime.dart` erstellen
  - [ ] Modell mit: id, title, imageUrl, addedDate, lastChecked
  - [ ] `toJson()` / `fromJson()` für Serialisierung
  
- [ ] **1.2** `notification_log.dart` erstellen
  - [ ] Modell für: id, favoriteTitle, releaseInfo, notificationTime, isShown
  - [ ] `toJson()` / `fromJson()` für Serialisierung

- [ ] **1.3** `favorites_repository.dart` erstellen
  - [ ] SQLite-Tabelle: `favorites` (id, title, imageUrl, addedDate)
  - [ ] Methoden: `addFavorite()`, `removeFavorite()`, `getAllFavorites()`, `isFavorite(title)`
  - [ ] Initialization und Schema-Management

- [ ] **1.4** `notification_repository.dart` erstellen
  - [ ] SQLite-Tabelle: `notifications` (id, favorite_id, releaseTitle, notifyTime, isShown)
  - [ ] Methoden: `logNotification()`, `getHistory()`, `markAsShown()`, `getUnshownCount()`
  - [ ] Cleanup alte Einträge (älter als 30 Tage)

### Phase 2: Release-Vergleich & Benachrichtigungen
- [ ] **2.1** `release_comparator.dart` erstellen
  - [ ] `findNewReleases()`: Vergleicht neue vs. gecachte Releases
  - [ ] `filterByFavorites()`: Filtert nur Favoriten
  - [ ] `avoidDuplicates()`: Verhindert doppelte Benachrichtigungen
  - [ ] `sortByRelevance()`: Sortiert nach Anzahl neuer Episodes

- [ ] **2.2** `notification_service.dart` erstellen
  - [ ] Flutter Local Notifications Setup (iOS + Android)
  - [ ] `showNotification()`: Zeigt Benachrichtigung an
  - [ ] `scheduleNotification()`: Plant Benachrichtigung zeitgesteuert
  - [ ] `setupNotificationChannels()`: Android Notification Channels
  - [ ] `onNotificationTap()`: Callback wenn Benachrichtigung angetippt wird

### Phase 3: Background Task Setup
- [ ] **3.1** `background_service.dart` erstellen
  - [ ] `initializeBackgroundTask()`: Workmanager Setup
  - [ ] `startPeriodicScraperTask()`: Startet periodische Aufgabe
  - [ ] `backgroundScraperCallback()`: Die Hintergrund-Funktion (static)
  - [ ] Error Handling & Logging für Background-Tasks
  - [ ] Fallback: Wenn App nicht installiert, Fehler elegant handhaben

- [ ] **3.2** Workmanager Konfiguration
  - [ ] Android: AndroidManifest.xml Permissions hinzufügen
    - [ ] `RECEIVE_BOOT_COMPLETED` (nach Neustart starten)
    - [ ] `VIBRATE` (für Benachrichtigungen)
  - [ ] iOS: Info.plist BGTaskSchedulerPermittedIdentifiers
  - [ ] Background Mode aktivieren

- [ ] **3.3** App Lifecycle Integration
  - [ ] `main.dart`: Background Service beim Start initialisieren
  - [ ] `MyHomeState`: onPause/onResumed Lifecycle Hooks
  - [ ] Bei App-Pause: Background Task starten
  - [ ] Bei App-Resume: Background Task pausieren (optional)

### Phase 4: UI-Integration (Favoriten-Feature)
- [ ] **4.1** Neuer Button "Zu Favoriten hinzufügen" in AnimeDetailsDialog
  - [ ] Herz-Icon in der Detail-View
  - [ ] Visuelles Feedback (Toggle zwischen favorit/nicht-favorit)
  - [ ] `onFavoriteToggle()` Callback

- [ ] **4.2** Neue Favoriten-Verwaltungs-Seite
  - [ ] Liste aller Favoriten anzeigen
  - [ ] Letzten Check-Zeitstempel anzeigen
  - [ ] Entfernen-Funktionalität
  - [ ] Anzahl neuer Releases pro Favorit

- [ ] **4.3** Benachrichtigungs-Einstellungen erweitern
  - [ ] Toggle: "Benachrichtigungen für Favoriten aktivieren"
  - [ ] Auswahl: "Welche Tageszeiten" (z.B. 8-22 Uhr)
  - [ ] Einstellung: "Nur neue Episoden benachrichtigen" vs. "Alle Updates"

### Phase 5: Testing & Optimierung
- [ ] **5.1** Background Task Testing
  - [ ] Manueller Test: App schließen, warten auf Benachrichtigung
  - [ ] Logging zu SharedPreferences für Debugging
  - [ ] Test mit verschiedenen Intervallen (1 min, 5 min, 30 min)

- [ ] **5.2** Datenbank-Integrity
  - [ ] Migration bei Schema-Änderungen
  - [ ] Cleanup alte Notification-Einträge
  - [ ] Größenlimit für Datenbank

- [ ] **5.3** Performance-Optimierung
  - [ ] Nur unterschiede zur letzten Check-Zeit scrapen
  - [ ] Batch-Processing von Benachrichtigungen
  - [ ] Netzwerk-Error Recovery (Exponential Backoff)

## 📱 Platform-spezifische Details

### Android
```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

### iOS
```swift
// Info.plist
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.example.crunchyroll-calendar.scraper</string>
</array>
```

## 🔐 Datenschutz & Speicher

- Favoriten werden **lokal** gespeichert (nicht an Server)
- Notification-Log wird nach **30 Tagen** automatisch gelöscht
- **Maximal 1000 Einträge** pro Tabelle
- User kann jederzeit alle Daten löschen

## ⚡ Erwartete Speichernutzung

- Pro Favorit: ~100 bytes
- Pro Notification-Log: ~150 bytes
- Bei 50 Favoriten + 365 täglich Checks: ~150 KB

## 🚀 Execution-Intervalle (configurable)

- **Minimum:** 15 Minuten (zu häufig = Batterieleere)
- **Empfohlen:** 30-60 Minuten
- **Maximum:** 6 Stunden
- **Nachts (22-8 Uhr):** Optional pausieren

## 🐛 Error Handling

```
Background Task Fehler:
├─ Netzwerkfehler → Retry mit Exponential Backoff (max 3x)
├─ API-Fehler (5xx) → Log + Skip diese Iteration
├─ Datenbank-Fehler → Log + Fallback zu In-Memory
└─ Permission Fehler → User benachrichtigen
```

## 📊 Datenbank-Schema

```sql
-- Favoriten
CREATE TABLE favorites (
  id INTEGER PRIMARY KEY,
  title TEXT UNIQUE NOT NULL,
  imageUrl TEXT,
  addedDate TEXT NOT NULL,
  lastChecked TEXT
);

-- Benachrichtigungen
CREATE TABLE notifications (
  id INTEGER PRIMARY KEY,
  favorite_id INTEGER NOT NULL,
  releaseTitle TEXT NOT NULL,
  episodeNumber TEXT,
  notifyTime TEXT NOT NULL,
  isShown INTEGER DEFAULT 0,
  FOREIGN KEY (favorite_id) REFERENCES favorites(id)
);

-- Release-Historie (für Duplikat-Vermeidung)
CREATE TABLE release_history (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  episodeNumber TEXT NOT NULL,
  lastSeenDate TEXT NOT NULL,
  UNIQUE(title, episodeNumber)
);
```

## 🔍 Monitoring & Debug

- [ ] Alle Background-Task Executions zu SharedPreferences loggen
- [ ] Letzter Check-Zeitstempel speichern
- [ ] Anzahl erfolgreicher/fehlgeschlagener Checks tracken
- [ ] Debug-Info im Settings-Screen anzeigen

## 📝 Code-Qualität Standards

- [ ] Alle Methoden dokumentiert (/// Dart Docs)
- [ ] Error Handling in allen async Operations
- [ ] Unit Tests für: Comparator, Repository, Notification Logic
- [ ] Integration Tests für: Background Task, DB Operations
- [ ] Consistent Naming Convention verwenden

## 🎓 Implementation-Reihenfolge

1. **Woche 1:** Datenmodelle + Repositories (Phase 1)
2. **Woche 2:** Release-Vergleich + Notifications (Phase 2)
3. **Woche 3:** Background Service + Android/iOS Setup (Phase 3)
4. **Woche 4:** UI-Integration (Phase 4)
5. **Woche 5:** Testing + Optimierung (Phase 5)

## 🤝 Best Practices

- Trennung von Concerns (Model/View/Service)
- Dependency Injection wo möglich
- Async/Await statt Callbacks
- Try-Catch in allen kritischen Bereichen
- Logging auf allen wichtigen Checkpoint
- Keine UI-Updates in Background-Tasks
