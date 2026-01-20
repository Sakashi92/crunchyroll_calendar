# 🧪 Testing & Troubleshooting

## Wie man die Deduplication testet

### Test 1: Einfacher Duplikat-Test (lokal)

1. **App starten**
   ```bash
   flutter run
   ```

2. **Zu den Einstellungen gehen**
   - Schaue auf die Logs im Terminal

3. **Einen Favoriten aktivieren**
   - Stelle sicher "Benachrichtigungen aktiv" ist enabled

4. **Den Background-Scraper sofort testen**
   ```dart
   // In settings.dart oder wo du einen Debug-Button hast
   await BackgroundService().testBackgroundScraperNow();
   ```

5. **Prüfe die Logs**
   ```
   📱 [BACKGROUND] Running scraper task...
   ✅ [BACKGROUND-SCRAPER] Found 2 releases for favorites today
   📤 [BACKGROUND-SCRAPER] Processing 2 releases...
   ✅ [BACKGROUND-SCRAPER] Sent: 2
   ⏭️  [BACKGROUND-SCRAPER] Duplicates skipped: 0
   ```

6. **Wieder sofort testen (in 1 Sekunde)**
   ```dart
   await BackgroundService().testBackgroundScraperNow();
   ```

7. **Prüfe die Logs - sollte diesmal Duplikate skippen!**
   ```
   ✅ [BACKGROUND-SCRAPER] Sent: 0        ← WICHTIG: 0 neue Benachrichtigungen!
   ⏭️  [BACKGROUND-SCRAPER] Duplicates skipped: 2   ← WICHTIG: 2 übersprungen!
   ```

---

### Test 2: Mehrfach-Benachrichtigungen testen

1. **Mehrere Favoriten hinzufügen**
   - Favorite 1: "Jujutsu Kaisen"
   - Favorite 2: "Attack on Titan"
   - Favorite 3: "My Hero Academia"

2. **Sicherstellen, dass für ALLE Benachrichtigungen aktiviert sind**
   - ✅ Jujutsu Kaisen
   - ✅ Attack on Titan
   - ✅ My Hero Academia

3. **Scraper sofort ausführen**
   ```dart
   await BackgroundService().testBackgroundScraperNow();
   ```

4. **Prüfe: Wie viele Benachrichtigungen kamen?**
   ```
   ✅ [BACKGROUND-SCRAPER] Sent: 3    ← 3 Favoriten = 3 Benachrichtigungen ✅
   ⏭️  [BACKGROUND-SCRAPER] Duplicates skipped: 0
   ```

5. **Sofort wieder ausführen**
   ```dart
   await BackgroundService().testBackgroundScraperNow();
   ```

6. **Prüfe: Sollten alle übersprungen sein**
   ```
   ✅ [BACKGROUND-SCRAPER] Sent: 0      ← Alle übersprungen
   ⏭️  [BACKGROUND-SCRAPER] Duplicates skipped: 3   ← 3 Duplikate erkannt
   ```

---

### Test 3: Zeitfenster testen

**Szenario:** Duplikat-Fenster auf 10 Sekunden setzen (nur für Test!)

```dart
// 🧪 TEMPORÄRE ÄNDERUNG in notification_repository.dart
static const int _deduplicationWindowMinutes = 10;  // ← Ändern zu: 0.00016 (10 sec)
// BESSER: Definiere eine Test-Konstante
static const int _deduplicationWindowSeconds = 10;  // ← Für Tests
```

Dann den Test durchführen:

1. **Scraper ausführen**
   ```dart
   await BackgroundService().testBackgroundScraperNow();
   ```
   → 3 Benachrichtigungen gesendet

2. **Nach 5 Sekunden wieder testen**
   ```dart
   await Future.delayed(Duration(seconds: 5));
   await BackgroundService().testBackgroundScraperNow();
   ```
   → Alle 3 sollten übersprungen sein (noch im Fenster)

3. **Nach 12 Sekunden wieder testen**
   ```dart
   await Future.delayed(Duration(seconds: 7));  // Insgesamt 12 sec
   await BackgroundService().testBackgroundScraperNow();
   ```
   → Alle 3 sollten WIEDER gesendet sein (außerhalb Fenster)

---

## Debugging: Datenbank-Abfragen

### Alle Benachrichtigungen anschauen

```dart
final notificationRepo = NotificationRepository();
final history = await notificationRepo.getHistory(limit: 20);

for (var log in history) {
  print('${log.notifyTime} | ${log.favoriteTitle} | ${log.contentHash}');
}
```

### Statistiken anschauen

```dart
final stats = await notificationRepo.getNotificationStats(hoursBack: 24);
print('📊 Letzte 24h:');
print('  Total: ${stats['totalCount']}');
print('  Unique: ${stats['uniqueCount']}');
print('  Favoriten: ${stats['favCount']}');
```

### Spezifischen Hash suchen

```dart
final history = await notificationRepo.getHistory();
final targetHash = 'abc123def456...';

final matching = history.where((log) => log.contentHash == targetHash).toList();
print('Gefunden: ${matching.length} Benachrichtigungen mit diesem Hash');

for (var log in matching) {
  print('  ${log.notifyTime}: ${log.favoriteTitle}');
}
```

### Alte Benachrichtigungen löschen (für Tests)

```dart
final notificationRepo = NotificationRepository();
await notificationRepo.deleteAllNotifications();
print('✓ Alle Benachrichtigungen gelöscht (DB clean)');
```

---

## Häufige Probleme

### Problem 1: Benachrichtigungen kommen IMMER noch doppelt

