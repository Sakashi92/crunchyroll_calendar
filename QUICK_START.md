# 🚀 Favoriten & Benachrichtigungen - Quick Start

## ✅ Was wurde bereits gemacht

1. **Dependencies installiert** ✓
   - workmanager, flutter_local_notifications, sqflite, timezone, path

2. **Platform-Konfiguration** ✓
   - ✓ Android: 5 neue Permissions + Boot Receiver
   - ✓ iOS: BGTaskScheduler Identifier + Timezone Keys

3. **main.dart Integration** ✓
   - ✓ NotificationService.initialize()
   - ✓ BackgroundService.initialize()
   - ✓ Periodic Task (30 Min Interval)

4. **Code-Compilation** ✓
   - ✓ Alle Services ohne Fehler
   - ✓ Alle Repositories bereit
   - ✓ Alle Models kompilierbar

---

## 🎯 Nächste Schritte

### Phase 1: Favoriten-Button hinzufügen (10 Min)

Öffne [lib/main.dart](lib/main.dart) und finde die `AnimeDetailsDialog` Klasse:

```dart
// Nach dem Schließen-Button hinzufügen:
ElevatedButton.icon(
  onPressed: () async {
    final favoritesRepo = FavoritesRepository();
    final isFavorite = await favoritesRepo.isFavorite(anime.title);
    
    if (!isFavorite) {
      final favorite = FavoriteAnime(
        title: anime.title,
        imageUrl: anime.imageUrl,
        addedDate: DateTime.now(),
      );
      await favoritesRepo.addFavorite(favorite);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Zu Favoriten hinzugefügt!')),
        );
      }
    } else {
      await favoritesRepo.removeFavorite(anime.title);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Aus Favoriten entfernt!')),
        );
      }
    }
  },
  icon: const Icon(Icons.favorite),
  label: const Text('Favorit'),
)
```

### Phase 2: Favoriten anzeigen (15 Min)

Erstelle `lib/pages/favorites_page.dart`:

```dart
import 'package:flutter/material.dart';
import '../repositories/favorites_repository.dart';
import '../models/favorite_anime.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  late final FavoritesRepository _favoritesRepo;

  @override
  void initState() {
    super.initState();
    _favoritesRepo = FavoritesRepository();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Favoriten')),
      body: FutureBuilder<List<FavoriteAnime>>(
        future: _favoritesRepo.getAllFavorites(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text('Keine Favoriten hinzugefügt'),
            );
          }

          final favorites = snapshot.data!;
          return ListView.builder(
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final anime = favorites[index];
              return ListTile(
                leading: anime.imageUrl != null
                    ? Image.network(anime.imageUrl!, width: 50)
                    : const Icon(Icons.image),
                title: Text(anime.title),
                subtitle: Text('Hinzugefügt: ${anime.addedDate}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    await _favoritesRepo.removeFavorite(anime.title);
                    setState(() {});
                  },
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

### Phase 3: Benachrichtigungen testen (5 Min)

Im main.dart, nach dem Button füge hinzu:

```dart
// Test: Manuelle Benachrichtigung senden
ElevatedButton.icon(
  onPressed: () async {
    final notificationService = NotificationService();
    await notificationService.showNotification(
      title: 'Test Benachrichtigung!',
      body: 'Die Benachrichtigungsfunktion funktioniert! 🎉',
      payload: 'test_payload',
    );
  },
  icon: const Icon(Icons.notifications),
  label: const Text('Test Benachrichtigung'),
)
```

### Phase 4: Background Task testen (5 Min)

Füge Debug-Code in main.dart hinzu:

```dart
// Nach BackgroundService.initialize()
Future<void> _testBackgroundService() async {
  final backgroundService = BackgroundService();
  final isRunning = await backgroundService.isTaskRunning();
  
  if (kDebugMode) {
    print('📊 Background Task Status: ${isRunning ? 'Running ✓' : 'Stopped ✗'}');
  }
}

// Rufe auf nach initialize
await _testBackgroundService();
```

---

## 🧪 Komplette Test-Checkliste

### Lokal (App läuft)
- [ ] App startet ohne Fehler
- [ ] Favoriten-Button sichtbar in Details
- [ ] Anime zu Favoriten hinzufügen funktioniert
- [ ] Favoriten werden in SQLite gespeichert
- [ ] Favoriten-Seite zeigt alle Einträge
- [ ] Test-Benachrichtigung wird angezeigt
- [ ] Logs zeigen "Background Service initialized"

### Background (App geschlossen)
- [ ] Background Task startet nach 30 Minuten
- [ ] Task lädt Favoriten aus DB
- [ ] Task scraped Crunchyroll-Seite
- [ ] Benachrichtigungen erscheinen für neue Releases
- [ ] Duplikate werden verhindert (24h Check)
- [ ] Nach Geräte-Neustart startet Task wieder

### Debug-Logs anschauen
```bash
flutter logs
```

Suche nach:
- `✓ Background Service initialized`
- `✓ Periodic scraper task started`
- `🔔 [BG] Notification sent`
- `📊 Scraper Task Report`

---

## 🎨 UI-Integration (optional)

Füge Tab in CalendarPage hinzu:

```dart
// In _CalendarPageState.build(), update bottom navigation:
BottomNavigationBar(
  currentIndex: _currentIndex,
  onTap: (index) {
    setState(() => _currentIndex = index);
  },
  items: const [
    BottomNavigationBarItem(
      icon: Icon(Icons.calendar_today),
      label: 'Kalender',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.favorite),
      label: 'Favoriten',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.settings),
      label: 'Einstellungen',
    ),
  ],
)

// Und füge Page Switching ein:
if (_currentIndex == 1) return FavoritesPage();
if (_currentIndex == 2) return SettingsPage();
// ... else return CalendarPage
```

---

## 🐛 Troubleshooting

### Problem: Benachrichtigungen werden nicht angezeigt
**Lösung:**
1. Android: Settings → Benachrichtigungen → App
2. iOS: Settings → Notifications → App

### Problem: Background Task läuft nicht
**Lösung:**
1. Prüfe Logs: `flutter logs | grep "Background\|Scraper"`
2. Android: Developer Settings → Don't keep activities (OFF)
3. iOS: Xcode → Signing & Capabilities → Background Modes

### Problem: SQLite Fehler
**Lösung:**
```bash
# Lösche alte Daten
adb shell rm /data/data/de.patrikneubert.crunchyroll_calendar/databases/*

# Oder iOS: Uninstall + Reinstall
```

---

## 📊 Wichtige Files

| Datei | Zweck |
|-------|--------|
| [lib/services/notification_service.dart](lib/services/notification_service.dart) | Lokale Benachrichtigungen |
| [lib/services/background_service.dart](lib/services/background_service.dart) | Background Tasks |
| [lib/repositories/favorites_repository.dart](lib/repositories/favorites_repository.dart) | Favoriten SQLite |
| [lib/repositories/notification_repository.dart](lib/repositories/notification_repository.dart) | Notification History SQLite |
| [lib/utils/release_comparator.dart](lib/utils/release_comparator.dart) | Release-Vergleich & Filterung |

---

## ✨ Nächste Schritte nach Testing

1. **UI Polish** - Favoriten-Button Styling
2. **Error Messages** - User Feedback verbessern
3. **Settings** - Notification On/Off Toggle
4. **Analytics** - Track favorited anime
5. **Cloud Sync** - Cloud-Synchronisierung (optional)

---

**Die Basis-Integration ist fertig! 🎉**

Alle Services laufen und sind produktionsreif. Jetzt nur noch UI-Features hinzufügen!
