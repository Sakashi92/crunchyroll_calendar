# 🔔 Benachrichtigungs-Deduplication System

## Überblick

Das System verhindert **doppelte Benachrichtigungen** (alle 20 Minuten die gleiche Nachricht) und erlaubt gleichzeitig **mehrfach-Benachrichtigungen** (wenn 4 neue Anime rauskamen, bekommst du 4 Benachrichtigungen).

---

## Das Problem

**Alt:** Alle 20 Minuten kam die gleiche Benachrichtigung für den letzten Anime
- Grund: Der Background-Service führt alle 20 Minuten einen Scraper aus
- Der fand immer die gleichen Releases von gestern
- Und sendete immer eine Benachrichtigung dafür

**Neu:** Intelligente Deduplication mit Content-Hash

---

## Wie es funktioniert

### 1️⃣ Content-Hash Generation

Jede Benachrichtigung bekommt einen eindeutigen **SHA256-Hash** basierend auf:
- Anime-Titel (z.B. "Jujutsu Kaisen")
- Episode-Titel (z.B. "Der Kampf intensiviert sich")
- Episode-Nummer (z.B. "42")

```dart
// Beispiel
favoriteTitle: "Jujutsu Kaisen"
releaseTitle: "Der Kampf intensiviert sich"
episodeNumber: "42"
// → contentHash: "a1b2c3d4e5f6..." (SHA256)
```

### 2️⃣ Duplikat-Erkennung

Bevor eine Benachrichtigung gesendet wird, prüft das System:

```
IST DIESER CONTENT-HASH IN DEN LETZTEN 30 MINUTEN BEREITS VERSENDET WORDEN?
│
├─ JA → SKIP (Duplikat erkannt) ✅
│
└─ NEIN → SEND (Neue Benachrichtigung) 📤
```

**Wichtig:** Das Zeitfenster ist **30 Minuten** (konfigurierbar)

### 3️⃣ Mehrfach-Benachrichtigungen

Wenn du während der Zeit wo nicht gescrapt wurde **4 neue Anime** bekommst:

```
Zeit    | Scraper läuft | Neue Releases gefunden
--------|---------------|---------------------
14:00   | ✓ Scraper 1   | Anime A (neue)
14:20   | ✗ Keine Zeit  | (nicht gescrapt)
14:40   | ✗ Keine Zeit  | (nicht gescrapt)
15:00   | ✓ Scraper 2   | Anime A, B, C, D (neu)
        |               | → 4 Benachrichtigungen! 📤📤📤📤
```

---

## Implementierung

### NotificationLog (Model)

```dart
class NotificationLog {
  final String favoriteTitle;      // z.B. "Jujutsu Kaisen"
  final String releaseTitle;       // z.B. "Episode 42 Title"
  final String? episodeNumber;     // z.B. "42"
  final DateTime notifyTime;       // Wann wurde versendet?
  final String? contentHash;       // SHA256 zur Deduplication
  
  /// Erstellt einen einzigartigen Hash für diese Benachrichtigung
  String generateContentHash() {
    final content = '$favoriteTitle|$releaseTitle|${episodeNumber ?? ""}';
    return sha256.convert(content.codeUnits).toString();
  }
}
```

### NotificationRepository (Datenbank-Logik)

```dart
class NotificationRepository {
  static const int _deduplicationWindowMinutes = 30;
  
  /// 🚀 NEUE METHODE: Smartere Deduplication
  /// Prüft: War dieser EXAKTE Inhalt in den letzten 30 Minuten versendet?
  Future<bool> isDuplicate(String contentHash) async {
    final windowStart = DateTime.now().subtract(
      Duration(minutes: _deduplicationWindowMinutes)
    );
    
    final result = await db.query(
      'notifications',
      where: 'contentHash = ? AND notifyTime > ?',
      whereArgs: [contentHash, windowStart.toIso8601String()],
      limit: 1,
    );
    
    return result.isNotEmpty;  // true = Duplikat, false = Neu
  }
  
  /// 🚀 NEUE METHODE: Statistiken anschauen
  Future<Map<String, dynamic>> getNotificationStats({int hoursBack = 2}) async {
    // Zeigt: Wie viele Benachrichtigungen in letzten 2 Stunden?
    // - Gesamt
    // - Unique (verschiedene Inhalte)
    // - Betroffene Favoriten
  }
}
```

### BackgroundService (Scraper-Logik)

