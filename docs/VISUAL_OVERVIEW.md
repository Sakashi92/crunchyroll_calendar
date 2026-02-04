# 📊 Visuelle Übersicht der Benachrichtigungs-Deduplication

## System-Architektur

```
┌─────────────────────────────────────────────────────────────┐
│                    BACKGROUND SCRAPER (alle 20 Min)         │
│                                                             │
│  1. Releases scrapen (CrunchyrollService)                  │
│  2. Mit Favoriten filtern (ReleaseComparator)              │
│  3. Benachrichtigungen vorbereiten (NotificationLog)       │
│  4. 🆕 Content-Hash generieren (SHA256)                    │
│  5. 🆕 Duplikat-Check (isDuplicate)                        │
│  6. Falls nicht Duplikat:                                  │
│     └─ Benachrichtigung senden (NotificationService)      │
│     └─ In DB protokollieren (NotificationRepository)       │
│  7. 🆕 Statistiken loggen (getNotificationStats)           │
└─────────────────────────────────────────────────────────────┘
                          ↓
        ┌─────────────────────────────────────┐
        │    NOTIFICATION REPOSITORY          │
        │     (Datenbank & Deduplication)     │
        │                                     │
        │  ✅ logNotification()               │
        │  ✅ isDuplicate()         🆕       │
        │  ✅ getNotificationStats() 🆕      │
        │  ✅ deleteAllNotifications()        │
        │  ✅ getHistory()                    │
        └─────────────────────────────────────┘
                          ↓
        ┌─────────────────────────────────────┐
        │      SQFLITE DATENBANK              │
        │                                     │
        │  notifications {                   │
        │    id: int                         │
        │    favoriteTitle: string           │
        │    releaseTitle: string            │
        │    episodeNumber: string           │
        │    notifyTime: datetime            │
        │    isShown: bool                   │
        │    contentHash: string    🆕       │
        │  }                                 │
        │                                    │
        │  INDEXES:                          │
        │  - idx_favorite_title             │
        │  - idx_notify_time                │
        │  - idx_content_hash      🆕       │
        └─────────────────────────────────────┘
```

---

## Workflow: Benachrichtigung senden mit Deduplication

```
START: Neuer Release gefunden
  │
  ├─ 📝 Erstelle NotificationLog
  │  ├─ favoriteTitle: "Jujutsu Kaisen"
  │  ├─ releaseTitle: "Episode 42"
  │  ├─ episodeNumber: "42"
  │  └─ notifyTime: now
  │
  ├─ 🔐 Generiere Content-Hash
  │  └─ SHA256("Jujutsu Kaisen|Episode 42|42")
  │  └─ Resultat: "a1b2c3d4e5f6g7h8..." (64 Zeichen)
  │
  ├─ 🔍 Duplikat-Check
  │  └─ Prüfe: Existiert "a1b2c3d4e5f6..." in letzten 30 Min?
  │
  ├─ 📊 Entscheidung (IF)
  │  │
  │  ├─ Falls JA (Duplikat gefunden)
  │  │  ├─ ⏭️  SKIP
  │  │  ├─ skippedDuplicates++
  │  │  └─ [FERTIG - Keine Benachrichtigung]
  │  │
  │  └─ Falls NEIN (Neu)
  │     ├─ 📤 Sende Benachrichtigung
  │     ├─ 💾 Speichere in Datenbank (mit Hash)
  │     ├─ notificationCount++
  │     └─ [FERTIG - Benachrichtigung gesendet]
  │
  └─ Gehe zum nächsten Release
```

---

## Zeitliche Abläufe

### Szenario 1: 20-Minuten-Duplikate verhindern

```
Zeit      │ Scraper │ Release gefunden │ Hash    │ isDup? │ Action
──────────┼─────────┼──────────────────┼─────────┼────────┼──────────
14:00:00  │ ✓ läuft │ JJK Ep. 42       │ aaa111  │ Nein   │ ✅ SEND
14:00:05  │ (DB-Op) │ -                │ -       │ -      │ Speichern
          │         │ Fenster: 14:00-14:30
14:20:00  │ ✓ läuft │ JJK Ep. 42       │ aaa111  │ Ja!    │ ⏭️  SKIP
14:20:05  │ (Check) │ -                │ -       │ -      │ (in DB)
          │         │ Fenster: 14:20-14:50
14:40:00  │ ✓ läuft │ JJK Ep. 42       │ aaa111  │ Ja!    │ ⏭️  SKIP
14:40:05  │ (Check) │ -                │ -       │ -      │ (in DB)
          │         │ Fenster: 14:40-15:10
15:00:00  │ ✓ läuft │ JJK Ep. 42       │ aaa111  │ Ja!    │ ⏭️  SKIP
15:00:05  │ (Check) │ -                │ -       │ -      │ (in DB)
          │         │ Fenster: 15:00-15:30
15:20:00  │ ✓ läuft │ JJK Ep. 42       │ aaa111  │ Nein!  │ ✅ SEND
15:20:05  │ (DB-Op) │ -                │ -       │ -      │ (>30 Min)
```

