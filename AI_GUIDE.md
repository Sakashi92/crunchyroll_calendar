# 🤖 AI Development Guide (LLM Instructions)

Dieses Dokument dient als Leitfaden für KI-Assistenten (LLMs), die an diesem Projekt arbeiten. Es enthält kritische Informationen über die Projektstruktur, Versionierung und wichtige Logiken.

---

## 📌 Projekt-Philosophie
- **Inoffizieller Fan-Kalender**: Die App scrapt die Crunchyroll-Webseite. Stabilität des Scrapers ist oberste Priorität.
- **Benutzerfreundlichkeit**: Dokumentation (`README.md`) immer für Endnutzer einfach halten. Technische Details gehören in die `DEVELOPER.md`.

---

## 🔢 Versionierung (Checkliste)
Bei jedem neuen Release **MÜSSEN** die Versionen an folgenden Stellen synchron aktualisiert werden:

1.  **`pubspec.yaml`**: 
    - `version: x.y.z+build`
2.  **`lib/pages/settings_page.dart`**:
    - Suche nach `_buildInfoTile()` und aktualisiere den `subtitle` Text (`Version x.y.z`).
3.  **`CHANGELOG.md`**:
    - Neuen Block oben hinzufügen: `## [x.y.z] - YYYY-MM-DD`.
    - Änderungen stichpunktartig auflisten.
4.  **`README.md`**:
    - Den Download-Link im Abschnitt "App herunterladen" aktualisieren.

---

## 🚀 Release-Prozess (CI/CD)
Das Projekt nutzt GitHub Actions für automatische APK-Builds.
- **Workflow**: `.github/workflows/release.yml`.
- **Trigger**: Ein Push eines Git-Tags, der mit `v` beginnt (z. B. `v0.9.1`).
- **APK-Name**: Der Workflow benennt die APK automatisch um in `cr_calendar_v<TAG>.apk`.
- **Berechtigungen**: Der Workflow benötigt `contents: write` für den `GITHUB_TOKEN`.

---

## 🛠 Kritische Code-Logiken

### 1. Scraper & Deduplizierung (`CrunchyrollService`)
- **Scraper**: Nutzt CSS-Selektoren (`:nth-child`). Vorsicht bei Änderungen am Layout von Crunchyroll.
- **Deduplizierung**: In `_deduplicateReleases` werden Episoden basierend auf dem Titel gruppiert. Es wird pro Tag nur die höchste Episodennummer behalten. Dies verhindert doppelte Einträge bei Batch-Releases.
- **Normalisierung**: Nutze immer `_normalizeForSearch()` für Titel-Vergleiche.

### 2. In-App Updates (`GitHubUpdateService`)
- Die App prüft gegen die GitHub API (`/releases/latest`).
- Die Versionsprüfung in `_isNewerVersion` vergleicht numerische Parts.
- Das APK-Asset wird auf GitHub anhand der Endung `.apk` erkannt.

### 3. Hintergrund-Tasks (`BackgroundService`)
- Nutzt `Workmanager`. 
- Beachte die Android-Einschränkungen für Hintergrundprozesse (Akku-Optimierung).

---

## 📂 Dokumentations-Struktur
- `README.md`: User-Guide & Download.
- `DEVELOPER.md`: Build-Anweisungen & Technik-Stack.
- `AI_GUIDE.md`: Dieses Dokument.
- `docs/`: Detaillierte Beschreibungen einzelner Features.

---

## 🧪 Testing
- Führe vor jedem Commit `flutter analyze` aus.
- Prüfe bei UI-Änderungen immer sowohl den Light- als auch den Dark-Mode.