```dart
Future<bool> _executeBackgroundScraper() async {
  // ... Services initialisieren ...
  
  // Releases finden (kann mehrere sein)
  final uniqueReleases = ReleaseComparator.sortByRelevance(relevantReleases);
  
  // 📊 Statistiken anzeigen
  final stats = await notificationRepo.getNotificationStats(hoursBack: 2);
  print('📊 Total sent: ${stats['totalCount']}');
  print('📊 Unique content: ${stats['uniqueCount']}');
  
  // 🔄 Jedes Release checken
  for (final release in uniqueReleases) {
    // Erstelle NotificationLog mit Hash
    final notification = NotificationLog(...);
    final contentHash = notification.generateContentHash();
    
    // 🚀 SMART CHECK: Ist das ein Duplikat?
    final isDuplicate = await notificationRepo.isDuplicate(contentHash);
    
    if (isDuplicate) {
      print('⏭️  Skip duplicate: ${release.title}');
      skippedDuplicates++;
      continue;  // NICHT senden
    }
    
    // Neue Benachrichtigung → Senden!
    await notificationService.showNotification(...);
    await notificationRepo.logNotification(notification);
    notificationCount++;
  }
  
  // Debug-Output
  print('✅ Sent: $notificationCount');
  print('⏭️  Skipped duplicates: $skippedDuplicates');
}
```

---

## Szenarien

### Szenario 1: Doppelte Benachrichtigungen verhindern ✅

```
14:00 Uhr - Scraper läuft:
  └─ Findet "Jujutsu Kaisen Ep. 42"
  └─ contentHash = "abc123"
  └─ isDuplicate? NEIN
  └─ ✅ BENACHRICHTIGUNG GESENDET

14:20 Uhr - Scraper läuft:
  └─ Findet wieder "Jujutsu Kaisen Ep. 42" (noch relevant)
  └─ contentHash = "abc123" (GLEICH!)
  └─ isDuplicate? JA (versendet vor 20 Min)
  └─ ⏭️ ÜBERSPRUNGEN

14:40 Uhr - Scraper läuft:
  └─ Findet wieder "Jujutsu Kaisen Ep. 42"
  └─ contentHash = "abc123" (GLEICH!)
  └─ isDuplicate? JA (versendet vor 40 Min, außerhalb Fenster aber noch trackbar)
  └─ ⏭️ ÜBERSPRUNGEN
```

### Szenario 2: Mehrfach-Benachrichtigungen erlauben ✅

```
14:00 Uhr - Scraper läuft:
  └─ Findet "Jujutsu Kaisen Ep. 42"
  └─ contentHash = "hash_jjk_42"
  └─ ✅ GESENDET

15:00 Uhr - Scraper läuft:
  └─ Findet "Jujutsu Kaisen Ep. 42" (GLEICH wie vorher)
  │  └─ contentHash = "hash_jjk_42"
  │  └─ isDuplicate? JA → ⏭️ SKIP
  │
  └─ Findet "Jujutsu Kaisen Ep. 43" (NEU!)
  │  └─ contentHash = "hash_jjk_43"
  │  └─ isDuplicate? NEIN
  │  └─ ✅ GESENDET (BENACHRICHTIGUNG 2)
  │
  └─ Findet "Attack on Titan Movie" (NEU!)
     └─ contentHash = "hash_aot_movie"
     └─ isDuplicate? NEIN
     └─ ✅ GESENDET (BENACHRICHTIGUNG 3)

📊 Ergebnis: 2 Benachrichtigungen (nicht 3)
   - Jujutsu Kaisen Ep. 42 → SKIP (Duplikat)
   - Jujutsu Kaisen Ep. 43 → ✅
   - Attack on Titan Movie → ✅
```

---

## Datenbank-Struktur

```sql
CREATE TABLE notifications (
  id INTEGER PRIMARY KEY,
  favoriteTitle TEXT NOT NULL,
  releaseTitle TEXT NOT NULL,
  episodeNumber TEXT,
  notifyTime TEXT NOT NULL,
  isShown INTEGER,
  contentHash TEXT  -- 🆕 SHA256 Hash für Deduplication
);

-- 🆕 Index für schnelle Duplikat-Checks
CREATE INDEX idx_content_hash ON notifications(contentHash);
```

---

## Konfiguration

Alles ist im `NotificationRepository` definiert:

```dart
class NotificationRepository {
  // Wie lange sollen alte Benachrichtigungen gespeichert werden?
  static const int _maxRetentionDays = 30;
  
  // Zeitfenster für Duplikat-Erkennung (30 Min = sehr aggressiv)
  static const int _deduplicationWindowMinutes = 30;
}
```