**Resultat:** 2 Benachrichtigungen statt 5 (60% weniger!)

---

### Szenario 2: Mehrfach-Benachrichtigungen

```
Zeit    │ Scraper│ Releases gefunden           │ Hash    │ Action
────────┼────────┼─────────────────────────────┼─────────┼──────────
15:00:00│✓ läuft │ 1. JJK Ep. 42 (alt)        │ aaa111  │ ⏭️  SKIP
        │        │ 2. JJK Ep. 43 (NEU!)       │ aaa222  │ ✅ SEND
        │        │ 3. AoT Ep. 10 (NEU!)       │ bbb333  │ ✅ SEND
        │        │ 4. MHA Ep. 5 (NEU!)        │ ccc444  │ ✅ SEND
        │        │ 5. Solo Leveling Ep. 7     │ ddd555  │ ✅ SEND
        │        │ (NEU!)                      │         │
        │        │                             │         │
        └────────┴─────────────────────────────┴─────────┴──────────
                  Versendet: 4 Benachrichtigungen! ✅✅✅✅
                  Übersprungen: 1 (Duplikat)
```

**Resultat:** 4 Benachrichtigungen (alle unterschiedlichen Inhalte!)

---

## Datenbank-Schema Evolution

### VORHER (Alt)

```sql
CREATE TABLE notifications (
  id INTEGER PRIMARY KEY,
  favoriteId INTEGER,
  favoriteTitle TEXT,
  releaseTitle TEXT,
  episodeNumber TEXT,
  notifyTime TEXT,
  isShown INTEGER
);

CREATE INDEX idx_favorite_title ON notifications(favoriteTitle);
CREATE INDEX idx_notify_time ON notifications(notifyTime);
```

### NACHHER (Neu) 🆕

```sql
CREATE TABLE notifications (
  id INTEGER PRIMARY KEY,
  favoriteId INTEGER,
  favoriteTitle TEXT,
  releaseTitle TEXT,
  episodeNumber TEXT,
  notifyTime TEXT,
  isShown INTEGER,
  contentHash TEXT          🆕 SHA256 Hash
);

CREATE INDEX idx_favorite_title ON notifications(favoriteTitle);
CREATE INDEX idx_notify_time ON notifications(notifyTime);
CREATE INDEX idx_content_hash ON notifications(contentHash);  🆕 Duplikat-Check
```

---

## Content-Hash Generierung

```
INPUT:
┌─────────────────────────────────┐
│ favoriteTitle: "Jujutsu Kaisen"  │
│ releaseTitle: "Episode 42"       │
│ episodeNumber: "42"              │
└─────────────────────────────────┘
           ↓
    [Concatenate mit |]
           ↓
    "Jujutsu Kaisen|Episode 42|42"
           ↓
    [SHA256 Hash]
           ↓
OUTPUT:
┌──────────────────────────────────────────────────────────────┐
│ a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9 │
│ (64 Zeichen, hexadecimal)                                    │
└──────────────────────────────────────────────────────────────┘

EIGENSCHAFTEN:
• Deterministic: Gleicher Input = Gleicher Output
• Unique: Unterschiedliche Input = Anderer Output
• One-way: Kann nicht rückwärts gerechnet werden
• Schnell: <1ms pro Hash
• Sicher: Cryptographisch stark
```

---

## Duplikat-Check Ablauf

