# ⚙️ Benachrichtigungs-Deduplication: Konfiguration

## Schneller Überblick

Das System verhindert automatisch doppelte Benachrichtigungen alle 20 Minuten. **Keine Konfiguration nötig** - es funktioniert sofort!

---

## Standard-Einstellungen

```dart
// lib/repositories/notification_repository.dart

class NotificationRepository {
  // Wie lange werden Benachrichtigungen gespeichert?
  static const int _maxRetentionDays = 30;  // 30 Tage
  
  // Zeitfenster für Duplikat-Erkennung
  static const int _deduplicationWindowMinutes = 30;  // 30 Minuten
}
```

---

## Anpassung der Einstellungen

### 1. Duplikat-Fenster verkürzen

Wenn Duplikate noch zu häufig kommen:

```dart
// Weniger aggressiv (60 Minuten)
static const int _deduplicationWindowMinutes = 60;

// Sehr aggressiv (5 Minuten)
static const int _deduplicationWindowMinutes = 5;
```

**Was ändert sich:**
- **5 Min:** Duplikate nur in den letzten 5 Minuten blockiert (mehr Benachrichtigungen)
- **30 Min:** (Standard) Duplikate in letzten 30 Minuten blockiert
- **60 Min:** Duplikate in letzter Stunde blockiert (weniger Benachrichtigungen)

### 2. Aufbewahrungsdauer ändern

```dart
// Nur 7 Tage speichern (weniger Speicher)
static const int _maxRetentionDays = 7;

// 90 Tage speichern (mehr Historie)
static const int _maxRetentionDays = 90;
```

**Was ändert sich:**
- Nach X Tagen werden alte Benachrichtigungen automatisch gelöscht
- Weniger Speicherplatz auf dem Gerät

---

## Debug-Modus

Im Terminal siehst du detaillierte Logs:

```
📊 [BACKGROUND-SCRAPER] Notification Stats (last 2 hours):
   - Total sent: 5           ← Gesamte Benachrichtigungen
   - Unique content: 3       ← Davon unterschiedliche Inhalte
   - Affected favorites: 2   ← Betroffene Favoriten

📤 [BACKGROUND-SCRAPER] Processing 3 releases...

⏭️  [DEDUP] Skipping duplicate: contentHash=abc123...

✅ [BACKGROUND-SCRAPER] Completed in 2s
   - Notifications sent: 2    ← VERSENDET
   - Duplicates skipped: 1    ← ÜBERSPRUNGEN
   - Total to send: 3         ← GESAMT
```

---

## Typische Szenarien

### Szenario A: Du möchtest KEINE Duplikate

```
Einstellung: _deduplicationWindowMinutes = 60 (1 Stunde)

14:00 - Scraper findet "Jujutsu Kaisen Ep. 42"
  └─ ✅ Benachrichtigung gesendet

14:20 - Scraper findet IMMER NOCH "Jujutsu Kaisen Ep. 42"
  └─ ⏭️ Übersprungen (vor 20 Min versendet)

15:00 - Scraper findet IMMER NOCH "Jujutsu Kaisen Ep. 42"
  └─ ⏭️ Übersprungen (vor 60 Min versendet, aber immer noch im Fenster)

16:05 - Scraper findet IMMER NOCH "Jujutsu Kaisen Ep. 42"
  └─ ✅ Benachrichtigung gesendet (>60 Min vergangen)
```

### Szenario B: Du möchtest nur SEHR NEUE Duplikate blockieren

```
Einstellung: _deduplicationWindowMinutes = 10 (10 Minuten)

14:00 - Scraper findet "Jujutsu Kaisen Ep. 42"
  └─ ✅ Benachrichtigung gesendet

14:08 - Scraper findet IMMER NOCH "Jujutsu Kaisen Ep. 42"
  └─ ⏭️ Übersprungen (vor 8 Min versendet)

14:12 - Scraper findet IMMER NOCH "Jujutsu Kaisen Ep. 42"
  └─ ✅ Benachrichtigung gesendet (>10 Min vergangen)

14:20 - Scraper findet IMMER NOCH "Jujutsu Kaisen Ep. 42"
  └─ ✅ NOCHMAL Benachrichtigung gesendet (>10 Min vergangen)
```

