# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

## [0.8.9] - 2026-02-04

### Behoben
- **Scraper-Wiederherstellung**: Die Scraping-Logik wurde auf den stabilen Stand von Commit `1be531e` zurückgesetzt, um Probleme beim Laden des Kalenders nach einem Reset zu beheben.
- **Leere Kalender-Ladefehler**: Fix für das Problem, dass nach einem Cache-Reset keine Anime mehr im Simulcast-Kalender angezeigt wurden.

### Hinzugefügt
- **Intelligente Deduplizierung**: Implementierung einer robusten Gruppierungslogik für Anime-Releases basierend auf dem (normalisierten) Titel. Dies verhindert zuverlässig doppelte Einträge am selben Tag.
- **Globale Cache-Bereinigung**: Die Deduplizierung wird nun global beim Speichern in die Datenbank angewendet (`_saveToCache` & `_saveMonthToCache`), sodass nur noch die jeweils höchste Episodennummer pro Serie und Tag angezeigt wird.

### Optimierungen
- **Code-Qualität**: Entfernung ungenutzter Methoden (`_getDayOffsetFromElement`) und Bereinigung von Importen zur Reduzierung von Lint-Warnungen.
- **Logging**: Verbesserte Debug-Ausgaben im `CrunchyrollService` zur einfacheren Fehlerdiagnose.