```
INPUT: contentHash = "a1b2c3d4e5f6..."

        ┌──────────────────────┐
        │  Aktuelle Uhrzeit    │
        │  14:25:00            │
        │  - 30 Min            │
        │  = 13:55:00          │
        │ (Fenster-Startzeit)  │
        └──────────────────────┘
                  ↓
    ┌──────────────────────────────────┐
    │ SQL Query:                       │
    │                                  │
    │ SELECT * FROM notifications     │
    │ WHERE contentHash = "a1b..."    │
    │   AND notifyTime > "13:55:00"   │
    │ LIMIT 1                          │
    └──────────────────────────────────┘
                  ↓
        ┌──────────────────────┐
        │  Resultat?           │
        │  [Entscheidung]      │
        └──────────────────────┘
          │                    │
        FOUND              NOT FOUND
          │                    │
      (Duplikat)            (Neu)
          │                    │
        isDuplicate()=true  isDuplicate()=false
          │                    │
       ⏭️  SKIP              ✅ SEND
```

---

## Performance-Vergleich

### Alte Methode (ohne Deduplication)

```
14:00 → Scraper
        └─ Findet JJK Ep. 42
        └─ Prüft: hasBeenNotified?
           └─ JA, aber egal...
           └─ ✅ SEND (Duplikat!)

14:20 → Scraper
        └─ Findet JJK Ep. 42
        └─ Prüft: hasBeenNotified?
           └─ JA, aber egal...
           └─ ✅ SEND (Duplikat!)

14:40 → Scraper
        └─ Findet JJK Ep. 42
        └─ Prüft: hasBeenNotified?
           └─ JA, aber egal...
           └─ ✅ SEND (Duplikat!)

Result: 3 identische Benachrichtigungen 😤
```

### Neue Methode (mit Deduplication)

```
14:00 → Scraper
        └─ Findet JJK Ep. 42
        └─ Hash: aaa111
        └─ Prüft: isDuplicate?
           └─ NEIN
           └─ ✅ SEND

14:20 → Scraper
        └─ Findet JJK Ep. 42
        └─ Hash: aaa111 (GLEICH)
        └─ Prüft: isDuplicate?
           └─ JA (vor 20 Min)
           └─ ⏭️  SKIP

14:40 → Scraper
        └─ Findet JJK Ep. 42
        └─ Hash: aaa111 (GLEICH)
        └─ Prüft: isDuplicate?
           └─ JA (vor 40 Min)
           └─ ⏭️  SKIP

Result: 1 Benachrichtigung (67% weniger!) ✅
```

---

## Statistik-Ausgabe

```
┌──────────────────────────────────────────────────┐
│  BACKGROUND-SCRAPER Statistics (Letzte 2h)      │
├──────────────────────────────────────────────────┤
│                                                  │
│  Total Benachrichtigungen versendet: 5           │
│  ├─ Davon eindeutige Inhalte: 3                 │
│  └─ Betroffen Favoriten: 2                      │
│                                                  │
│  Älteste: 13:30:00                              │
│  Neuste:  15:25:00                              │
│                                                  │
├──────────────────────────────────────────────────┤
│  Dieser Lauf (aktuell):                         │
│                                                  │
│  ✅ Neu versendet:  2                            │
│  ⏭️  Duplikate übersprungen: 1                   │
│  📊 Gesamte zu verarbeiten: 3                   │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

## Dateien-Struktur

```
lib/
├── models/
│   ├── anime_release.dart
│   ├── favorite_anime.dart
│   └── notification_log.dart              ✏️ MODIFIED
│       ├── contentHash: String?          🆕
│       └── generateContentHash(): String 🆕
│
├── repositories/
│   ├── favorites_repository.dart
│   └── notification_repository.dart       ✏️ MODIFIED
│       ├── isDuplicate(): Future<bool>   🆕
│       ├── getNotificationStats()        🆕
│       └── _deduplicationWindowMinutes   🆕
│
├── services/
│   ├── crunchyroll_service.dart
│   ├── notification_service.dart
│   ├── background_service.dart           ✏️ MODIFIED
│   │   └─ Neue Deduplication-Logik      🆕
│   ├── permission_service.dart
│   └── battery_optimization_service.dart
│
├── main.dart
└── settings.dart

pubspec.yaml                               ✏️ MODIFIED
├── + crypto: ^3.0.3                      🆕