**Mögliche Ursachen:**
1. Duplikat-Fenster ist zu klein
2. Content-Hash wird nicht korrekt generiert
3. Datenbank wird nicht richtig aktualisiert

**Lösung:**

```dart
// 1. Prüfe: Wird der Hash generiert?
final notification = NotificationLog(
  favoriteTitle: 'JJK',
  releaseTitle: 'Ep42',
  episodeNumber: '42',
  notifyTime: DateTime.now(),
);
print('Hash: ${notification.generateContentHash()}');
// Should output: a1b2c3d4e5f6... (64 Zeichen)

// 2. Prüfe: Werden alte Hashes gefunden?
final isDup = await notificationRepo.isDuplicate('a1b2c3d4e5f6...');
print('Is duplicate: $isDup');  // Should be true after first send

// 3. Vergrößere das Fenster
static const int _deduplicationWindowMinutes = 60;  // Statt 30
```

### Problem 2: Mehrfach-Benachrichtigungen kommen nicht

**Mögliche Ursachen:**
1. Releases haben die gleiche Episode-Nummer
2. Hash ist zu simpel (unterscheidet nicht genug)
3. Releases werden falsch gefiltert

**Lösung:**

```dart
// Debug: Was ist der Hash für jedes Release?
for (final release in uniqueReleases) {
  final notification = NotificationLog(
    favoriteTitle: release.title,
    releaseTitle: release.episodeTitle,
    episodeNumber: release.episodeNumber,
    notifyTime: DateTime.now(),
  );
  print('Release: ${release.title} - ${release.episodeNumber}');
  print('Hash: ${notification.generateContentHash()}');
}

// Sollte unterschiedliche Hashes pro Release anzeigen!
```

### Problem 3: App crasht nach Update

**Mögliche Ursachen:**
1. Alte Datenbank-Version kompatibel mit neuem Schema
2. Migration nicht durchgeführt

**Lösung:**

```dart
// Force reset (alle Daten gehen verloren, aber App funktioniert)
final notificationRepo = NotificationRepository();
await notificationRepo.close();
await notificationRepo.deleteAllNotifications();

// Oder: Neue Datenbank-Version erzwingen
// In notification_repository.dart:
return await openDatabase(
  path,
  version: 2,  // ← Erhöht die Version
  onUpgrade: (db, oldVersion, newVersion) async {
    // Migration code hier
  },
);
```

---

## Performance-Tests

### Wie schnell ist der Duplikat-Check?

```dart
import 'package:stopwatch_toolkit/stopwatch_toolkit.dart';

final stopwatch = Stopwatch()..start();

for (int i = 0; i < 1000; i++) {
  final isDup = await notificationRepo.isDuplicate('hash_$i');
}

stopwatch.stop();
print('1000 checks took: ${stopwatch.elapsedMilliseconds}ms');
// Expected: <100ms (sehr schnell)
```

### Datenbank-Größe prüfen

```dart
import 'dart:io';

final dbPath = await getDatabasesPath();
final dbFile = File(join(dbPath, 'crunchyroll_calendar.db'));
final sizeInBytes = await dbFile.length();
final sizeInMB = sizeInBytes / (1024 * 1024);

print('Datenbank-Größe: ${sizeInMB.toStringAsFixed(2)} MB');
// Normal: <10 MB für 30 Tage Benachrichtigungen
```

---

## Log-Analyzer

Kopiere diese Logs aus dem Terminal und analysiere sie:

```
📊 [BACKGROUND-SCRAPER] Notification Stats (last 2 hours):
   - Total sent: 5
   - Unique content: 3
   - Affected favorites: 2

📤 [BACKGROUND-SCRAPER] Processing 3 releases...

⏭️  [DEDUP] Skipping duplicate: contentHash=abc123...

✅ [BACKGROUND-SCRAPER] Completed in 2s
   - Notifications sent: 2
   - Duplicates skipped: 1
   - Total to send: 3
```

**Interpretation:**
- 5 Benachrichtigungen in 2h versendet
- Aber nur 3 unterschiedliche Inhalte (2 waren Duplikate)
- In diesem Scraper-Lauf: 2 neue + 1 Duplikat

---

## Was könnte noch nicht stimmen?

### ✅ Alles funktioniert perfekt wenn:

- Logs zeigen: `Duplicates skipped: X` (wobei X > 0)
- Mehrere Releases werden als unterschiedliche Benachrichtigungen versendet
- Nach erneutem Lauf werden Duplikate übersprungen
- Hash hat immer 64 Zeichen und ist unterschiedlich für unterschiedliche Releases

### ⚠️ Es könnte Probleme geben wenn:

- Logs zeigen: `Duplicates skipped: 0` (immer)
- Gleiche Benachrichtigung kommt mehrmals
- Hash ist NULL oder undefiniert
- App crasht beim Scraper-Lauf

---

## Wenn nichts funktioniert: Reset

```dart
// 1. Schließe die App komplett

// 2. Führe dies aus (z.B. im main oder Settings)
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

final dbPath = await getDatabasesPath();
final path = join(dbPath, 'crunchyroll_calendar.db');
await deleteDatabase(path);  // ← Löscht alte DB

// 3. Starte die App neu
// → Neue Datenbank wird erstellt mit neuem Schema
```

---

## Nächste Schritte

- [ ] Test 1 durchführen (einfacher Duplikat-Test)
- [ ] Test 2 durchführen (mehrfach-Benachrichtigungen)
- [ ] Logs im Terminal beobachten
- [ ] Bei Problemen: Problem-Sektion oben anschauen
- [ ] Optional: Performance-Tests durchführen