---

## Häufig Gestellte Fragen

### F: Warum bekomme ich immer noch Duplikate?

A: Das Zeitfenster ist zu groß. Reduziere es:

```dart
// von
static const int _deduplicationWindowMinutes = 30;

// zu
static const int _deduplicationWindowMinutes = 120;  // 2 Stunden
```

### F: Ich möchte mehrere verschiedene Benachrichtigungen bekommen

A: Das passiert automatisch! Der Hash unterscheidet zwischen:
- Verschiedenen Anime-Titeln
- Verschiedenen Episoden-Nummern
- Verschiedenen Episoden-Titeln

Das System blockiert **nur exakte Duplikate**.

### F: Wie kann ich alle Benachrichtigungen löschen?

A: Im Code kannst du das für Debug-Zwecke tun:

```dart
final notificationRepo = NotificationRepository();
await notificationRepo.deleteAllNotifications();
```

### F: Werden Benachrichtigungen auf mehreren Geräten synchronisiert?

A: Nein. Die Datenbank ist **lokal auf dem Gerät**. Jedes Gerät hat seine eigene Benachrichtigungs-Historie.

---

## Automatische Bereinigung

Das System löscht automatisch alte Benachrichtigungen:

```dart
// Runs automatically when logging new notifications
await _cleanupOldNotifications(retentionDays: 30);
```

**Beispiel:**
- Heutiges Datum: 20. Januar 2026
- Gelöscht werden: Alle Benachrichtigungen vor 21. Dezember 2025 (>30 Tage alt)

---

## Statistiken anschauen

```dart
final stats = await notificationRepo.getNotificationStats(hoursBack: 2);

print('Letzte 2 Stunden:');
print('- Versendet: ${stats['totalCount']}');
print('- Unterschiedliche Inhalte: ${stats['uniqueCount']}');
print('- Favoriten: ${stats['favCount']}');
print('- Älteste: ${stats['oldestTime']}');
print('- Neuste: ${stats['newestTime']}');
```

---

## Technische Implementierung

### Wie funktioniert der Hash?

```dart
// Beispiel
String makeHash(String title, String releaseTitle, String? episodeNumber) {
  final content = '$title|$releaseTitle|${episodeNumber ?? ""}';
  // "Jujutsu Kaisen|Episode 42|42"
  
  return sha256.convert(content.codeUnits).toString();
  // "a1b2c3d4e5f6..." (64 Zeichen)
}

// Gleiche Input → Gleicher Hash
makeHash('JJK', 'Ep42', '42')  // → "a1b2c3..."
makeHash('JJK', 'Ep42', '42')  // → "a1b2c3..."

// Unterschiedliche Input → Unterschiedlicher Hash
makeHash('JJK', 'Ep42', '42')  // → "a1b2c3..."
makeHash('JJK', 'Ep43', '43')  // → "f7g8h9..."
```

### Duplikat-Check

```dart
// 1. Generiere Hash für neue Benachrichtigung
String hash = notification.generateContentHash();

// 2. Prüfe: War dieser Hash in letzten 30 Min versendet?
bool isDup = await notificationRepo.isDuplicate(hash);

// 3. Entscheidung
if (isDup) {
  print('⏭️ Skip');
  return;
}

// 4. Sende neue Benachrichtigung
await notificationService.showNotification(...);
await notificationRepo.logNotification(...);
```

---

## Zusammenfassung

| Feature | Standard | Anpassbar |
|---------|----------|-----------|
| Duplikat-Fenster | 30 Min | Ja |
| Aufbewahrungsdauer | 30 Tage | Ja |
| Automatische Bereinigung | ✅ | - |
| Debug-Logs | ✅ | - |
| Statistiken | ✅ | - |
| Hash-Algorithmus | SHA256 | Nein |

---

## Nächste Schritte

- [ ] Starte die App neu (wird Datenbank-Migration durchführen)
- [ ] Achte auf Debug-Logs im Terminal
- [ ] Beobachte: Bekommst du noch Duplikate? Dann Fenster vergrößern
- [ ] Optional: `_deduplicationWindowMinutes` anpassen