📄 NOTIFICATION_DEDUPLICATION.md           📄 NEW
📄 NOTIFICATION_CONFIG.md                  📄 NEW
📄 NOTIFICATION_TESTING.md                 📄 NEW
📄 NOTIFICATION_QUICKSTART.md              📄 NEW
📄 CHANGES_SUMMARY.md                      📄 NEW
```

---

## Lebenszykus einer Benachrichtigung

```
    ┌─────────────────────────────────────┐
    │  Release auf Crunchyroll            │
    │  "Jujutsu Kaisen Episode 42"        │
    └──────────────┬──────────────────────┘
                   │
        Alle 20 Minuten
                   ↓
    ┌─────────────────────────────────────┐
    │  BackgroundService Scraper           │
    │  - Sucht nach Releases              │
    │  - Findet: "JJK Ep. 42"             │
    └──────────────┬──────────────────────┘
                   │
        Erstelle NotificationLog
                   ↓
    ┌─────────────────────────────────────┐
    │  Generiere Content-Hash             │
    │  SHA256("JJK|Ep42|42")              │
    │  = "a1b2c3d4..."                    │
    └──────────────┬──────────────────────┘
                   │
        Prüfe: War dieser Hash in letzten 30 Min?
                   ↓
            ┌──────┴──────┐
            │             │
        JA  │             │  NEIN
            │             │
            ↓             ↓
        ⏭️  SKIP      ✅ SEND
        (kein         (Benachrichtigung
        Log-Eintrag)  an User)
                        │
                Speichere in DB
                        │
                        ↓
                ┌──────────────────┐
                │  Database Entry  │
                │                  │
                │ favoriteTitle    │
                │ releaseTitle     │
                │ episodeNumber    │
                │ contentHash ← 🔑 │
                │ notifyTime       │
                └──────────────────┘
                        │
                Nächster Scraper-Lauf
                mit gleichen Release?
                        ↓
            isDuplicate("a1b2c3d4...")?
                        │
                    → JA! ⏭️  SKIP
```

---

## Zusammenfassung als Diagramm

```
      VORHER (Problem)             NACHHER (Lösung)
      
Scraper 1 (14:00)          Scraper 1 (14:00)
  └─ JJK Ep. 42              └─ JJK Ep. 42
     └─ ✅ SEND                 └─ Hash: aaa111
                                └─ ✅ SEND (new)
Scraper 2 (14:20)
  └─ JJK Ep. 42              Scraper 2 (14:20)
     └─ ✅ SEND (!!!)           └─ JJK Ep. 42
                                └─ Hash: aaa111
Scraper 3 (14:40)                └─ isDuplicate?
  └─ JJK Ep. 42                     └─ JA
     └─ ✅ SEND (!!!)                └─ ⏭️  SKIP
                                
Scraper 4 (15:00)              Scraper 3 (14:40)
  └─ JJK Ep. 42                 └─ JJK Ep. 42
     └─ ✅ SEND (!!!)              └─ Hash: aaa111
                                   └─ isDuplicate?
                                      └─ JA
      = 4 BENACHRICHTIGUNGEN        └─ ⏭️  SKIP
        (ALLE GLEICH!) 😤
                                   Scraper 4 (15:00)
                                   └─ JJK Ep. 42
                                      └─ Hash: aaa111
                                      └─ isDuplicate?
                                         └─ JA
                                         └─ ⏭️  SKIP
                                   
                                   = 1 BENACHRICHTIGUNG
                                     (nur 1x!) ✅
```

---

## Migration: Alte Datenbank → Neue Datenbank

```
ALTE DATENBANK                MIGRATION              NEUE DATENBANK
(Ohne contentHash)            (Auto)                (Mit contentHash)
                              
┌─────────────────┐     ┌──────────────────┐   ┌─────────────────┐
│ id: 1           │────→│ contentHash = ?  │───→│ id: 1           │
│ title: "JJK"    │     │ Generiere:       │   │ title: "JJK"    │
│ releaseTitle... │     │ generateHash()   │   │ releaseTitle... │
│ contentHash: NULL    │                  │   │ contentHash:    │
│                 │     └──────────────────┘   │ "a1b2c3d4..."  │
│ id: 2           │────→│ id: 2            │───→│ id: 2           │
│ title: "AoT"    │     │ title: "AoT"     │   │ title: "AoT"    │
│ releaseTitle... │     │ releaseTitle...  │   │ releaseTitle... │
│ contentHash: NULL    │ contentHash: NULL     │ contentHash:    │
│                 │                           │ "b2c3d4e5..."  │
└─────────────────┘                           └─────────────────┘

Automatisch beim App-Start!
Nutzer müssen nichts tun!
```

---

Diese Übersicht zeigt das komplette System auf einen Blick! 🎯

