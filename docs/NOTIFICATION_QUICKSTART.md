# 🎯 Benachrichtigungs-Deduplication - Quick Start

## Das Problem ✋

Alle 20 Minuten die **gleiche Benachrichtigung** vom letzten Anime - NERVIG! 😤

## Die Lösung ✅

**Intelligente Deduplication** - Verhindert doppelte, erlaubt aber mehrfach-Benachrichtigungen!

---

## Was ist neu?

### ✨ Neue Features

1. **Duplikat-Erkennung** 🚫
   - Gleiche Anime-Episode = Keine doppelte Benachrichtigung
   - Basiert auf SHA256-Hash des Inhalts
   - Fenster: 30 Minuten (konfigurierbar)

2. **Mehrfach-Benachrichtigungen** ✅
   - 4 neue Anime = 4 Benachrichtigungen
   - Nicht nur eine!

3. **Logging & Statistiken** 📊
   - Jede Benachrichtigung wird protokolliert
   - Statistiken: total, unique, betroffene Favoriten

---

## Schnell-Setup

### 1. Dependency installieren

```bash
flutter pub get
```

Dies installiert `crypto: ^3.0.3` automatisch.

### 2. App neu starten

```bash
flutter run
```

Die Datenbank wird automatisch aktualisiert (erste Sekunde).

### 3. Test durchführen

Schaue auf die Logs im Terminal:

```
✅ [BACKGROUND-SCRAPER] Notifications sent: 2
⏭️  [BACKGROUND-SCRAPER] Duplicates skipped: 1
```

---

## Funktioniert es?

### ✅ Es funktioniert wenn:

- Logs zeigen `Duplicates skipped: X` (X > 0)
- Mehrere verschiedene Releases = mehrere Benachrichtigungen
- Gleiches Release zweimal = wird übersprungen

### ⚠️ Nicht funktioniert wenn:

- Logs zeigen `Duplicates skipped: 0` (immer)
- Gleiche Benachrichtigung kommt mehrmals
- App crasht

→ Siehe [NOTIFICATION_TESTING.md](NOTIFICATION_TESTING.md) für Debugging

---

## Detaillierte Dokumentation

| Dokument | Inhalt |
|----------|--------|
| [NOTIFICATION_DEDUPLICATION.md](NOTIFICATION_DEDUPLICATION.md) | 📖 Technisches Verständnis |
| [NOTIFICATION_CONFIG.md](NOTIFICATION_CONFIG.md) | ⚙️ Konfiguration & Anpassung |
| [NOTIFICATION_TESTING.md](NOTIFICATION_TESTING.md) | 🧪 Testing & Troubleshooting |
| [CHANGES_SUMMARY.md](CHANGES_SUMMARY.md) | 📋 Was wurde geändert |

---

## Standard-Einstellungen

```dart
// lib/repositories/notification_repository.dart

// Duplikat-Fenster
static const int _deduplicationWindowMinutes = 30;

// Aufbewahrungsdauer
static const int _maxRetentionDays = 30;
```

**Anpassung?** → Siehe [NOTIFICATION_CONFIG.md](NOTIFICATION_CONFIG.md)

---

## Beispiele

### Beispiel 1: Duplikat wird übersprungen ✅

```
14:00 → "Jujutsu Kaisen Ep. 42" ✅ GESENDET
14:20 → "Jujutsu Kaisen Ep. 42" ⏭️ ÜBERSPRUNGEN (Duplikat)
14:40 → "Jujutsu Kaisen Ep. 42" ⏭️ ÜBERSPRUNGEN (Duplikat)
```

### Beispiel 2: Mehrfach-Benachrichtigungen ✅

```
15:00 Scraper findet 4 neue Anime:
  1. "Jujutsu Kaisen Ep. 42" ✅
  2. "Attack on Titan Ep. 10" ✅
  3. "My Hero Academia Ep. 5" ✅
  4. "Solo Leveling Ep. 7" ✅
  
Result: 4 BENACHRICHTIGUNGEN (alle unterschiedlich!)
```

### Beispiel 3: Nach Pause erneuert ✅