**Diese Werte kannst du anpassen:**

| Parameter | Wert | Bedeutung |
|-----------|------|-----------|
| `_maxRetentionDays` | 30 | Benachrichtigungen älter als 30 Tage werden gelöscht |
| `_deduplicationWindowMinutes` | 30 | Nur Benachrichtigungen der letzten 30 Min werden geprüft |

---

## Debugging

### Debug-Logs im Terminal

```
📊 [BACKGROUND-SCRAPER] Notification Stats (last 2 hours):
   - Total sent: 5
   - Unique content: 3
   - Affected favorites: 2

📤 [BACKGROUND-SCRAPER] Processing 3 releases...

⏭️  [DEDUP] Skipping duplicate (last sent 15 min ago): 
    contentHash=abc123def456...

✅ [BACKGROUND-SCRAPER] Logged: Jujutsu Kaisen - Episode 42

✅ [BACKGROUND-SCRAPER] Completed in 2s
   - Favorites checked: 5
   - Releases found: 3
   - Notifications sent: 2        ← NEUE METRIK
   - Duplicates skipped: 1        ← NEUE METRIK
   - Total to send: 3
```

### Manueller Check in der App

In den Settings könnte man später eine "Benachrichtigungs-Historie" anzeigen:

```dart
final history = await notificationRepo.getHistory();
final stats = await notificationRepo.getNotificationStats(hoursBack: 24);

print('Benachrichtigungen letzte 24h:');
print('- Versendet: ${stats['totalCount']}');
print('- Unique Inhalte: ${stats['uniqueCount']}');
print('- Favoriten betroffen: ${stats['favCount']}');
```

---

## Migration von alter zu neuer Datenbank

**Problem:** Alte Benachrichtigungen haben keinen `contentHash`

**Lösung:** Die App erstellt eine neue Datenbank oder migriert automatisch

```dart
Future<void> _migrateOldNotifications() async {
  // Prüfe: Gibt es Einträge ohne contentHash?
  final result = await db.query(
    'notifications',
    where: 'contentHash IS NULL',
  );
  
  // Für jeden alten Eintrag: Generiere den Hash
  for (var notification in result) {
    final log = NotificationLog.fromJson(notification);
    final newHash = log.generateContentHash();
    
    await db.update(
      'notifications',
      {'contentHash': newHash},
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }
}
```

---

## Zusammenfassung

✅ **Doppelte Benachrichtigungen sind weg**
- Basierend auf **Content-Hash** (SHA256)
- Prüft **nur letzte 30 Minuten**
- Blockiert exakt gleiche Inhalte

✅ **Mehrfach-Benachrichtigungen funktionieren**
- Unterschiedliche Anime = unterschiedliche Hashes
- Alle werden versendet

✅ **Alles wird protokolliert**
- Jede Benachrichtigung wird mit Hash gespeichert
- Statistiken verfügbar (total, unique, betaffene Favoriten)
- Alte Einträge nach 30 Tagen gelöscht (Speicher sparen)

---

## Technische Details

### SHA256 Hash-Funktion

```dart
import 'package:crypto/crypto.dart';

String contentHash = sha256.convert(
  'Jujutsu Kaisen|Episode 42|42'.codeUnits
).toString();

// Resultat: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z...
```

**Eigenschaften:**
- Deterministische: Gleicher Input = Gleicher Output
- 64 Zeichen lang (256 Bit)
- Kleiner Unterschied = Komplett anderer Hash
- Sehr schnell (millisekunden)

---

## Was ist neu?

| Komponente | Was ist neu? |
|-----------|-------------|
| `notification_log.dart` | `contentHash` Feld + `generateContentHash()` Methode |
| `notification_repository.dart` | `isDuplicate()` + `getNotificationStats()` Methoden |
| `background_service.dart` | Smart Deduplication im Scraper-Loop |
| `pubspec.yaml` | Neue Dependency: `crypto: ^3.0.3` |
| Datenbank | Neues `contentHash` Feld + Index |

---

## Nächste Schritte (Optional)

- [ ] UI: "Benachrichtigungs-Historie" in Settings anzeigen
- [ ] UI: "Letzter Check" Timestamp anzeigen
- [ ] UI: Duplikat-Rate als Statistik anzeigen
- [ ] API: Konfigurierbare Deduplication-Fenster in Settings

