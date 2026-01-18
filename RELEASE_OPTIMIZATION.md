# Release-Optimierung für Crunchyroll Kalender App

## Debug-Modus

Die App wurde für zwei Modi konfiguriert:

### Debug-Build (Development)
Alle Debug-Ausgaben werden angezeigt:
```bash
flutter run
# oder
flutter run --debug
```

### Release-Build (Production)
Alle Debug-Ausgaben sind deaktiviert für bessere Performance:
```bash
flutter run --release
# oder
flutter build apk --release  # Android
flutter build ios --release  # iOS
flutter build windows --release  # Windows
```

## Implementierung

### Code-Änderungen

1. **crunchyroll_service.dart**
   - Konstante `_debugPrint` hinzugefügt (nutzt `bool.fromEnvironment`)
   - Alle 100+ Print-Statements automatisch mit `if (_debugPrint)` umhüllt
   - Print-Statements nur ausgeführt wenn Debug-Modus aktiv ist

2. **main.dart**
   - Konstante `_debugPrint` hinzugefügt
   - Alle Print-Statements mit Debug-Guard umhüllt

3. **Automatisierung**
   - `fix_debug.py` - Python-Skript zum Umhüllen aller Print-Statements
   - Regex-basierte automatische Anpassung

## Performance-Verbesserungen

- **Eliminierteter Overhead**: Print-Statements sind im Release-Build völlig deaktiviert
- **Netzwerk**: Keine zusätzliche Konsolen-I/O
- **Speicher**: Keine String-Concatination für Debug-Ausgaben
- **Startup**: Schnelleres App-Starten ohne Debug-Ausgaben

## Beispiele

### Debug-Modus (flutter run)
```
🗑️ Clearing image cache...
✓ Image cache cleared - 0 images, 0 processed titles
🚀 Loading cache on startup...
✓ Cache loaded - processed titles: 452, image URLs: 845
Loading releases for: 18.1.2026
```

### Release-Modus (flutter run --release)
```
(Keine Debug-Ausgaben - App läuft silent)
```

## Verwenden im Code

Wenn Sie neue Debug-Ausgaben hinzufügen möchten:

```dart
// ✓ Richtig - wird im Release-Build ignoriert
if (_debugPrint) print('Debug-Nachricht');

// ✗ Falsch - wird immer ausgegeben
print('Debug-Nachricht');
```

## Deployment

Für Google Play oder App Store:
```bash
# Android
flutter build appbundle --release

# iOS  
flutter build ipa --release
```

Alle Debug-Print-Statements sind automatisch deaktiviert.
