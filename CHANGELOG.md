# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

## [0.9.9] - 2026-02-08
- **Fix**: Metadaten-Matching verbessert (One Piece Episodenzahl wird nun korrekt geladen).
- **Fix**: Problem mit mehrdeutigen AniList-Suchergebnissen bei populären Shows behoben.
- **Fix**: URL-Matching robuster gestaltet (Ignoriert http/https und www Differenzen).
- **Fix**: Anime-Details-Dialog lädt Metadaten nun auch dann vorab, wenn die Episodenzahl 0 ist.
- **UI**: Gesamtepisodenzahl wird nun in den Details immer angezeigt, wenn verfügbar.

## [0.9.8+1] - 2026-02-07
- **Fix**: Problem behoben, bei dem der "Im Simulcast" Status nach dem Umbennen eines Anime verschwand.

## [0.9.8] - 2026-02-07
- **UI**: Schwarzes "+" Icon in der Anime-Suchliste beim manuellen Hinzufügen korrigiert - verwendet jetzt die korrekte Theme-Farbe.
- **Feat**: Umfassendes Einstellungsmanagement mit dedizierten Services für App-Einstellungen implementiert.
- **Feat**: AniList, Crunchyroll und Kitsu Services für Metadaten-Abfrage hinzugefügt.
- **Refactor**: Verbesserte Service-Architektur mit modularen API-Komponenten.

## [0.9.7] - 2026-02-05
- **UI**: Animationen beim Minimieren des Kalenders verlangsamt und sanfter gestaltet (Fade-Effekt + längere Dauer).
- **Feat**: Neue Einstellung hinzugefügt: "Vollständiges Datum in Pillenform" (erlaubt Wechsel zwischen Kurz- und Langform).
- **Feat**: Standardwerte für Einstellungen optimiert ("Aktuelle Episodenzahl bevorzugen" ist nun standardmäßig aktiviert).

## [0.9.6+1] - 2026-02-05
- **UI**: Smooth Übergänge beim Wechsel zwischen Kalenderformaten (AnimatedSwitcher-Integration).
- **Feat**: Update-Snooze-Funktion (Dialog erscheint nach "Später" erst nach dem 3. weiteren App-Start erneut).
- **Feat**: Responsives Grid-Layout für Anime-Releases hinzugefügt (automatische Spalten bei breitem Fenster oder Landscape).
- **Feat**: Dynamische Landscape-Optimierung (Kalender wechselt im Querformat automatisch zur Wochenansicht und wird zentriert).

## [0.9.6] - 2026-02-05
- **UI**: Expandierter Kalender hat nun einen abgerundeten Hintergrund mit Schatten, der beim Scrollen transparent wird.
- **UI**: Wochentage im Kalender sind jetzt dunkler und besser lesbar.
- **UI**: Kalender-Abstände und Tageskreise optimiert.
- **UI**: Vorhersage-Badge ("V") Position für Portrait und Landscape separat angepasst.
- **UI**: Fenstergröße unter Windows auf ein Smartphone-ähnliches Format begrenzt (450x850 px).
- **Fix**: Absturz im GitHub-Update-Service auf Windows behoben (`OtaStatus.UNKNOWN` durch `INTERNAL_ERROR` ersetzt).

## [0.9.5+1] - 2026-02-04
- **Feat**: Neuer professioneller Update-Dialog in deutscher Sprache.
- **UI**: In-App Update-Benachrichtigung für bessere Sichtbarkeit verbessert.
- **Internal**: Versionsformat auf 0.9.5+1 umgestellt und Vergleichslogik für Build-Nummern optimiert.
- **Security**: App-Signing für lokale und automatisierte GitHub-Builds konfiguriert.

## [0.9.4] - 2026-02-04
- **Fix**: Android In-App Update Problem behoben (FileProvider Berechtigung hinzugefügt).
- **Feat**: Automatischer Update-Check beim App-Start.

## [0.9.3] - 2026-02-04
- **Feat**: Dynamische Versionsanzeige in den Einstellungen.
- **Doku**: Build-Status Badge in README.md hinzugefügt.

## [0.9.2] - 2026-02-04
- **Fix**: Android Build-Fehler behoben (OTA Update benötigt neuere Library Desugaring Version).
- **Lizenz**: Wechsel zur GNU GPL v3.0 Lizenz.

## [0.9.1] - 2026-02-04
- **CI/CD**: Anpassung der APK-Benennung auf GitHub (`cr_calendar_v0.9.1.apk`).

## [0.9.0] - 2026-02-04
- **Feature**: In-App Update System integriert. Updates können jetzt direkt über GitHub in den Einstellungen geprüft und installiert werden.
- **CI/CD**: Vollständige Automatisierung der Releases via GitHub Actions.
- **Fix**: Anime-Deduplizierung verbessert, um doppelte Einträge am selben Tag zu verhindern.
- **Doku**: README grundlegend überarbeitet und für Endnutzer optimiert. Technical-Docs in DEVELOPER.md verschoben.

### Behoben
- **Scraper-Wiederherstellung**: Die Scraping-Logik wurde auf den stabilen Stand von Commit `1be531e` zurückgesetzt, um Probleme beim Laden des Kalenders nach einem Reset zu beheben.
- **Leere Kalender-Ladefehler**: Fix für das Problem, dass nach einem Cache-Reset keine Anime mehr im Simulcast-Kalender angezeigt wurden.

### Hinzugefügt
- **Intelligente Deduplizierung**: Implementierung einer robusten Gruppierungslogik für Anime-Releases basierend auf dem (normalisierten) Titel. Dies verhindert zuverlässig doppelte Einträge am selben Tag.
- **Globale Cache-Bereinigung**: Die Deduplizierung wird nun global beim Speichern in die Datenbank angewendet (`_saveToCache` & `_saveMonthToCache`), sodass nur noch die jeweils höchste Episodennummer pro Serie und Tag angezeigt wird.

### Optimierungen
- **Code-Qualität**: Entfernung ungenutzter Methoden (`_getDayOffsetFromElement`) und Bereinigung von Importen zur Reduzierung von Lint-Warnungen.
- **Logging**: Verbesserte Debug-Ausgaben im `CrunchyrollService` zur einfacheren Fehlerdiagnose.