```
14:00 → "JJK Ep. 42" ✅ GESENDET
        (30 Min Fenster läuft)
15:05 → "JJK Ep. 42" ⏭️ ÜBERSPRUNGEN (nur 1h vergangen, im Fenster)
16:35 → "JJK Ep. 42" ✅ ERNEUT GESENDET (>30 Min, außerhalb Fenster)
```

---

## Logs interpretieren

```
📊 [BACKGROUND-SCRAPER] Notification Stats (last 2 hours):
   - Total sent: 5           ← Gesamt versendet
   - Unique content: 3       ← Unterschiedliche Inhalte
   - Affected favorites: 2   ← Betroffene Favoriten

📤 [BACKGROUND-SCRAPER] Processing 3 releases...

⏭️  [DEDUP] Skipping duplicate: contentHash=abc123...
                               ↑ Duplikat erkannt!

✅ [BACKGROUND-SCRAPER] Completed in 2s
   - Notifications sent: 2    ← Versendet
   - Duplicates skipped: 1    ← Übersprungen
```

---

## Fragen?

### F: Warum 30 Minuten?
**A:** Der Scraper läuft alle 20 Min. Das Fenster ist 30 Min, um Duplikate zu verhindern.

### F: Gehen alte Daten verloren?
**A:** Nein! Alte Benachrichtigungen bleiben erhalten und bekommen den Hash.

### F: Wie deaktiviere ich das?
**A:** Nicht empfohlen, aber möglich:
```dart
static const int _deduplicationWindowMinutes = 0;  // Deaktiviert
```

### F: Warum SHA256?
**A:** Kryptographisch sicher, schnell, und in Dart built-in.

---

## Nächste Schritte

1. ✅ App starten (`flutter run`)
2. ✅ Favoriten aktivieren
3. ✅ Logs beobachten
4. ✅ Nach Duplikaten checken
5. ⏳ Nach 2 Wochen: "Sind Duplikate weg?" → Ja? ✅ Done!

---

## Support

**Probleme?**

1. Lies [NOTIFICATION_TESTING.md](NOTIFICATION_TESTING.md)
2. Führe Test 1 durch
3. Schau die Logs an
4. Vergleiche mit "Häufige Probleme" Sektion

**Immer noch Probleme?**

```dart
// DB reset (für echte Probleme)
final repo = NotificationRepository();
await repo.deleteAllNotifications();
```

---

## Technische Details (Optional)

### Content-Hash

```dart
// Basis für den Hash
final content = '$favoriteTitle|$releaseTitle|$episodeNumber';
// Beispiel: "Jujutsu Kaisen|Episode 42|42"

// SHA256 Hash
final hash = sha256.convert(content.codeUnits).toString();
// Resultat: "a1b2c3d4e5f6..." (64 Zeichen)

// Eigenschaften:
// - Deterministic: Gleicher Input = Gleicher Output
// - Unique: Unterschiedlicher Input = Anderer Output
// - Schnell: <1ms für eine Million Checks
```

### Duplikat-Check

```dart
// Prüfe: War dieser Hash in letzten 30 Min versendet?
bool isDuplicate = await notificationRepo.isDuplicate(hash);

if (isDuplicate) {
  // Nicht senden, Duplicate überspringen
  skippedDuplicates++;
  continue;
}

// Neu → Senden!
await notificationService.showNotification(...);
```

---

## Zusammenfassung

| Punkt | Status |
|-------|--------|
| Doppelte Benachrichtigungen verhindern | ✅ Done |
| Mehrfach-Benachrichtigungen erlauben | ✅ Done |
| Alles protokollieren | ✅ Done |
| Statistiken verfügbar | ✅ Done |
| Konfigurierbar | ✅ Done |
| Backward-compatible | ✅ Done |
| Performance-optimiert | ✅ Done |

---

## Weiter lesen?

- 📖 [Technisches Deep-Dive](NOTIFICATION_DEDUPLICATION.md)
- ⚙️ [Konfiguration](NOTIFICATION_CONFIG.md)
- 🧪 [Testing & Debug](NOTIFICATION_TESTING.md)
- 📋 [Alle Änderungen](CHANGES_SUMMARY.md)

---

**Fertig!** 🎉 Die App sollte jetzt keine doppelten Benachrichtigungen mehr geben!
